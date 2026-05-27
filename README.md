# FluidAI DevOps Challenge — Kubernetes + CI/CD

## Stack

| Component | Choice | Why |
|-----------|--------|-----|
| App | Python / FastAPI | Minimal, fast, built-in `/docs` |
| Dependency | Redis 7 | Lighter than Postgres, great for counters |
| Cluster | Minikube (local) | No cloud cost, full K8s API |
| CI/CD | GitHub Actions | Native Docker + kubectl, free tier |
| Reliability | Readiness + Liveness probes | Solves traffic routing during failures |
| Failure demo | Bad `REDIS_HOST` env var | Realistic, clearly observable, easy to fix live |

---

## Project Structure

```
fluidai-devops/
├── app/
│   ├── main.py              # FastAPI app with /health, /ready, /counter
│   ├── requirements.txt
│   └── Dockerfile           # Multi-stage, non-root user
├── k8s/
│   ├── 00-namespace-configmap.yaml
│   ├── 01-secret.yaml       # Redis password (base64)
│   ├── 02-redis.yaml        # Redis Deployment + Service + probes
│   ├── 03-app.yaml          # FastAPI Deployment + Service + probes  ← main file
│   └── BROKEN-app.yaml      # Intentional failure: wrong REDIS_HOST
├── .github/
│   └── workflows/
│       └── deploy.yml       # Build → Push → Deploy pipeline
├── demo.sh                  # All commands for the video
└── README.md
```

---

## Quick Setup

### 1. Prerequisites
```bash
# macOS
brew install minikube kubectl docker

# Verify
minikube version
kubectl version --client
docker --version
```

### 2. Start cluster
```bash
minikube start --cpus=2 --memory=2048 --driver=docker
kubectl get nodes   # should show 1 node Ready
```

### 3. Build & push image
```bash
export DOCKERHUB_USER=your-username   # ← set this

cd app
docker build -t $DOCKERHUB_USER/fluidai-demo:latest .
docker login
docker push $DOCKERHUB_USER/fluidai-demo:latest
cd ..
```

### 4. Deploy
```bash
# Substitute your username
sed -i "s|YOUR_DOCKERHUB_USERNAME|$DOCKERHUB_USER|g" k8s/03-app.yaml
sed -i "s|IMAGE_TAG|latest|g" k8s/03-app.yaml

kubectl apply -f k8s/
kubectl rollout status deployment/fastapi-app -n fluidai --timeout=90s
kubectl get all -n fluidai
```

### 5. Access the app
```bash
# Terminal 1
kubectl port-forward service/fastapi-service 8080:80 -n fluidai

# Terminal 2
curl http://localhost:8080/
curl http://localhost:8080/health
curl http://localhost:8080/ready
curl http://localhost:8080/counter   # run 3x to see count go up
```

### 6. GitHub Actions setup
Add these secrets to your repo → Settings → Secrets:

| Secret | Value |
|--------|-------|
| `DOCKERHUB_USERNAME` | your Docker Hub username |
| `DOCKERHUB_TOKEN` | Docker Hub access token |
| `KUBECONFIG_B64` | `base64 ~/.kube/config` output |

---

## Reliability Feature: Readiness + Liveness Probes

### What problem it solves
Without probes, Kubernetes routes traffic to pods that are still starting up or broken, causing `502/503` errors to end users.

### How it works
| Probe | Endpoint | Checks | Action on failure |
|-------|----------|--------|-------------------|
| **Liveness** | `GET /health` | Is the Python process alive? | Restart the container |
| **Readiness** | `GET /ready` | Can we reach Redis? | Remove pod from load balancer |

### The key design decision
`/health` has **no external dependencies** — it only confirms uvicorn is running.
`/ready` **actually pings Redis** — it fails if the dependency is down.

This split means:
- A pod with a broken Redis connection is removed from routing (readiness fails) but not restarted (liveness still passes), because restarting won't fix a network issue.

### Tradeoff
Misconfigured `initialDelaySeconds` causes false-positive restarts. If your app takes 30s to start and you set `initialDelaySeconds: 10`, Kubernetes will restart a perfectly healthy pod. Always tune to real startup time.

---

## Failure Scenario: Wrong REDIS_HOST Environment Variable

### Trigger the failure
```bash
sed -i "s|YOUR_DOCKERHUB_USERNAME|$DOCKERHUB_USER|g" k8s/BROKEN-app.yaml
kubectl apply -f k8s/BROKEN-app.yaml
```

### Debug it (these are your live video commands)

**Step 1 — Observe the symptom**
```bash
kubectl get pods -n fluidai
# OUTPUT: fastapi-app-xxx   0/2   Running   0   45s
#         ^^^^^^^^^^^^^^^^  ^^^
#         pods exist but READY shows 0 — not receiving traffic
```

**Step 2 — Describe the pod**
```bash
kubectl describe pod <pod-name> -n fluidai
# Look for:
#   Readiness probe failed: HTTP probe failed with statuscode: 503
#   Warning  Unhealthy  Readiness probe failed
```

**Step 3 — Check logs**
```bash
kubectl logs <pod-name> -n fluidai
# OUTPUT: Redis connection refused: redis-broken-host:6379
#         Error: Connection timed out
```

**Step 4 — Check events**
```bash
kubectl get events -n fluidai --sort-by='.lastTimestamp'
# Shows: Readiness probe failed repeatedly
```

**Step 5 — Find root cause**
```bash
kubectl get deployment fastapi-app -n fluidai -o yaml | grep -A5 "env:"
# See: REDIS_HOST = redis-broken-host  ← wrong!
```

**Step 6 — Fix it**
```bash
kubectl apply -f k8s/03-app.yaml   # apply the correct manifest
kubectl rollout status deployment/fastapi-app -n fluidai
kubectl get pods -n fluidai
# OUTPUT: fastapi-app-xxx   2/2   Running   0   15s  ← fixed!
```

### Why this failure is realistic
Wrong environment variable names are one of the most common production incidents. The K8s probes made it *safe* — traffic was never routed to the broken pods because readiness failed. Without probes, users would have received 500 errors.

---

## Video Script (8–12 min)

### Section 1: Live Demo (3–4 min)
1. `kubectl get nodes` — show cluster is up
2. `kubectl get all -n fluidai` — show all resources
3. Hit `/health`, `/ready`, `/counter` — show app working
4. Show GitHub Actions run completing successfully

### Section 2: Architecture Walkthrough (2–3 min)
- Walk through `k8s/03-app.yaml` — explain ConfigMap, Secret, probes
- Explain rolling update strategy (`maxUnavailable: 0`)
- Show `deploy.yml` — explain build → push → sed substitution → apply → rollout wait
- Explain why readiness/liveness are split

### Section 3: Failure Debug (2–3 min)
Follow the 6-step debug script above.
**Key talking points:**
- "The liveness probe passed — the process was alive"
- "The readiness probe failed — it couldn't reach Redis"
- "The probes protected users — zero traffic went to the broken pods"
- "Checked describe → logs → events in that order"
- "Root cause: wrong env var. Fix: apply correct manifest"

### Section 4: Tradeoffs (1–2 min)
**What I simplified:**
- Used NodePort instead of Ingress (no TLS, no hostname routing)
- Secrets stored as base64 in YAML — in prod: Vault or External Secrets Operator
- Single Redis replica — no persistence, no sentinel/cluster mode
- No horizontal pod autoscaler (HPA)
- `kubectl apply` for deploy — in prod: ArgoCD / Flux for GitOps

**What would break at scale:**
- Redis single point of failure → use Redis Sentinel or a managed service
- No persistent volume on Redis → all data lost on pod restart
- NodePort not suitable for production → need Ingress + TLS termination
- No resource quotas at namespace level → noisy neighbour risk

**What I'd add next:**
- HPA based on request rate
- Prometheus + Grafana for metrics
- External Secrets Operator for secret management
- ArgoCD for proper GitOps
- PodDisruptionBudget for safe node maintenance
