# Expensy - DevOps Cluster Setup Guide

This guide covers how to start and provision the Expensy application cluster in both Docker Compose (development) and Kubernetes (production) environments.

## Table of Contents

- [Prerequisites](#prerequisites)
- [Quick Start with Docker Compose](#quick-start-with-docker-compose)
- [Kubernetes Deployment](#kubernetes-deployment)
- [Secrets Management](#secrets-management)
- [Troubleshooting](#troubleshooting)

---

## Prerequisites

### Required Tools

- **Docker & Docker Compose** (for local development)
  ```bash
  docker --version
  docker-compose --version
  ```

- **kubectl** (for Kubernetes)
  ```bash
  kubectl version --client
  ```

- **Kubernetes Cluster** (for production)
  - minikube, Docker Desktop Kubernetes, EKS, AKS, GKE, etc.

### Project Structure

```
expensy/
├── docker-compose.yml          # Local development setup
├── k8s/                         # Kubernetes manifests
│   ├── namespace.yaml           # expensy namespace
│   ├── secrets.yaml             # Secret template (placeholders)
│   ├── secrets.yaml.local       # Actual secrets (do NOT commit)
│   ├── mongo.yaml               # MongoDB deployment
│   ├── mongo-pvc.yaml           # MongoDB persistent volume
│   ├── redis.yaml               # Redis deployment
│   ├── backend.yaml             # Backend service & deployment
│   └── frontend.yaml            # Frontend service & deployment
├── apply_all.sh                 # Provision all K8s resources
├── delete_all.sh                # Clean up all K8s resources
├── expensy_backend/             # Node.js backend
├── expensy_frontend/            # Next.js frontend
└── README.md                    # This file
```

---

## Quick Start with Docker Compose

Use Docker Compose for local development. This spins up all services in containers on your machine.

### 1. Start the Cluster

```bash
docker-compose up --build
```

### 2. Wait for Services

All services should be healthy after ~30 seconds:
- **Frontend**: http://localhost:3000
- **Backend**: http://localhost:8706
- **MongoDB**: localhost:27017 (root/example)
- **Redis**: localhost:6379 (password: someredispassword)

### 3. Stop the Cluster

```bash
docker-compose down
```

### 4. Clean Up (Remove Volumes)

```bash
docker-compose down -v
```

---

## Running Frontend & Backend Locally

Run the frontend and backend services natively on your machine without Docker. Useful for development when you want faster iteration.

### Prerequisites

- **Node.js 18+** and **npm**
  ```bash
  node --version
  npm --version
  ```

- **MongoDB & Redis running** (use Docker Compose for these)
  ```bash
  # In a separate terminal, start only the databases:
  docker-compose up mongo redis
  ```

### 1. Install Dependencies

**Backend:**
```bash
cd expensy_backend
npm install
```

**Frontend:**
```bash
cd expensy_frontend
npm install
```

### 2. Start Backend (Development)

```bash
cd expensy_backend
npm run build
npm start
```

Backend runs on: http://localhost:8706

**Or use watch mode for development** (requires `ts-node-dev`):
```bash
cd expensy_backend
npx ts-node-dev --respawn src/server.ts
```

### 3. Start Frontend (Development)

```bash
cd expensy_frontend
NEXT_PUBLIC_API_URL=http://localhost:8706 npm run dev
```

Frontend runs on: http://localhost:3000

### 4. Environment Variables

**Backend** (`expensy_backend/.env` or set inline):
```bash
PORT=8706
DATABASE_URI=mongodb://root:example@localhost:27017/expensy?authSource=admin
REDIS_HOST=localhost
REDIS_PORT=6379
REDIS_PASSWORD=someredispassword
```

**Frontend** (set when running):
```bash
NEXT_PUBLIC_API_URL=http://localhost:8706
```

### 5. Stop Services

Backend:
```bash
Ctrl+C
```

Frontend:
```bash
Ctrl+C
```

Stop databases:
```bash
docker-compose down
```

---

## Kubernetes Deployment

Deploy the application to a Kubernetes cluster.

### Prerequisites

1. **Kubernetes Cluster Running**
   ```bash
   kubectl cluster-info
   ```

2. **Current Context Set**
   ```bash
   kubectl config current-context
   ```

### 1. Set Up Secrets

The cluster needs access to credentials for MongoDB and Redis.

**Option A: Create from Template (Recommended)**

Copy the template and fill in your actual values:

```bash
cp k8s/secrets.yaml.local k8s/secrets.yaml.local
# Edit k8s/secrets.yaml.local with your actual secrets
```

**Option B: Create Manually**

```bash
kubectl create secret generic expensy-secrets \
  --from-literal=mongo_user=root \
  --from-literal=mongo_pass=example \
  --from-literal=redis_password=someredispassword \
  --from-literal=database_uri=mongodb://root:example@mongo:27017/expensy?authSource=admin \
  -n expensy
```

### 2. Provision the Cluster

Apply all Kubernetes manifests in order:

```bash
./apply_all.sh
```

This deploys:
1. `expensy` namespace
2. Secrets
3. MongoDB with persistent storage
4. Redis cache
5. Backend service
6. Frontend service

### 3. Verify Deployment

Check pod status:

```bash
kubectl get pods -n expensy
```

Expected output:
```
NAME                        READY   STATUS    RESTARTS   AGE
mongo-xxx                   1/1     Running   0          2m
redis-xxx                   1/1     Running   0          2m
expensy-backend-xxx         1/1     Running   0          1m
expensy-frontend-xxx        1/1     Running   0          1m
```

Check services:

```bash
kubectl get svc -n expensy
```

### 4. Access the Application

**Port-Forward to Backend**
```bash
kubectl port-forward -n expensy svc/expensy-backend 8706:8706
```
Backend available at: http://localhost:8706

**Port-Forward to Frontend**
```bash
kubectl port-forward -n expensy svc/expensy-frontend 3000:3000
```
Frontend available at: http://localhost:3000

### 5. View Logs

Backend logs:
```bash
kubectl logs -n expensy -f deployment/expensy-backend
```

Frontend logs:
```bash
kubectl logs -n expensy -f deployment/expensy-frontend
```

MongoDB logs:
```bash
kubectl logs -n expensy -f pod/mongo-xxx
```

### 6. Clean Up

Delete all resources:

```bash
./delete_all.sh
```

Or delete manually:

```bash
kubectl delete namespace expensy
```

---

## Secrets Management

### ⚠️ Important Security Notes

**DO NOT commit actual secrets to GitHub!**

We use a template + local file approach:

- **`k8s/secrets.yaml`** (committed): Template with placeholders
- **`k8s/secrets.yaml.local`** (gitignored): Your actual secrets

### Creating `secrets.yaml.local`

1. Copy the template:
   ```bash
   cp k8s/secrets.yaml k8s/secrets.yaml.local
   ```

2. Edit with actual values:
   ```bash
   nano k8s/secrets.yaml.local
   ```

3. Replace placeholders:
   ```yaml
   stringData:
     mongo_user: your_actual_user
     mongo_pass: your_actual_password
     redis_password: your_actual_redis_password
     database_uri: mongodb://...
   ```

4. Use `secrets.yaml.local` for deployment (never commit it)

### For Team Members

1. Clone the repo
2. Create `k8s/secrets.yaml.local` with your values (based on template)
3. Run `./apply_all.sh` - it uses `secrets.yaml.local`

---

## Troubleshooting

### Pods Not Starting

Check pod status and events:
```bash
kubectl describe pod -n expensy <pod-name>
```

Common issues:
- **ImagePullBackOff**: Build images first or check registry access
- **CrashLoopBackOff**: Check logs with `kubectl logs`
- **Pending**: Check node resources or storage provisioning

### MongoDB Connection Issues

Check if MongoDB is ready:
```bash
kubectl exec -n expensy <mongo-pod> -- mongo -u root -p example --eval "db.adminCommand('ping')"
```

Check MongoDB volume:
```bash
kubectl get pvc -n expensy
```

### Backend Can't Connect to Database

Verify environment variables:
```bash
kubectl env pod/<backend-pod> -n expensy
```

Check if MongoDB and Redis pods are running:
```bash
kubectl get pods -n expensy
```

### Port Forward Not Working

Try a different port:
```bash
kubectl port-forward -n expensy svc/expensy-backend 9000:8706
```

Then access at http://localhost:9000

### Can't Access Frontend/Backend Services

Ensure services exist:
```bash
kubectl get svc -n expensy
```

Check service endpoints:
```bash
kubectl get endpoints -n expensy
```

---

## Environment Variables

### Backend (expensy-backend)

- `PORT`: 8706
- `DATABASE_URI`: MongoDB connection string
- `REDIS_HOST`: redis
- `REDIS_PORT`: 6379
- `REDIS_PASSWORD`: Redis password

### Frontend (expensy-frontend)

- `NEXT_PUBLIC_API_URL`: Backend API URL (http://localhost:8706 for local dev)

---

## Quick Reference Commands

```bash
# Docker Compose
docker-compose up --build          # Start all services
docker-compose down                # Stop all services
docker-compose logs -f             # View logs

# Kubernetes
kubectl get pods -n expensy        # List all pods
kubectl logs -n expensy <pod>      # View pod logs
kubectl port-forward -n expensy svc/<svc-name> <local>:<remote>  # Port forward
./apply_all.sh                     # Deploy everything
./delete_all.sh                    # Clean up everything
kubectl delete namespace expensy   # Delete namespace
```

---

## Need Help?

- Check pod logs: `kubectl logs -n expensy -f <pod-name>`
- Describe pod issues: `kubectl describe pod -n expensy <pod-name>`
- Check all resources: `kubectl get all -n expensy`
- Check cluster events: `kubectl get events -n expensy`
