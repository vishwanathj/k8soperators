# Containerized Development Guide (Ansible Operator)

This guide details how to build **Ansible-based Kubernetes Operators** using containers instead of installing binaries directly on your host machine. It is configured to work seamlessly with **Podman**, **SELinux**, and local **Kubernetes clusters** (like Kind, Minikube, or OpenShift Local).

## Prerequisites

* **Container Engine:** Podman (recommended) or Docker.
* **Kubernetes Config:** A valid `kubeconfig` file (usually at `~/.kube/config`).

---

# Part 1: Ansible Development Environment

The Ansible operator requires Python, Ansible, and the Operator SDK. We'll use a Python-based container image and install the necessary tools.

## 🚀 Quick Start (One-Off Command)

Run the following command to verify your environment:

```bash
docker run --rm -it \
  --net=host \
  --security-opt label=disable \
  -v ~/.kube/config:/root/.kube/config \
  -v $(pwd):/app \
  -w /app \
  python:3.12 python --version
```

## 📦 Interactive / Background Mode

For a persistent container with all tools pre-installed, follow these steps.

### 1. Start the Ansible Dev Container

```bash
docker run -itd \
  --name ansible-dev \
  --net=host \
  --security-opt label=disable \
  -v $(pwd):/app \
  -v ~/.kube/config:/root/.kube/config \
  -w /app \
  -v ansible-bin:/usr/local/bin \
  -v pip-cache:/root/.cache/pip \
  python:3.12
```

### 2. Install Ansible & Operator SDK (Inside Container)

Enter the container:

```bash
docker exec -it ansible-dev bash
```

**Install Ansible and Dependencies:**

```bash
# Install Ansible and kubernetes Python packages
pip install ansible ansible-runner ansible-runner-http openshift kubernetes jmespath

# Verify
ansible --version
```

**Install Operator SDK:**

```bash
# Set version
export ARCH=amd64
export OS=linux
export VER=v1.39.1

# Download binary
curl -LO "https://github.com/operator-framework/operator-sdk/releases/download/${VER}/operator-sdk_${OS}_${ARCH}"

# Make executable and move to path
chmod +x operator-sdk_${OS}_${ARCH} && mv operator-sdk_${OS}_${ARCH} /usr/local/bin/operator-sdk

# Verify
operator-sdk version
```

**Install Make (Required for building):**

```bash
apt-get update && apt-get install -y make
```

### 3. Enter the Shell

```bash
docker exec -it ansible-dev bash
```

### 4. Cleanup

```bash
docker rm -f ansible-dev
```

---

### ⚠️ Binary Persistence

| Action | Status |
|--------|--------|
| `docker stop ansible-dev` → `docker start ansible-dev` | ✅ Everything survives |
| `docker rm ansible-dev` → `docker run ...` (recreate) | ❌ Installed packages lost, reinstall required |

---

#### Option 1: Auto-Install Entrypoint (Recommended)

This directory includes an `entrypoint.sh` script that automatically installs tools if missing. 

See: [`entrypoint.sh`](./entrypoint.sh)

Run the container with the custom entrypoint:

```bash
# Run container with auto-install entrypoint
docker run -itd \
  --name ansible-dev \
  --net=host \
  --security-opt label=disable \
  -v $(pwd):/app \
  -v ~/.kube/config:/root/.kube/config \
  -w /app \
  -v ansible-bin:/usr/local/bin \
  -v pip-cache:/root/.cache/pip \
  -v $(pwd)/entrypoint.sh:/entrypoint.sh:ro \
  --entrypoint /entrypoint.sh \
  python:3.12
```

Now every time the container starts, it will automatically check for and install the following tools if missing:
- **Ansible** (with `ansible-runner`, `openshift`, `kubernetes`, `jmespath`)
- **Operator SDK** (v1.39.1)
- **Make**

---

#### Option 2: Build a Custom Image

This directory includes a `Dockerfile.dev` with Ansible, Operator SDK, and Make pre-installed.

See: [`Dockerfile.dev`](./Dockerfile.dev)

**Build and run:**

```bash
# Build the custom image
docker build -f Dockerfile.dev -t ansible-operator-dev:latest .

# Run using your custom image
docker run -itd \
  --name ansible-dev \
  --net=host \
  --security-opt label=disable \
  -v $(pwd):/app \
  -v ~/.kube/config:/root/.kube/config \
  -w /app \
  ansible-operator-dev:latest
```

---

# Part 2: Building an Ansible Operator (Memcached Example)

Follow these steps to scaffold a new Ansible Operator from scratch.

### 1. Create Project Directory

Inside the container (`docker exec -it ansible-dev bash`), create a new folder for your operator:

```bash
mkdir memcached-operator
cd memcached-operator
```

### 2. Initialize the Operator

```bash
operator-sdk init --plugins=ansible \
  --domain=example.com
```

**What this command creates:**

| File/Folder | Purpose |
|-------------|---------|
| `PROJECT` | Project metadata and plugin info |
| `Makefile` | Build, deploy, and test commands |
| `Dockerfile` | Build the operator container image |
| `config/` | Kubernetes manifests (CRD, RBAC, deployment) |
| `playbooks/` | Directory for Ansible playbooks |
| `roles/` | Directory for Ansible roles |
| `watches.yaml` | Maps CRs to Ansible roles/playbooks |
| `requirements.yml` | Ansible Galaxy dependencies |
| `molecule/` | Testing framework |

### 3. Create an API (Custom Resource Definition)

```bash
operator-sdk create api \
  --group cache \
  --version v1alpha1 \
  --kind Memcached \
  --generate-role
```

**What this command does:**

| Flag | Purpose |
|------|---------|
| `--group=cache` | API group name → results in `cache.example.com` |
| `--version=v1alpha1` | API version (alpha/beta/stable) |
| `--kind=Memcached` | The Custom Resource type name (`kubectl get memcached`) |
| `--generate-role` | Creates an Ansible role skeleton |

This creates:
- `config/crd/bases/cache.example.com_memcacheds.yaml` - The CRD
- `config/samples/cache_v1alpha1_memcached.yaml` - Sample CR
- `roles/memcached/` - Ansible role skeleton
- Updates `watches.yaml` to map Memcached CR → memcached role

### 4. Implement the Ansible Role

The generated role at `roles/memcached/` is empty. Let's add real functionality to deploy Memcached.

> **⚠️ Important: Integer Type Handling**
> 
> Kubernetes API expects `replicas` as an integer, but inline YAML Jinja expressions like `replicas: "{{ size }}"` pass strings. To preserve native types, use a **template file** with `lookup('template', ...) | from_yaml`.

**Create `roles/memcached/templates/deployment.yaml.j2`:**

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: "{{ ansible_operator_meta.name }}-memcached"
  namespace: "{{ ansible_operator_meta.namespace }}"
  labels:
    app: memcached
    app.kubernetes.io/name: memcached
    app.kubernetes.io/instance: "{{ ansible_operator_meta.name }}"
    app.kubernetes.io/managed-by: ansible-operator
spec:
  replicas: {{ size | default(1) | int }}
  selector:
    matchLabels:
      app: memcached
      app.kubernetes.io/instance: "{{ ansible_operator_meta.name }}"
  template:
    metadata:
      labels:
        app: memcached
        app.kubernetes.io/instance: "{{ ansible_operator_meta.name }}"
    spec:
      containers:
        - name: memcached
          image: "{{ image | default('memcached:1.6-alpine') }}"
          imagePullPolicy: "{{ image_pull_policy | default('IfNotPresent') }}"
          ports:
            - containerPort: 11211
              name: memcached
              protocol: TCP
          resources:
            limits:
              cpu: "{{ cpu_limit | default('200m') }}"
              memory: "{{ memory_limit | default('256Mi') }}"
            requests:
              cpu: "{{ cpu_request | default('100m') }}"
              memory: "{{ memory_request | default('128Mi') }}"
          command:
            - memcached
            - "-m"
            - "{{ memory_mb | default('64') }}"
            - "-o"
            - modern
            - "-v"
          livenessProbe:
            tcpSocket:
              port: memcached
            initialDelaySeconds: 30
            periodSeconds: 10
          readinessProbe:
            tcpSocket:
              port: memcached
            initialDelaySeconds: 5
            periodSeconds: 10
```

**Edit `roles/memcached/tasks/main.yml`:**

```yaml
---
# tasks file for Memcached

- name: Create Memcached Deployment
  kubernetes.core.k8s:
    definition: "{{ lookup('template', 'deployment.yaml.j2') | from_yaml }}"

- name: Create Memcached Service
  kubernetes.core.k8s:
    definition:
      apiVersion: v1
      kind: Service
      metadata:
        name: "{{ ansible_operator_meta.name }}-memcached"
        namespace: "{{ ansible_operator_meta.namespace }}"
        labels:
          app: memcached
          app.kubernetes.io/instance: "{{ ansible_operator_meta.name }}"
      spec:
        type: ClusterIP
        ports:
          - port: 11211
            targetPort: 11211
            protocol: TCP
            name: memcached
        selector:
          app: memcached
          app.kubernetes.io/instance: "{{ ansible_operator_meta.name }}"
```

**Edit `roles/memcached/defaults/main.yml`:**

```yaml
---
# defaults file for Memcached

# Number of memcached replicas
size: 1

# Container image
image: memcached:1.6-alpine
image_pull_policy: IfNotPresent

# Resource limits
cpu_limit: "200m"
memory_limit: "256Mi"
cpu_request: "100m"
memory_request: "128Mi"

# Memcached memory allocation in MB
memory_mb: "64"
```

### 4b. Add RBAC Permissions for Services

The default RBAC role doesn't include permissions for Services. If your operator creates Services, add them to `config/rbac/role.yaml`:

```yaml
  - apiGroups:
      - ""
    resources:
      - secrets
      - pods
      - pods/exec
      - pods/log
      - services          # <-- Add this line
    verbs:
      - create
      - delete
      - get
      - list
      - patch
      - update
      - watch
```

> **Note:** After modifying `role.yaml`, run `make deploy` to apply the updated RBAC, or manually apply with `kubectl apply -f config/rbac/role.yaml`.

### 5. Update the Sample CR

**Edit `config/samples/cache_v1alpha1_memcached.yaml`:**

```yaml
apiVersion: cache.example.com/v1alpha1
kind: Memcached
metadata:
  name: memcached-sample
  labels:
    app.kubernetes.io/name: memcached-operator
    app.kubernetes.io/managed-by: kustomize
spec:
  # Number of memcached replicas
  size: 3
  
  # Optional: Override the image
  # image: memcached:1.6-alpine
  
  # Optional: Customize resource limits
  # cpu_limit: "500m"
  # memory_limit: "512Mi"
  
  # Optional: Memcached memory in MB
  # memory_mb: "128"
```

### 6. Understanding watches.yaml

The `watches.yaml` file tells the operator which Ansible role/playbook to run for each CR:

```yaml
---
- version: v1alpha1
  group: cache.example.com
  kind: Memcached
  role: memcached
  # Optionally use a playbook instead:
  # playbook: playbooks/memcached.yml
  
  # Optional configurations:
  # reconcilePeriod: 0s          # How often to reconcile (0 = only on changes)
  # manageStatus: true           # Let operator manage CR status
  # watchDependentResources: true # Watch resources created by this role
  # watchClusterScopedResources: false
```

### 7. Add Required Ansible Collections

**Edit `requirements.yml`:**

```yaml
---
collections:
  - name: kubernetes.core
    version: "3.0.0"
  - name: operator_sdk.util
    version: "0.5.0"
```

---

# Part 3: Building and Deploying the Operator

### 1. Build the Operator Image

Exit the container and run these commands **on your host machine**:

```bash
# Exit the container first (if inside)
exit

# Navigate to your project directory
cd ~/Documents/vishwanathj_github/k8soperators/ansibleoperator/memcached-operator

# Build the image
make docker-build IMG=memcached-operator:v0.0.1
```

### 2. Load Image into Kind (Local Clusters Only)

If you're using **Kind**, the cluster runs in its own container and cannot access images on your host:

```bash
# Load the image into Kind (replace 'vish' with your cluster name)
kind load docker-image memcached-operator:v0.0.1 --name vish

# Verify the image is loaded
docker exec -it vish-control-plane crictl images | grep memcached
```

> **Podman Users:** The `kind load docker-image` command works with Podman, but may not tag images correctly. If you see `ErrImagePull`, see the [Podman Workaround](#-podman-users-kind-image-loading-workaround) section below.

### 3. Deploy the Operator

```bash
# Deploy to the cluster
make deploy IMG=memcached-operator:v0.0.1
```

### 4. Verify the Operator

```bash
# Check the operator pod is running
kubectl get pods -n memcached-operator-system

# Expected output:
# NAME                                                    READY   STATUS    RESTARTS   AGE
# memcached-operator-controller-manager-xxxxxxxxx-xxxxx   2/2     Running   0          30s
```

If you see `ErrImagePull`, make sure you loaded the image into Kind (Step 2).

### 5. Deploy a Memcached Instance

```bash
# Apply the sample CR
kubectl apply -f config/samples/cache_v1alpha1_memcached.yaml

# Watch the memcached pods come up
kubectl get pods -w

# Check your custom resource
kubectl get memcached

# Check the created deployment
kubectl get deployment

# Check the created service
kubectl get svc
```

### 6. View Operator Logs

```bash
# Stream operator logs to see reconciliation
kubectl logs -n memcached-operator-system deployment/memcached-operator-controller-manager -c manager -f
```

### 7. Modify the CR

Test that the operator responds to changes:

```bash
# Scale up memcached replicas
kubectl patch memcached memcached-sample --type merge -p '{"spec":{"size":5}}'

# Watch the new pods appear
kubectl get pods -w
```

### 8. Cleanup

```bash
# Delete the memcached instance
kubectl delete -f config/samples/cache_v1alpha1_memcached.yaml

# Undeploy the operator
make undeploy
```

---

# Part 4: How the Ansible Operator Works

Understanding the architecture helps when troubleshooting.

## Architecture Overview

```
kubectl apply CR  →  Kubernetes API  →  ansible-operator (watches.yaml)
                                              │
                                              ▼
                                        Reads CR.spec as Ansible extra_vars
                                              │
                                              ▼
                                        Runs roles/memcached/tasks/main.yml
                                              │
                                              ▼
                                        Creates Deployment, Service, etc.
                                              │
                                              ▼
                                        Updates CR status
```

## Key Components

### 1. `watches.yaml` - The Configuration

```yaml
- group: cache.example.com
  version: v1alpha1
  kind: Memcached
  role: memcached
```

This tells the operator: *"When you see a CR of kind `Memcached`, run the Ansible role at `roles/memcached/`"*

### 2. The Ansible Operator Base Image - The Engine

The `Dockerfile` uses a pre-built base image:

```dockerfile
FROM quay.io/operator-framework/ansible-operator:v1.39.1
COPY requirements.yml ${HOME}/requirements.yml
RUN ansible-galaxy collection install -r ${HOME}/requirements.yml
COPY watches.yaml ${HOME}/watches.yaml
COPY roles/ ${HOME}/roles/
COPY playbooks/ ${HOME}/playbooks/
```

The base image handles:
- **Watching** for CR changes via Controller Runtime
- **Running** Ansible roles/playbooks with CR spec as extra_vars
- **Updating** CR status with results
- **Managing** finalizers for cleanup

### 3. Variable Mapping

| CR Field | Ansible Variable |
|----------|-----------------|
| `.metadata.name` | `ansible_operator_meta.name` |
| `.metadata.namespace` | `ansible_operator_meta.namespace` |
| `.spec.size` | `size` |
| `.spec.image` | `image` |
| Any `.spec.*` field | Same variable name |

## Ansible Role vs Playbook

| Approach | Use When |
|----------|----------|
| **Role** (`--generate-role`) | Simple CRs, single responsibility |
| **Playbook** (`--generate-playbook`) | Complex logic, multiple roles, conditionals |

Example playbook (`playbooks/memcached.yml`):

```yaml
---
- hosts: localhost
  gather_facts: false
  collections:
    - kubernetes.core
    - operator_sdk.util
  tasks:
    - name: Include memcached role
      include_role:
        name: memcached
      when: state != "absent"
    
    - name: Cleanup memcached
      include_role:
        name: memcached_cleanup
      when: state == "absent"
```

---

# Part 5: Advanced Topics

## Finalizers (Cleanup on Delete)

Ansible operators automatically add a finalizer to CRs. To run cleanup tasks when a CR is deleted:

**Add to `roles/memcached/tasks/main.yml`:**

```yaml
- name: Handle deletion
  when: ansible_operator_meta.deletionTimestamp is defined
  block:
    - name: Log deletion
      debug:
        msg: "Memcached {{ ansible_operator_meta.name }} is being deleted"
    
    # Kubernetes resources with ownerReferences are auto-deleted
    # Add any custom cleanup here (external resources, etc.)
```

## Watching Dependent Resources

To re-reconcile when resources created by the operator change:

**Edit `watches.yaml`:**

```yaml
- version: v1alpha1
  group: cache.example.com
  kind: Memcached
  role: memcached
  watchDependentResources: true
```

## Periodic Reconciliation

Force reconciliation at regular intervals:

```yaml
- version: v1alpha1
  group: cache.example.com
  kind: Memcached
  role: memcached
  reconcilePeriod: 10m  # Reconcile every 10 minutes
```

## Multiple APIs in One Operator

You can create multiple APIs (CRDs) in one operator:

```bash
# Create another API
operator-sdk create api \
  --group cache \
  --version v1alpha1 \
  --kind Redis \
  --generate-role
```

This adds a new entry to `watches.yaml` and creates `roles/redis/`.

---

## 🧐 Why These Container Flags?

| Flag | Purpose |
|------|---------|
| `--net=host` | Allows container to reach localhost clusters (Kind/Minikube) |
| `--security-opt label=disable` | Prevents SELinux "Permission Denied" errors on Fedora/RHEL |
| `-v ~/.kube/config:/root/.kube/config` | Cluster access for building and testing |
| `-v ansible-bin:/usr/local/bin` | Persists installed binaries across container restarts |
| `-v pip-cache:/root/.cache/pip` | Speeds up pip installs by caching downloads |

---

## 🐳 Podman Users: Kind Image Loading Workaround

If using **Podman**, `kind load docker-image` may fail to properly tag images. You'll see pods stuck in `ErrImagePull`.

### The Fix: Manual Retag

```bash
# 1. Load the image
kind load docker-image memcached-operator:v0.0.1 --name <cluster-name>

# 2. Check how it was imported
docker exec -it <cluster-name>-control-plane crictl images | grep memcached

# 3. Create the alias Kubernetes expects
docker exec -it <cluster-name>-control-plane ctr --namespace=k8s.io images tag \
  localhost/memcached-operator:v0.0.1 \
  docker.io/library/memcached-operator:v0.0.1

# 4. Restart deployment
kubectl rollout restart deployment/memcached-operator-controller-manager -n memcached-operator-system
```

---

## 🔧 Troubleshooting

### Common Errors and Fixes

| Error | Cause | Fix |
|-------|-------|-----|
| `ErrImagePull` | Image not in Kind cluster | Load with `kind load`, retag for Podman |
| `ansible-runner: not found` | Missing Python packages | Ensure `ansible-runner` is in `requirements.txt` |
| `kubernetes.core collection not found` | Missing Galaxy collection | Check `requirements.yml` includes `kubernetes.core` |
| `RBAC forbidden` | Missing permissions | Add required permissions to `config/rbac/role.yaml` |
| `CRD not found` | CRD not installed | Run `make install` before `make deploy` |
| `cannot unmarshal string into int32` | Integer fields (like `replicas`) passed as strings | Use template file with `lookup('template', ...) \| from_yaml` |
| `services is forbidden` | RBAC missing services permission | Add `services` to the role's resources list |
| `PLAY RECAP` shows nothing | Empty role tasks file | Ensure `roles/<name>/tasks/main.yml` has actual tasks |
| `Spec was not found for CR` | CR applied with empty/null spec | Delete and re-apply the CR with valid spec fields |

### Check Operator Logs

```bash
# Ansible operator has two containers: manager and kube-rbac-proxy
kubectl logs -n memcached-operator-system deployment/memcached-operator-controller-manager -c manager --tail=100

# For Ansible-specific debugging, check the ansible logs
kubectl logs -n memcached-operator-system deployment/memcached-operator-controller-manager -c manager | grep -A 20 "TASK"
```

### Debug Mode

Run the operator locally for easier debugging:

```bash
# Install CRD first
make install

# Run operator locally (not in cluster)
make run

# In another terminal, apply a CR
kubectl apply -f config/samples/cache_v1alpha1_memcached.yaml
```

---

## 🧹 Clean Start Procedure

> **⚠️ Important:** When rebuilding the operator image, **always delete the old image from Kind first** before loading the new one. Kind may cache images and use stale versions even after rebuilding locally.

### Option 1: Clean Images Only

```bash
# Undeploy operator
make undeploy

# IMPORTANT: Delete images from Kind BEFORE loading new ones
docker exec -it <cluster-name>-control-plane crictl rmi \
  $(docker exec <cluster-name>-control-plane crictl images | grep memcached | awk '{print $3}') 2>/dev/null || true

# Rebuild without cache to ensure changes are included
docker build --no-cache -t memcached-operator:v0.0.1 .

# Load fresh image into Kind
kind load docker-image memcached-operator:v0.0.1 --name <cluster-name>

# Retag for Podman users
docker exec -it <cluster-name>-control-plane ctr --namespace=k8s.io images tag \
  localhost/memcached-operator:v0.0.1 \
  docker.io/library/memcached-operator:v0.0.1

# Redeploy
make deploy IMG=memcached-operator:v0.0.1
```

### Option 2: Start Fresh Project

```bash
cd ..
rm -rf memcached-operator
mkdir memcached-operator && cd memcached-operator
operator-sdk init --plugins=ansible --domain=example.com
# ... continue from step 3
```

---

## 📖 References

| Resource | URL |
|----------|-----|
| **Ansible Operator Tutorial** | https://sdk.operatorframework.io/docs/building-operators/ansible/tutorial/ |
| **Ansible Operator Reference** | https://sdk.operatorframework.io/docs/building-operators/ansible/reference/ |
| **Operator SDK Documentation** | https://sdk.operatorframework.io/docs/ |
| **kubernetes.core Collection** | https://galaxy.ansible.com/kubernetes/core |
| **Ansible Documentation** | https://docs.ansible.com/ |

### Base Image Details

| Component | Details |
|-----------|---------|
| **Image** | `quay.io/operator-framework/ansible-operator:v1.39.1` |
| **Source Code** | [operator-sdk/images/ansible-operator](https://github.com/operator-framework/operator-sdk/tree/master/images/ansible-operator) |
| **Architectures** | `amd64`, `arm64`, `ppc64le`, `s390x` |
| **Python Version** | 3.9+ |
| **Ansible Version** | Bundled with operator image |
