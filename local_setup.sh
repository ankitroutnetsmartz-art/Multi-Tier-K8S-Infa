#!/bin/bash
set -e

echo "--- 🛠️ Starting Local DevOps Environment Setup ---"

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# 1. Install Docker Engine
if ! command -v docker &> /dev/null; then
    echo "📦 Installing Docker..."
    sudo apt update && sudo apt install -y docker.io
    sudo usermod -aG docker $USER
    echo "⚠️ Docker installed. You may need to restart your session for group changes."
fi

# 2. Install kubectl
if ! command -v kubectl &> /dev/null; then
    echo "📦 Installing kubectl..."
    sudo snap install kubectl --classic
fi

# 3. Install minikube
if ! command -v minikube &> /dev/null; then
    echo "📦 Installing minikube..."
    curl -LO https://storage.googleapis.com/minikube/releases/latest/minikube-linux-amd64
    sudo install minikube-linux-amd64 /usr/local/bin/minikube
    rm minikube-linux-amd64
fi

# 4. Start Local Cluster
if ! minikube status --format='{{.Host}}' 2>/dev/null | grep -q "Running"; then
    echo "🚀 Initializing Minikube (2 Cores, 4GB RAM)..."
    minikube start --cpus=2 --memory=4096 --driver=docker
fi

# 5. Enable Required Add-ons
echo "⚙️  Enabling Add-ons: Metrics Server & Ingress..."
minikube addons enable metrics-server
minikube addons enable ingress

# 6. Build Backend Docker image INSIDE Minikube's Docker daemon
echo "🐳 Building backend image inside Minikube..."
eval $(minikube docker-env)
docker build -t k8s-status-backend:latest "$PROJECT_DIR/backend/"
eval $(minikube docker-env --unset)

# 7. Apply Backend Stack (RBAC + Deployment + Service)
echo "📄 Deploying Backend API..."
kubectl apply -f "$PROJECT_DIR/manifests/backend-stack.yaml"

# 8. Apply Redis Stack
echo "📄 Deploying Redis..."
kubectl apply -f "$PROJECT_DIR/manifests/redis-stack.yaml"

# 9. Sync UI Content (ConfigMap with index.html + about.html)
echo "📄 Syncing UI Content to ConfigMap..."
kubectl delete configmap website-html --ignore-not-found
kubectl create configmap website-html \
    --from-file=index.html="$PROJECT_DIR/index.html" \
    --from-file=about.html="$PROJECT_DIR/about.html"

# 10. Sync Nginx Config
echo "📄 Syncing Nginx Config to ConfigMap..."
kubectl delete configmap nginx-config --ignore-not-found
kubectl create configmap nginx-config --from-file=nginx.conf="$PROJECT_DIR/nginx.conf"

# 10. Apply Website Stack (Deployment + Service + HPA)
echo "🏗️  Applying Website Stack..."
kubectl apply -f "$PROJECT_DIR/manifests/website-stack.yaml"

# 11. Apply Ingress
echo "🌐 Applying Ingress Rules..."
kubectl apply -f "$PROJECT_DIR/manifests/ingress.yaml"

# 12. Rollout restart to pick up new configmap
echo "🔄 Rolling out updated pods..."
kubectl rollout restart deployment azure-k8s-site
kubectl rollout status deployment azure-k8s-site --timeout=90s

# 13. Wait for backend to be ready
echo "⏳ Waiting for backend API to be ready..."
kubectl rollout status deployment k8s-status-backend --timeout=90s

echo ""
echo "--- ✅ Local Environment Ready ---"
echo ""
echo "🌐 Access via Minikube tunnel URL:"
minikube service azure-k8s-site-service --url
echo ""
echo "📈 Monitor Auto-scaling with:"
echo "    watch kubectl get hpa,pods -l app=web-server"
echo ""
echo "🔥 Load test with Apache Benchmark:"
echo "    ab -n 10000 -c 50 http://\$(minikube ip):<nodeport>/"
