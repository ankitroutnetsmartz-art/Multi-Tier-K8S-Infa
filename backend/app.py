from flask import Flask, jsonify
from flask_cors import CORS
from kubernetes import client, config
import os
import requests
import time
import threading

app = Flask(__name__)
CORS(app)

# Global state to track traffic metrics across polls
traffic_stats = {
    "prev_total_requests": 0,
    "prev_timestamp": time.time(),
    "current_rps": 0,
    "total_hits": 0
}
stats_lock = threading.Lock()

def load_k8s_config():
    try:
        config.load_incluster_config()
    except Exception:
        config.load_kube_config()

def poll_nginx_stats(pod_ips):
    total_requests = 0
    for ip in pod_ips:
        try:
            # Poll the /nginx_status endpoint we enabled
            response = requests.get(f"http://{ip}/nginx_status", timeout=1)
            if response.status_code == 200:
                # stub_status format:
                # Active connections: 1 
                # server accepts handled requests
                #  10 10 10 
                # Reading: 0 Writing: 1 Waiting: 0
                lines = response.text.splitlines()
                if len(lines) >= 3:
                    req_line = lines[2].strip().split()
                    if len(req_line) >= 3:
                        total_requests += int(req_line[2])
        except Exception as e:
            print(f"Error polling pod {ip}: {e}")
    return total_requests

@app.route("/status")
def status():
    try:
        load_k8s_config()
        apps_v1 = client.AppsV1Api()
        autoscaling_v2 = client.AutoscalingV2Api()
        core_v1 = client.CoreV1Api()

        namespace = os.environ.get("NAMESPACE", "default")
        deployment_name = os.environ.get("DEPLOYMENT_NAME", "azure-k8s-site")
        hpa_name = os.environ.get("HPA_NAME", "web-autoscaler")

        # Get HPA info
        hpa = autoscaling_v2.read_namespaced_horizontal_pod_autoscaler(
            name=hpa_name, namespace=namespace
        )
        current_replicas = hpa.status.current_replicas or 0
        desired_replicas = hpa.status.desired_replicas or 0
        min_replicas = hpa.spec.min_replicas or 2
        max_replicas = hpa.spec.max_replicas or 10

        # Extract CPU utilization from HPA metrics
        cpu_utilization = 0
        if hpa.status.current_metrics:
            for metric in hpa.status.current_metrics:
                if metric.type == "Resource" and metric.resource and metric.resource.name == "cpu":
                    if metric.resource.current and metric.resource.current.average_utilization is not None:
                        cpu_utilization = metric.resource.current.average_utilization

        # Get CPU target
        cpu_target = 50
        if hpa.spec.metrics:
            for m in hpa.spec.metrics:
                if m.type == "Resource" and m.resource and m.resource.name == "cpu":
                    if m.resource.target and m.resource.target.average_utilization:
                        cpu_target = m.resource.target.average_utilization

        # Get pods and their IPs for traffic monitoring
        pods = core_v1.list_namespaced_pod(
            namespace=namespace,
            label_selector="app=web-server"
        )
        
        pod_list = []
        pod_ips = []
        for pod in pods.items:
            pod_list.append({
                "name": pod.metadata.name,
                "phase": pod.status.phase,
                "ip": pod.status.pod_ip,
                "ready": all(
                    cs.ready for cs in (pod.status.container_statuses or [])
                ) if pod.status.container_statuses else False
            })
            if pod.status.pod_ip:
                pod_ips.append(pod.status.pod_ip)

        # Calculate RPS
        with stats_lock:
            now = time.time()
            current_total_requests = poll_nginx_stats(pod_ips)
            
            time_diff = now - traffic_stats["prev_timestamp"]
            req_diff = current_total_requests - traffic_stats["prev_total_requests"]
            
            # Reset if pods restarted or first run
            if req_diff < 0: req_diff = 0
            
            if time_diff > 0:
                traffic_stats["current_rps"] = round(req_diff / time_diff, 1)
            
            traffic_stats["prev_total_requests"] = current_total_requests
            traffic_stats["prev_timestamp"] = now
            traffic_stats["total_hits"] = current_total_requests

        return jsonify({
            "current_replicas": current_replicas,
            "desired_replicas": desired_replicas,
            "min_replicas": min_replicas,
            "max_replicas": max_replicas,
            "cpu_utilization": cpu_utilization,
            "cpu_target": cpu_target,
            "pods": pod_list,
            "total_pods": len(pod_list),
            "traffic": {
                "rps": traffic_stats["current_rps"],
                "total_hits": traffic_stats["total_hits"]
            }
        })

    except Exception as e:
        return jsonify({"error": str(e)}), 500

@app.route("/health")
def health():
    return jsonify({"status": "ok"})

if __name__ == "__main__":
    app.run(host="0.0.0.0", port=5000)
