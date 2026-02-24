#!/bin/bash
set -e

echo "--- 🛠️ Starting Local DevOps Environment Setup ---"

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
echo "🚀 Initializing Minikube (2 Cores, 4GB RAM)..."
minikube start --cpus=2 --memory=4096 --driver=docker

# 5. Apply Project State
echo "📄 Deploying K8S Manifests..."
kubectl apply -f manifests/redis-stack.yaml
kubectl create configmap website-html --from-file=index=index.html --from-file=about=about.html --dry-run=client -o yaml | kubectl apply -f -
kubectl apply -f manifests/website-stack.yaml

echo "--- ✅ Local Environment Ready ---"
minikube service azure-k8s-site-service --url
