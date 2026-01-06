# Containerized Development Guide (Helm & Go)

This guide details how to run **Helm v3** and **Golang + Operator SDK** using containers instead of installing binaries directly on your host machine. It is configured to work seamlessly with **Podman**, **SELinux**, and local **Kubernetes clusters** (like Kind, Minikube, or OpenShift Local).

## Prerequisites

* **Container Engine:** Podman (recommended) or Docker.
* **Kubernetes Config:** A valid `kubeconfig` file (usually at `~/.kube/config`).

---

# Part 1: Helm v3

## 🚀 Quick Start (One-Off Command)
Run the following command to verify your Helm version. This mounts your local kubeconfig and network stack so Helm can see your cluster.

```bash
docker run --rm -it \
  --net=host \
  --security-opt label=disable \
  -v ~/.kube/config:/root/.kube/config \
  -v $(pwd):/apps \
  alpine/helm:3.16.4 version
```

## 📦 Interactive / Background Mode
If you want a persistent container (so you can exec in and out of it without it deleting itself), use this command.

### 1. Start the Container
Note: We use `--security-opt label=disable` to prevent SELinux errors on home directories.

```bash
docker run -itd \
  --name helm-box \
  --net=host \
  --entrypoint /bin/sh \
  --security-opt label=disable \
  -v ~/.kube/config:/root/.kube/config \
  -v $(pwd):/apps \
  alpine/helm:3.16.4
```

### 2. Enter the Shell

```bash
docker exec -it helm-box sh
```

### 3. Cleanup

```bash
docker rm -f helm-box
```

## 🛠️ Setup: Create an Alias
Add this to your `~/.bashrc` or `~/.zshrc` to make helm feel like a native command:

```bash
alias helm='docker run --rm -it --net=host --security-opt label=disable -v ~/.kube/config:/root/.kube/config -v $(pwd):/apps alpine/helm:3.16.4'
```

---

# Part 2: Golang & Operator SDK Environment

This setup provides a persistent Golang environment with module caching (so you don't re-download deps on every restart) and the Operator SDK installed.

### 1. Start the Golang Container
Run this in the root of your project. It maps the current folder to `/app` and your kubeconfig for cluster access.

```bash
docker run -itd \
  --name go-dev \
  --net=host \
  --security-opt label=disable \
  -v $(pwd):/app \
  -v ~/.kube/config:/root/.kube/config \
  -w /app \
  -e GOCACHE=/go/.cache \
  -v go-modules:/go/pkg \
  -v go-bin:/usr/local/bin \
  golang:1.25
```

> **Note:** 
> - The kubeconfig mount (`-v ~/.kube/config:/root/.kube/config`) allows `operator-sdk init` to generate optimized RBAC rules by inspecting your cluster.
> - The `go-bin` volume (`-v go-bin:/usr/local/bin`) persists installed binaries (`helm`, `operator-sdk`) across container restarts.

### 2. Install Helm & Operator SDK (Inside Container)
The golang image does not come with `helm` or `operator-sdk`. You must install both binaries once after creating the container.

Enter the container:

```bash
docker exec -it go-dev bash
```

**Install Helm:**

```bash
# Install Helm using the official script
curl -fsSL https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash

# Verify
helm version
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

### ⚠️ Binary Persistence (Helm & Operator SDK)

**Important:** Both `helm` and `operator-sdk` are installed inside the container's filesystem at `/usr/local/bin/`. This location is **not** on a persistent volume, which means:

| Action | Binaries Status |
|--------|-----------------|
| `docker stop go-dev` → `docker start go-dev` | ✅ Binaries survive |
| `docker rm go-dev` → `docker run ...` (recreate) | ❌ Binaries are lost, reinstall required |

Choose one of the following options based on your preference:

---

#### Option 1: Persistent Volume for Binaries (Recommended)

Add an additional volume mount to persist `/usr/local/bin`. This keeps binaries across container recreation without installing anything on your host.

```bash
docker run -itd \
  --name go-dev \
  --net=host \
  --security-opt label=disable \
  -v $(pwd):/app \
  -v ~/.kube/config:/root/.kube/config \
  -w /app \
  -e GOCACHE=/go/.cache \
  -v go-modules:/go/pkg \
  -v go-bin:/usr/local/bin \
  golang:1.25
```

> **Note:** The first time you use this, you'll still need to install `helm` and `operator-sdk` once. After that, they persist in the `go-bin` volume even if you remove and recreate the container.
>
> ⚠️ Running `docker system prune --volumes` or `docker volume rm go-bin` will delete the volume and require reinstallation of both tools.

**Auto-Install Enhancement:** To automatically install both tools if missing, create an entrypoint script:

**entrypoint.sh** (save this in your project directory):

```bash
#!/bin/bash
set -e

# Auto-install Helm if not present
if ! command -v helm &> /dev/null; then
    echo "⚙️  helm not found. Installing..."
    curl -fsSL https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash
    echo "✅ helm installed successfully!"
else
    echo "✅ helm already installed: $(helm version --short)"
fi

# Auto-install operator-sdk if not present
if ! command -v operator-sdk &> /dev/null; then
    echo "⚙️  operator-sdk not found. Installing..."
    ARCH=amd64
    OS=linux
    VER=v1.39.1
    curl -sLO "https://github.com/operator-framework/operator-sdk/releases/download/${VER}/operator-sdk_${OS}_${ARCH}"
    chmod +x operator-sdk_${OS}_${ARCH}
    mv operator-sdk_${OS}_${ARCH} /usr/local/bin/operator-sdk
    echo "✅ operator-sdk ${VER} installed successfully!"
else
    echo "✅ operator-sdk already installed: $(operator-sdk version | head -1)"
fi

# Execute the passed command or start bash
exec "${@:-bash}"
```

Make it executable and run the container with the custom entrypoint:

```bash
# Make the script executable (one-time)
chmod +x entrypoint.sh

# Run container with auto-install entrypoint
docker run -itd \
  --name go-dev \
  --net=host \
  --security-opt label=disable \
  -v $(pwd):/app \
  -v ~/.kube/config:/root/.kube/config \
  -w /app \
  -e GOCACHE=/go/.cache \
  -v go-modules:/go/pkg \
  -v go-bin:/usr/local/bin \
  -v $(pwd)/entrypoint.sh:/entrypoint.sh:ro \
  --entrypoint /entrypoint.sh \
  golang:1.25
```

Now every time the container starts, it will automatically check for and install `helm` and `operator-sdk` if missing.

---

#### Option 2: Build a Custom Image

Create a `Dockerfile` with `helm` and `operator-sdk` pre-installed. This is cleaner but requires you to maintain and rebuild the image when updating versions.

**Dockerfile:**

```dockerfile
FROM golang:1.25

# Install Helm
RUN curl -fsSL https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash

# Install Operator SDK
ARG ARCH=amd64
ARG OS=linux
ARG VER=v1.39.1

RUN curl -LO "https://github.com/operator-framework/operator-sdk/releases/download/${VER}/operator-sdk_${OS}_${ARCH}" \
    && chmod +x operator-sdk_${OS}_${ARCH} \
    && mv operator-sdk_${OS}_${ARCH} /usr/local/bin/operator-sdk

# Verify installations
RUN helm version --short && operator-sdk version
```

**Build and run:**

```bash
# Build the custom image
docker build -t go-helm-operator-sdk:1.25 .

# Run using your custom image
docker run -itd \
  --name go-dev \
  --net=host \
  --security-opt label=disable \
  -v $(pwd):/app \
  -v ~/.kube/config:/root/.kube/config \
  -w /app \
  -e GOCACHE=/go/.cache \
  -v go-modules:/go/pkg \
  go-helm-operator-sdk:1.25
```

---

#### Option 3: Avoid Removing the Container

Simply use `docker stop` and `docker start` instead of `docker rm`. The container's filesystem (including installed binaries) persists as long as the container exists.

```bash
# Stop the container (preserves filesystem)
docker stop go-dev

# Start it again later
docker start go-dev

# Re-enter the shell
docker exec -it go-dev bash
```

> **Caveat:** If you accidentally run `docker rm go-dev` or `docker system prune`, you'll lose the binary and need to reinstall.

---

# Part 3: Building a Helm Operator (Nginx Example)

Follow these steps to scaffold a new Operator using a Helm chart.

### 1. Create Project Directory
Inside the container (`docker exec -it go-dev bash`), create a new folder for your operator.

```bash
mkdir nginx-operator
cd nginx-operator
```

### 2. Create a Helm Chart

```bash
# Create a simple nginx chart (recommended)
helm create nginx

# Verify it was created
ls nginx/
# Should show: Chart.yaml  charts  templates  values.yaml
```

**What `helm create` generates:**

| File/Folder | Purpose |
|-------------|---------|
| `Chart.yaml` | Chart metadata (name, version, description) |
| `values.yaml` | Default configuration values |
| `templates/` | Kubernetes manifest templates |
| `templates/deployment.yaml` | Deployment for nginx pods |
| `templates/service.yaml` | Service to expose the deployment |
| `templates/serviceaccount.yaml` | ServiceAccount for the pods |
| `templates/ingress.yaml` | Optional Ingress resource |
| `templates/hpa.yaml` | Optional HorizontalPodAutoscaler |
| `templates/_helpers.tpl` | Reusable template helpers |
| `templates/NOTES.txt` | Post-install instructions shown to users |
| `charts/` | Subcharts/dependencies (empty initially) |

The generated chart is a working nginx deployment out of the box—no modifications needed.

### 3. Initialize the Operator

```bash
operator-sdk init --plugins=helm \
  --domain=example.com \
  --group=web \
  --version=v1alpha1 \
  --kind=Nginx \
  --helm-chart=./nginx
```

**What this command does:**

| Flag | Purpose |
|------|---------|
| `--plugins=helm` | Creates a Helm-based operator (vs Go or Ansible) |
| `--domain=example.com` | Your organization's domain for the API group |
| `--group=web` | API group name → results in `web.example.com` |
| `--version=v1alpha1` | API version (alpha/beta/stable) |
| `--kind=Nginx` | The Custom Resource type name (`kubectl get nginx`) |
| `--helm-chart=./nginx` | Path to the Helm chart to use |

This scaffolds a complete operator project including:
- **Dockerfile** - Build the operator image
- **Makefile** - Build, deploy, and test commands
- **config/crd/** - Custom Resource Definition
- **config/rbac/** - RBAC permissions
- **config/samples/** - Example CR to test with
- **helm-charts/** - Your Helm chart (copied here)

You should see:
```
INFO[0000] Writing kustomize manifests for you to edit...
Created helm-charts/nginx
Generating RBAC rules
```

### 4. Simplify the Sample CR (Important!)

The auto-generated sample CR at `config/samples/web_v1alpha1_nginx.yaml` contains **all** values from `values.yaml`, including many empty objects (`{}`) and arrays (`[]`). This can cause YAML parsing errors when the operator renders the Helm templates.

**Replace it with a minimal CR:**

```bash
cat > config/samples/web_v1alpha1_nginx.yaml << 'EOF'
apiVersion: web.example.com/v1alpha1
kind: Nginx
metadata:
  name: nginx-sample
spec:
  # Minimal spec - most values use chart defaults
  replicaCount: 1
  
  image:
    repository: nginx
    pullPolicy: IfNotPresent
    # tag defaults to Chart.appVersion (1.16.0)
  
  service:
    type: ClusterIP
    port: 80
EOF
```

> **Why?** The CR's `.spec` is passed as Helm values. Only specify values you want to override — the chart's `values.yaml` provides sensible defaults for everything else.

That's it! Your operator is scaffolded and ready to build.

---

### How the Helm Operator Works

Understanding the architecture helps when troubleshooting. A Helm operator has **no custom Go code** — it relies on two components:

#### 1. `watches.yaml` - The Configuration

```yaml
- group: web.example.com
  version: v1alpha1
  kind: Nginx
  chart: helm-charts/nginx
```

This tells the operator: *"When you see a CR of kind `Nginx` in API group `web.example.com/v1alpha1`, deploy the Helm chart at `helm-charts/nginx`"*

#### 2. The Helm Operator Base Image - The Engine

The `Dockerfile` uses a pre-built base image that contains all the reconciliation logic:

```dockerfile
FROM quay.io/operator-framework/helm-operator:v1.39.1
COPY watches.yaml ${HOME}/watches.yaml
COPY helm-charts  ${HOME}/helm-charts
```

The base image handles:
- **Watching** for CR changes via Controller Runtime
- **Rendering** Helm charts with CR spec values
- **Installing/Upgrading/Deleting** releases automatically
- **Updating** CR status with results

#### The Flow

```
kubectl apply CR  →  Kubernetes API  →  helm-operator (watches.yaml)
                                              │
                                              ▼
                                        Reads CR.spec as Helm values
                                              │
                                              ▼
                                        Renders helm-charts/nginx/
                                              │
                                              ▼
                                        Creates Deployment, Service, etc.
```

**Key insight:** The CR's `.spec` field becomes the Helm `values.yaml` override. Any field you put in the CR spec gets passed to the chart templates.

---

### Advanced: Using Bitnami Charts

> ⚠️ **Warning:** Bitnami charts have OCI-based dependencies that cause operator-sdk to crash. Only use this if you specifically need Bitnami chart features. The simple chart above is recommended for learning and most use cases.

<details>
<summary>Click to expand Bitnami chart instructions</summary>

#### Known Issues with Bitnami Charts

| Issue | Description |
|-------|-------------|
| OCI dependency crash | operator-sdk crashes with nil pointer when resolving OCI deps |
| Registry authentication | Requires Docker Hub login |
| Version compatibility | Latest versions may have unpublished dependencies |
| RBAC complexity | Requires additional permissions for NetworkPolicy, PDB, etc. |

#### Workaround Steps

```bash
# 1. Login to Docker Hub (required)
helm registry login registry-1.docker.io

# 2. Add Bitnami repo
helm repo add bitnami https://charts.bitnami.com/bitnami
helm repo update

# 3. Pull specific version (18.1.0 works reliably)
helm pull bitnami/nginx --version 18.1.0 --untar

# 4. Build dependencies
cd nginx
helm dependency build
cd ..

# 5. CRITICAL: Comment out dependencies in Chart.yaml to prevent operator-sdk crash
sed -i 's/^dependencies:/#dependencies:/' nginx/Chart.yaml
sed -i 's/^- name: common/#- name: common/' nginx/Chart.yaml
sed -i 's/^  repository:/#  repository:/' nginx/Chart.yaml
sed -i 's/^  tags:/#  tags:/' nginx/Chart.yaml
sed -i 's/^  - bitnami-common/#  - bitnami-common/' nginx/Chart.yaml
sed -i 's/^  version: 2.x.x/#  version: 2.x.x/' nginx/Chart.yaml

# 6. Now initialize (this will work)
operator-sdk init --plugins=helm \
  --domain=example.com \
  --group=web \
  --version=v1alpha1 \
  --kind=Nginx \
  --helm-chart=./nginx
```

#### Why Comment Out Dependencies?

Even after running `helm dependency build`, operator-sdk still tries to re-resolve OCI dependencies and crashes because its registry client is nil (a bug in operator-sdk). Since the dependencies are already downloaded in `nginx/charts/`, commenting them out in `Chart.yaml` prevents this crash while keeping the chart functional.

#### Additional RBAC Permissions

Bitnami charts may require additional RBAC permissions. Add these to `config/rbac/role.yaml` if you encounter permission errors:

```yaml
# Networking
- apiGroups: ["networking.k8s.io"]
  resources: ["networkpolicies", "ingresses"]
  verbs: ["*"]

# Policy
- apiGroups: ["policy"]
  resources: ["poddisruptionbudgets"]
  verbs: ["*"]

# Autoscaling
- apiGroups: ["autoscaling"]
  resources: ["horizontalpodautoscalers"]
  verbs: ["*"]
```

</details>

---

### 5. Build the Operator Image

Exit the container and run these commands **on your host machine** (not inside the go-dev container):

```bash
# Exit the container first (if inside)
exit

# Navigate to your project directory
cd ~/helm/k8soperators/helmoperator/nginx-operator

# Build the image
make docker-build IMG=nginx-operator:v0.0.1
```

### 6. Load Image into Kind (Local Clusters Only)

If you're using **Kind**, the cluster runs in its own container and cannot access images on your host. You must load the image **before deploying**:

```bash
# Load the image into Kind (replace 'vish' with your cluster name)
kind load docker-image nginx-operator:v0.0.1 --name vish

# Verify the image is loaded
docker exec -it vish-control-plane crictl images | grep nginx
```

> **Note:** Skip this step if you're pushing to a remote registry that your cluster can access.

### 7. Deploy the Operator

```bash
# Deploy to the cluster
make deploy IMG=nginx-operator:v0.0.1
```

### 8. Verify the Operator

```bash
# Check the operator pod is running
# Note: Replace <project-name> with your project directory name (e.g., nginx-operator)
kubectl get pods -n <project-name>-system

# Expected output:
# NAME                                                   READY   STATUS    RESTARTS   AGE
# <project-name>-controller-manager-xxxxxxxxx-xxxxx     1/1     Running   0          30s
```

If you see `ErrImagePull`, make sure you loaded the image into Kind (Step 6).

### 9. Deploy an Nginx Instance

Create a Custom Resource (CR) to test your operator:

```bash
# View the sample CR
cat config/samples/web_v1alpha1_nginx.yaml

# Apply it to create an nginx instance
kubectl apply -f config/samples/web_v1alpha1_nginx.yaml

# Watch the nginx pods come up
kubectl get pods -w

# Check your custom resource
kubectl get nginx
```

### 10. View Operator Logs

```bash
# Stream operator logs to see it reconciling
# Note: Replace <project-name> with your project directory name (e.g., nginx-operator)
kubectl logs -n <project-name>-system deployment/<project-name>-controller-manager -f

# Example for nginx-operator:
kubectl logs -n nginx-operator-system deployment/nginx-operator-controller-manager -f
```

### 11. Cleanup

```bash
# Delete the nginx instance
kubectl delete -f config/samples/web_v1alpha1_nginx.yaml

# Undeploy the operator
make undeploy
```

---

## 🧐 Why these flags?

| Flag | Purpose |
|------|---------|
| `--net=host` | Crucial. Allows the container to share your laptop's network. Fixes connection refused errors to localhost clusters. |
| `--security-opt label=disable` | SELinux Fix. Prevents "Permission Denied" errors on Fedora/RHEL/CentOS without needing dangerous `:Z` relabeling on home dirs. |
| `-v ~/.kube/config:/root/.kube/config` | Cluster Access. Allows `operator-sdk init` to generate optimized RBAC rules by inspecting your Kubernetes cluster. |
| `-v go-modules:/go/pkg` | Caching. Creates a persistent volume for Go modules so builds are instant after restarts. |
| `-v go-bin:/usr/local/bin` | Binary Persistence (Option 1). Keeps installed tools like `helm` and `operator-sdk` across container recreation. |

---

## 🐳 Podman Users: Kind Image Loading Workaround

If you're using **Podman** instead of Docker, `kind load docker-image` may fail to properly tag images. You'll see:

```
enabling experimental podman provider
Image with ID: xxx already present on node but is missing the tag...
```

And your pods will show `ErrImagePull` or `ImagePullBackOff`.

### Why This Happens

| What Podman Does | What Kubernetes Expects |
|------------------|------------------------|
| Stores as `localhost/nginx-operator:v0.0.3` | Looks for `docker.io/library/nginx-operator:v0.0.3` |

Kind's podman support is **experimental** and doesn't always retag images correctly.

### The Fix: Manual Retag

After `kind load`, manually create the correct tag inside Kind:

```bash
# 1. Load the image (may show warnings - that's OK)
kind load docker-image nginx-operator:v0.0.3 --name <cluster-name>

# 2. Check how it was imported
docker exec -it <cluster-name>-control-plane crictl images | grep nginx-operator
# You'll likely see: localhost/nginx-operator:v0.0.3

# 3. Create the alias Kubernetes expects
docker exec -it <cluster-name>-control-plane ctr --namespace=k8s.io images tag \
  localhost/nginx-operator:v0.0.3 \
  docker.io/library/nginx-operator:v0.0.3

# 4. Verify both tags exist
docker exec -it <cluster-name>-control-plane crictl images | grep nginx-operator
# Should show both localhost/... and docker.io/library/...

# 5. Restart deployment to pick up the image
kubectl rollout restart deployment/<project-name>-controller-manager -n <project-name>-system
```

---

## 🔧 Troubleshooting

### Common Errors and Fixes

| Error | Cause | Fix |
|-------|-------|-----|
| `ErrImagePull` / `ImagePullBackOff` | Image not in Kind cluster, or wrong tag | Load image with `kind load`, then retag for Podman users (see above) |
| `YAML parse error on deployment.yaml` | Sample CR has complex/empty values (`{}`, `[]`) | Simplify the CR to only essential values (see Step 4) |
| `networkpolicies is forbidden` | Old chart with NetworkPolicy baked into image | Rebuild operator with fresh `helm create` chart |
| `nil pointer dereference` during `operator-sdk init` | Bitnami chart OCI dependencies issue | Use simple chart (`helm create`) instead, or see Advanced section |
| `already initialized` | Previous failed `operator-sdk init` left files | Remove `PROJECT`, `Makefile`, `config/`, `helm-charts/` and retry |
| Operator running but no nginx pod | Check operator logs for errors | `kubectl logs -n <ns> deployment/<name> --tail=50` |

### Check Operator Logs

Always check logs when things don't work:

```bash
kubectl logs -n nginx-operator-system deployment/nginx-operator-controller-manager --tail=50
```

### Verify Image is in Kind

```bash
# List images in Kind cluster
docker exec -it <cluster-name>-control-plane crictl images | grep nginx-operator

# Should show your operator image with correct tag
```

---

## 🧹 Clean Start Procedure

When troubleshooting gets messy, here's how to start fresh:

### Option 1: Clean Images Only (Quick)

Use when: Image tagging issues, wrong chart baked into image

```bash
# 1. Undeploy operator
make undeploy

# 2. Delete operator images from Kind
docker exec -it <cluster-name>-control-plane crictl rmi \
  $(docker exec <cluster-name>-control-plane crictl images | grep nginx-operator | awk '{print $3}') 2>/dev/null || true

# 3. Delete local project and start fresh
cd ..
rm -rf nginx-operator
mkdir nginx-operator && cd nginx-operator

# 4. Rebuild from scratch (helm create, operator-sdk init, etc.)
```

### Option 2: Delete Kind Cluster (Nuclear)

Use when: Many stale resources, persistent weird behavior, or cluster corruption

```bash
# Delete the cluster
kind delete cluster --name <cluster-name>

# Recreate
kind create cluster --name <cluster-name>

# Reload all needed images
kind load docker-image nginx-operator:v0.0.3 --name <cluster-name>
# ... and retag if using Podman
```

### When to Use Which

| Situation | Recommended Action |
|-----------|-------------------|
| `ErrImagePull` after rebuild | Clean images (Option 1) |
| RBAC errors from old deployment | `make undeploy` + redeploy |
| Wrong chart in operator image | Clean images + rebuild project |
| Unexplained cluster behavior | Delete Kind cluster (Option 2) |
| Testing from absolute scratch | Delete Kind cluster (Option 2) |

---

## 📖 References

| Resource | URL |
|----------|-----|
| **Helm Operator Tutorial** | https://sdk.operatorframework.io/docs/building-operators/helm/tutorial/ |
| **Operator SDK Documentation** | https://sdk.operatorframework.io/docs/ |
| **Helm Operator Advanced Features** | https://sdk.operatorframework.io/docs/building-operators/helm/reference/ |
| **Operator SDK GitHub** | https://github.com/operator-framework/operator-sdk |
| **Helm Documentation** | https://helm.sh/docs/ |

### Base Image Details

The Helm operator uses a pre-built base image that handles all reconciliation logic:

| Component | Details |
|-----------|---------|
| **Image** | `quay.io/operator-framework/helm-operator:v1.39.1` |
| **Source Code** | [operator-sdk/images/helm-operator](https://github.com/operator-framework/operator-sdk/tree/master/images/helm-operator) |
| **Architectures** | `amd64`, `arm64`, `ppc64le`, `s390x` |
| **Reconciler Logic** | [internal/helm/controller/reconciler.go](https://github.com/operator-framework/operator-sdk/blob/master/internal/helm/controller/reconciler.go) |
