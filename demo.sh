#!/usr/bin/env bash

set -euo pipefail

DOCKERHUB_USER="mjai3747"   
IMAGE="$DOCKERHUB_USER/fluidai-demo"

# ─────────────────────────────────────────────────────────────────────────────
# SECTION 1 — Start Minikube cluster
# ─────────────────────────────────────────────────────────────────────────────
echo "=== Starting Minikube ==="
minikube start --cpus=2 --memory=2048 --driver=docker

# Verify cluster is up
kubectl cluster-info
kubectl get nodes

# ─────────────────────────────────────────────────────────────────────────────
# SECTION 2 — Build & push Docker image
# ─────────────────────────────────────────────────────────────────────────────
echo "=== Building Docker image ==="
cd app
docker build -t "$IMAGE:latest" .
docker push "$IMAGE:latest"
cd ..

# ─────────────────────────────────────────────────────────────────────────────
# SECTION 3 — Deploy to Kubernetes
# ─────────────────────────────────────────────────────────────────────────────
echo "=== Applying Kubernetes manifests ==="

# Update your username in the app manifest
sed -i "s|mjai3747|$DOCKERHUB_USER|g" k8s/03-app.yaml
sed -i "s|IMAGE_TAG|latest|g" k8s/03-app.yaml

kubectl apply -f k8s/00-namespace-configmap.yaml
kubectl apply -f k8s/01-secret.yaml
kubectl apply -f k8s/02-redis.yaml
kubectl apply -f k8s/03-app.yaml

echo "=== Waiting for deployments to be ready ==="
kubectl rollout status deployment/redis -n fluidai --timeout=60s
kubectl rollout status deployment/fastapi-app -n fluidai --timeout=60s

# ─────────────────────────────────────────────────────────────────────────────
# SECTION 4 — Verify everything is running 
# ─────────────────────────────────────────────────────────────────────────────
echo "=== Kubernetes resources ==="
kubectl get all -n fluidai

# ─────────────────────────────────────────────────────────────────────────────
# SECTION 5 — Access the app
# ─────────────────────────────────────────────────────────────────────────────
echo "=== Getting service URL ==="
# In one terminal, run this to forward the port:
#   minikube service fastapi-service -n fluidai
# OR:
#   kubectl port-forward service/fastapi-service 8080:80 -n fluidai
# Then hit:
#   curl http://localhost:8080/
#   curl http://localhost:8080/health
#   curl http://localhost:8080/ready
#   curl http://localhost:8080/counter
#   curl http://localhost:8080/counter
#   curl http://localhost:8080/counter

echo ""
echo "=== TRIGGERING INTENTIONAL FAILURE ==="
echo "Deploying broken config with wrong REDIS_HOST..."

# Patch the broken manifest with your username first
sed -i "s|mjai3747|$DOCKERHUB_USER|g" k8s/BROKEN-app.yaml
kubectl apply -f k8s/BROKEN-app.yaml

echo ""
echo "--- Wait 30 seconds, then observe ---"
sleep 30

echo ""
echo "=== SYMPTOM 1: Pods stuck in 0/2 READY ==="
kubectl get pods -n fluidai

echo ""
echo "=== SYMPTOM 2: Describe pod to see probe failures ==="
POD=$(kubectl get pods -n fluidai -l app=fastapi-app -o jsonpath='{.items[0].metadata.name}')
kubectl describe pod "$POD" -n fluidai

echo ""
echo "=== SYMPTOM 3: Logs show Redis connection refused ==="
kubectl logs "$POD" -n fluidai

echo ""
echo "=== SYMPTOM 4: Events tell the full story ==="
kubectl get events -n fluidai --sort-by='.lastTimestamp' | tail -20

echo ""
echo "=== ROOT CAUSE: Wrong env var — REDIS_HOST=redis-broken-host ==="
kubectl get deployment fastapi-app -n fluidai -o jsonpath='{.spec.template.spec.containers[0].env}' | python3 -m json.tool

echo ""
echo "=== FIX: Correct the env var and redeploy ==="
kubectl apply -f k8s/03-app.yaml

echo ""
echo "=== Waiting for healthy rollout ==="
kubectl rollout status deployment/fastapi-app -n fluidai --timeout=120s

echo ""
echo "=== FIXED: Pods now 2/2 READY ==="
kubectl get pods -n fluidai

echo ""
echo "=== Verify readiness probe passes ==="
kubectl port-forward service/fastapi-service 8080:80 -n fluidai &
PF_PID=$!
sleep 3
curl -s http://localhost:8080/ready | python3 -m json.tool
kill $PF_PID 2>/dev/null || true

# ─────────────────────────-------------------------------------
# SECTION 7 — Rollback demo 
# ───────────────────────── 
# kubectl rollout history deployment/fastapi-app -n fluidai
# kubectl rollout undo deployment/fastapi-app -n fluidai
# kubectl rollout status deployment/fastapi-app -n fluidai

echo ""
echo "=== ALL DONE — stack is healthy ==="
kubectl get all -n fluidai
