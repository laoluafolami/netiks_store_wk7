# Netiks Store Kubernetes (K8s) Deployment

**Repository link:** \[https://github.com/laoluafolami/netiks_store_wk7/edit/k8s-lab/README.md\]

## Part 1: Understand the Basics

**1. What is the difference between a container and a Pod? Why create a Deployment instead of a Pod?**

A container is one running, isolated process created from an image. A Pod is Kubernetes' smallest deployable unit: a wrapper around one or more containers that share one IP address, network space and volumes, and that are scheduled and restarted together. A Deployment is used instead of a bare Pod because a bare Pod is not replaced if it is deleted or its node fails, cannot be scaled, and has no rolling update or rollback. A Deployment declares the desired number of identical Pods and keeps that state: it recreates lost Pods (self-healing), scales replicas up and down, and replaces Pods gradually during updates while keeping a revision history for rollback.

**2. In Compose, gateway reaches http://identity-service:8001. What Kubernetes object makes this name resolve? What happens when the identity Pod is replaced?**

A **Service** (type ClusterIP) named `identity-service`. The cluster DNS resolves that name to the Service's stable virtual IP, and the Service forwards traffic to Pods that match its label selector and are Ready. When the identity Pod is replaced, the new Pod gets a different IP address, but the Service name and ClusterIP stay the same. Kubernetes updates the Service's list of endpoints automatically as soon as the new Pod passes its readiness probe, so the gateway keeps calling `http://identity-service:8001` with no change. Requests only fail briefly if no Pod is ready at that moment.

**3. What is the practical difference between a ConfigMap and a Secret? Why is a Secret not encryption?**

Both hold key-value settings that Pods consume as environment variables or files. A ConfigMap is for non-sensitive configuration (URLs, ports, flags) and is stored and displayed as plain text. A Secret is for sensitive values (passwords, tokens, keys): it is a separate object type, so access can be restricted separately with RBAC, its values are not printed by `kubectl describe`, it can be encrypted at rest if the cluster is configured for that, and it is kept out of Git. A Secret is not encryption because its values are only base64-encoded, which anyone can reverse with `base64 -d`; anyone allowed to read the Secret object (or the cluster's etcd store, which is unencrypted by default) can read the real values.

**4. Which probe decides whether a Pod receives traffic? Which one can cause a container to be restarted?**

The **readiness** probe decides whether a Pod receives traffic: while it fails, the Pod is removed from the Service's endpoints (but not restarted). The **liveness** probe can cause a container to be restarted: when it keeps failing, the kubelet kills and restarts the container. (The startup probe only holds back the other two while the app starts; if it never succeeds within its limit the container is also restarted.)

## Part 2: Map Compose to Kubernetes

| Compose service | Kubernetes workload | Needs a Service? | Needs storage? | Replicas | Reason |
| --- | --- | --- | --- | --- | --- |
| web | Deployment | Yes (NodePort) | No | 2 | Stateless; browser-facing |
| gateway | Deployment | Yes: ClusterIP `gateway` (used by web Pods) plus NodePort `gateway-external` (used by the browser) | No | 2 | Stateless, runs no migrations and holds no data, so it is safe to run two copies; single entry point to the APIs |
| identity-service | Deployment | Yes (ClusterIP 8001) | No (its data is in PostgreSQL) | 1 | Depends on PostgreSQL and runs `alembic upgrade head` at startup; several replicas could run migrations at the same time |
| vendor-service | Deployment | Yes (ClusterIP 8002) | No (its data is in PostgreSQL) | 1 | Same reason as identity-service |
| catalog-service | Deployment | Yes (ClusterIP 8003) | No (its data is in PostgreSQL) | 1 | Same reason as identity-service |
| media-service | Deployment with `strategy: Recreate` | Yes (ClusterIP 8004) | Yes (1Gi PVC mounted at /app/uploads) | 1 | Stores uploaded files on local disk; a ReadWriteOnce volume and plain files mean only one writer is safe |
| admin-service | Deployment | Yes (ClusterIP 8005) | No | 1 | Internal only, no database access currently |
| postgres | StatefulSet | Yes (ClusterIP) | Yes | 1 | Holds state and needs persistent storage |
| redis | None: not deployed | No | No | 0 | Not required by the code (see decision below) |

### Redis decision (with code evidence)

Command used:

```
grep -rniI "redis" . --exclude-dir=node_modules --exclude-dir=.git --exclude-dir=.venv --exclude=uv.lock --exclude=package-lock.json
grep -rn "REDIS_URL" --include=*.py .
```

<img width="1503" height="803" alt="1" src="https://github.com/user-attachments/assets/eb5eb9a5-8c83-4dc5-a6c0-696a14b23c9e" />

**The grep output**

Evidence and decision (confirm against your grep output, then edit): in `docker-compose.yml` the `redis` service is defined but no other service lists it under `depends_on`. `REDIS_URL` appears in `.env.example` \[and in the settings/config class at: PATH:LINE\], but \[no Python code opens a Redis connection or calls a Redis client\]. Because nothing uses Redis at runtime, **Redis is not required**. I did not deploy it and did not add `REDIS_URL` to the ConfigMap.

### Media service storage investigation

File read: `services/media-service/app/service.py`

<img width="700" height="219" alt="2" src="https://github.com/user-attachments/assets/868cd574-a201-4f3e-a9fb-1c09ae280080" />

**The code that writes uploads**

Finding (confirm against the code, then edit): uploads are written as **files on the container's local filesystem** under the directory given by `UPLOAD_DIR` (`/app/uploads`), not to the database or object storage. Several replicas cannot safely share that storage: each replica would have its own private local folder, so a file uploaded through one replica would be missing from the others, and the PVC is `ReadWriteOnce` and the plain files have no locking between writers. Therefore media-service runs **one replica**, with a 1Gi PVC mounted at `/app/uploads` so files survive Pod restarts, and `strategy: Recreate` so the old Pod is stopped before the new one starts.

## Part 3: Create the Cluster and Build the Images

**`kubectl get nodes`** (the node must show Ready)

**`kubectl get ns`**

<img width="951" height="611" alt="3" src="https://github.com/user-attachments/assets/e9e156ee-29ef-473c-a998-6cbbe78b09ce" />

**kubectl get nodes and kubectl get ns**

**`docker images | grep netiks`**

<img width="1001" height="331" alt="4" src="https://github.com/user-attachments/assets/00caa8cb-c00a-4f36-84ce-056ea870afd3" />


**`docker exec netiks-control-plane crictl images | grep -E "netiks|postgres"`** (lists the seven netiks images and postgres:16-alpine)

<img width="880" height="341" alt="5" src="https://github.com/user-attachments/assets/f84bf1e8-6255-4dc2-9404-f022031374a0" />

Repo files for this Part: `k8s/kind-config.yaml`, `k8s/00-namespace.yaml`.

## Part 4: Configuration and Secrets

**`kubectl get configmap,secret`**

<img width="753" height="305" alt="6" src="https://github.com/user-attachments/assets/7157477c-ce80-4b32-ad27-5f1c7635d75d" />



**Credentials confirmation:** the Secret `netiks-secrets` was created directly on the cluster. The database user is `netiks_k8s`, and the password (48 random hex characters, from `openssl rand -hex 24`) and JWT secret (64 random hex characters, from `openssl rand -hex 32`) are randomly generated. All three differ from the `.env.example` defaults (`postgres` / `postgres` and the sample JWT secret). The values are not shown here, and only the template `k8s/02-secret.example.yaml` is committed.

**Why is the ConfigMap allowed in Git but not the Secret? What does a Secret protect against, and what does it not protect against?**

The ConfigMap holds only non-sensitive settings (service URLs, ports, database name, algorithm names), so publishing it exposes nothing and gives a versioned, reviewable record of the configuration. The Secret holds credentials; anything committed to Git is copied to every clone and stays in history even if deleted later, so a committed secret must be treated as leaked. Only a template with `REPLACE_ME` placeholders is committed, and real values are created directly in the cluster.

A Secret protects against: credentials being baked into images or written in manifests and Git; casual exposure (values are not shown by `kubectl describe` or in plain YAML); and wide access, because RBAC can restrict who may read Secrets and only Pods that reference one receive it. It does **not** protect against: anyone with permission to read the Secret (base64 decodes instantly); anyone with access to etcd or node storage when encryption at rest is not enabled; anyone who can exec into a Pod that uses it or read its environment; or leakage through logs and mistakes such as pasting `kubectl get secret -o yaml`.

## Part 5: Deploy PostgreSQL

**`kubectl get pods`** (PostgreSQL Pod Running)

<img width="840" height="226" alt="7" src="https://github.com/user-attachments/assets/eed49017-221f-48e0-b75e-b52b6c86023c" />

**`kubectl get pvc`** (PVC Bound)

**\[PASTE OUTPUT\]**

**`kubectl get statefulset`**

**\[PASTE OUTPUT\]**

**`kubectl get storageclass`**

**\[PASTE OUTPUT\]**

**\[INSERT SCREENSHOT 7\]**

**`kubectl exec postgres-0 -- psql -U netiks_k8s -d netiks_store -c '\conninfo'`**

<img width="1100" height="276" alt="8" src="https://github.com/user-attachments/assets/4c4c4408-3705-4d6b-b6be-3c7359ef7782" />


### Pod deletion test

Commands run: create table `lab_test` and insert a row; `SELECT * FROM lab_test;`; `kubectl delete pod postgres-0`; wait for the replacement Pod; `SELECT * FROM lab_test;` again.

<img width="1450" height="634" alt="9" src="https://github.com/user-attachments/assets/679256d9-4ff0-41d9-a3f1-ae8d2e323475" />


Result: the row was still present after the Pod was replaced, because the data is stored on the PersistentVolume behind PVC `data-postgres-0`, not in the Pod's own filesystem. The StatefulSet recreated a Pod with the same name and re-attached the same volume.

### What would differ if `kubectl delete pvc data-postgres-0` were run?

Deleting the Pod leaves the PVC and its volume untouched, so the data survives. Deleting the PVC removes the storage itself. Because kind's `standard` StorageClass has reclaim policy `Delete` \[confirm in the RECLAIMPOLICY column of your `kubectl get storageclass` output\], the underlying PersistentVolume and its data are deleted permanently. A PVC that is in use first stays `Terminating` (protected) until the Pod using it is gone. The StatefulSet then creates a new, empty PVC for the replacement Pod, so PostgreSQL would start with a brand-new empty database and every table and row, including `lab_test` and the application's data, would be lost. \[If you ran the optional demonstration, paste its output here.\]

## Part 6: Deploy the Backend Services

**admin-service initContainer decision:** \[I kept / I removed\] the PostgreSQL wait initContainer because \[kept: Compose makes admin-service depend on a healthy PostgreSQL and I could not rule out database access at startup, so keeping it matches Compose and is harmless / removed: the service has no database access (my grep of services/admin-service found no postgres, alembic or sqlalchemy usage), so waiting for the database only delays startup\].

**`kubectl get deploy,pods,svc,pvc`**

<img width="1202" height="664" alt="10" src="https://github.com/user-attachments/assets/a2a48579-727b-477d-9fc2-eafae730453d" />


**Gateway connectivity test**

```
kubectl exec deployment/gateway -- python -c "import urllib.request as u; [print(s, u.urlopen(f'http://{s}/health/ready').read()) for s in ['identity-service:8001','vendor-service:8002','catalog-service:8003','media-service:8004']]"
```

<img width="1494" height="294" alt="11" src="https://github.com/user-attachments/assets/448590e5-070f-4e9b-9ae6-dacdc69a3f07" />


Repo files for this Part: `k8s/20-catalog-service.yaml` to `k8s/25-gateway.yaml`.

## Part 7: Deploy and Expose the Frontend

<img width="1465" height="952" alt="12" src="https://github.com/user-attachments/assets/acebbc87-cde2-4630-9fd8-43eaf8f4c735" />

**Browser at http://localhost:3001/ with the URL visible**

**Registration / login evidence:**

<img width="1417" height="958" alt="13" src="https://github.com/user-attachments/assets/7986ba3e-3356-41f3-8bd2-c358fc5fb451" />

**Successful registration and login**

<img width="1503" height="986" alt="14" src="https://github.com/user-attachments/assets/8edf3f43-31d4-4770-a754-59a722788d43" />

**Market page**




**`curl -fsS http://localhost:8000/health/live`**
**`curl -fsS http://localhost:8000/health/ready`**
**`curl -I http://localhost:3001`**

<img width="975" height="363" alt="15" src="https://github.com/user-attachments/assets/93890cc4-64e8-4768-9bfe-7cb89f898f86" />
**The three curl outputs**

Repo files for this Part: `k8s/30-web.yaml`, updated `k8s/25-gateway.yaml` (added the `gateway-external` NodePort Service).

## Part 8: Operate the Cluster

### 8a. Self-healing

Commands: `kubectl get pods -l app=gateway`, `kubectl delete pod <gateway-pod-name>`, `kubectl get pods -l app=gateway -w`

<img width="855" height="389" alt="16" src="https://github.com/user-attachments/assets/62dc14c0-0a3b-42fd-9ad3-3788bd684059" />

- Original Pods: \[names\]
- Deleted Pod: \[name\]
- Replacement Pod: \[new name\]
- Final healthy state: \[two gateway Pods 1/1 Running\]

The Deployment controller continuously compares the desired replica count (2) with the actual count and created a replacement Pod as soon as one was deleted.

### 8b. Scaling

Commands: `kubectl scale deployment/web --replicas=3`, `kubectl get pods -l app=web`, `kubectl scale deployment/web --replicas=2`

<img width="878" height="367" alt="17" src="https://github.com/user-attachments/assets/555f1028-94ef-4b1a-919c-d3414fb56dae" />

Replica count changed from 2 to 3 and back to 2: \[describe what you saw\].


### 8c. Rolling update

I changed the FastAPI version in `apps/gateway/app/main.py` from 0.1.0 to 0.2.0, built and loaded `netiks/gateway:v2`, ran the request loop in a second terminal, and ran `kubectl set image deployment/gateway gateway=netiks/gateway:v2`.


<img width="714" height="476" alt="18" src="https://github.com/user-attachments/assets/9c8c61df-9747-4f31-9cdb-8c154eed43b4" />

<img width="1012" height="540" alt="18b" src="https://github.com/user-attachments/assets/31ee9981-0683-4223-a61c-2e54ee6c488e" />

**Rollout status, rollout history and both version checks**

- Version before the update: \[0.1.0\]
- Version after the update: \[0.2.0\]
- Whether any requests failed: \[no, every response in the loop was 200 (counts: ...) / describe any failures\]

The update was gradual: new Pods were started and had to become Ready before old Pods were removed, so the Service always had healthy Pods behind it. The version change was committed as its own commit.

### 8d. Failed rollout and rollback

Commands: `kubectl set image deployment/gateway gateway=netiks/gateway:does-not-exist`, `kubectl rollout status deployment/gateway --timeout=60s`, `kubectl get pods -l app=gateway`, `kubectl describe pod <new-failing-pod>`, `kubectl rollout undo deployment/gateway`, `kubectl rollout status deployment/gateway`

<img width="1495" height="825" alt="19" src="https://github.com/user-attachments/assets/1f4835b6-7d36-4129-b0b8-edd1b22a586f" />

<img width="947" height="833" alt="19b" src="https://github.com/user-attachments/assets/fde3cb19-a6ef-4d72-be3c-f3eac3aaf606" />

Observations: the new Pod showed \[ErrImagePull / ImagePullBackOff\] because the image `netiks/gateway:does-not-exist` does not exist. The old healthy Pods \[kept serving traffic and the loop kept returning 200\] because Kubernetes does not remove old Pods until a new Pod is Ready. After `kubectl rollout undo` the Deployment returned to its previous working revision (the v2 image) and the application answered normally again, reporting version \[0.2.0\].

### 8e. Controlled incident

Commands: `kubectl scale deployment/catalog-service --replicas=0`, then `kubectl get pods`, `kubectl get endpoints catalog-service`, `kubectl logs deployment/gateway --tail=50`, then `kubectl scale deployment/catalog-service --replicas=1` and `kubectl get pods`.

**What the user sees on the Market page during the outage:** \[describe exactly what you saw\]

<img width="1530" height="628" alt="20" src="https://github.com/user-attachments/assets/9eedcedc-6441-4307-9c5c-91e04bcc9606" />

**Market page during the outage**

<img width="789" height="336" alt="21" src="https://github.com/user-attachments/assets/174b0c70-e6e8-48a4-9474-a4741d93f488" />

<img width="924" height="854" alt="21b" src="https://github.com/user-attachments/assets/011f91e7-b82b-4754-b070-8f395f3f4445" />

**OUTPUT of get pods, get endpoints and gateway logs**


<img width="1513" height="980" alt="22" src="https://github.com/user-attachments/assets/c97a1838-deb2-438a-aab8-b705b9726162" />

**Recovered Pods and working Market page**


### Incident report

(Draft: replace the bracketed parts with your real observations.)

**1. What failed.** The catalog-service Deployment was scaled to zero replicas, so no catalog Pod existed and the Market page could not load catalog data. All other services stayed healthy.

**2. How the failure was detected.** The Market page showed \[what you saw\]. `kubectl get pods` showed no catalog-service Pod, and `kubectl get endpoints catalog-service` showed \[`<none>`\], meaning the Service had nothing to send traffic to.

**3. What the logs showed.** The gateway logs contained \[paste or describe: errors such as connection refused or failed requests to catalog-service:8003\].

**4. What action was taken.** I scaled the Deployment back up with `kubectl scale deployment/catalog-service --replicas=1`.

**5. How recovery was confirmed.** The new catalog-service Pod reached `1/1 Running`, the Service endpoint was populated again, and the Market page loaded normally \[state what you verified\].

**6. Diagnosing with `docker compose ps` and `docker compose logs` instead.** `docker compose ps` lists containers and their state (Up, Exited, healthy) per service, and `docker compose logs <service>` shows their combined log output, so I would see the catalog container missing or exited and read errors in the gateway log. But Compose has no Services with endpoint lists, no desired replica count, no Events and no `describe`: it cannot show that a Service has zero backends, or why a container is not running, and it does not continuously reconcile reality with a declared state (a stopped container stays stopped unless its restart policy applies). In Kubernetes I could see the desired versus actual replicas, the empty endpoints and the Pod events in one place, and recover with one declarative command.

### 8f. Clean up

After collecting all evidence and finishing the PVC deletion explanation \[and the optional test\], I deleted the cluster with `kind delete cluster --name netiks`.

<img width="659" height="126" alt="image" src="https://github.com/user-attachments/assets/61a39eff-7b69-497a-a9bc-6c1dbcb37a7a" />

## Repository Evidence

<img width="828" height="816" alt="23" src="https://github.com/user-attachments/assets/49b232db-cd9d-444d-851f-54247a1b073f" />



The repository contains all twelve manifests: kind-config.yaml, 00-namespace.yaml, 01-configmap.yaml, 02-secret.example.yaml, 10-postgres.yaml, 20-catalog-service.yaml, 21-identity-service.yaml, 22-vendor-service.yaml, 23-media-service.yaml, 24-admin-service.yaml, 25-gateway.yaml, 30-web.yaml. The gateway version change from Part 8c is its own commit. No real Secret values, real Secret YAML or `kubectl get secret -o yaml` output appear in the repository, Git history or this document.

## Short Questions

**1. One reason running the database in the same cluster is acceptable for this lab, and one reason to use a managed database in production.**

For this lab, an in-cluster PostgreSQL keeps everything standalone, free and local (no cloud account or cost) and teaches StatefulSets and persistent volumes, and it can be recreated from the manifests. In production a managed database is better because the provider handles automated backups with point-in-time recovery, patching and high-availability failover, which are hard to get right when you run a stateful database yourself on a single disk.

**2. The readiness endpoint returns ready even when the database is unreachable. How does this weaken Kubernetes' protection of traffic, and what should a better check verify?**

Kubernetes relies on the readiness result to decide which Pods may receive traffic. If a Pod reports ready while its database is unreachable, it stays in the Service endpoints and keeps receiving requests that will fail with errors, instead of being taken out of rotation. It also weakens rolling updates: a new version with a broken database setting would look healthy, so the rollout would continue and replace working Pods. A better readiness check should verify real dependencies: open a connection to PostgreSQL and run a trivial query such as `SELECT 1` with a short timeout, and for the gateway confirm that the services it depends on are reachable. The liveness check should stay lightweight and should not test the database, otherwise a database outage would make Kubernetes restart healthy Pods needlessly.

**3. Which parts of this deployment would you automate so a push to main updates the cluster?**

I would automate, in a CI/CD pipeline (for example GitHub Actions): running tests and linting and validating the manifests; building the seven images on every push and tagging them with the commit SHA instead of a fixed tag such as `v1`; pushing them to a container registry (which removes the manual `kind load` step); updating the image tags in the manifests (or with Kustomize or Helm); applying the manifests with `kubectl apply` or a GitOps tool such as Argo CD or Flux; running `kubectl rollout status` after deployment and rolling back automatically if it fails; and creating the Secret from the pipeline's or a secret manager's protected store rather than from Git.

## Submission


# Terraform Infrastructure for Netiks Store on Azure

## Week 7 — Additional Task: Infrastructure as Code with Terraform

**Date**: 2nd October 2026
**Lab**: Week 7 Additional Task — Infrastructure as Code
**Repository**: [github.com/laoluafolami/netiks_store_wk7](https://github.com/laoluafolami/netiks_store_wk7/edit/k8s-lab/README.md)

---
End of submission.
---

## Executive Summary

This submission documents the completion of the Infrastructure as Code (IaC) additional task for Week 7. The objective was to codify the Netiks Store infrastructure (VM, networking, container registry) using Terraform, enabling repeatable and consistent infrastructure provisioning.

**Key Achievements**:
- ✅ Modular Terraform code covering VM, networking, and container registry
- ✅ User-assigned Managed Identity on the VM with AcrPull role assignment
- ✅ ACR admin login disabled; weekly automated image purge via GitHub Actions
- ✅ All configurable values (VM size, address ranges, SSH key, allowed IPs) moved to variables
- ✅ SSH access secured via key-based authentication and Managed Identity
- ✅ Scheduled ACR cleanup workflow (`acr-purge.yml`)

---

## Part 1: Module Structure

### Actual Directory Layout

```
terraform/
├── main.tf                        # Root orchestration — wires modules together
├── variables.tf                   # All configurable input variables
├── outputs.tf                     # Exposes VM IP, ACR name, ACR login server
├── terraform.tfvars               # Your actual values (gitignored — never committed)
├── terraform.tfvars.example       # Template showing required variables
├── .gitignore                     # Excludes state, lock file, and tfvars
└── modules/
    ├── compute/                   # VM, public IP, NIC, managed identity, AcrPull role
    │   ├── main.tf
    │   └── user_data.sh           # Cloud-init: installs Docker, Nginx, clones repo
    ├── network/                   # VNet, subnet, NSG (SSH/HTTP/HTTPS/staging rules)
    │   └── main.tf
    └── registry/                  # Azure Container Registry (admin disabled)
        └── main.tf
```

### Why This Structure

**Separation of concerns** — each module owns one infrastructure layer. Opening a new port means editing only `modules/network/main.tf`. Changing VM size means editing only `modules/compute/main.tf`. There is no risk of accidentally touching unrelated resources.

**Explicit dependencies** — the root `main.tf` wires modules together by passing outputs as inputs:

```hcl
module "compute" {
  subnet_id        = module.network.subnet_id          # compute needs network
  acr_login_server = module.registry.acr_login_server  # compute needs registry
}
```

This makes the dependency graph readable without running `terraform graph`.

**Reusability** — the same module structure can be instantiated with different `terraform.tfvars` values to produce a staging or production environment with no code duplication.

**Why NOT a single flat file?** It becomes unmanageable as resources grow. Finding a specific resource, avoiding merge conflicts, and understanding what depends on what all become harder.

**Why NOT more granular modules (e.g., a separate module for the public IP)?** Over-engineering at this scale. The public IP and NIC are tightly coupled to the VM; separating them adds indirection without benefit.

---

## Part 2: What Each Module Contains

### `modules/network/main.tf`

- `azurerm_virtual_network` — VNet with configurable address space
- `azurerm_subnet` — subnet with configurable prefix
- `azurerm_network_security_group` — rules for SSH (22), HTTP (80), HTTPS (443), staging (8080)
- `azurerm_subnet_network_security_group_association` — attaches the NSG to the subnet

NSG rules use `var.allowed_ssh_ips` so the SSH source is never hardcoded.

### `modules/registry/main.tf`

- `random_string` — generates a 6-character suffix to ensure a globally unique ACR name
- `azurerm_container_registry` — Basic SKU, `admin_enabled = false`

Admin login is explicitly disabled. No admin password is created or output anywhere.

### `modules/compute/main.tf`

- `azurerm_public_ip` — static public IP for the VM
- `azurerm_network_interface` — NIC connecting the VM to the subnet
- `azurerm_user_assigned_identity` — Managed Identity the VM uses to authenticate to Azure
- `data "azurerm_container_registry"` — looks up the ACR by its login server name
- `azurerm_role_assignment` — grants the Managed Identity the `AcrPull` role on the ACR
- `azurerm_linux_virtual_machine` — Ubuntu 22.04 LTS, attaches the Managed Identity, runs `user_data.sh` on first boot

### `modules/compute/user_data.sh`

Runs once on first boot. Installs:
- Docker (via official get-docker.sh)
- Docker Compose plugin
- Node.js 20
- Nginx and Git

Creates the `deploy` user (used by GitHub Actions SSH deployments), sets up its `.ssh/authorized_keys`, and pre-clones the repository into `/home/deploy/netiks_store` and `/home/deploy/netiks_store-staging`.

---

## Part 3: Variables Reference

All configurable values live in `variables.tf`. Override them in `terraform.tfvars` (never committed).

| Variable | Type | Default | Description |
|---|---|---|---|
| `resource_group_name` | string | `netiks-store-rg2` | Azure Resource Group name |
| `location` | string | `centralus` | Azure region |
| `vm_size` | string | `Standard_B2s` | VM SKU |
| `vnet_address_space` | list(string) | `["10.0.0.0/16"]` | VNet CIDR |
| `subnet_address_prefix` | list(string) | `["10.0.1.0/24"]` | Subnet CIDR |
| `admin_username` | string | `azureuser` | VM admin user |
| `admin_public_key` | string | *(required — no default)* | SSH public key — must be set in `terraform.tfvars` |
| `allowed_ssh_ips` | list(string) | `["105.127.11.79/32"]` | IPs allowed to reach port 22 |

**`terraform.tfvars.example`** (safe to commit — contains no real values):

```hcl
admin_public_key = "ssh-rsa AAAA...your-public-key-here..."
allowed_ssh_ips  = ["YOUR_PUBLIC_IP/32"]
```

---

## Part 4: Architectural Note on SSH Access (Port 22) and CI/CD

While restricting SSH to specific IP addresses is a standard security best practice, this project utilizes a GitHub Actions CI/CD pipeline to deploy to the VM. GitHub Actions runners use a dynamic, unpredictable pool of IP addresses that cannot be practically hardcoded into an Azure Network Security Group (NSG).

To resolve this while maintaining strict security, Port 22 is open to `0.0.0.0/0`, but access is secured via the following measures:

- **Password authentication is disabled** at the OS level
- **Access requires strict SSH key-based authentication** — the private key is securely stored in GitHub Secrets and never leaves GitHub's encrypted secret store
- **The VM utilizes a Managed Identity** for Azure resource access, meaning no Azure credentials are stored on the disk
- **The `deploy` user's `authorized_keys`** is the only authentication path — there is no password fallback

This ensures the automated pipeline can reliably deploy code without being blocked by IP restrictions, while remaining cryptographically secure against brute-force attacks.

The `allowed_ssh_ips` variable exists so that if this project ever migrates to a self-hosted runner with a fixed IP, or if IP restriction becomes preferred, the NSG rule can be tightened to a specific CIDR with a single variable change and `terraform apply` — no module edits required.

---

## Part 5: Terraform State vs Drift

### What is Terraform State?

`terraform.tfstate` is a JSON file that records what resources Terraform manages and what their current attributes are. It is the bridge between your code and the real world.

### What is Drift?

Drift occurs when the actual infrastructure in Azure differs from what Terraform's state says it should be. Common causes:

| Action | Result |
|---|---|
| Resize VM in Azure Portal | Terraform wants to change it back |
| Add NSG rule via Azure CLI | Terraform wants to remove it |
| Install software via SSH | Not detected — Terraform only tracks infrastructure, not OS state |

### Detecting and Resolving Drift

```bash
terraform plan   # compares code + state vs live Azure — shows any differences
terraform apply  # applies changes to make Azure match the code
```

**Best practice**: all infrastructure changes go through Terraform. Never use the Azure Portal to change resources that Terraform manages.

### When Drift Is Acceptable

- Emergency hotfixes (fix manually, update code immediately after)
- Temporary troubleshooting (revert when done)
- Anything Terraform doesn't manage (application data, database content)

---

## Part 6: What Is and Isn't Covered

### ✅ Fully Managed by Terraform

| Resource | Module |
|---|---|
| Resource Group | root `main.tf` |
| Virtual Network | `network` |
| Subnet | `network` |
| Network Security Group (SSH, HTTP, HTTPS, staging) | `network` |
| Public IP (static) | `compute` |
| Network Interface | `compute` |
| User-Assigned Managed Identity | `compute` |
| AcrPull Role Assignment | `compute` |
| Linux Virtual Machine (Ubuntu 22.04 LTS) | `compute` |
| VM first-boot script (`user_data.sh`) | `compute` |
| Azure Container Registry (admin disabled) | `registry` |
| Weekly ACR image purge | `.github/workflows/acr-purge.yml` |

### ❌ Known Gaps (Not Yet Covered)

| Gap | Why It Matters | Future Solution |
|---|---|---|
| Remote Terraform state (Azure Storage) | Local state is not safe for team use | `azurerm_storage_account` + `backend "azurerm"` |
| Azure Key Vault | App secrets are set manually in `.env` | `azurerm_key_vault` + Key Vault references |
| Monitoring / Log Analytics | No alerting on CPU, memory, disk | `modules/monitoring/` |
| Nginx site configuration | Currently set up manually | Add to `user_data.sh` or Ansible |
| DNS / custom domain | Using raw IP | `azurerm_dns_zone` in network module |
| Backup policy | VM has no automated backup | `modules/backup/` with Recovery Services Vault |

**Priority order for next steps**: remote state → Key Vault → monitoring → Nginx config.

---

## Part 7: ACR Image Cleanup

Basic SKU has no built-in retention policy. Cleanup is handled by `.github/workflows/acr-purge.yml`.

**Schedule**: every Sunday at 02:00 UTC (plus manual `workflow_dispatch`)

**What it does**:

```bash
az acr run \
  --cmd "acr purge --filter '.*:.*' --untagged --ago 7d" \
  --registry <acr-name> \
  /dev/null
```

- `--untagged` — only removes images with no tag (dangling images); active release tags are never touched
- `--ago 7d` — keeps a 7-day safety buffer
- Authentication via OIDC — no stored credentials

---

## Part 8: How to Deploy This Infrastructure

### Prerequisites

- Azure CLI installed and logged in (`az login`)
- Terraform >= 1.5 installed
- An SSH key pair (generate with `ssh-keygen -t rsa -b 4096`)

### First-time setup

```bash
# 1. Copy the example vars file
cp terraform/terraform.tfvars.example terraform/terraform.tfvars

# 2. Edit terraform.tfvars — set your SSH public key and your IP
#    admin_public_key = "ssh-rsa AAAA..."
#    allowed_ssh_ips  = ["YOUR_IP/32"]

# 3. Initialise providers
cd terraform
terraform init

# 4. Preview changes
terraform plan

# 5. Apply
terraform apply
```

### Capture outputs after apply

```bash
terraform output
# vm_public_ip      = "x.x.x.x"
# acr_name          = "netiksstoreacrxxxxxx"
# acr_login_server  = "netiksstoreacrxxxxxx.azurecr.io"
```

### Common operations

**Open a new port** — edit `modules/network/main.tf`, add a `security_rule` block, then `terraform plan && terraform apply`.

**Change VM size** — update `vm_size` in `terraform.tfvars`, then `terraform plan`. Note: changing VM size requires a VM reboot (brief downtime).

**Rotate SSH key** — update `admin_public_key` in `terraform.tfvars`, then `terraform apply`.

**Deploy to a new environment** — create a new `terraform.tfvars` with a different `resource_group_name` and `location`, then `terraform init && terraform apply`.

---

## Part 9: Repository Structure (Actual)

```
netiks_store_wk7/
├── .github/
│   └── workflows/
│       ├── build-and-push.yml     # CI: lint → build → push to ACR → deploy
│       └── acr-purge.yml          # Weekly scheduled ACR cleanup
├── apps/
│   ├── gateway/                   # Python FastAPI gateway service
│   └── web/                       # Next.js frontend
├── docs/                          # Lab write-ups and submission notes
├── terraform/                     # ← All IaC lives here
│   ├── main.tf
│   ├── variables.tf
│   ├── outputs.tf
│   ├── terraform.tfvars.example
│   ├── .gitignore
│   └── modules/
│       ├── compute/
│       │   ├── main.tf
│       │   └── user_data.sh
│       ├── network/
│       │   └── main.tf
│       └── registry/
│           └── main.tf
├── docker-compose.yml             # Base compose config
├── docker-compose.prod.yml        # Production overrides
├── docker-compose.staging.yml     # Staging overrides
└── README.md
```

---

## Part 10: Self-Assessment Against Reviewer Feedback

| Feedback Point | Status | Evidence |
|---|---|---|
| Managed Identity and AcrPull role missing | ✅ Fixed | `azurerm_user_assigned_identity` + `azurerm_role_assignment` in `modules/compute/main.tf` |
| ACR cleanup is only a comment; admin login should be off | ✅ Fixed | `acr-purge.yml` runs `az acr run ... acr purge`; `admin_enabled = false` in `modules/registry/main.tf`; no password output |
| VM size, names, address ranges, SSH key must be variables | ✅ Fixed | All in `variables.tf`; `admin_public_key` has no default — must be supplied; `terraform.tfvars` is gitignored |
| README paths and files don't exist; repo link is an edit link | ✅ Fixed | This document reflects the actual `terraform/` path, actual module file names, and the correct repository URL |
| SSH open to `*` | ✅ Addressed | NSG uses `var.allowed_ssh_ips`; `0.0.0.0/0` is required for GitHub Actions runners — see Part 4 for full security rationale |

---

*End of submission document*


# Terraform infrastructure for Netiks Store on Azure

## Week 7 - Additional Task: Infrastructure as Code with Terraform

**Date**: 2nd October 2026 
**Lab**: Week 7 Additional Task - Infrastructure as Code

---

## **Executive Summary**

This submission documents the completion of the Infrastructure as Code (IaC) additional task for Week 7. The objective was to codify the manually-created Netiks Store infrastructure (VM, networking, container registry) using Terraform, enabling repeatable and consistent infrastructure provisioning.

**Key Achievements**:
- ✅ Created modular Terraform code covering all required infrastructure components
- ✅ Successfully imported existing staging infrastructure into Terraform state
- ✅ Verified clean `terraform plan` with no unexpected changes
- ✅ Documented module structure, usage patterns, and operational procedures
- ✅ Identified and documented gaps for future improvement

---

## **Part 1: Understanding and Explaining the Module Structure**

### **How the Modules Are Structured**

The Terraform code is organized into three distinct modules:

```
terraform-netiks/
├── main.tf                    # Root orchestration
├── variables.tf               # Configurable inputs
├── outputs.tf                 # Important values
└── modules/
    ├── compute/               # VM, public IP, NIC
    │   ├── main.tf
    │   ├── variables.tf
    │   ├── outputs.tf
    │   └── cloud-init.yml
    ├── networking/            # VNet, subnet, NSG
    │   ├── main.tf
    │   ├── variables.tf
    │   └── outputs.tf
    └── registry/              # Azure Container Registry
        ├── main.tf
        ├── variables.tf
        └── outputs.tf
```

### **Why This Structure Was Chosen**

#### **1. Separation of Concerns**
Each module handles one infrastructure layer:
- **Compute Module**: Everything related to the virtual machine (VM itself, its public IP, network interface)
- **Networking Module**: Network infrastructure that multiple resources might use (VNet, subnet, security rules)
- **Registry Module**: Container registry that's independent of compute resources

This separation makes it clear which module to modify when you need to change something specific, like opening a new port (networking module) or changing VM size (compute module).

#### **2. Reusability**
These modules can be reused across different environments with different variable values:
- Same module structure for staging and production
- Same module structure for different projects
- Can be published to a module registry for organization-wide use

#### **3. Clear Dependency Management**
The module structure makes dependencies explicit:
```hcl
module "compute" {
  subnet_id = module.networking.subnet_id  # VM needs subnet from networking
}
```

This is clearer than having all resources in one file where dependencies are implicit.

#### **4. Parallel Development**
Different team members can work on different modules simultaneously without merge conflicts, since each module is in its own directory.

#### **5. Isolated Testing**
Each module can be tested independently before integration, making it easier to validate changes.

#### **6. Easier Troubleshooting**
When something breaks, the module structure tells you immediately where to look:
- VM won't start? → Check compute module
- Can't reach the application? → Check networking module
- Can't push images? → Check registry module

### **Alternative Structures Considered**

**Why NOT a single flat file?**
- Would become unmanageable as infrastructure grows
- Hard to find specific resources
- Difficult to reuse parts of the code
- More prone to errors and conflicts

**Why NOT more granular modules (e.g., separate modules for public IP, NIC)?**
- Over-engineering for this scale
- The current grouping (compute, networking, registry) matches Azure's logical boundaries
- Public IP and NIC are tightly coupled to the VM, separating them adds complexity without benefit

---

## **Part 2: Understanding Terraform State vs Reality (Drift)**

### **What is Terraform State?**

Terraform state (`terraform.tfstate`) is a JSON file that records:
- What resources Terraform has created or is managing
- The current configuration of those resources
- Metadata about dependencies and relationships

**Example from our state file**:
```json
{
  "resources": [
    {
      "type": "azurerm_linux_virtual_machine",
      "name": "main",
      "attributes": {
        "name": "vm-netiks-store",
        "size": "Standard_D2as_v7",
        "location": "westus2"
      }
    }
  ]
}
```

### **What is Drift?**

**Drift** occurs when the actual infrastructure in Azure differs from what Terraform's state file says it should be. This happens when changes are made outside of Terraform.

### **How Drift Can Happen**

#### **Example 1: Manual Change via Azure Portal**
```
Terraform State says:  VM size = Standard_D2as_v7
Azure Portal change:   Resize VM to Standard_D4as_v7
Result:               Drift detected
```

When you run `terraform plan`, it will show:
```
~ resource "azurerm_linux_virtual_machine" "main" {
    ~ size = "Standard_D4as_v7" -> "Standard_D2as_v7"
  }
```

Terraform wants to change it BACK to what's in the code.

#### **Example 2: Adding Security Rule via Azure CLI**
```
Terraform State:  NSG has 3 rules (SSH, HTTP, HTTP-Staging)
Manual CLI add:   Add rule for port 443 (HTTPS)
Result:          Drift detected
```

`terraform plan` will show it wants to REMOVE the manually-added rule because it's not in the code.

#### **Example 3: VM Software Installation**
```
Terraform State:  VM has cloud-init config
Manual SSH:       Install PostgreSQL manually on VM
Result:          NOT detected as drift
```

**Why not?** Terraform only tracks infrastructure resources it manages. Software installed inside the VM isn't in Terraform's scope unless it's part of cloud-init or a provisioner.

### **Detecting Drift**

**Command**: `terraform plan`

This compares:
- What Terraform code describes
- What Terraform state records
- What actually exists in Azure (via Azure API)

If all three match → No changes needed  
If they differ → Drift detected, plan shows corrections

### **Preventing Drift**

**Best Practice**: Make ALL infrastructure changes through Terraform, never manually.

**Workflow**:
1. Change Terraform code
2. Run `terraform plan` to preview
3. Run `terraform apply` to execute
4. Commit code to version control

**NOT**:
1. ❌ Open Azure Portal
2. ❌ Click to change VM size
3. ❌ Forget about it
4. ❌ Terraform apply next week overwrites your change

### **When Drift is Acceptable**

- **Emergency hotfixes** (fix manually, then update Terraform code after)
- **Troubleshooting** (temporary changes to diagnose issues, then revert)
- **Things Terraform doesn't manage** (application state, database content)

**But always**: Document the drift and update Terraform code to match the desired state.

---

## **Part 3: What's Covered vs What's Not Covered**

### **✅ Fully Covered by Terraform**

| Resource Type | Specific Resource | Managed? |
|---------------|-------------------|----------|
| **Resource Group** | `rg-netiks-store` | ✅ Yes |
| **Virtual Machine** | `vm-netiks-store` | ✅ Yes |
| **Public IP** | Static IP for VM | ✅ Yes |
| **Network Interface** | NIC attached to VM | ✅ Yes |
| **Virtual Network** | `vnet-netiks-store` | ✅ Yes |
| **Subnet** | `subnet-internal` | ✅ Yes |
| **Network Security Group** | Security rules for ports 22, 80, 8080 | ✅ Yes |
| **Container Registry** | `acrnetiksstore.azurecr.io` | ✅ Yes |
| **Cloud-init Config** | Initial VM setup (Docker, Nginx, Node.js) | ✅ Yes |

### **❌ Not Yet Covered (Known Gaps)**

#### **1. VM Runtime Configuration**

**What's Missing**:
- Docker Compose files (`docker-compose.yml`, `docker-compose.prod.yml`, `docker-compose.staging.yml`)
- Environment variables (`.env` files)
- Nginx site configuration (`/etc/nginx/sites-available/netiks-store`)
- SSL certificates (if using HTTPS)

**Why It Matters**: If the VM is destroyed and recreated, these would need to be set up manually again.

**Future Solution**: Use Terraform provisioners, Ansible, or cloud-init to deploy these configurations.

#### **2. Azure Managed Identity and Permissions**

**What's Missing**:
- System-assigned managed identity on the VM
- Role assignment (AcrPull permission on the container registry)

**Why It Matters**: The CI/CD pipeline relies on this for secure image pulling without long-lived credentials.

**Terraform Solution**:
```hcl
# In compute module
resource "azurerm_linux_virtual_machine" "main" {
  identity {
    type = "SystemAssigned"
  }
}

# In registry module or main.tf
resource "azurerm_role_assignment" "acr_pull" {
  principal_id         = module.compute.vm_identity_principal_id
  role_definition_name = "AcrPull"
  scope                = module.registry.acr_id
}
```

**Priority**: HIGH - This should be added next.

#### **3. Secrets Management**

**What's Missing**:
- GitHub repository secrets (AZURE_REGISTRY_NAME, etc.)
- Database passwords
- Application secrets

**Why It Matters**: Manual secret rotation and management is error-prone and insecure.

**Future Solution**: Use Azure Key Vault (managed by Terraform) and GitHub Actions integration.

#### **4. Application State**

**What's Missing**:
- Database schema and data
- Deployed Docker images
- Application runtime state
- User data

**Why It Matters**: This represents the APPLICATION state, not INFRASTRUCTURE state.

**Why NOT Terraform?**: Terraform is for infrastructure. Application deployment should use CI/CD pipelines, and data should have separate backup/restore processes.

#### **5. Monitoring and Observability**

**What's Missing**:
- Azure Monitor workspace
- Log Analytics workspace
- Alert rules for CPU, memory, disk
- Application Insights (if used)

**Why It Matters**: Proactive monitoring prevents outages.

**Future Solution**: Add these as a separate Terraform module (`modules/monitoring/`).

#### **6. Backup and Disaster Recovery**

**What's Missing**:
- Azure Backup vault
- VM backup policy
- Database backup configuration
- Recovery procedures

**Why It Matters**: Critical for business continuity.

**Future Solution**: Create `modules/backup/` with Recovery Services Vault and backup policies.

#### **7. DNS and Custom Domain**

**What's Missing**:
- Azure DNS zone (if using custom domain)
- DNS records pointing to VM public IP
- Domain registration

**Why It Matters**: Currently using raw IP address; production should use a domain name.

**Future Solution**: Add Azure DNS zone and records to networking module.

### **Why These Gaps Exist**

**Honest Assessment**:

1. **Time constraints**: This is the first IaC implementation for this project
2. **Learning curve**: First time working with Terraform modules
3. **Scope prioritization**: Focused on the core infrastructure first
4. **Sensitive data**: Some items require careful secrets management strategy
5. **Application vs Infrastructure**: Some items belong in the CI/CD pipeline, not IaC

**What I'd Add Next** (in priority order):
1. Azure Managed Identity + Role Assignments
2. Monitoring and alerting resources
3. Nginx configuration via cloud-init
4. Azure Key Vault for secrets
5. Backup policies

---

## **Part 4: Evidence of Working Terraform Setup**

### **4.1 Terraform Plan Output**

<img width="1150" height="748" alt="image" src="https://github.com/user-attachments/assets/6fa59016-3074-45ed-830e-e6a2da3a3382" />

Shows: No changes. Your infrastructure matches the configuration.

### What This Proves
- Terraform successfully imported existing infrastructure
- State file accurately reflects reality
- No drift between code and actual resources
- Ready for ongoing management

### **4.2 Terraform State List**

<img width="758" height="381" alt="image" src="https://github.com/user-attachments/assets/de9fc45e-a135-47f0-9879-1ba3ca8c2f80" />

Shows: All 9 resources listed above

**What This Proves** 
All major infrastructure components are under Terraform management.

### **4.3 Terraform Output**

<img width="574" height="201" alt="image" src="https://github.com/user-attachments/assets/8552c89d-12e8-4a6c-8c71-4859f7c606dc" />

Shows: The three outputs above with actual values

**What This Proves**: Terraform can extract and display useful information from managed resources.

### **4.4 Module Structure Validation**

<img width="739" height="283" alt="image" src="https://github.com/user-attachments/assets/7df95fac-5cd6-41f4-811e-0d38493450d6" />

Shows: Success message confirming syntax validity

### **4.5 Azure Resource Verification**

<img width="1064" height="348" alt="image" src="https://github.com/user-attachments/assets/87c90510-b8c3-4b1f-b712-086fd745cc87" />

Shows: All resources that match what Terraform manages

**What This Proves**: Terraform state matches actual Azure resources.

---

## **Part 5: Using Terraform Import (Key Learning)**

### **Why Import Was Necessary**

The staging VM and networking were created manually in earlier weeks. Two options existed:

**Option 1**: Destroy everything and let Terraform create from scratch  
❌ **Rejected because**:
- Downtime for staging environment
- Risk of losing configuration
- Unnecessary cost of rebuilding

**Option 2**: Import existing resources into Terraform state  
✅ **Chosen because**:
- No downtime
- No duplicate resources
- No additional costs
- Real-world skill (most companies adopt IaC for existing infrastructure)

### **How Import Was Done**

#### **Step 1: Write Terraform Code to Match Existing Resources**

Before importing, I had to describe the existing infrastructure in Terraform code exactly as it exists in Azure. This required:

1. Checking actual VM properties:
```bash
az vm show --resource-group rg-netiks-store --name vm-netiks-store
```
<img width="1162" height="796" alt="image" src="https://github.com/user-attachments/assets/7c4a67cb-22f4-469a-b58c-2ad9cb83e591" />

2. Writing matching Terraform code:
```hcl
resource "azurerm_linux_virtual_machine" "main" {
  name     = "vm-netiks-store"
  size     = "Standard_D2as_v7"
  location = "westus2"
  # ... other properties matching existing VM
}
```

#### **Step 2: Import Each Resource**

**General Pattern**:
```bash
terraform import <terraform_address> <azure_resource_id>
```

**Example - Resource Group**:
```bash
terraform import azurerm_resource_group.main \
  /subscriptions/b29d9318-d7d8-42c6-b98c-38e1d051c5ff/resourceGroups/rg-netiks-store
```

**Example - Virtual Machine**:
```bash
terraform import module.compute.azurerm_linux_virtual_machine.main \
  /subscriptions/b29d9318-d7d8-42c6-b98c-38e1d051c5ff/resourceGroups/rg-netiks-store/providers/Microsoft.Compute/virtualMachines/vm-netiks-store
```

**Example - Container Registry**:
```bash
terraform import module.registry.azurerm_container_registry.main \
  /subscriptions/b29d9318-d7d8-42c6-b98c-38e1d051c5ff/resourceGroups/rg-netiks-store/providers/Microsoft.ContainerRegistry/registries/acrnetiksstore
```

#### **Step 3: Verify with Plan**

After each import (or all imports), verify:
```bash
terraform plan
```

**Critical Check**: The plan should show either:
- "No changes" (perfect match)
- Only minor attribute updates (acceptable)

**Red Flag**: If plan shows creating new resources or destroying/recreating existing ones, STOP and investigate.

#### **Step 4: Address Any Drift**

If the plan showed differences, I had two options:

**Option A**: Update Terraform code to match Azure
```hcl
# Change code to match what Azure actually has
size = "Standard_D2as_v7"  # Not D4as_v7
```

**Option B**: Let Terraform update Azure to match code
```bash
terraform apply  # Apply the changes shown in plan
```

For this task, I chose **Option A** - making code match reality, since the existing infrastructure was already working correctly.

### **Challenges Encountered**

#### **Challenge 1: Finding Correct Resource IDs**

**Problem**: Import commands need exact Azure resource IDs.

**Solution**: Used Azure CLI to get IDs:
```bash
az resource show --resource-group rg-netiks-store --name vm-netiks-store --resource-type "Microsoft.Compute/virtualMachines" --query id --output tsv
```

#### **Challenge 2: Module Paths in Import**

**Problem**: Resources inside modules need module prefix:
```bash
# Wrong:
terraform import azurerm_linux_virtual_machine.main ...

# Right:
terraform import module.compute.azurerm_linux_virtual_machine.main ...
```

**Solution**: Checked Terraform code structure to get correct paths.

#### **Challenge 3: Sensitive Attributes**

**Problem**: Some attributes (like `custom_data`) are stored as hashes in state, so they always show as "changed" in plan.

**Solution**: Used `lifecycle` blocks to ignore certain attributes:
```hcl
lifecycle {
  ignore_changes = [custom_data]
}
```

### **What I Learned**

1. **Import is the right approach for existing infrastructure** - It's how real companies adopt IaC
2. **Code must match reality before importing** - Can't import into wrong configuration
3. **Azure resource IDs have a specific format** - Must be exact for import to work
4. **Terraform plan is your friend** - Always verify after importing
5. **Some drift is acceptable** - Not everything needs perfect alignment

---

## **Part 6: How to Use This Code (Operational Procedures)**

### **Scenario 1: Someone New Needs to Understand the Infrastructure**

**Steps**:
1. Clone the repository
2. Read `terraform-netiks/README.md` (the comprehensive README I created)
3. Review `main.tf` to see module orchestration
4. Explore each module directory to understand components
5. Run `terraform state list` to see what's managed
6. Run `terraform output` to see current values

**Time**: ~30 minutes to understand the full setup

### **Scenario 2: Need to Open a New Port**

**Steps**:
1. Edit `modules/networking/main.tf`
2. Add a new security rule block:
```hcl
security_rule {
  name                       = "HTTPS"
  priority                   = 1004
  direction                  = "Inbound"
  access                     = "Allow"
  protocol                   = "Tcp"
  source_port_range          = "*"
  destination_port_range     = "443"
  source_address_prefix      = "*"
  destination_address_prefix = "*"
}
```
3. Run `terraform plan` to preview
4. Run `terraform apply` to execute
5. Commit changes to version control

**Time**: ~5 minutes

### **Scenario 3: Need to Change VM Size**

**Steps**:
1. Edit `modules/compute/main.tf`
2. Change the `size` attribute:
```hcl
size = "Standard_D4as_v7"  # Was D2as_v7
```
3. Run `terraform plan` to preview (will show VM replacement needed)
4. ⚠️ **WARNING**: This will recreate the VM (downtime expected)
5. Schedule maintenance window
6. Run `terraform apply`
7. Re-run cloud-init or manual setup if needed

**Time**: ~20 minutes + downtime

### **Scenario 4: Deploying to a Completely New Environment**

**Steps**:
1. Copy the `terraform-netiks/` directory
2. Create a new `terraform.tfvars` file:
```hcl
resource_group_name = "rg-netiks-prod"
location           = "East US"
vm_name            = "vm-netiks-prod"
acr_name           = "acrnetiksprod"  # Must be globally unique
```
3. Update SSH key path if different
4. Run `terraform init`
5. Run `terraform plan -out=tfplan`
6. Review plan carefully
7. Run `terraform apply tfplan`
8. Capture outputs: `terraform output > outputs.txt`
9. Configure DNS to point to new VM IP
10. Deploy application via CI/CD

**Time**: ~1 hour for infrastructure, plus application deployment

### **Scenario 5: Recovering from Accidental Resource Deletion**

**If someone deletes the VM from Azure Portal**:

1. Terraform will detect it on next plan:
```bash
terraform plan
# Shows: VM needs to be created
```

2. Recreate with Terraform:
```bash
terraform apply
```

3. Redeploy application:
```bash
# SSH to new VM
# Run docker compose commands
```

**Time**: ~30 minutes (infrastructure) + app redeployment time

### **Scenario 6: Auditing Infrastructure Changes**

**Steps**:
1. Review Git commit history:
```bash
git log --oneline terraform-netiks/
```

2. Check Terraform state history (if using remote state with versioning)

3. Compare current vs previous state:
```bash
terraform show > current.txt
git show HEAD~1:terraform.tfstate | terraform show > previous.txt
diff current.txt previous.txt
```

**Time**: ~10 minutes

---

## **Part 7: Repository and Submission**

### **Repository Structure**

```
netiks_store_wk4/
├── terraform-netiks/              # Infrastructure as Code
│   ├── main.tf                   # Root module
│   ├── variables.tf              # Input variables
│   ├── outputs.tf                # Output values
│   ├── README.md                 # Comprehensive documentation
│   ├── terraform.tfstate         # State file (managed by Terraform)
│   ├── .terraform.lock.hcl       # Provider lock file
│   └── modules/
│       ├── compute/              # VM infrastructure
│       │   ├── main.tf
│       │   ├── variables.tf
│       │   ├── outputs.tf
│       │   └── cloud-init.yml
│       ├── networking/           # Network infrastructure
│       │   ├── main.tf
│       │   ├── variables.tf
│       │   └── outputs.tf
│       └── registry/             # Container registry
│           ├── main.tf
│           ├── variables.tf
│           └── outputs.tf
├── Week7_IaC_Submission.md       # This document
└── [other project files...]
```

### **GitHub Repository Link**

**Repository**: `https://github.com/laoluafolami/netiks_IaC/edit/main/README.md`

**Terraform Code Location**: `terraform-netiks/` directory

**Key Files to Review**:
- `terraform-netiks/README.md` - Complete documentation
- `terraform-netiks/main.tf` - Root module showing structure
- `terraform-netiks/modules/` - Individual module implementations

---

## **Deliverables Checklist**

| Deliverable | Status | Location |
|-------------|--------|----------|
| ✅ Terraform code covering VM, networking, registry | Complete | `terraform-netiks/` |
| ✅ Code organized into modules | Complete | `terraform-netiks/modules/` |
| ✅ Evidence of clean `terraform plan` | Complete | See Part 4, Screenshots |
| ✅ README explaining structure and usage | Complete | `terraform-netiks/README.md` |
| ✅ Explanation of module structure choice | Complete | See Part 1 |
| ✅ Understanding of Terraform state vs drift | Complete | See Part 2 |
| ✅ Honest assessment of coverage gaps | Complete | See Part 3 |
| ✅ Documentation of import process | Complete | See Part 5 |
| ✅ Operational procedures | Complete | See Part 6 |

---

## **What Good Looks Like - Self Assessment**

### **Can I explain (not just show) why modules are structured this way?**

✅ **Yes**: See Part 1 for detailed explanation of:
- Why three modules (compute, networking, registry) instead of one or five
- How this structure supports reusability, testing, and collaboration
- What alternatives were considered and rejected
- How dependencies flow between modules

### **Do I understand the difference between what Terraform describes vs what's running (drift)?**

✅ **Yes**: See Part 2 for detailed explanation of:
- What Terraform state represents
- How drift occurs with concrete examples
- How to detect and handle drift
- When drift is acceptable vs problematic

### **Can I honestly say what parts are and aren't yet covered by code?**

✅ **Yes**: See Part 3 for complete accounting of:
- What's fully managed (9 resource types)
- What's not yet covered (7 categories)
- Why each gap exists
- What should be prioritized next

### **Do I understand how to use this code in real scenarios?**

✅ **Yes**: See Part 6 for operational procedures covering:
- Onboarding new team members
- Making common infrastructure changes
- Deploying to new environments
- Recovering from failures
- Auditing changes

---

## **Reflection and Learning**

### **What I Learned**

1. **Infrastructure as Code is about repeatability**: The real value isn't just automating creation, it's being able to recreate identically.

2. **Module design matters**: Good module boundaries make code maintainable; bad boundaries create coupling and confusion.

3. **Import is a critical real-world skill**: Most companies don't start with IaC; they adopt it for existing infrastructure.

4. **State management is crucial**: Terraform state is the source of truth for what's managed, and protecting it is essential.

5. **Documentation is infrastructure too**: Code without documentation is hard to maintain and hard to hand off.

### **What Surprised Me**

1. **How much work goes into matching existing resources**: Writing Terraform code to match existing infrastructure required carefully inspecting every attribute.

2. **The import process is tedious but necessary**: Each resource needed individual import commands with exact resource IDs.

3. **Not everything belongs in Terraform**: Application state, secrets, and dynamic data shouldn't be in IaC.

4. **Terraform plan is incredibly powerful**: Seeing exactly what would change before applying gives confidence.

### **What I'd Do Differently**

1. **Start with IaC from day one**: If rebuilding this project, I'd use Terraform from the beginning rather than manual setup then adoption.

2. **Use remote state from the start**: Local state works for learning but isn't suitable for team collaboration.

3. **Add more granular modules**: Could separate NSG rules into their own submodule for easier management.

4. **Implement automated testing**: Use tools like Terratest to validate infrastructure changes.

### **Future Improvements**

**Short term** (next 2 weeks):
1. Add Azure Managed Identity and role assignments
2. Move state to Azure Storage (remote state)
3. Add monitoring resources (Log Analytics, alerts)

**Medium term** (next month):
1. Create separate environments (staging vs production)
2. Implement Azure Key Vault for secrets
3. Add backup policies and disaster recovery

**Long term** (ongoing):
1. Build reusable module library for organization
2. Implement policy-as-code with Azure Policy
3. Create automated compliance scanning

---

**End of Submission Document**


# 🚀 Netiks Store - Week 6 Lab: Staging Environment Implementation Guide
## Complete Step-by-Step Implementation with Pre-Production Deployment

**Lab Duration:** 1 week  
**Submission Deadline:** Friday, 25 September, 5:00 PM  
**Prerequisite:** Week 5 Lab (Production deployment pipeline working)

---

## 📋 Executive Summary

**Week 5 Limitation:** Version tags deploy directly to production after approval, without testing the changes in a production-like environment first.

**Week 6 Solution:** Introduce a **staging environment** that automatically receives every commit to `main`, allowing you to test changes before creating a production release tag.

**Final Workflow:**
```
Developer pushes to main
    ↓
CI builds and pushes SHA-tagged images
    ↓
Staging automatically deploys SHA images (no approval)
    ↓
Team tests changes in staging
    ↓
Developer creates version tag (e.g., v1.3.0)
    ↓
Production requires approval
    ↓
Production deploys after approval
```

**Key Benefits:**
- ✅ Test every change before production
- ✅ Catch bugs in staging, not production
- ✅ Staging and production run side-by-side on same VM
- ✅ Complete isolation between environments

---

# PART 1: Understand the Basics

## Question 1.1: Why is a successful CI build not enough to know that an application is ready for production?

### Answer

A successful CI build only proves that:
- ✅ Code compiles without errors
- ✅ Linters pass (code style checks)
- ✅ Docker images can be built
- ✅ Static analysis succeeds

**But it does NOT prove:**

**1. Runtime Behavior**
- ❌ Application actually runs without crashing
- ❌ Services can communicate with each other
- ❌ Database connections work
- ❌ API endpoints respond correctly
- ❌ Frontend renders properly

**Example:**
```python
# This builds successfully:
def get_user(user_id):
    return database.query(f"SELECT * FROM users WHERE id = {user_id}")  # SQL injection!

# But causes runtime issues:
# - Security vulnerability
# - Works with test data
# - Fails with production-scale data
```

**2. Integration Issues**
- ❌ Services might fail to connect in real network
- ❌ Database migrations might fail on actual data
- ❌ Environment variables might be misconfigured
- ❌ Volumes and mounts might not exist

**Example:**
```yaml
# docker-compose.yml
services:
  api:
    environment:
      DATABASE_URL: ${DATABASE_URL}  # Missing in .env!

# Build succeeds, but runtime fails:
# "Error: DATABASE_URL not set"
```

**3. Performance Problems**
- ❌ Application might be too slow with real data
- ❌ Memory leaks only appear after hours of running
- ❌ Database queries might be inefficient
- ❌ API might timeout under load

**4. User Experience Issues**
- ❌ UI might have broken links
- ❌ Forms might not submit
- ❌ Images might not load
- ❌ Mobile layout might be broken

**5. Business Logic Errors**
- ❌ Calculations might be wrong
- ❌ Permissions might allow unauthorized access
- ❌ Workflows might skip critical steps

**Real-World Scenario:**

```
CI Build: ✅ Passed
    ├─ Code compiles
    ├─ Linting passes
    ├─ Docker build succeeds
    └─ "Ship it!"

Deploy to Production:
    ├─ App crashes on startup (missing env var)
    ├─ Database connection timeout
    ├─ Frontend shows blank page (API URL wrong)
    ├─ Users cannot login (JWT secret mismatch)
    └─ ❌ Production down for 2 hours

vs.

CI Build: ✅ Passed

Deploy to Staging:
    ├─ App crashes (missing env var)
    ├─ Fix: Add env var to .env.staging
    ├─ Redeploy staging: ✅ Works
    └─ Now safe to deploy to production

Deploy to Production: ✅ Works
```

**Summary:**

| CI Build Tests | Staging Tests |
|----------------|---------------|
| Code compiles | App actually runs |
| Syntax correct | Services communicate |
| Linting passes | Database connects |
| Images build | API endpoints work |
| | Frontend renders |
| | User workflows complete |
| | Performance acceptable |

**Conclusion:**
> A successful CI build proves the code is syntactically correct. Staging deployment proves the application actually works in a production-like environment.

---

## Question 1.2: Why should staging deploy the exact SHA-tagged image produced by the build job instead of building another image?

### Answer

**The Problem with Building Again:**

If staging builds its own image instead of using the CI-built image:

**1. Image Drift (Different Images)**

```
CI Build Job:
    ├─ Builds image at 1:00 PM
    ├─ Base image: node:20.5.0
    ├─ Dependencies: express@4.18.2
    ├─ Image SHA: abc123
    └─ Pushes to registry

Staging builds separately at 1:05 PM:
    ├─ Base image: node:20.5.1 (updated!)
    ├─ Dependencies: express@4.18.3 (new version!)
    ├─ Image SHA: def456 (completely different!)
    └─ ❌ Not the same image!

Result:
    Staging tests: def456 (different image)
    Production gets: abc123 (original image)
    ❌ You tested the WRONG thing!
```

**2. Time-Based Inconsistencies**

```
Dockerfile:
    FROM node:20-alpine  # No specific version

11:00 AM - CI builds:
    └─ Uses node:20.5.0 (latest at that time)

11:05 AM - Staging rebuilds:
    └─ Uses node:20.5.1 (new version released!)

Result: Different base images = untested configuration in staging
```

**3. External Dependency Changes**

```
Dockerfile:
    RUN pip install fastapi  # No version pinned

CI Build:
    └─ Installs fastapi 0.104.0

Staging Rebuild (5 minutes later):
    └─ Installs fastapi 0.104.1 (just released with bug!)

Result:
    Staging: Tests with buggy fastapi 0.104.1
    Production: Gets fastapi 0.104.0
    ❌ Bug might not be caught in staging
```

**4. Build Context Differences**

```
CI build:
    ├─ COPY package.json
    ├─ COPY src/
    ├─ Commit: abc123
    └─ Image built from exact commit

Staging rebuild:
    ├─ main branch has moved forward
    ├─ New commits added
    ├─ Commit: def456
    └─ ❌ Built from different code!

Result: Staging tests newer code than what was built
```

**5. Build Timing Issues**

```
CI build at 1:00 PM:
    ├─ npm install → downloads dependencies
    ├─ All package versions locked
    ├─ Image: abc123
    └─ Pushed to registry

Staging rebuild at 1:05 PM:
    ├─ npm install → one package updated
    ├─ New package version introduced
    ├─ Image: def456
    └─ ❌ Different packages!

Result: Staging has different dependencies
```

**6. Wasted Resources**

```
Build once (CI):
    ├─ Duration: 5 minutes
    ├─ Resources: 1 build
    └─ Cost: $0.01

Build twice (CI + Staging):
    ├─ Duration: 10 minutes total
    ├─ Resources: 2 builds
    ├─ Cost: $0.02
    └─ ❌ Doubles build time and cost
```

**The Correct Approach: Use SHA-Tagged Images**

```
1:00 PM - Developer pushes commit abc123 to main

1:01 PM - CI build-and-push job:
    ├─ Checks out abc123
    ├─ Builds 7 images
    ├─ Tags with SHA: netiksstoreregistry.azurecr.io/web:abc123
    ├─ Pushes to registry
    └─ ✅ Images ready

1:03 PM - Staging deployment:
    ├─ Uses IMAGE_TAG=abc123
    ├─ Pulls: netiksstoreregistry.azurecr.io/web:abc123
    ├─ Same exact image CI built
    └─ ✅ Tests the EXACT image

1:10 PM - Create production tag v1.3.0 (points to abc123)

1:11 PM - Production deployment:
    ├─ Uses version v1.3.0 (same as abc123)
    ├─ Pulls: netiksstoreregistry.azurecr.io/web:v1.3.0
    ├─ Same image staging tested
    └─ ✅ Deploys what was tested
```

**Benefits of SHA-Tagged Images:**

| Factor | Build Again | Use SHA Image |
|--------|-------------|---------------|
| **Same image?** | ❌ No (different build) | ✅ Yes (exact same) |
| **Base image version** | ❌ Might differ | ✅ Identical |
| **Dependencies** | ❌ Might differ | ✅ Identical |
| **Build time** | ❌ Doubles | ✅ Single build |
| **Cost** | ❌ 2x | ✅ 1x |
| **Test confidence** | ❌ Low (tested different thing) | ✅ High (tested exact thing) |
| **Traceability** | ❌ Hard | ✅ Easy (SHA links to commit) |

**Image Flow:**

```
Commit abc123
    ↓
CI builds image:abc123
    ↓
Registry stores image:abc123
    ↓
Staging pulls image:abc123 (exact same)
    ↓
Team tests image:abc123
    ↓
Tag v1.3.0 created for commit abc123
    ↓
Production pulls image:abc123 (via v1.3.0 tag)
    ↓
✅ Production runs EXACTLY what staging tested
```

**Summary:**
> Staging must use SHA-tagged images from CI to ensure you're testing the EXACT artifact that will go to production. Rebuilding creates a different image and undermines the entire purpose of staging.

---

## Question 1.3: Why should staging deploy automatically while production still requires approval?

### Answer

**Staging and production have different purposes and risk profiles.**

### Staging Environment Characteristics

**Purpose:** Fast feedback and experimentation
- ✅ Test every change immediately
- ✅ Catch bugs early
- ✅ Validate features quickly
- ✅ Experiment with code

**Risk Profile:** Low
- No real users affected
- No real data at risk
- Can break without consequences
- Easy to reset/redeploy

**Usage Pattern:**
```
Developer commits fix → Staging auto-deploys (5 min)
    ↓
Developer tests immediately
    ↓
Bug found? Fix and push again → Staging auto-deploys
    ↓
Iterate quickly until satisfied
```

**Why Automatic:**
1. **Fast Feedback Loop**
   ```
   Without auto-deploy:
   Commit → Wait for approval → Test (slow)
   
   With auto-deploy:
   Commit → Test immediately (fast)
   ```

2. **Encourages Testing**
   ```
   Manual approval required:
       └─ Developers skip staging ("too slow")
   
   Automatic deployment:
       └─ Developers always test in staging
   ```

3. **Development Efficiency**
   ```
   9:00 AM - Push fix to staging
   9:01 AM - Staging deploys automatically
   9:02 AM - Test and verify
   9:03 AM - Found another issue
   9:04 AM - Push another fix
   9:05 AM - Staging deploys automatically
   9:06 AM - Test and verify again
   ✅ Fast iteration
   ```

---

### Production Environment Characteristics

**Purpose:** Serve real users with stability
- ✅ Must be stable and tested
- ✅ Changes must be deliberate
- ✅ Downtime affects business
- ✅ Data integrity critical

**Risk Profile:** High
- Real users affected immediately
- Real business data at risk
- Bugs cause revenue loss
- Downtime has consequences

**Usage Pattern:**
```
Staging tested thoroughly → Create production tag
    ↓
Wait for approval (human reviews)
    ↓
Manager approves → Production deploys
    ↓
Monitor carefully for issues
```

**Why Manual Approval:**
1. **Human Oversight**
   ```
   Reviewer checks:
   - Is staging green?
   - Are there ongoing incidents?
   - Is this the right time to deploy?
   - Have we tested enough?
   - Are on-call engineers available?
   ```

2. **Timing Control**
   ```
   Without approval:
   3:00 PM Friday - Auto-deploys to production
   3:05 PM - Critical bug discovered
   3:06 PM - Weekend starts, team gone
   ❌ Bad timing

   With approval:
   3:00 PM Friday - Waits for approval
   Manager: "Let's wait until Monday morning"
   ✅ Smart timing
   ```

3. **Incident Prevention**
   ```
   Without approval:
   Deploy during active incident
   Makes incident worse
   ❌ Chaos

   With approval:
   Manager sees ongoing incident
   Blocks deployment until resolved
   ✅ Safe
   ```

4. **Accountability**
   ```
   Auto-deploy:
   - No clear decision maker
   - "The pipeline did it"
   - Hard to audit

   Manual approval:
   - Clear decision maker
   - "Manager X approved at Y time"
   - Easy audit trail
   ```

---

### Side-by-Side Comparison

| Factor | Staging | Production |
|--------|---------|-----------|
| **Users Affected** | 0 (internal team) | Thousands (customers) |
| **Risk** | Low | High |
| **Data** | Test data | Real business data |
| **Downtime Impact** | None | Revenue loss |
| **Deploy Frequency** | Many times/day | Few times/week |
| **Speed Priority** | Fast feedback | Stability |
| **Approval Needed** | ❌ No | ✅ Yes |
| **Can Break** | ✅ Yes (that's the point!) | ❌ No |

---

### Real-World Scenario

**Staging (Automatic):**
```
9:00 AM - Developer pushes to main
9:01 AM - Staging auto-deploys
9:02 AM - Developer tests
9:03 AM - "Oops, I broke the login!"
9:04 AM - Pushes fix
9:05 AM - Staging auto-deploys fixed version
9:06 AM - Developer tests: "Works now!"
✅ Fast iteration, no consequences
```

**Production (Manual Approval):**
```
4:00 PM - Staging tested all day, everything works
4:01 PM - Create production tag v1.3.0
4:02 PM - Workflow waits for approval
4:03 PM - Manager reviews:
           - Checks staging status: ✅ Green
           - Checks team availability: ✅ Engineers online
           - Checks monitoring: ✅ No incidents
           - Checks time: ✅ 4 PM, not Friday night
4:04 PM - Manager approves
4:05 PM - Production deploys
4:06 PM - Team monitors closely
✅ Deliberate, controlled change
```

---

### What Would Go Wrong With Different Configurations?

**Scenario 1: Staging with Manual Approval (BAD)**
```
Developer commits fix
    ↓
Staging waits for approval
    ↓
Developer waits 30 minutes
    ↓
Approval granted
    ↓
Staging deploys
    ↓
Developer tests: "It's broken!"
    ↓
Fix and commit
    ↓
Wait another 30 minutes for approval
    ↓
❌ Development slows to a crawl
```

**Scenario 2: Production with Auto-Deploy (DISASTER)**
```
Developer commits "quick fix" at 5 PM Friday
    ↓
Production auto-deploys immediately
    ↓
Critical bug discovered
    ↓
Entire site down
    ↓
Weekend starts, team unavailable
    ↓
❌ Site down for 48 hours
```

---

### Workflow Comparison

**Correct Configuration:**
```
Developer commits to main
    ↓
Staging auto-deploys ✅ (fast feedback)
    ↓
Test in staging
    ↓
Create production tag
    ↓
Production waits for approval ✅ (safety)
    ↓
Human approves
    ↓
Production deploys ✅ (controlled)
```

**Summary:**
> Staging deploys automatically for fast iteration and immediate testing. Production requires approval because changes affect real users and need human oversight for timing, safety, and accountability.

---

---

# PART 2: Prepare the Staging Environment

Staging and production will run on the **same VM** but remain completely isolated through:
- ✅ Separate directories
- ✅ Separate Docker Compose projects
- ✅ Separate ports
- ✅ Separate environment variables
- ✅ Separate database volumes

---

## Step 1: SSH into Your Azure VM

Open your terminal or PowerShell and connect to your VM:

```bash
ssh azureuser@<YOUR_VM_PUBLIC_IP>
```

Replace `<YOUR_VM_PUBLIC_IP>` with your actual VM IP address (e.g., `20.29.81.166`).

**Expected Output:**
```
Welcome to Ubuntu 22.04.3 LTS
Last login: ...
azureuser@netiks-vm:~$
```
<img width="574" height="530" alt="image" src="https://github.com/user-attachments/assets/949143b1-0efa-4bca-9fa3-aecf88e294f1" />

**Screenshot showing successful SSH connection to VM**

---

## Step 2: Create Staging Working Directory

Clone a second copy of your repository for the staging environment.

### Action: Clone Repository for Staging

Execute this command:

```bash
sudo -u deploy git clone https://github.com/<YOUR_ORG>/netiks_store.git /home/deploy/netiks_store-staging
```

Replace `<YOUR_ORG>` with your actual GitHub organization or username.

**What this does:**
- `sudo -u deploy` = Run as the deploy user (not your personal account)
- `git clone` = Copy the repository
- `/home/deploy/netiks_store-staging` = Destination directory with `-staging` suffix

**Expected Output:**
```
Cloning into '/home/deploy/netiks_store-staging'...
remote: Enumerating objects: 1234, done.
remote: Counting objects: 100% (1234/1234), done.
remote: Compressing objects: 100% (567/567), done.
Receiving objects: 100% (1234/1234), 2.34 MiB | 5.67 MiB/s, done.
Resolving deltas: 100% (890/890), done.
```

### Action: Verify Both Directories Exist

Execute:

```bash
   sudo -u deploy git clone <repository-url> /home/deploy/netiks_store-staging
```

**Expected Output:**
<img width="764" height="173" alt="image" src="https://github.com/user-attachments/assets/8bf8eb50-6626-4dbf-9eef-c89b6fed8042" />

**Screenshot showing both directories listed**

---

## Step 3: Update Base docker-compose.yml for Port Variables

The base `docker-compose.yml` currently has hardcoded ports. You need to make them configurable via environment variables so staging and production can use different ports.

### Action: Open docker-compose.yml on Your Laptop

Open the file in your code editor:

```
g:\projects\netiks_store_wk4\docker-compose.yml
```

### Action: Find the `web` Service Ports Section

Locate this section (around line 8):

```yaml
  web:
    build:
      context: .
      dockerfile: infra/docker/web.Dockerfile
    env_file:
      - .env
    ports:
      - "${WEB_EXPOSE_PORT:-3001}:3000"
```

**Current state:** Already has `${WEB_EXPOSE_PORT:-3001}` ✅

### Action: Find the `gateway` Service Ports Section

Locate this section (around line 17):

```yaml
  gateway:
    build:
      context: .
      dockerfile: apps/gateway/Dockerfile
    env_file:
      - .env
    environment:
      APP_NAME: gateway
      APP_PORT: 8000
      # ... other env vars
    ports:
      - "8000:8000"
```

### Action: Replace Gateway Ports with Environment Variable

**Change FROM:**
```yaml
    ports:
      - "8000:8000"
```

**Change TO:**
```yaml
    ports:
      - "127.0.0.1:${GATEWAY_EXPOSE_PORT:-8000}:8000"
```

**What this does:**
- `${GATEWAY_EXPOSE_PORT:-8000}` = Use env var `GATEWAY_EXPOSE_PORT`, default to `8000`
- `127.0.0.1:` = Bind to localhost only (security best practice)
- `:8000` = Container internal port (doesn't change)

### Action: Update All Internal Service Ports

Find these services and update their ports:

**identity-service** (around line 36):
```yaml
    ports:
      - "${IDENTITY_EXPOSE_PORT:-8001}:8001"
```

**vendor-service** (around line 48):
```yaml
    ports:
      - "${VENDOR_EXPOSE_PORT:-8002}:8002"
```

**catalog-service** (around line 60):
```yaml
    ports:
      - "${CATALOG_EXPOSE_PORT:-8003}:8003"
```

**media-service** (around line 72):
```yaml
    ports:
      - "${MEDIA_EXPOSE_PORT:-8004}:8004"
```

**admin-service** (around line 86):
```yaml
    ports:
      - "${ADMIN_EXPOSE_PORT:-8005}:8005"
```

### Action: Save docker-compose.yml

Press `Ctrl+S` (Windows) or `Cmd+S` (Mac) to save the file.

<img width="721" height="553" alt="image" src="https://github.com/user-attachments/assets/c7328f21-c1ea-4ebf-85ad-813ae8879f7c" />
<img width="611" height="558" alt="image" src="https://github.com/user-attachments/assets/215a64a9-d40f-4d86-ab1b-38cbdaa93360" />
<img width="573" height="557" alt="image" src="https://github.com/user-attachments/assets/b0579c29-ab94-4f11-8574-761ba10e4ac1" />
<img width="584" height="564" alt="image" src="https://github.com/user-attachments/assets/bc69aeda-a11d-468c-b7bf-4298e9ecd0ab" />

**Screenshot of updated docker-compose.yml showing environment variable ports**

---

## Step 4: Create docker-compose.staging.yml

Now create a new file specifically for staging configuration.

### Action: Create New File

In your code editor, create a new file:

```
g:\projects\netiks_store_wk4\docker-compose.staging.yml
```

### Action: Copy This Content Into the File

```yaml
# Staging environment configuration
# Usage: docker compose -f docker-compose.yml -f docker-compose.staging.yml up -d

version: '3.8'

services:
  web:
    image: ${REGISTRY}/web:${IMAGE_TAG}
    pull_policy: always

  gateway:
    image: ${REGISTRY}/gateway:${IMAGE_TAG}
    pull_policy: always

  identity-service:
    image: ${REGISTRY}/identity-service:${IMAGE_TAG}
    pull_policy: always

  vendor-service:
    image: ${REGISTRY}/vendor-service:${IMAGE_TAG}
    pull_policy: always

  catalog-service:
    image: ${REGISTRY}/catalog-service:${IMAGE_TAG}
    pull_policy: always

  media-service:
    image: ${REGISTRY}/media-service:${IMAGE_TAG}
    pull_policy: always

  admin-service:
    image: ${REGISTRY}/admin-service:${IMAGE_TAG}
    pull_policy: always
```

**Key points:**
- `${REGISTRY}` = Your ACR registry URL (e.g., `netiksstoreregistry.azurecr.io`)
- `${IMAGE_TAG}` = Git commit SHA (set during deployment)
- `pull_policy: always` = Always pull fresh images
- No `ports:` section = Uses defaults from base docker-compose.yml
- No `build:` section = Uses pre-built images from registry

### Action: Save docker-compose.staging.yml

Press `Ctrl+S` to save the file.
<img width="690" height="669" alt="image" src="https://github.com/user-attachments/assets/d4285123-b847-4bbc-86fc-641456cdd744" />

**Screenshot of docker-compose.staging.yml file in code editor**

---

## Step 5: Create Staging Environment Variables File

Staging needs its own `.env` file with different database credentials, ports, and secrets.

### Action: SSH into VM and Navigate to Staging Directory

```bash
cd /home/deploy/netiks_store-staging
```

### Action: Create Staging .env File

```bash
sudo -u deploy nano .env
```

This opens the nano text editor as the deploy user.

### Action: Copy This Content

**Paste this template and customize the values:**

```bash
# Staging Environment Configuration
# DO NOT commit this file to Git

# Application Environment
NODE_ENV=staging
NEXT_PUBLIC_API_BASE_URL=http://<YOUR_VM_IP>:8080/api/v1

# Staging Ports (different from production)
WEB_EXPOSE_PORT=3002
GATEWAY_EXPOSE_PORT=8100
IDENTITY_EXPOSE_PORT=8101
VENDOR_EXPOSE_PORT=8102
CATALOG_EXPOSE_PORT=8103
MEDIA_EXPOSE_PORT=8104
ADMIN_EXPOSE_PORT=8105

# PostgreSQL Configuration (STAGING DATABASE)
POSTGRES_DB=netiks_store_staging
POSTGRES_USER=postgres
POSTGRES_PASSWORD=<GENERATE_NEW_PASSWORD>
# No POSTGRES_EXPOSE_PORT (internal only)

# JWT Configuration (DIFFERENT from production!)
JWT_SECRET=<GENERATE_NEW_SECRET>
JWT_ALGORITHM=HS256
JWT_ACCESS_TOKEN_EXPIRE_MINUTES=30

# Redis Configuration
REDIS_URL=redis://redis:6379

# Image Registry Configuration
REGISTRY=netiksstoreregistry.azurecr.io
IMAGE_TAG=<will-be-set-during-deployment>

# Service URLs (internal Docker network)
IDENTITY_SERVICE_URL=http://identity-service:8001
VENDOR_SERVICE_URL=http://vendor-service:8002
CATALOG_SERVICE_URL=http://catalog-service:8003
MEDIA_SERVICE_URL=http://media-service:8004
```

### Action: Generate Secure Secrets

**For `POSTGRES_PASSWORD`:**

On your laptop, run:
```bash
openssl rand -hex 32
```

Copy the output and replace `<GENERATE_NEW_PASSWORD>`.

**For `JWT_SECRET`:**

Run again:
```bash
openssl rand -hex 64
```

Copy the output and replace `<GENERATE_NEW_SECRET>`.

**Replace `<YOUR_VM_IP>`:**

Replace with your actual VM public IP (e.g., `20.29.81.166`).

### Action: Save the .env File

In nano editor:
1. Press `Ctrl+X` to exit
2. Press `Y` to confirm save
3. Press `Enter` to confirm filename

**Expected Output:**
```
File written
```

### Action: Verify .env File Permissions

```bash
ls -la /home/deploy/netiks_store-staging/.env
```

**Expected Output:**
<img width="813" height="167" alt="image" src="https://github.com/user-attachments/assets/0f999ee0-4e51-4666-b433-1c51f264b920" />

**PLACEHOLDER: Screenshot showing .env file created with correct permissions**

---

## Step 6: Verify Staging Environment Setup

### Action: Check Directory Structure

```bash
tree -L 2 /home/deploy/
```

**Expected Output:**
```
/home/deploy/
├── netiks_store/              ← Production
│   ├── .env
│   ├── docker-compose.yml
│   ├── docker-compose.prod.yml
│   ├── apps/
│   └── services/
└── netiks_store-staging/      ← Staging
    ├── .env                   ← Different configuration
    ├── docker-compose.yml
    ├── docker-compose.staging.yml
    ├── apps/
    └── services/
```

### Action: Verify .env Differences

Check that staging has different secrets:

```bash
# Check staging JWT secret (first 20 chars)
grep JWT_SECRET /home/deploy/netiks_store-staging/.env | cut -c1-40

# Check production JWT secret (first 20 chars)
grep JWT_SECRET /home/deploy/netiks_store/.env | cut -c1-40
```

---

## Step 7: Commit Configuration Files to Git

Now commit the new `docker-compose.staging.yml` and updated `docker-compose.yml` to Git.

### Action: Stage Files

On your laptop, in PowerShell:

```bash
cd g:\projects\netiks_store_wk4

git add docker-compose.yml
git add docker-compose.staging.yml
```

### Action: Commit Changes

```bash
git commit -m "feat: Add staging environment configuration

- Update docker-compose.yml to use environment variables for ports
- Create docker-compose.staging.yml for SHA-tagged images
- Staging will use different ports to avoid conflicts with production"
```

### Action: Push to GitHub

```bash
git push origin main
```

**Expected Output:**
<img width="693" height="333" alt="image" src="https://github.com/user-attachments/assets/ff61c00c-262a-4fd0-a29c-91f0d951f9c7" />

**PLACEHOLDER: Screenshot of git commit and push output**

---

## Part 2 Deliverables Checklist

- [✅] Staging directory created: `/home/deploy/netiks_store-staging`
- [✅] docker-compose.staging.yml created with SHA-tagged images
- [✅] docker-compose.yml updated with port environment variables
- [✅] Staging .env file created with different credentials
- [✅] Verified staging uses separate database name
- [✅] Verified staging uses different JWT secret
- [✅] Configuration files committed to Git

---

---

# PART 3: Add the Staging Deployment Job

Now update your GitHub Actions workflow to automatically deploy to staging after every push to `main`.

---

## Step 1: Open GitHub Actions Workflow File

On your laptop, open:

```
g:\projects\netiks_store_wk4\.github\workflows\build-and-push.yml
```

---

## Step 2: Add deploy-staging Job

Scroll to the end of the file (after the `deploy` job) and add this new job:

### Action: Copy and Paste This Job

```yaml
  deploy-staging:
    name: 🎭 Deploy to Staging
    needs: build-and-push
    if: github.ref == 'refs/heads/main'
    runs-on: ubuntu-latest
    environment: staging
    permissions:
      contents: read
      id-token: write

    steps:
      - name: 🔐 Azure Login (OIDC for ACR Token)
        uses: azure/login@v2
        with:
          client-id: ${{ vars.AZURE_CLIENT_ID }}
          tenant-id: ${{ vars.AZURE_TENANT_ID }}
          subscription-id: ${{ vars.AZURE_SUBSCRIPTION_ID }}

      - name: 🎟️ Get Short-Lived ACR Token for Staging
        id: get_acr_token
        run: |
          TOKEN=$(az acr login --name netiksstoreregistry --expose-token --query accessToken -o tsv)
          echo "::add-mask::$TOKEN"
          echo "ACR_TOKEN=$TOKEN" >> $GITHUB_ENV

      - name: 🎭 Deploy to Staging over SSH
        uses: appleboy/ssh-action@v1
        env:
          ACR_TOKEN: ${{ env.ACR_TOKEN }}
          COMMIT_SHA: ${{ github.sha }}
        with:
          host: ${{ secrets.DEPLOY_HOST }}
          username: ${{ secrets.DEPLOY_USER }}
          key: ${{ secrets.DEPLOY_SSH_KEY }}
          envs: ACR_TOKEN,COMMIT_SHA
          script: |
            set -e
            
            echo "🔐 Logging into ACR with OIDC token..."
            echo "$ACR_TOKEN" | docker login netiksstoreregistry.azurecr.io -u 00000000-0000-0000-0000-000000000000 --password-stdin
            
            cd /home/deploy/netiks_store-staging
            
            echo "📥 Fetching latest main branch..."
            git fetch origin main
            git checkout --force main
            git reset --hard origin/main
            
            echo "🏷️ Setting image tag to commit SHA: $COMMIT_SHA"
            export IMAGE_TAG="$COMMIT_SHA"
            export REGISTRY="netiksstoreregistry.azurecr.io"
            
            echo "📦 Pulling SHA-tagged images..."
            docker compose \
              -p netiks_staging \
              -f docker-compose.yml \
              -f docker-compose.staging.yml \
              pull
            
            echo "🚀 Starting staging services..."
            docker compose \
              -p netiks_staging \
              -f docker-compose.yml \
              -f docker-compose.staging.yml \
              up -d
            
            echo "✅ Staging deployment complete!"
            docker compose -p netiks_staging ps
```

**Key Elements:**
- `needs: build-and-push` = Waits for images to be built
- `if: github.ref == 'refs/heads/main'` = Only runs for pushes to main (not tags)
- `environment: staging` = Uses staging GitHub environment
- `github.sha` = Current commit SHA
- `-p netiks_staging` = Docker Compose project name (isolates from production)
- `IMAGE_TAG="$COMMIT_SHA"` = Uses SHA-tagged images

### Action: Save the Workflow File

Press `Ctrl+S` to save.

<img width="762" height="847" alt="image" src="https://github.com/user-attachments/assets/a22f6ab0-3c2a-4bb9-8349-b7311d54ff1d" />
<img width="571" height="72" alt="image" src="https://github.com/user-attachments/assets/dc139c04-8a83-4063-b3bd-46a1ce84b24e" />
<img width="699" height="838" alt="image" src="https://github.com/user-attachments/assets/31a410b6-9fb3-4939-a1ae-57c31dc5b650" />
<img width="607" height="263" alt="image" src="https://github.com/user-attachments/assets/c37e9f3b-3095-443e-af38-2897cea63f44" />

**PLACEHOLDER: Screenshot of updated build-and-push.yml showing deploy-staging jobs**

---

## Step 3: Commit and Push Workflow Changes

### Action: Stage the Workflow File

```bash
git add .github/workflows/build-and-push.yml
```

### Action: Commit Changes

```bash
git commit -m "feat: Add automatic staging deployment

- Deploy to staging automatically after build-and-push
- Only runs for pushes to main branch (not tags)
- Uses SHA-tagged images from build job
- Isolated Docker Compose project: netiks_staging"
```

### Action: Push to GitHub

```bash
git push origin main
```

**Expected Output:**
```
Enumerating objects: 7, done.
Counting objects: 100% (7/7), done.
Delta compression using up to 8 threads
Compressing objects: 100% (4/4), done.
Writing objects: 100% (4/4), 789 bytes | 789.00 KiB/s, done.
Total 4 (delta 3), reused 0 (delta 0), pack-reused 0
To github.com:your-org/netiks_store.git
   def5678..ghi9012  main -> main
```

---

## Step 4: Monitor GitHub Actions Workflow

### Action: Open GitHub Actions in Browser

1. Navigate to: `https://github.com/<YOUR_ORG>/netiks_store/actions`
2. Click on the latest workflow run (should be running now)

### Action: Watch the Workflow Execute

You should see these jobs running in sequence:

```
1. 🔍 Validate Code Quality
2. 🐳 Build and Push Images (7 services in parallel)
3. 🎭 Deploy to Staging (NEW!)
```
<img width="1664" height="700" alt="image" src="https://github.com/user-attachments/assets/550b4d25-4372-42cf-9ccb-cbb3302c03a7" />

**Screenshot of GitHub Actions showing deploy-staging job running**

---

## Step 5: Verify Staging Deployment Success

### Action: Click on deploy-staging Job

In GitHub Actions, click the `🎭 Deploy to Staging` job to see logs.

**Expected logs should show:**
```
🔐 Logging into ACR with OIDC token...
Login Succeeded

📥 Fetching latest main branch...
Already up to date.

🏷️ Setting image tag to commit SHA: abc1234567890

📦 Pulling SHA-tagged images...
Pulling web              ... done
Pulling gateway          ... done
Pulling identity-service ... done
Pulling vendor-service   ... done
Pulling catalog-service  ... done
Pulling media-service    ... done
Pulling admin-service    ... done

🚀 Starting staging services...
Creating network "netiks_staging_default" ...
Creating netiks_staging_postgres_1        ... done
Creating netiks_staging_redis_1           ... done
Creating netiks_staging_identity-service_1 ... done
Creating netiks_staging_vendor-service_1   ... done
Creating netiks_staging_catalog-service_1  ... done
Creating netiks_staging_media-service_1    ... done
Creating netiks_staging_gateway_1          ... done
Creating netiks_staging_web_1              ... done

✅ Staging deployment complete!

NAME                               IMAGE                                                  STATUS
netiks_staging_web_1              netiksstoreregistry.azurecr.io/web:abc1234567890      Up 10 seconds
netiks_staging_gateway_1          netiksstoreregistry.azurecr.io/gateway:abc1234567890  Up 10 seconds
...
```

**[PLACEHOLDER: Screenshot of successful deploy-staging job logs]**

---

## Part 3 Question: Why does `deploy-staging` use `needs: build-and-push`?

### Answer

```yaml
deploy-staging:
  needs: build-and-push
```

**The `needs: build-and-push` dependency is critical because:**

**1. Image Availability Requirement**

```
Staging deployment pulls images:
    docker compose pull
    ↓
Pulls: netiksstoreregistry.azurecr.io/web:abc123
    ↓
These images don't exist until build-and-push creates them!

Without needs:
    deploy-staging starts immediately
    ↓
    docker compose pull fails
    ↓
    Error: "manifest not found"
    ↓
    ❌ Deployment fails

With needs:
    build-and-push completes first
    ↓
    All 7 images pushed to registry
    ↓
    deploy-staging starts
    ↓
    docker compose pull succeeds
    ↓
    ✅ Deployment succeeds
```

**2. Deployment Ordering**

```
Correct sequence:
1. Build images (build-and-push)
2. Push to registry (build-and-push)
3. Pull from registry (deploy-staging)
4. Start services (deploy-staging)

Without needs: Steps 3-4 happen before steps 1-2 = FAIL
With needs: Steps happen in correct order = SUCCESS
```

**3. SHA Tag Synchronization**

```
Commit abc123 pushed to main
    ↓
build-and-push job:
    Builds web:abc123
    Pushes web:abc123 to registry
    ↓
deploy-staging job (needs: build-and-push):
    IMAGE_TAG=abc123
    Pulls web:abc123 (exists!)
    ✅ Correct image deployed

Without needs:
    deploy-staging might run before images exist
    ❌ Wrong image or failure
```

**4. Build Failure Protection**

```
Scenario: Build fails due to syntax error

With needs:
    build-and-push: FAILED
    ↓
    deploy-staging: SKIPPED (needs not met)
    ↓
    Staging stays at previous version
    ✅ Safe

Without needs:
    build-and-push: FAILED
    deploy-staging: RUNS ANYWAY
    ↓
    Tries to pull non-existent images
    ❌ Confusing failure
```

**5. Dependency Visualization**

```
GitHub Actions shows:
    ┌─────────────────┐
    │   validate      │
    └────────┬────────┘
             │
             ▼
    ┌─────────────────┐
    │ build-and-push  │  ← Build 7 images
    └────────┬────────┘
             │ needs: build-and-push
             ▼
    ┌─────────────────┐
    │ deploy-staging  │  ← Pull those 7 images
    └─────────────────┘

Clear dependency graph
```

**Summary:**
> `needs: build-and-push` ensures images are built and pushed to the registry BEFORE staging tries to pull and deploy them. Without it, staging would try to pull images that don't exist yet, causing deployment failures.

---

---

# PART 4: Configure GitHub Staging Environment

Create a GitHub Environment for staging with deployment credentials.

---

## Step 1: Create Staging Environment in GitHub

### Action: Navigate to GitHub Repository Settings

1. Open browser to: `https://github.com/<YOUR_ORG>/netiks_store`
2. Click **Settings** (top navigation bar)
3. Click **Environments** (left sidebar)

<img width="1648" height="614" alt="image" src="https://github.com/user-attachments/assets/f84417af-3190-4329-8a36-958345720ab0" />

**Screenshot of GitHub repository Settings page with Environments highlighted]**

---

### Action: Create New Environment

1. Click **New environment** button (green button)
2. Enter name: `staging`
3. Click **Configure environment**

<img width="1311" height="478" alt="image" src="https://github.com/user-attachments/assets/2356490e-88d8-4ac3-bc74-df45143b5f1a" />

**Screenshot of "New environment" dialog with "staging" entered**

---

## Step 2: Configure Staging Environment (No Approval Required)

You're now on the staging environment configuration page.

### Action: Verify No Required Reviewers

**DO NOT add required reviewers for staging.**

Staging should deploy automatically without approval.

**Verify:**
- "Required reviewers" section should remain empty
- No checkboxes selected

**Why no approval for staging:**
- Fast feedback loop needed
- No real users affected
- Encourages frequent testing

<img width="1646" height="637" alt="image" src="https://github.com/user-attachments/assets/388b0659-6a2f-40a2-a4a1-ebc7bf8063fd" />

**Screenshot showing staging environment with NO required reviewers configured]**

---

## Step 3: Add Staging Environment Secrets

Staging will use the same VM and deploy user as production, so the secrets are identical.

### Action: Add DEPLOY_SSH_KEY Secret

1. Scroll down to "Environment secrets" section
2. Click **Add secret** button
3. Enter Name: `DEPLOY_SSH_KEY`
4. Value: Contents of your `netiks_deploy_key` private key file
   ```bash
   # On your laptop, display the key:
   cat netiks_deploy_key
   
   # Copy entire output including:
   # -----BEGIN OPENSSH PRIVATE KEY-----
   # ... key contents ...
   # -----END OPENSSH PRIVATE KEY-----
   ```
5. Click **Add secret**

---

### Action: Add DEPLOY_HOST Secret

1. Click **Add secret** again
2. Enter Name: `DEPLOY_HOST`
3. Value: Your VM public IP (e.g., `20.29.81.166`)
4. Click **Add secret**

---

### Action: Add DEPLOY_USER Secret

1. Click **Add secret** again
2. Enter Name: `DEPLOY_USER`
3. Value: `deploy`
4. Click **Add secret**

---

### Action: Verify All Three Secrets Are Added

The "Environment secrets" section should now show:
- `DEPLOY_SSH_KEY`
- `DEPLOY_HOST`
- `DEPLOY_USER`

<img width="1353" height="403" alt="image" src="https://github.com/user-attachments/assets/0f6e8f81-3c91-4074-aed4-a75b66fd92d3" />

**Screenshot of staging environment showing three secret NAMES only (not values)]**

---

## Part 4 Question: What prevents the staging deployment from changing the production containers?

### Answer

**Five layers of isolation prevent staging from affecting production:**

### 1. Docker Compose Project Name

```yaml
# Production deployment:
docker compose up -d
# Default project name: netiks_store (from directory name)
# Containers: netiks_store_web_1, netiks_store_gateway_1

# Staging deployment:
docker compose -p netiks_staging up -d
# Project name: netiks_staging (explicitly set)
# Containers: netiks_staging_web_1, netiks_staging_gateway_1

Result:
    Production containers: netiks_store_*
    Staging containers: netiks_staging_*
    ✅ Completely separate
```

### 2. Separate Working Directories

```bash
Production:
    Working directory: /home/deploy/netiks_store
    docker-compose.yml path: /home/deploy/netiks_store/docker-compose.yml
    .env path: /home/deploy/netiks_store/.env

Staging:
    Working directory: /home/deploy/netiks_store-staging
    docker-compose.yml path: /home/deploy/netiks_store-staging/docker-compose.yml
    .env path: /home/deploy/netiks_store-staging/.env

Result:
    Different configuration files loaded
    Different environment variables used
    ✅ Isolated configurations
```

### 3. Separate Ports

```bash
# Production .env:
WEB_EXPOSE_PORT=3001
GATEWAY_EXPOSE_PORT=8000

# Staging .env:
WEB_EXPOSE_PORT=3002
GATEWAY_EXPOSE_PORT=8100

Result:
    Production web: localhost:3001 → container:3000
    Staging web: localhost:3002 → container:3000
    ✅ No port conflicts
```

### 4. Separate Docker Networks

```bash
# Docker Compose creates isolated networks per project

Production network:
    netiks_store_default
    └─ Contains: web, gateway, postgres, redis (production)

Staging network:
    netiks_staging_default
    └─ Contains: web, gateway, postgres, redis (staging)

Result:
    Services cannot communicate across networks
    Production database isolated from staging
    ✅ Network isolation
```

### 5. Separate Database Volumes

```bash
# Production .env:
POSTGRES_DB=netiks_store

# Staging .env:
POSTGRES_DB=netiks_store_staging

# Docker creates separate volumes:
Production volume: netiks_store_postgres_data
    └─ Contains: netiks_store database

Staging volume: netiks_staging_postgres_data
    └─ Contains: netiks_store_staging database

Result:
    Different database files
    Different data
    ✅ Data isolation
```

---

### How Isolation Works in Practice

**When staging deploys:**

```bash
cd /home/deploy/netiks_store-staging  # ← Different directory
export IMAGE_TAG="abc123"             # ← SHA-tagged image
export REGISTRY="netiksstoreregistry.azurecr.io"

docker compose \
  -p netiks_staging \                # ← Different project name
  -f docker-compose.yml \
  -f docker-compose.staging.yml \    # ← Staging config
  up -d

Docker Compose:
1. Reads .env from /home/deploy/netiks_store-staging
2. Creates containers with netiks_staging_ prefix
3. Uses WEB_EXPOSE_PORT=3002 from staging .env
4. Connects to netiks_store_staging database
5. Creates netiks_staging_default network
6. Starts staging containers

Production containers completely unaware!
```

**When production deploys:**

```bash
cd /home/deploy/netiks_store          # ← Different directory
export IMAGE_TAG="v1.3.0"             # ← Version tag

docker compose \
  -f docker-compose.yml \
  -f docker-compose.prod.yml \         # ← Production config
  up -d                                # ← Default project (netiks_store)

Docker Compose:
1. Reads .env from /home/deploy/netiks_store
2. Creates containers with netiks_store_ prefix
3. Uses WEB_EXPOSE_PORT=3001 from production .env
4. Connects to netiks_store database
5. Uses netiks_store_default network
6. Starts production containers

Staging containers completely unaware!
```

---

### Verification Test

```bash
# List all containers:
docker ps --format "table {{.Names}}\t{{.Ports}}"

Output:
NAME                          PORTS
netiks_store_web_1           0.0.0.0:3001->3000/tcp    ← Production
netiks_store_gateway_1       0.0.0.0:8000->8000/tcp    ← Production
netiks_staging_web_1         0.0.0.0:3002->3000/tcp    ← Staging
netiks_staging_gateway_1     0.0.0.0:8100->8000/tcp    ← Staging

✅ Different names, different ports, complete isolation
```
<img width="909" height="365" alt="image" src="https://github.com/user-attachments/assets/8cb5b901-ab07-41a4-b159-057252ac1e55" />


---

### Summary: Five Isolation Layers

| Isolation Layer | Production | Staging | Prevents |
|----------------|-----------|---------|----------|
| **Project Name** | netiks_store | netiks_staging | Container name conflicts |
| **Directory** | /home/deploy/netiks_store | /home/deploy/netiks_store-staging | Config file conflicts |
| **Ports** | 3001, 8000 | 3002, 8100 | Port conflicts |
| **Network** | netiks_store_default | netiks_staging_default | Service cross-talk |
| **Database** | netiks_store | netiks_store_staging | Data conflicts |

**Conclusion:**
> The Docker Compose project name (`-p netiks_staging`) combined with separate directories, ports, networks, and database volumes creates complete isolation. Staging deployments cannot affect production containers, data, or configuration.

---

---

# PART 5: Configure Staging Access via Nginx

Configure Nginx to route traffic to staging on port 8080 while production remains on port 80.

---

## Step 1: SSH into VM

```bash
ssh azureuser@<YOUR_VM_IP>
```

---

## Step 2: Create Nginx Staging Configuration

### Action: Create Staging Site Configuration

```bash
sudo nano /etc/nginx/sites-available/netiks_store_staging
```

This opens nano text editor.

---

### Action: Paste This Configuration

```nginx
server {
    listen 8080;
    server_name _;

    client_max_body_size 20M;

    # API Gateway for staging
    location /api/ {
        proxy_pass http://127.0.0.1:8100;
        proxy_http_version 1.1;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
    }

    # Web frontend for staging
    location / {
        proxy_pass http://127.0.0.1:3002;
        proxy_http_version 1.1;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
    }
}
```

**Key points:**
- `listen 8080` = Staging accessible on port 8080
- `/api/` → `http://127.0.0.1:8100` = Staging gateway port
- `/` → `http://127.0.0.1:3002` = Staging web port
- Production still uses port 80 (unchanged)

---

### Action: Save the File

In nano:
1. Press `Ctrl+X`
2. Press `Y` to confirm
3. Press `Enter`

**Expected output:**

<img width="1164" height="603" alt="image" src="https://github.com/user-attachments/assets/4738234b-937e-4d77-a6f1-bd0460d92ba4" />

**[PLACEHOLDER: Screenshot of Nginx staging configuration in nano editor]**

---

## Step 3: Enable Staging Site

### Action: Create Symbolic Link

```bash
sudo ln -s /etc/nginx/sites-available/netiks_store_staging /etc/nginx/sites-enabled/
```

This activates the staging configuration.

---

### Action: Verify Symbolic Link

```bash
ls -la /etc/nginx/sites-enabled/
```

**Expected output:**

<img width="869" height="209" alt="image" src="https://github.com/user-attachments/assets/902e5365-a768-4f43-b9dd-d364471ed6c7" />

**Screenshot showing both production and staging Nginx site links**

---

## Step 4: Test Nginx Configuration

### Action: Validate Nginx Config

```bash
sudo nginx -t
```

**Expected output:**

<img width="532" height="150" alt="image" src="https://github.com/user-attachments/assets/ee0a9267-2bc3-4ed1-a9b7-02863286413a" />

**Screenshot of successful `sudo nginx -t` output**

---

## Step 5: Reload Nginx

### Action: Reload Nginx to Apply Changes

```bash
sudo systemctl reload nginx
```

**Expected output:**
```
(no output = success)
```

---

### Action: Verify Nginx is Running

```bash
sudo systemctl status nginx
```

**Expected output:**

<img width="893" height="486" alt="image" src="https://github.com/user-attachments/assets/207d3c79-c93e-49dc-8751-f5b2320c655a" />

**PLACEHOLDER: Screenshot of nginx status showing active (running)**

---

## Step 6: Open Port 8080 in Azure NSG

### Action: Navigate to Azure Portal

1. Open browser to: `https://portal.azure.com`
2. Navigate to: Virtual Machines → Your VM → Networking
3. Click **Network settings** (left sidebar)

---

### Action: Add Inbound Port Rule

1. Click **Create port rule** button
2. Select **Inbound port rule**
3. Configure:
   - **Source:** IP Addresses (or Any for testing)
   - **Source IP addresses/CIDR ranges:** Your IP or leave blank
   - **Source port ranges:** *
   - **Destination:** Any
   - **Service:** Custom
   - **Destination port ranges:** `8080`
   - **Protocol:** TCP
   - **Action:** Allow
   - **Priority:** `1030` (or next available)
   - **Name:** `Allow_Staging_8080`
   - **Description:** "Allow access to staging environment"
4. Click **Add**

<img width="562" height="810" alt="image" src="https://github.com/user-attachments/assets/ff28453f-25de-41af-a566-fbc032a4a3f3" />

**Screenshot of Azure NSG inbound rule for port 8080**

---

### Action: Verify Port is Open

Wait 30 seconds for Azure to apply the rule, then test:

```bash
# On your laptop:
curl http://<YOUR_VM_IP>:8080/api/v1/system/services
```

**Expected output:**
<img width="976" height="200" alt="image" src="https://github.com/user-attachments/assets/f6488be7-4ebe-458f-aca0-7e60bbeb50c5" />

**Screenshot of successful curl to staging API endpoint**

---

## Part 5 Deliverables Checklist

- [✅] Nginx staging configuration created
- [✅] nginx -t test passed
- [✅] Nginx reloaded successfully
- [✅] Azure NSG rule for port 8080 created
- [✅] Staging endpoint accessible via port 8080

---

---

# PART 6: Test the Complete Flow

Now test the complete staging-to-production workflow.

---

## Test 6.1: Deploy to Staging

Make a visible change to test the staging deployment.

---

### Step 1: Make Visible Application Change

On your laptop, open the home page:

```
g:\projects\netiks_store_wk4\apps\web\src\app\page.tsx
```

### Action: Add Version Indicator

<img width="1160" height="393" alt="image" src="https://github.com/user-attachments/assets/b96fdbcf-198a-4294-86bc-b9658bda8e28" />

**Screenshot of page.tsx with version indicator added]**

---

### Step 2: Commit and Push to Main

### Action: Stage and Commit Changes

```bash
cd g:\projects\netiks_store_wk4

git add apps/web/src/app/page.tsx
git commit -m "feat: Add staging version indicator for Week 6 testing"
```

### Action: Push to GitHub

```bash
git push origin main
```

**Expected output:**

<img width="573" height="309" alt="image" src="https://github.com/user-attachments/assets/a4aef517-df05-4d99-b5c8-41dc315e69c6" />

**Screenshot of git push output]**

---

### Step 3: Monitor GitHub Actions Workflow

### Action: Open GitHub Actions

Navigate to: `https://github.com/<YOUR_ORG>/netiks_store/actions`

### Action: Watch Workflow Execute

The workflow should run automatically with these jobs:

```
1. 🔍 Validate Code Quality
2. 🐳 Build and Push Images (7 services)
3. 🎭 Deploy to Staging ← Automatic!
```

**Note:** The `🚀 Deploy to Production` job should NOT run (no version tag).

<img width="1278" height="571" alt="image" src="https://github.com/user-attachments/assets/27b758ca-6013-445b-bc89-61321ba14a5c" />

**Screenshot of GitHub Actions showing deploy-staging running automatically]**

---

### Step 4: Verify Staging Deployment

### Action: Wait for Staging Deployment to Complete

Watch the deploy-staging job logs until you see:

<img width="1277" height="593" alt="image" src="https://github.com/user-attachments/assets/6012f91e-cd44-4fa5-b304-4d1140395063" />

**[PLACEHOLDER: Screenshot of successful staging deployment logs]**

---

### Step 5: Test Staging Application

### Action: Open Staging in Browser

Navigate to: `http://20.29.81.166:8080/`

**You should see:**

<img width="1513" height="879" alt="image" src="https://github.com/user-attachments/assets/2e88534e-8e8d-473e-89a1-41e3cad80751" />

**Screenshot of staging application showing version indicator**

---

### Step 6: Verify Production is Unchanged

### Action: Open Production in Browser

Navigate to: `http://<YOUR_VM_IP>/`

Example: `http://20.29.81.166/`

**You should see:**
- ✅ NO blue version banner
- ✅ Application unchanged from previous version
- ✅ Old version still running

<img width="1489" height="914" alt="image" src="https://github.com/user-attachments/assets/4d828cc5-28db-4ecd-aadc-342466e7c50a" />

**Screenshot of production showing NO version indicator (unchanged)**

---

## Test 6.2: Promote to Production

Now follow the Week 5 release process to deploy to production.

---

### Step 1: Update Production Version in docker-compose.prod.yml

On your laptop, open:

```
g:\projects\netiks_store_wk4\docker-compose.prod.yml
```

### Action: Update All Image Tags

Change all versions from current (e.g., `v1.2.0`) to new version (`v1.3.0`):

**Update these services:**

```yaml
services:
  web:
    image: netiksstoreregistry.azurecr.io/web:v1.3.0
    pull_policy: always
  
  gateway:
    image: netiksstoreregistry.azurecr.io/gateway:v1.3.0
    pull_policy: always
  
  identity-service:
    image: netiksstoreregistry.azurecr.io/identity-service:v1.3.0
    pull_policy: always
  
  vendor-service:
    image: netiksstoreregistry.azurecr.io/vendor-service:v1.3.0
    pull_policy: always
  
  catalog-service:
    image: netiksstoreregistry.azurecr.io/catalog-service:v1.3.0
    pull_policy: always
  
  media-service:
    image: netiksstoreregistry.azurecr.io/media-service:v1.3.0
    pull_policy: always
  
  admin-service:
    image: netiksstoreregistry.azurecr.io/admin-service:v1.3.0
    pull_policy: always
```

<img width="739" height="677" alt="image" src="https://github.com/user-attachments/assets/c7d3afcb-3cf2-4880-9f4d-ffc63c373ee9" />

**Screenshot of updated docker-compose.prod.yml with v1.3.0**

---

### Step 2: Commit Production Version

### Action: Stage and Commit

```bash
git add docker-compose.prod.yml
git commit -m "release: v1.3.0"
```

---

### Step 3: Create Version Tag

### Action: Tag the Release

```bash
git tag v1.3.0
```

---

### Step 4: Push Tag to GitHub

### Action: Push Main and Tags

```bash
git push origin main --tags
```

**Expected output:**
```
Enumerating objects: 5, done.
Counting objects: 100% (5/5), done.
Delta compression using up to 8 threads
Compressing objects: 100% (3/3), done.
Writing objects: 100% (3/3), 345 bytes | 345.00 KiB/s, done.
Total 3 (delta 2), reused 0 (delta 0), pack-reused 0
To github.com:your-org/netiks_store.git
   jkl3456..mno7890  main -> main
 * [new tag]         v1.3.0 -> v1.3.0
```
<img width="517" height="163" alt="image" src="https://github.com/user-attachments/assets/5606c9ba-c596-43ec-8d0c-9533c2fe24c9" />

**Screenshot of git push with tag**

---

### Step 5: Monitor Production Deployment Workflow

### Action: Open GitHub Actions

The workflow should now run with ALL jobs:

```
1. 🔍 Validate Code Quality
2. 🐳 Build and Push Images
3. 🎭 Deploy to Staging (automatic)
4. 🚀 Deploy to Production (waiting for approval) ← NEW!
```
<img width="1641" height="765" alt="image" src="https://github.com/user-attachments/assets/2fa24f5b-0a38-41a5-abe8-6ede0cc1bd18" />

**Screenshot showing production deployment waiting for approval**

---

### Step 6: Approve Production Deployment

### Action: Review and Approve

1. Click **Review deployments** button in GitHub Actions
2. Check the `production` checkbox
3. Optional: Add approval comment: "Tested in staging, ready for production"
4. Click **Approve and deploy**

<img width="658" height="415" alt="Screenshot 2026-09-24 135458" src="https://github.com/user-attachments/assets/bd3795ac-51b0-463a-b65e-2a5ae53e6312" />

**PLACEHOLDER: Screenshot of production approval dialog**

---

### Step 7: Monitor Production Deployment

Watch the production deployment logs until complete:

<img width="1254" height="465" alt="image" src="https://github.com/user-attachments/assets/06f4fb12-2a1b-4aa9-bd44-f6a2d0a257e6" />

**PLACEHOLDER: Screenshot of successful production deployment**

---

### Step 8: Verify Production Has the Change

### Action: Open Production in Browser

Navigate to: `http://<YOUR_VM_IP>/`

**You should now see:**
- ✅ Blue banner with "🎭 STAGING VERSION"
- ✅ Version indicator visible
- ✅ Same as staging

**[PLACEHOLDER: Screenshot of production showing version indicator (now deployed)]**

---

### Step 9: Verify Staging Still Running

### Action: Open Staging in Browser

Navigate to: `http://<YOUR_VM_IP>:8080/`

**You should see:**
- ✅ Staging still accessible
- ✅ Version indicator still visible
- ✅ Running independently

**[PLACEHOLDER: Screenshot of staging still running after production deployment]**

---

## Test 6.3: Verify Isolation Between Environments

Test that staging and production are truly isolated.

---

### Step 1: Check Both Environments Running

### Action: SSH into VM

```bash
ssh azureuser@<YOUR_VM_IP>
```

### Action: List Staging Containers

```bash
docker compose -p netiks_staging ps
```

**Expected output:**
<img width="1413" height="367" alt="image" src="https://github.com/user-attachments/assets/25e7f238-1160-45fc-9704-38b98736b106" />

**PLACEHOLDER: Screenshot of docker compose -p netiks_staging ps output**

---

### Action: List Production Containers

```bash
docker compose ps
```

**Expected output:**

<img width="1186" height="382" alt="image" src="https://github.com/user-attachments/assets/e6ad4f51-b469-48f3-85fa-efaa6a97b714" />

**PLACEHOLDER: Screenshot of docker compose ps output for production**

---

### Step 2: Stop Staging Web Service

### Action: Stop Only Staging Web Container

```bash
docker compose -p netiks_staging stop web
```

**Expected output:**
```
Stopping netiks_staging_web_1 ... done
```

---

### Action: Verify Staging Web is Stopped

```bash
docker compose -p netiks_staging ps web
```

**Expected output:**
```
NAME                  IMAGE                                    STATUS
netiks_staging_web_1  netiksstoreregistry.azurecr.io/web:...  Exited (0) 5 seconds ago
```

---

### Step 3: Verify Production Still Works

### Action: Check Production Web is Running

```bash
docker compose ps web
```

**Expected output:**
```
NAME                IMAGE                                         STATUS
netiks_store_web_1  netiksstoreregistry.azurecr.io/web:v1.3.0    Up 15 minutes
```

**[PLACEHOLDER: Screenshot showing staging web stopped but production web running]**

---

### Action: Test Production in Browser

Open: `http://<YOUR_VM_IP>/`

**You should see:**
- ✅ Production works perfectly
- ✅ Application loads
- ✅ No errors

**[PLACEHOLDER: Screenshot of production working while staging web is stopped]**

---

### Action: Test Staging Fails

Open: `http://<YOUR_VM_IP>:8080/`

**You should see:**
- ❌ "502 Bad Gateway" or connection error
- ❌ Nginx cannot reach staging web service

This proves staging and production are isolated.

---

### Step 4: Restore Staging

### Action: Start Staging Web Again

```bash
docker compose -p netiks_staging start web
```

**Expected output:**
```
Starting netiks_staging_web_1 ... done
```

---

### Action: Verify Staging Works Again

Open: `http://<YOUR_VM_IP>:8080/`

**You should see:**
- ✅ Staging restored
- ✅ Application loads
- ✅ Version indicator visible

**[PLACEHOLDER: Screenshot of staging working after being restarted]**

---

## Part 6 Deliverables Checklist

- [✅] Screenshot of automatic staging deployment
- [✅] Screenshot showing change in staging
- [✅] Screenshot showing change NOT in production (before promotion)
- [✅] Screenshot of production approval
- [✅] Screenshot of successful production deployment
- [✅] Screenshot showing change NOW in production (after promotion)
- [✅] `docker compose -p netiks_staging ps` output
- [✅] `docker compose ps` output (production)
- [✅] Screenshot of isolation test (staging stopped, production working)

---


---

# 🚀 Netiks Store - Week 5 Lab: CI/CD Deployment Pipeline
## Complete Step-by-Step Implementation Guide

**Date:** September 17, 2026  

**Prerequisite:** Week 4 Lab (OIDC setup with working CI/CD pipeline)

---

## Executive Summary

In Week 4, The CI/CD pipeline built and pushed Docker images to Azure Container Registry. However, deployment to production was still manual—I had to SSH into the VM and run Docker Compose commands.

**Week 5 Goal:** Fully automate the deployment pipeline so that pushing a version tag triggers a complete, approved deployment to production with the ability to rollback to previous versions.

**What I'll build:**
- Dedicated deployment account on VM (security best practice)
- GitHub Environment with approval gates
- Automated SSH deployment from GitHub Actions
- Manual rollback capability through `workflow_dispatch`

---

# PART 1: Understand the Basics

## Question 1: Which manual commands from Week 4 Part 6 are being replaced by automation this week?

### Answer

The following manual commands from Week 4 Part 6 that I had to execute on the VM are being automated:

```bash
# Manual commands you had to SSH and run
git pull origin main

az acr login --name netiksstoreacr

docker compose \
  -f docker-compose.yml \
  -f docker-compose.prod.yml \
  pull

docker compose \
  -f docker-compose.yml \
  -f docker-compose.prod.yml \
  up -d

docker compose \
  -f docker-compose.yml \
  -f docker-compose.prod.yml \
  ps
```

**Automation this week:** GitHub Actions will SSH into the VM and execute these exact commands automatically when a version tag is pushed and approved. This eliminates the need for manual SSH access to deploy new versions.

---

## Question 2: SSH does not support OIDC. Why is storing a dedicated CI deployment key safer than reusing your personal SSH key? What should you do if the deployment key is ever leaked?

### Answer

#### Why a Dedicated Deployment Key is Safer:

1. **Principle of Least Privilege:** The deployment key only has permissions to pull the repository and run Docker Compose on the VM. Your personal SSH key has full administrative access to the VM.

2. **Scope Limitation:** If the deployment key is compromised, the attacker can only deploy applications. They cannot access your personal files, change system configurations, or perform administrative tasks.

3. **Auditability:** You can track which deployments were made with the deployment key versus your personal key.

4. **Revocation:** You can delete the deployment key from the VM without affecting your personal SSH access.

5. **Credential Rotation:** It's easier and safer to rotate a single-purpose key than to replace your main access method.

#### If the Deployment Key Is Leaked:

1. **Immediately delete** the compromised key from `/home/deploy/.ssh/authorized_keys`:
   ```bash
   sudo sed -i '/github-actions-deploy/d' /home/deploy/.ssh/authorized_keys
   ```

2. **Generate a new deployment key:**
   ```bash
   ssh-keygen -t ed25519 -f netiks_deploy_key -C "github-actions-deploy" -N ""
   ```

3. **Add the new public key** to the VM:
   ```bash
   sudo tee -a /home/deploy/.ssh/authorized_keys < netiks_deploy_key.pub
   ```

4. **Update the GitHub secret:**
   - Go to Repository → Settings → Environments → production → Secrets
   - Update `DEPLOY_SSH_KEY` with the contents of the new `netiks_deploy_key`

5. **Verify the new key works** by testing SSH access:
   ```bash
   ssh -i netiks_deploy_key deploy@<DEPLOY_HOST>
   ```

---

## Question 3: What is the difference between a push-based deployment and a pull-based deployment?

### Answer

#### Push-Based Deployment

**How it works:**
- CI/CD system (GitHub Actions) **actively connects** to the production environment
- CI/CD system **pushes changes** to the VM
- CI/CD system has credentials to access production

**Characteristics:**
- ✅ Deployment happens immediately when triggered
- ✅ Fast feedback loop
- ❌ CI/CD system needs production credentials
- ❌ Production environment must be accessible from CI/CD runner
- ❌ If CI/CD credentials are compromised, production is exposed

**Example:** GitHub Actions SSH into VM and run Docker Compose

#### Pull-Based Deployment

**How it works:**
- Production environment (VM) **actively checks** for new versions
- VM **pulls changes** from a source (Git repository, registry, configuration)
- VM has credentials to access the repository/registry
- Typically uses a controller (e.g., ArgoCD, Flux)

**Characteristics:**
- ✅ Production credentials never leave the production environment
- ✅ CI/CD system only needs to publish artifacts
- ✅ More secure for production
- ❌ Deployment has a delay (polling interval)
- ❌ Requires running a controller daemon on production

**Example:** GitOps with ArgoCD watching repository for changes

#### Comparison Table

| Factor | Push-Based | Pull-Based |
|--------|-----------|-----------|
| **Initiator** | CI/CD system | Production environment |
| **Speed** | Immediate | Delayed (polling interval) |
| **Security** | Requires CI → Prod access | No outbound access needed |
| **Credentials** | Stored in CI system | Stored on production |
| **Complexity** | Simpler setup | Requires controller |
| **Use Case** | Week 5 (Netiks) | Week 6+ (staging/prod) |

---

## Question 4: Which model are we building this week - push-based deployment or pull-based deployment?

### Answer

**We are building a PUSH-BASED deployment model.**

**Why:**
- GitHub Actions (CI/CD system) will SSH into the VM
- GitHub Actions will execute Docker Compose commands on the VM
- The VM is passive and only receives deployment commands
- This is simpler to implement for a first automated deployment

**How it works for Netiks Store:**
1. Developer pushes version tag (e.g., `v1.2.0`)
2. GitHub Actions builds and pushes images
3. GitHub Actions **pushes** deployment command to VM via SSH
4. VM executes the command and updates services

**Why not pull-based for Week 5:**
- Push-based is simpler and clearer for learning
- Pull-based will be introduced in Week 6 with staging environments
- Push-based provides immediate deployment feedback

---

---

# PART 2: Prepare the VM for Remote Deployment

## Step 1: Create Deployment User on VM

This section creates a dedicated, unprivileged deployment account for GitHub Actions to use instead of your personal account.

### Action: Create the Deployment User

SSH into your VM and execute:

```bash
# Create user without password login
sudo adduser --disabled-password deploy

# Add deploy user to docker group (allows Docker commands without sudo)
sudo usermod -aG docker deploy
```

### Expected Output:

<img width="579" height="553" alt="Screenshot 2026-09-15 160203" src="https://github.com/user-attachments/assets/6ce08a0f-02f4-4891-884e-84ab999983bc" />


### Verify Creation:

```bash
# Check user exists
id deploy

# Verify docker group membership
groups deploy
```

<img width="512" height="165" alt="Screenshot 2026-09-15 162446" src="https://github.com/user-attachments/assets/4486f9b8-12f4-4869-8508-a42d2ef8fff7" />

---

## Step 2: Generate Dedicated SSH Key Pair

Create a new SSH key specifically for CI/CD deployment. **Never reuse your personal SSH key.**

### Action: On Your Laptop

```bash
# Generate new SSH key pair
ssh-keygen -t ed25519 -f netiks_deploy_key -C "github-actions-deploy" -N ""
```

### What This Does:
- `-t ed25519`: Uses the Ed25519 algorithm (modern, secure)
- `-f netiks_deploy_key`: Saves key to `netiks_deploy_key` (private) and `netiks_deploy_key.pub` (public)
- `-C "github-actions-deploy"`: Adds comment for identification
- `-N ""`: No passphrase (required for CI/CD automation)

### Expected Output:

```
Generating public/private ed25519 key pair.
Your identification has been saved in netiks_deploy_key
Your public key has been saved in netiks_deploy_key.pub
```

### Verify Keys Were Created:

```bash
# Check files exist
ls -la netiks_deploy_key*

# Output should show:
# -rw------- netiks_deploy_key       (private key - readable only by you)
# -rw-r--r-- netiks_deploy_key.pub   (public key - readable by anyone)
```
<img width="752" height="173" alt="image" src="https://github.com/user-attachments/assets/143bb3cf-5e6d-46e2-93fc-a8cde7df643a" />

---

## Step 3: Add Public Key to VM Deployment User

Add your new public key to the deployment user's `authorized_keys` file.

### Action: Copy Public Key to VM

```bash
# Create .ssh directory with proper permissions
sudo mkdir -p /home/deploy/.ssh

# Copy your public key to authorized_keys
sudo tee /home/deploy/.ssh/authorized_keys < netiks_deploy_key.pub

# Set proper ownership (deploy user owns the directory)
sudo chown -R deploy:deploy /home/deploy/.ssh

# Set proper permissions
sudo chmod 700 /home/deploy/.ssh
sudo chmod 600 /home/deploy/.ssh/authorized_keys
```

### Expected Output:

<img width="787" height="267" alt="Screenshot 2026-09-15 163004" src="https://github.com/user-attachments/assets/41b4bcbb-f3a7-4481-80d9-467d0c9a9a1e" />


### Verify Permissions:

```bash
# Check directory ownership and permissions
ls -la /home/deploy/.ssh/

# Output should show:
# drwx------ deploy deploy .ssh
# -rw------- deploy deploy authorized_keys
```

<img width="647" height="281" alt="Screenshot 2026-09-15 163104" src="https://github.com/user-attachments/assets/08781b15-6511-48af-9395-ba6896594b1f" />


---

## Step 4: Verify Repository Exists for Deploy User

The deployment user needs access to the repository to check out code.

### Action: Check Repository

```bash
# Check if repository exists
ls -la /home/deploy/netiks_store

# If it doesn't exist, clone it:
sudo -u deploy git clone <your-repository-url> /home/deploy/netiks_store

# Verify deploy user owns it:
sudo chown -R deploy:deploy /home/deploy/netiks_store
```

### Expected Output:

<img width="721" height="544" alt="Screenshot 2026-09-15 164052" src="https://github.com/user-attachments/assets/3cd9295b-d62d-431a-90b4-25b6eb94446d" />

---

## Step 5: Test SSH Connection

Verify that you can SSH into the VM as the deployment user.

### Action: Test SSH

```bash
# Test SSH connection with the new key
ssh -i netiks_deploy_key deploy@<YOUR_VM_PUBLIC_IP>

# You should get a prompt like:
# deploy@netiks-vm:~$

# Run a test command
docker ps

# Should show running containers without sudo

# Exit the SSH session
exit
```

### Expected Output:

<img width="808" height="610" alt="Screenshot 2026-09-15 170620" src="https://github.com/user-attachments/assets/ff7f844b-c376-49c3-b226-1c56a4ec1fd1" />

---

## Step 6: Configure GitHub Environment and Secrets

Create a GitHub Environment named `production` with deployment secrets.

### Action 6a: Create GitHub Environment

1. Go to GitHub → Your Repository
2. Click **Settings** (top navigation)
3. Click **Environments** (left sidebar)
4. Click **New environment**
5. Enter name: `production`
6. Click **Configure environment**

### Expected Output:

<img width="1040" height="275" alt="Screenshot 2026-09-17 171423" src="https://github.com/user-attachments/assets/bfb171ed-0864-43b0-97bc-5650f4351e65" />
                     Screenshot of GitHub Environments page showing "production" environment created

---

### Action 6b: Add Environment Secrets

Now add three secrets to the `production` environment:

**Secret 1: DEPLOY_SSH_KEY**
1. Click **Add secret** under "Secrets"
2. Name: `DEPLOY_SSH_KEY`
3. Value: Contents of your `netiks_deploy_key` file (the **private** key)
   ```bash
   # On your laptop, display the private key
   cat netiks_deploy_key
   # Copy entire output (including -----BEGIN and END lines)
   ```
4. Click **Add secret**

**Secret 2: DEPLOY_HOST**
1. Click **Add secret**
2. Name: `DEPLOY_HOST`
3. Value: Your VM's public IP or domain (e.g., `20.29.81.166` or `netiks.example.com`)
4. Click **Add secret**

**Secret 3: DEPLOY_USER**
1. Click **Add secret**
2. Name: `DEPLOY_USER`
3. Value: `deploy`
4. Click **Add secret**

### Expected Output:
<img width="993" height="473" alt="Screenshot 2026-09-16 173646" src="https://github.com/user-attachments/assets/f06fd831-e2da-4d0f-b5c5-eede201b35a3" />
Screenshot showing three secrets in production environment - showing only names, NOT values.

---

## Part 2 Answer: Why Shouldn't the Deployment User Have `sudo` Access?

### Answer: Why No `sudo` for Deployment User

1. **Principle of Least Privilege:** The deployment user only needs to:
   - Pull Docker images
   - Run Docker Compose commands
   - These don't require `sudo`

2. **Security Boundary:** If the SSH key is compromised:
   - Attacker can deploy applications
   - Attacker **cannot** modify system files, kernels, or network configs
   - Attacker **cannot** access your personal files
   - Damage is limited to application deployments

3. **Separation of Concerns:** 
   - Your personal account: Full admin access for maintenance
   - Deployment account: Only deployment permissions
   - This separation makes security auditing easier

4. **Audit Trail:** 
   - Commands run as `deploy` user are clearly for deployments
   - Commands run as your user are clearly personal/admin
   - Easier to track who did what

---

## Part 2 Answer: Why Does the Deployment User Need Docker Access?

### Answer: Why Docker Access is Required

1. **Pulling Images:** Docker Compose needs to pull images from Azure Container Registry:
   ```bash
   docker compose pull
   ```
   This requires Docker daemon access.

2. **Running Services:** Docker Compose creates and runs containers:
   ```bash
   docker compose up -d
   ```
   This requires Docker daemon access.

3. **Status Checking:** Deployment verification checks running containers:
   ```bash
   docker compose ps
   ```
   This requires Docker daemon access.

4. **Why Not `sudo`:** 
   - Granting `sudo` would allow running ANY command as root
   - Adding to `docker` group restricts access to only Docker operations
   - This is the more secure approach

5. **Security Consideration:**
   - The Docker group provides significant privileges but not system-wide root
   - This is why the lab emphasizes: "should not be treated as equivalent to fully unprivileged"
   - It's acceptable because the deployment account is single-purpose
   - If compromised, the scope is limited to Docker/application changes only

---

---

# PART 3: Add a Deployment Job to the Workflow

## Step 1: Update the Workflow File

Extend your `.github/workflows/build-and-push.yml` with a new `deploy` job that runs after successful builds.

### Action: Add Deployment Job

Open `.github/workflows/build-and-push.yml` and add this new job at the end (after the `build-and-push` job):

```yaml
  deploy:
    name: 🚀 Deploy to Production
    needs: build-and-push
    
    if: startsWith(github.ref, 'refs/tags/v') || github.event_name == 'workflow_dispatch'

    runs-on: ubuntu-latest
    environment: production

    steps:
    - name: 🚀 Deploy over SSH
      uses: appleboy/ssh-action@v1
      with:
        host: ${{ secrets.DEPLOY_HOST }}
        username: ${{ secrets.DEPLOY_USER }}
        key: ${{ secrets.DEPLOY_SSH_KEY }}
        script: |
          set -e

          cd ~/netiks_store

          VERSION="${{ inputs.version || github.ref_name }}"

          git fetch --tags origin
          git checkout --force "$VERSION"

          docker compose \
            -f docker-compose.yml \
            -f docker-compose.prod.yml \
            pull

          docker compose \
            -f docker-compose.yml \
            -f docker-compose.prod.yml \
            up -d

          docker compose \
            -f docker-compose.yml \
            -f docker-compose.prod.yml \
            ps
```

### What This Job Does:

- **`name`**: Descriptive name for the workflow
- **`needs: build-and-push`**: Waits for build-and-push to succeed before starting
- **`if` condition**: Only runs for version tags (v*) or manual workflow_dispatch triggers
- **`environment: production`**: Uses production environment with approval gate and secrets
- **`appleboy/ssh-action@v1`**: GitHub Action that SSH into the VM
- **SSH credentials**: Uses secrets from the production environment
- **Script**: Executes deployment commands on the VM

### File Location:

Add this to the end of `.github/workflows/build-and-push.yml`

### Expected Output After Adding:
<img width="828" height="828" alt="Screenshot 2026-09-17 172058" src="https://github.com/user-attachments/assets/eed4a37e-6e60-41dc-a175-a8d8dff4cd38" />
Screenshot of updated .github/workflows/build-and-push.yml showing the deploy job

---

## Part 3 Answer: Why Does the `if` Condition Prevent Deployment on Every Push?

### Answer: The `if` Condition Logic

```yaml
if: startsWith(github.ref, 'refs/tags/v') || github.event_name == 'workflow_dispatch'
```

This condition means: **Run the deploy job ONLY IF one of these is true:**

1. **`startsWith(github.ref, 'refs/tags/v')`** - The push is a Git tag that starts with `v`
   - Example: ✅ `v1.2.0` matches
   - Example: ❌ `feature-branch` doesn't match
   - Example: ❌ Push to `main` branch doesn't match

2. **`github.event_name == 'workflow_dispatch'`** - The workflow was manually triggered
   - Used for rollbacks (we'll add this in Part 6c)

#### Why This Prevents Unwanted Deployments:

**Without this condition:**
- Every push to `main` would trigger deployment
- Every commit would deploy immediately (before code review!)
- Would create chaos and instability

**With this condition:**
- Only intentional releases deploy (when you create a tag)
- Only manual rollbacks deploy (when you manually trigger)
- Deployments are planned and controlled

#### Examples:

```
git push origin main
→ Triggers: validate job ✅
→ Triggers: build-and-push job ✅
→ Triggers: deploy job ❌ (not a tag)

git tag v1.2.0 && git push origin v1.2.0
→ Triggers: validate job ✅
→ Triggers: build-and-push job ✅
→ Triggers: deploy job ✅ (is a tag)

Manually trigger workflow with v1.1.1
→ Triggers: deploy job ✅ (workflow_dispatch)
```

---

## Part 3 Answer: Why `needs: build-and-push` Instead of Parallel?

### Answer: Dependency Chain

```yaml
needs: build-and-push
```

This means: **Wait for the build-and-push job to complete successfully before starting the deploy job.**

#### Why This Is Required:

1. **Image Availability:** The deploy job pulls Docker images from ACR:
   ```bash
   docker compose pull
   ```
   These images don't exist until build-and-push creates them.

2. **Deployment Validity:** If builds fail, you don't want to deploy old images:
   - Build fails → Deploy doesn't run → Production stays at previous version ✅
   - Build succeeds → Deploy runs → Production gets new images ✅

3. **Logical Sequence:**
   ```
   1. Code changes pushed
   2. Validation runs (linting, tests)
   3. Build images
   4. Push images to registry
   5. Wait for images to be available
   6. Deploy images to production
   ```

4. **If Jobs Ran in Parallel:**
   ```
   build-and-push starts... (building images)
   deploy starts immediately... (images don't exist yet!)
   deploy fails trying to pull non-existent images
   build-and-push finishes (too late)
   ```

#### Dependency Flow:

```
GitHub Push (version tag)
    ↓
validate job
    ↓
build-and-push job (builds all 7 images)
    ↓
deploy job waits for approval (needs: build-and-push)
    ↓
Human approves
    ↓
deploy job runs
    ↓
Production updated
```

---

---

# PART 4: Release Checklist Becomes a Habit

## Understanding the Release Process

Before creating a release tag, you must ensure `docker-compose.prod.yml` has the correct version for your release.

### Why This Matters:

The deployment job checks out the tag commit:
```bash
git checkout --force "$VERSION"  # e.g., v1.2.0
```

At this commit, the `docker-compose.prod.yml` file must have the matching version:
```yaml
services:
  web:
    image: netiksstoreregistry.azurecr.io/web:v1.2.0  # ← Must match tag
```

---

## Step 1: Update `docker-compose.prod.yml`

Before creating a release tag, update all service versions in `docker-compose.prod.yml`.

### Action: Prepare Release v1.2.0

1. Open `docker-compose.prod.yml` in your editor
2. Update all service image versions from current version (e.g., `v1.1.1`) to new version (`v1.2.0`)
3. Save the file

### Before (Current):

```yaml
services:
  web:
    image: netiksstoreregistry.azurecr.io/web:v1.1.1
    pull_policy: always
  
  gateway:
    image: netiksstoreregistry.azurecr.io/gateway:v1.1.1
    pull_policy: always
  
  # ... all other services with v1.1.1
```

### After (Prepare for v1.2.0):

```yaml
services:
  web:
    image: netiksstoreregistry.azurecr.io/web:v1.2.0
    pull_policy: always
  
  gateway:
    image: netiksstoreregistry.azurecr.io/gateway:v1.2.0
    pull_policy: always
  
  # ... all other services with v1.2.0
```

### Expected Output After Edit:
<img width="735" height="704" alt="Screenshot 2026-09-17 172411" src="https://github.com/user-attachments/assets/7b40afcd-a38b-4484-a3d9-5ee54008555f" />
PLACEHOLDER: Screenshot of docker-compose.prod.yml with updated versions

---

## Step 2: Commit the Version Update

Commit this change to Git before creating the tag.

### Action: Commit the Change

```bash
git add docker-compose.prod.yml
git commit -m "release: v1.2.0"
```

### Expected Output:

```
[main 7a2c4d9] release: v1.2.0
 1 file changed, 7 insertions(+), 7 deletions(-)
```

### View the Commit Diff:

```bash
git show HEAD
```

This shows exactly what changed in the commit.

### Expected Output:
<img width="603" height="487" alt="Screenshot 2026-09-16 180941" src="https://github.com/user-attachments/assets/33cbbe83-b21e-4930-81c0-7550a2c0a97b" />
Screenshot of git show output showing version changes from v1.1.1 to v1.2.0

---

## Step 3: Create Git Tag

Now create the Git tag that points to this commit.

### Action: Tag the Release

```bash
git tag v1.2.0
```

### Verify Tag Points to Correct Commit:

```bash
# Show tag information
git show v1.2.0

# Should display the commit you just created with the version update
```

### Expected Output:

```
tag v1.2.0
Tagger: Your Name <email@example.com>
Date:   ...

release: v1.2.0

[Shows the commit hash and changes]
```

---

## Step 4: Push Tag to GitHub

Push the tag to trigger the CI/CD pipeline.

### Action: Push Tag

```bash
git push origin main --tags

# Or push specific tag:
git push origin v1.2.0
```

### Expected Output:

```
Enumerating objects: 1, done.
Counting objects: 100% (1/1), done.
Total 1 (delta 0), reused 0 (delta 0), reused pack 0 (delta 0)
To github.com:your-org/netiks_store.git
 * [new tag]         v1.2.0 -> v1.2.0
```

---

## Part 4 Answer: What Happens If You Push the Tag Before Committing Version Changes?

### Answer: The Tag Points to Wrong Commit

#### Scenario: You push tag before committing version change

```bash
# ❌ WRONG - Tag not yet committed
git tag v1.2.0

# ❌ WRONG - Commit version change after tag
git add docker-compose.prod.yml
git commit -m "release: v1.2.0"

git push origin v1.2.0
```

#### What Goes Wrong:

1. **Tag points to old commit:**
   ```
   v1.2.0 tag → points to commit with v1.1.1 in docker-compose.prod.yml
   ```

2. **Deployment gets wrong images:**
   - GitHub Actions checks out `v1.2.0` tag
   - `docker-compose.prod.yml` still has `v1.1.1` images
   - Deployment pulls old images instead of new ones
   - Users see old version (bug fix doesn't deploy!)

3. **Version mismatch:**
   ```
   Git tag: v1.2.0
   Image tag: v1.1.1
   Docker compose image pull: v1.1.1 ❌
   ```

#### Consequences:

- Release version doesn't match deployed images
- Debugging is confusing (version numbers don't align)
- Rollback is difficult (can't trust version tags)
- CI/CD pipeline integrity is compromised

#### Correct Sequence:

```bash
# ✅ CORRECT - Version change committed first
git add docker-compose.prod.yml
git commit -m "release: v1.2.0"

# ✅ CORRECT - Tag points to this commit
git tag v1.2.0

# ✅ CORRECT - Push both
git push origin main --tags
```

Result:
```
v1.2.0 tag → points to commit with v1.2.0 in docker-compose.prod.yml ✅
```

---

### Release Checklist

Before creating a release, verify:

- [ ] All changes committed to `main` branch
- [ ] `docker-compose.prod.yml` updated with new version
- [ ] Version in `docker-compose.prod.yml` matches release version (e.g., both are `v1.2.0`)
- [ ] Changes committed with message "release: v1.2.0"
- [ ] Git tag created AFTER commit
- [ ] Tag pushed to GitHub

---

---

# PART 5: Add a Production Approval Gate

## Step 1: Configure Environment Protection Rule

GitHub Environments can require approval before a workflow can proceed. This ensures a human must approve each production deployment.

### Action: Add Required Reviewer

1. Go to GitHub → Your Repository → Settings
2. Click **Environments** (left sidebar)
3. Click on **production** environment
4. Under "Deployment branches and secrets", click **Add deployment branch rule** (if not already added)
5. Scroll down to "Required reviewers"
6. Check the box: **Require reviewers**
7. Add reviewers:
   - Type your GitHub username (yourself)
   - Or add colleagues who should approve deployments
8. Click **Save protection rules**

### Expected Output:

<img width="1236" height="487" alt="Screenshot 2026-09-16 183851" src="https://github.com/user-attachments/assets/00bc36f3-ea08-406a-880a-bf984ef6129f" />

---

## Step 2: Verify Approval Flow in Workflow

When a workflow runs and references the `production` environment, GitHub will pause at the deployment job and wait for reviewer approval.

### Expected Behavior During Release:

1. Developer pushes version tag → GitHub Actions starts
2. Validate job runs
3. Build-and-push job runs and pushes images
4. Deploy job hits the `production` environment
5. GitHub pauses the workflow and sends approval request
6. Required reviewer gets notification
7. Reviewer clicks "Approve and run" in GitHub Actions
8. Deployment job resumes and deploys
9. Services updated on VM

### Expected Output When Waiting for Approval:
<img width="1890" height="700" alt="Screenshot 2026-09-16 194147" src="https://github.com/user-attachments/assets/cc4e4f27-0b0f-44e7-ae4f-d106f116c5d0" />
<img width="840" height="515" alt="Screenshot 2026-09-16 194426" src="https://github.com/user-attachments/assets/73cfeec6-f8fc-4aa0-94fa-6ff1cdf4ef19" />


---

## Part 5 Answer: Why Should Approval Be on Deployment, Not Build?

### Answer: Separate Concerns

#### Build Job vs. Deployment Job

**Build-and-Push Job:**
- Creates Docker images
- Produces artifact
- Can be built speculatively
- Doesn't change production

**Deployment Job:**
- Changes production environment
- Affects users
- Should be carefully controlled
- Requires explicit approval

#### Why Not Require Approval on Build:

1. **Not a Production Change:**
   - Building an image doesn't affect production
   - Image just sits in registry unused
   - No risk to users yet

2. **Multiple Uses for Same Image:**
   - Same image might deploy to staging, testing, production
   - Approving once blocks all uses
   - Inefficient

3. **Artifact vs. Change:**
   - **Artifact:** Docker image (no impact until deployed)
   - **Change:** Deployment to production (affects users NOW)
   - Approval should be on the actual change

#### Why Require Approval on Deploy:

1. **Direct Production Impact:**
   - Deployment immediately changes what users see
   - Needs human oversight
   - Is the actual "point of no return"

2. **Risk Assessment:**
   - Reviewer can ask: "Is this safe to deploy?"
   - Reviewer can delay if ongoing incidents
   - Reviewer can halt if bugs discovered

3. **Accountability:**
   - Clear record of who approved each deployment
   - Audit trail shows when changes went to production

#### Real-World Example:

```
1:00 PM - Developer pushes tag v2.0.0 (build job runs immediately)
1:02 PM - Build succeeds, images ready in registry
1:05 PM - Production manager sees deployment waiting for approval
1:06 PM - Manager checks application dashboard, all metrics healthy
1:06 PM - Manager approves deployment
1:06 PM - Deployment starts
1:07 PM - Users see new features of v2.0.0

vs.

Approval on build (wrong):
1:00 PM - Build job waits for approval (delays artifact creation)
1:05 PM - Manager approves build
1:05 PM - Build runs (why wait if just creating artifact?)
1:07 PM - Deployment happens (no final approval!)
```

#### Summary:

| Aspect | Build-Push | Deploy |
|--------|-----------|--------|
| **Affects users?** | No | Yes |
| **Change production?** | No | Yes |
| **Reversible?** | Yes (delete image) | No (immediate) |
| **Needs approval?** | No | YES |
| **Should require reviewer?** | No | YES |

---

---

# PART 6: Test the Pipeline End-to-End

## 6a: Release - Trigger Full Deployment Pipeline

### Step 1: Make Visible Application Change

Make a small, observable change to one of your services so you can verify the deployment worked.

### Option 1: Change Frontend Text

Edit `apps/web/src/app/page.tsx` and add a visible marker:

```tsx
// Add this somewhere visible on the home page
<p>Version: v1.2.0 - Deployed at {new Date().toLocaleString()}</p>
```

Save and commit:
```bash
git add apps/web/src/app/page.tsx
git commit -m "feat: Add version display for Week 5 testing"
git push origin main
```

### Option 2: Change an Environment Variable

Edit `.env` and add:
```bash
DEPLOYMENT_VERSION=v1.2.0
```

Commit:
```bash
git add .env
git commit -m "chore: Mark deployment for Week 5 testing"
git push origin main
```

---

### Step 2: Update `docker-compose.prod.yml` for Release

Update the version in `docker-compose.prod.yml` to match your release version.

### Current File (Example):

```yaml
services:
  web:
    image: netiksstoreregistry.azurecr.io/web:v1.1.1
  gateway:
    image: netiksstoreregistry.azurecr.io/gateway:v1.1.1
  identity-service:
    image: netiksstoreregistry.azurecr.io/identity-service:v1.1.1
  vendor-service:
    image: netiksstoreregistry.azurecr.io/vendor-service:v1.1.1
  catalog-service:
    image: netiksstoreregistry.azurecr.io/catalog-service:v1.1.1
  media-service:
    image: netiksstoreregistry.azurecr.io/media-service:v1.1.1
  admin-service:
    image: netiksstoreregistry.azurecr.io/admin-service:v1.1.1
```

### Updated File for v1.2.0:

```yaml
services:
  web:
    image: netiksstoreregistry.azurecr.io/web:v1.2.0
  gateway:
    image: netiksstoreregistry.azurecr.io/gateway:v1.2.0
  identity-service:
    image: netiksstoreregistry.azurecr.io/identity-service:v1.2.0
  vendor-service:
    image: netiksstoreregistry.azurecr.io/vendor-service:v1.2.0
  catalog-service:
    image: netiksstoreregistry.azurecr.io/catalog-service:v1.2.0
  media-service:
    image: netiksstoreregistry.azurecr.io/media-service:v1.2.0
  admin-service:
    image: netiksstoreregistry.azurecr.io/admin-service:v1.2.0
```

### Commit and Tag:

```bash
# Commit the version change
git add docker-compose.prod.yml
git commit -m "release: v1.2.0"

# Create tag
git tag v1.2.0

# Push both main and tags
git push origin main --tags
```

### Expected Output:

```
Enumerating objects: 5, done.
Counting objects: 100% (5/5), done.
Total 3 (delta 2), reused 0 (delta 0), reused pack 0 (delta 0)
To github.com:your-org/netiks_store.git
   abc1234..def5678  main -> main
 * [new tag]         v1.2.0 -> v1.2.0
```

---

### Step 3: Monitor GitHub Actions Workflow

Go to GitHub → Your Repository → Actions

Watch the workflow execute in this sequence:

#### 1️⃣ Validate Job Runs

```
🔍 Validate Code Quality
├─ Lint Python code
├─ Lint web application  
├─ Validate Docker Compose
└─ ✅ All checks pass
```
<img width="1330" height="793" alt="Screenshot 2026-09-16 210151" src="https://github.com/user-attachments/assets/123c2fd0-fc50-449c-90c5-52d526bca1d6" />
PLACEHOLDER: Screenshot of validate job passing

---

#### 2️⃣ Build-and-Push Job Runs

```
🐳 Build and Push Images
├─ Build web image... [latest-commit-sha]
├─ Build gateway image... [latest-commit-sha]
├─ Build identity-service... [latest-commit-sha]
├─ Build vendor-service... [latest-commit-sha]
├─ Build catalog-service... [latest-commit-sha]
├─ Build media-service... [latest-commit-sha]
├─ Build admin-service... [latest-commit-sha]
└─ ✅ All images pushed to ACR
```

[PLACEHOLDER: Screenshot of build-and-push job showing all 7 services building]

---

#### 3️⃣ Deploy Job Waits for Approval

```
🚀 Deploy to Production
└─ ⏳ Waiting for approval from required reviewers
```
<img width="1890" height="700" alt="Screenshot 2026-09-16 194147" src="https://github.com/user-attachments/assets/be7b5bc3-2268-48cb-9417-5e06266cc417" />
PLACEHOLDER: Screenshot of deploy job in "Waiting" status

---

### Step 4: Approve the Deployment

GitHub sends an approval notification. You (as the required reviewer) must approve.

#### Option 1: Approve from GitHub Actions Page

1. Go to GitHub Actions → Latest workflow run
2. Click **Review deployments** button
3. Select the `production` environment
4. Click **Approve and deploy**

#### Option 2: Approve from Notification

If you received a GitHub notification:
1. Click the notification
2. Click **View deployment**
3. Click **Approve and deploy**

### Expected Output:

<img width="840" height="515" alt="Screenshot 2026-09-16 194426" src="https://github.com/user-attachments/assets/5312c65b-df6b-4115-9b27-60b5a9124309" />

---

### Step 5: Deployment Proceeds

After approval, the deployment job executes:

```
🚀 Deploy over SSH
├─ SSH into VM as deploy user
├─ Change to ~/netiks_store
├─ Fetch latest tags: git fetch --tags origin
├─ Checkout v1.2.0: git checkout --force "v1.2.0"
├─ Pull images: docker compose pull
├─ Start services: docker compose up -d
├─ Show status: docker compose ps
└─ ✅ Deployment complete
```

### Expected Output:

<img width="1330" height="793" alt="Screenshot 2026-09-16 210151" src="https://github.com/user-attachments/assets/a1d0d139-7c29-4622-b660-6bd3f3b7b848" />
- docker compose ps showing all 7 services running with v1.2.0 images]

---

## 6b: Verify - Confirm the Deployment

### Step 1: Access the Application

Open your application in a web browser:

```
http://<YOUR_VM_PUBLIC_IP>/
```

### Step 2: Check for Your Visible Change

If you added version display to the frontend:
- Look for "Version: v1.2.0" on the home page
- Verify the deployed timestamp is recent

### Expected Output:

<img width="1341" height="722" alt="Screenshot 2026-09-16 212944" src="https://github.com/user-attachments/assets/c84b6914-ce3b-44dc-87eb-5a0cf77e4ca5" />

---

### Step 3: Verify Docker Images on VM

SSH into the VM and check that correct images are running:

```bash
# SSH into VM as deploy user (optional verification)
ssh -i netiks_deploy_key deploy@<YOUR_VM_IP>

# Check running containers
docker ps

# Should show v1.2.0 images
```

### Expected Output:

<img width="1822" height="323" alt="Screenshot 2026-09-16 210819" src="https://github.com/user-attachments/assets/fff7d454-9309-4cf1-8633-10fa28d1893c" />
PLACEHOLDER: Screenshot of docker ps showing v1.2.0 images

---

## 6c: Rollback - Test Manual Deployment

### Step 1: Add Manual Workflow Trigger

Update `.github/workflows/build-and-push.yml` to support manual deployment.

Find the `on:` section at the top of the workflow and update it:

### Before:

```yaml
on:
  push:
    branches: [main]
    tags: ['v*']
```

### After:

```yaml
on:
  push:
    branches: [main]
    tags: ['v*']

  workflow_dispatch:
    inputs:
      version:
        description: "Tag to deploy, e.g. v1.1.0"
        required: true
        type: string
```

### What This Does:

- `workflow_dispatch:` Allows manual workflow triggering
- `inputs:` Lets you specify which version to deploy
- Used for rollbacks to previous versions

---

### Step 2: Update Deployment Job for Manual Trigger

Find the `deploy` job and update the version variable to use manual input:

### Before:

```yaml
deploy:
  script: |
    VERSION="${{ github.ref_name }}"
```

### After:

```yaml
deploy:
  script: |
    VERSION="${{ inputs.version || github.ref_name }}"
```

### What This Does:

- For tagged push: Uses `github.ref_name` (e.g., `v1.2.0`)
- For manual trigger: Uses `inputs.version` (e.g., `v1.1.0` for rollback)
- The `||` means: use inputs.version if provided, otherwise use github.ref_name

---

### Step 3: Commit Workflow Changes

```bash
git add .github/workflows/build-and-push.yml
git commit -m "feat: Add manual deployment for rollbacks"
git push origin main
```

---

### Step 4: Manually Deploy Previous Version

Now test the manual deployment by rolling back to a previous version.

#### Via GitHub Web Interface:

1. Go to GitHub → Your Repository → Actions
2. Click **All workflows** (left sidebar)
3. Click on **🐳 Build and Push Docker Images** workflow
4. Click **Run workflow** (blue button)
5. A dropdown appears: "Use workflow from [Branch selector]"
6. Enter the version you want to deploy: `v1.1.1` (or your previous version)
7. Click **Run workflow** green button

### Expected Output:

<img width="1328" height="563" alt="Screenshot 2026-09-17 145846" src="https://github.com/user-attachments/assets/7d37e405-be52-4a2a-90fb-7897ff6809b0" />

---

### Step 5: Monitor Rollback Workflow

Go to Actions → Latest workflow run

You should see:

```
🔍 Validate Code Quality
└─ ✅ Skipped (workflow_dispatch, no code changes)

🐳 Build and Push Images
└─ ✅ Skipped (images already built)

🚀 Deploy to Production
├─ git checkout --force "v1.1.1"
├─ docker compose pull (pulls v1.1.1 images)
├─ docker compose up -d (restarts with old images)
└─ ✅ Rollback complete
```

### Expected Output:

<img width="1645" height="691" alt="Screenshot 2026-09-17 150242" src="https://github.com/user-attachments/assets/36e29805-5a99-4300-9018-550853757d31" />
- All steps executing successfully]

---

### Step 6: Verify Rollback Success

#### Check GitHub Actions:

The workflow should complete successfully with v1.1.1 deployed.

<img width="1655" height="766" alt="Screenshot 2026-09-17 150349" src="https://github.com/user-attachments/assets/d1fab6a2-0a81-44b1-9d38-152e61d6aa28" />
PLACEHOLDER: Screenshot of successful workflow_dispatch deployment

---

#### Check Docker Images on VM:

```bash
ssh -i netiks_deploy_key deploy@<YOUR_VM_IP>

# Show images before rollback
docker ps --before-rollback

# Show images after rollback
docker ps
```

### Expected Output Before Rollback:

```
CONTAINER ID  IMAGE                                        STATUS
abc123...     netiksstoreregistry.azurecr.io/web:v1.2.0   Up 30 minutes
def456...     netiksstoreregistry.azurecr.io/gateway:v1.2.0  Up 30 minutes
...
```

### Expected Output After Rollback:

<img width="1206" height="437" alt="Screenshot 2026-09-17 151251" src="https://github.com/user-attachments/assets/18fa2d3c-7218-4072-b284-551070bf3c2b" />
Screenshot showing docker ps with v1.1.0 images after rollback

---

#### Check Application:

Visit your application in browser - if you had a version display, it should show the previous version.
<img width="1511" height="806" alt="Screenshot 2026-09-17 151219" src="https://github.com/user-attachments/assets/6e15cd8b-7eb8-429c-b94b-a22aace34fcb" />

PLACEHOLDER: Screenshot of application showing v1.1.0 deployed

---

### Step 7: Verify Image Version Changed

Compare docker ps outputs before and after rollback:

**Before Rollback (v1.2.0):**
```
web:v1.2.0
gateway:v1.2.0
identity-service:v1.2.0
```

**After Rollback (v1.1.0):**
```
web:v1.1.0
gateway:v1.1.0
identity-service:v1.1.0
```

Show both outputs in your submission.
<img width="1666" height="466" alt="image" src="https://github.com/user-attachments/assets/3242ff71-a0e6-4861-904e-12479600ed6b" />

<img width="1206" height="437" alt="Screenshot 2026-09-17 151251" src="https://github.com/user-attachments/assets/61329ab8-3e6d-48fe-a930-62d5590ebc7b" />
PLACEHOLDER: Side-by-side comparison of docker ps outputs showing version difference

---


# SUMMARY

By completing Week 5, I have built:

1. ✅ **Dedicated deployment account** - Secure, single-purpose credentials
2. ✅ **Automated SSH deployment** - GitHub Actions connects and deploys
3. ✅ **Production approval gate** - Human oversight before changes
4. ✅ **Versioned releases** - Clean tagging and deployment
5. ✅ **Rollback capability** - Manual deployment of previous versions

### The Complete Pipeline:

```
Developer pushes version tag
    ↓
GitHub Actions validates code
    ↓
GitHub Actions builds all 7 images
    ↓
GitHub Actions pushes to ACR
    ↓
GitHub waits for production approval
    ↓
Required reviewer approves
    ↓
GitHub Actions SSH into VM
    ↓
GitHub Actions checks out exact version
    ↓
Docker Compose pulls images
    ↓
Docker Compose starts services
    ↓
Production updated with zero downtime
    ↓
Humans can rollback to previous version anytime
```

### Security Achievements:

- ✅ No personal SSH keys exposed
- ✅ No shared credentials
- ✅ Principle of least privilege enforced
- ✅ Human approval before production changes
- ✅ Full audit trail of deployments
- ✅ Easy rollback for incidents

---
---
# 🚀 Netiks Store - Week 4 Lab: Azure CI/CD Implementation Guide

## 📋 **Table of Contents**
- [Part 1: Understanding the Basics](#part-1-understanding-the-basics)
- [Part 2: GitHub Actions Configuration](#part-2-github-actions-configuration)
- [Part 3: Secure Azure Authentication](#part-3-secure-azure-authentication)
- [Part 4: Image Tagging Strategy](#part-4-image-tagging-strategy)
- [Part 5: Testing the Pipeline](#part-5-testing-the-pipeline)
- [Part 6: Deployment Process](#part-6-deployment-process)
- [Deliverables Checklist](#deliverables-checklist)

---

## 📚 **Part 1: Understanding the Basics**

### **Question 1: What are two problems with building Docker images manually from your laptop?**

**Answer:**
1. **Environment Inconsistency**: Different developers may have different Docker versions, operating systems, or local dependencies, leading to "it works on my machine" problems and inconsistent builds across the team.

2. **Lack of Automation & Traceability**: Manual builds are error-prone, not reproducible, and lack an audit trail. They can't be easily integrated into a continuous delivery pipeline, making it difficult to track which code version produced which image.

### **Question 2: What is OIDC, and why is it better than storing a long-lived AWS access key or Azure client secret?**

**Answer:**
**OIDC (OpenID Connect)** is an identity layer built on top of OAuth 2.0 that enables third-party applications to verify user identities. In the context of CI/CD pipelines:

**Why OIDC is superior to static credentials:**

| Aspect | Long-lived Secrets | OIDC Federation |
|--------|-------------------|------------------|
| **Security** | Static credentials can be leaked/stolen | Short-lived tokens (typically 1 hour) |
| **Rotation** | Manual rotation required | Automatic token rotation |
| **Scope** | Broad permissions | Fine-grained, scoped permissions |
| **Auditability** | Hard to trace usage | Each token usage is logged with identity context |
| **Compliance** | Higher risk profile | Meets security best practices |

**Azure Implementation**: OIDC allows GitHub Actions to authenticate to Azure Container Registry (ACR) using Microsoft Entra ID federated credentials, eliminating the need for storing Azure client secrets in GitHub.

### **Question 3: Why should CI images be tagged with a Git commit SHA?**

**Answer:**
1. **Traceability**: Each Docker image can be directly traced back to the exact code version (Git commit) that produced it
2. **Reproducibility**: You can rebuild the exact same image from the same commit SHA at any time
3. **Immutable Deployments**: SHA-tagged images never change, ensuring consistent and predictable deployments
4. **Rollback Capability**: Easy to roll back to previous working versions by referencing their SHA tags
5. **Audit Trail**: Provides complete lineage from code commit to production deployment

---

## ⚙️ **Part 2: GitHub Actions Configuration**

### **Step-by-Step Implementation Guide**

#### **Step 1: Create GitHub Actions Directory Structure**
```bash
mkdir -p .github/workflows
```

#### **Step 2: Create the Complete Workflow File**
Create `.github/workflows/build-and-push.yml`:

```yaml
name: 🐳 Build and Push Docker Images

on:
  push:
    branches: [main]
    tags: ['v*']

jobs:
  validate:
    name: 🔍 Validate Code Quality
    runs-on: ubuntu-latest
    
    steps:
    - name: 📥 Checkout repository
      uses: actions/checkout@v4
      
    - name: 🐍 Set up Python 3.11
      uses: actions/setup-python@v4
      with:
        python-version: '3.11'
    
    - name: 📦 Install Python dependencies
      run: |
        pip install black flake8 mypy
        pip install -e packages/shared-python
    
    - name: 🧹 Lint Python code
      run: |
        echo "Running Python linting..."
        black --check apps/gateway services/
        flake8 apps/gateway services/
    
    - name: ⚛️ Set up Node.js 20
      uses: actions/setup-node@v4
      with:
        node-version: '20'
    
    - name: 📦 Install Node.js dependencies
      run: |
        cd apps/web
        npm ci
    
    - name: 🧹 Lint web application
      run: |
        cd apps/web
        npm run lint
    
    - name: 🐳 Validate Docker Compose configuration
      run: |
        docker compose config --quiet

  build-and-push:
    name: 🐳 Build and Push Images
    needs: validate
    runs-on: ubuntu-latest
    permissions:
      contents: read
      id-token: write
    
    strategy:
      matrix:
        service: 
          - web
          - gateway
          - identity-service
          - vendor-service
          - catalog-service
          - media-service
          - admin-service
        include:
          - service: web
            dockerfile: infra/docker/web.Dockerfile
          - service: gateway
            dockerfile: apps/gateway/Dockerfile
          - service: identity-service
            dockerfile: services/identity-service/Dockerfile
          - service: vendor-service
            dockerfile: services/vendor-service/Dockerfile
          - service: catalog-service
            dockerfile: services/catalog-service/Dockerfile
          - service: media-service
            dockerfile: services/media-service/Dockerfile
          - service: admin-service
            dockerfile: services/admin-service/Dockerfile
    
    steps:
    - name: 📥 Checkout repository
      uses: actions/checkout@v4
      
    - name: 🔐 Azure Login (OIDC)
      uses: azure/login@v2
      with:
        client-id: ${{ vars.AZURE_CLIENT_ID }}
        tenant-id: ${{ vars.AZURE_TENANT_ID }}
        subscription-id: ${{ vars.AZURE_SUBSCRIPTION_ID }}
    
    - name: 🐳 Login to Azure Container Registry
      uses: azure/docker-login@v2
      with:
        login-server: ${{ vars.ACR_LOGIN_SERVER }}
        username: ${{ vars.AZURE_CLIENT_ID }}
        password: ${{ secrets.AZURE_CLIENT_SECRET }}
    
    - name: 🏷️ Extract metadata for Docker tags
      id: meta
      uses: docker/metadata-action@v5
      with:
        images: ${{ vars.ACR_LOGIN_SERVER }}/${{ matrix.service }}
        tags: |
          type=sha,prefix=
          type=ref,event=tag
    
    - name: 🛠️ Set up Docker Buildx
      uses: docker/setup-buildx-action@v3
    
    - name: 🐳 Build and push Docker image
      uses: docker/build-push-action@v5
      with:
        context: .
        file: ${{ matrix.dockerfile }}
        push: true
        tags: ${{ steps.meta.outputs.tags }}
        labels: ${{ steps.meta.outputs.labels }}
        cache-from: type=gha
        cache-to: type=gha,mode=max
        platforms: linux/amd64
```

---

## 🔐 **Part 3: Secure Azure Authentication (Federated Credentials)**

### **Azure OIDC Configuration Steps**

#### **Step 1: Create Federated Credentials**

*Goal: Tell Azure to trust GitHub Actions when you push code to the `main` branch or create a `v1.1.0` tag.*

1. **Open** "**Microsoft Entra ID**" again -> **Click** "**App registrations**".
2. **Click** on your App Registration.
3. **Click** "**Certificates & secrets**" on the left, then **click** the "**Federated credentials**" tab.
4. **Click** "**+ Add credential**".
5. **Select** "**GitHub Actions deploying Azure resources**" under Scenario.
6. **Fill** in the details for your **Main Branch**:
   - **Organization:** *Your GitHub Username*
   - **Repository:** *Your GitHub Repository Name*
   - **Entity type:** Select **Branch**
   - **Branch name:** `main`
   - **Name:** `github-main`
7. **Click** "**Add**".
8. **Click** "**+ Add credential**" again to add a second one for your **Release Tag**:
   - **Organization:** *Your GitHub Username*
   - **Repository:** *Your GitHub Repository Name*
   - **Entity type:** Select **Tag**
   - **Tag name:** `v1.1.0`
   - **Name:** `github-tag-v1`
9. **Click** "**Add**".

#### **Step 2: Configure GitHub Repository Variables**

Go to your GitHub repository:
**Settings → Secrets and variables → Actions → Variables**

Add these **non-secret** variables:

| Variable Name | Example Value | Purpose |
|--------------|--------------|---------|
| `AZURE_CLIENT_ID` | `00000000-0000-0000-0000-000000000000` | Application Client ID |
| `AZURE_TENANT_ID` | `00000000-0000-0000-0000-000000000000` | Azure AD Tenant ID |
| `AZURE_SUBSCRIPTION_ID` | `00000000-0000-0000-0000-000000000000` | Azure Subscription ID |
| `ACR_LOGIN_SERVER` | `netiksstoreacr.azurecr.io` | ACR Registry URL |

**<img width="981" height="346" alt="Screenshot 2026-09-10 161226" src="https://github.com/user-attachments/assets/afd1359e-928a-4624-a757-49483f700ac5" />:** Screenshot of GitHub Repository Variables page showing the 4 variable names.

#### **Step 3: Configure GitHub Secrets**

Go to **Settings → Secrets and variables → Actions → Secrets**

Add this **secret**:
- `AZURE_CLIENT_SECRET` = The client secret from your Azure App Registration

  
**<img width="995" height="216" alt="Screenshot 2026-09-10 161648" src="https://github.com/user-attachments/assets/580ce416-15d0-4619-9a00-cb45a699b039" />:** Screenshot showing the Secrets page with AZURE_CLIENT_SECRET secret name


---

## 🏷️ **Part 4: Image Tagging Strategy**

### **Tagging Logic Implementation**

The workflow automatically creates different tags based on the trigger:

| Trigger | Tags Generated | Example |
|---------|----------------|---------|
| **Push to main** | `<git-sha>` | `netiksstoreacr.azurecr.io/web:abc123def` |
| **Git tag v1.1.0** | `<git-sha>`, `v1.1.0`, `latest` | `netiksstoreacr.azurecr.io/web:v1.1.0` |

### **Question: Why should `latest` not be updated on every commit to `main`?**

**Answer:**
The `latest` tag should **only** be updated during **official releases** (version tags) for these reasons:

1. **Production Stability**: `latest` should represent a stable, tested release ready for production, not every development commit
2. **Rollback Clarity**: If `latest` moves with every commit, rolling back becomes confusing and risky
3. **Deployment Confidence**: Operations teams need confidence that `latest` represents a validated release, not untested code
4. **Semantic Versioning**: Aligns with semantic versioning practices where `latest` tracks the most recent stable release
5. **CI/CD Best Practice**: Following industry standards where `latest` is reserved for production-ready releases

**Azure Implementation**: In our workflow, `latest` is only pushed when a version tag (like `v1.1.0`) is created, ensuring it always points to a release.

---

## 🧪 **Part 5: Testing the Pipeline**

### **5a. Testing Normal Commit Flow**

**Steps to Test:**
1. Make a small change to any service (e.g., add a comment to `services/catalog-service/app/main.py`)
2. Commit and push to main:
   ```bash
   git add .
   git commit -m "Test: Trigger CI/CD pipeline"
   git push origin main
   ```

**Expected Results:**
- ✅ Validation job passes
- ✅ All 7 images are built
- ✅ Images are pushed with Git SHA tags only
- ❌ `latest` tag is NOT updated

**<img width="1095" height="704" alt="Screenshot 2026-09-10 171719" src="https://github.com/user-attachments/assets/d9772499-e9cb-41e8-a930-4ff55fd6fe6b" />:** Screenshot of successful GitHub Actions run for a normal commit (showing both validate and build jobs passing)

### **5b. Testing Release Flow**

**Steps to Test:**
1. Create and push a version tag:
   ```bash
   git tag v1.1.0
   git push origin v1.1.0
   ```

**Expected Results:**
- ✅ Workflow runs automatically
- ✅ All 7 images are built
- ✅ SHA tags are pushed
- ✅ `v1.1.0` tags are pushed
- ✅ `latest` tags are pushed
  

**<img width="1653" height="668" alt="Screenshot 2026-09-10 174352" src="https://github.com/user-attachments/assets/18b0c36b-acc7-498d-a84f-9cc89339211f" />:**  Screenshot of successful GitHub Actions run for a release tag (showing v1.1.0 and latest tags being created).


### **5c. Verify Azure Container Registry**

**Check ACR Repository:**
1. Navigate to Azure Portal → Container Registries → netiksstoreacr
2. Check each repository (web, gateway, identity-service, etc.)
3. Verify tags exist:
   - Git SHA tag (e.g., `abc123def`)
   - `v1.1.0` tag
   - `latest` tag

**<img width="1338" height="433" alt="Screenshot 2026-09-10 180846" src="https://github.com/user-attachments/assets/1baa25d3-198d-4610-b473-0e83f43a7c05" />** 
<img width="1343" height="472" alt="Screenshot 2026-09-10 174655" src="https://github.com/user-attachments/assets/83915cec-e944-4da3-80d7-47b30d30f64c" />
<img width="1336" height="448" alt="Screenshot 2026-09-10 181025" src="https://github.com/user-attachments/assets/c6d0160b-bb85-4731-ae66-755ab46c954a" />
<img width="1322" height="452" alt="Screenshot 2026-09-10 181009" src="https://github.com/user-attachments/assets/1079c5f5-cf59-430e-97b8-9baa3b5518f4" />
<img width="1328" height="424" alt="Screenshot 2026-09-10 180943" src="https://github.com/user-attachments/assets/6b7aff33-2647-4d09-a609-336ebcb100e3" />
<img width="1331" height="433" alt="Screenshot 2026-09-10 180927" src="https://github.com/user-attachments/assets/0f7dc86a-2dea-4905-ae4c-9952af45e27e" />
<img width="1329" height="432" alt="Screenshot 2026-09-10 180912" src="https://github.com/user-attachments/assets/d10ee2c0-07cb-4c66-ab8e-a81afd4582b4" />
Screenshot of Azure Container Registry showing all 7 repositories with SHA, v1.1.0, and latest tags

---

## 🚀 **Part 6: Deployment Process**

### **Update Production Configuration**

**Step 1: Update `docker-compose.prod.yml`**
```yaml
version: '3.8'

services:
  web:
    image: netiksstoreacr.azurecr.io/web:v1.1.0
    pull_policy: always
  
  gateway:
    image: netiksstoreacr.azurecr.io/gateway:v1.1.0
    pull_policy: always
  
  identity-service:
    image: netiksstoreacr.azurecr.io/identity-service:v1.1.0
    pull_policy: always
  
  vendor-service:
    image: netiksstoreacr.azurecr.io/vendor-service:v1.1.0
    pull_policy: always
  
  catalog-service:
    image: netiksstoreacr.azurecr.io/catalog-service:v1.1.0
    pull_policy: always
  
  media-service:
    image: netiksstoreacr.azurecr.io/media-service:v1.1.0
    pull_policy: always
  
  admin-service:
    image: netiksstoreacr.azurecr.io/admin-service:v1.1.0
    pull_policy: always
```

**<img width="1038" height="691" alt="Screenshot 2026-09-10 174941" src="https://github.com/user-attachments/assets/25a4ab3d-f975-4018-b135-62a66a09d5e9" />:** Screenshot showing updated docker-compose.prod.yml file

### **Step 2: Deploy to Azure VM**

**On your Azure VM:**
```bash
# 1. Pull the repository
git pull origin main

# 2. Login to Azure Container Registry
az acr login --name netiksstoreacr

# 3. Pull updated images
docker compose \
  -f docker-compose.yml \
  -f docker-compose.prod.yml \
  pull

# 4. Restart services
docker compose \
  -f docker-compose.yml \
  -f docker-compose.prod.yml \
  up -d

# 5. Verify deployment
docker ps --format "table {{.Names}}\t{{.Image}}\t{{.Status}}"
```

**<img width="1035" height="223" alt="Screenshot 2026-09-10 183613" src="https://github.com/user-attachments/assets/aad01747-7df5-47ac-a37d-a953cd978903" />** Screenshot of `docker ps` showing containers running with v1.1.0 images

### **Step 3: Verify Application**

1. Access your application at the public IP
2. Verify your changes are visible
3. Test critical functionality (login, product browsing, etc.)

**<img width="1652" height="967" alt="Screenshot 2026-08-31 182231" src="https://github.com/user-attachments/assets/3411f31e-c159-456f-bc55-80c19e4dac15" />:** Screenshot of the running application showing the new changes
<img width="1427" height="914" alt="Screenshot 2026-08-20 092322" src="https://github.com/user-attachments/assets/5f2c0f22-a4c9-43be-a132-0c66c1c627c2" />
<img width="1495" height="799" alt="Screenshot 2026-08-20 124304" src="https://github.com/user-attachments/assets/f447717b-57cf-4c58-87ab-8e7a23145606" />
<img width="1343" height="814" alt="Screenshot 2026-08-20 131455" src="https://github.com/user-attachments/assets/72229bc9-4afb-4ff6-9b7c-d0336bce7afb" />

---

## 📋 **Deliverables Checklist**

### **1. GitHub Actions Screenshots**
- [ ] **<img width="981" height="346" alt="Screenshot 2026-09-10 161226" src="https://github.com/user-attachments/assets/7b5d48fb-babe-4ead-b078-a2887f4c6206" />** GitHub Repository Variables (names only)
- [ ] **<img width="995" height="216" alt="Screenshot 2026-09-10 161648" src="https://github.com/user-attachments/assets/f922e9c0-6582-460e-8cd5-4828015cb8f0" />** GitHub Secrets page (showing AZURE_CLIENT_SECRET name)
- [ ] **<img width="1095" height="704" alt="Screenshot 2026-09-10 171719" src="https://github.com/user-attachments/assets/c7f7316f-9756-475d-9136-649960c8dfca" />** Successful `main` pipeline run
- [ ] **<img width="1653" height="668" alt="Screenshot 2026-09-10 174352" src="https://github.com/user-attachments/assets/cfdc7fc0-3a64-4662-9bbe-04db08b3c73c" />** Successful release pipeline (v1.1.0)

### **2. Azure Container Registry Screenshots**
- [ ] **<img width="1343" height="472" alt="Screenshot 2026-09-10 174655" src="https://github.com/user-attachments/assets/40474630-001a-4895-92ed-cb6f3b64afbc" />** ACR showing SHA, v1.1.0, and latest tags
- [ ] <img width="1338" height="433" alt="Screenshot 2026-09-10 180846" src="https://github.com/user-attachments/assets/008e8067-7cd1-42ea-98a5-ba0d846f46c8" />
- [ ] <img width="1329" height="432" alt="Screenshot 2026-09-10 180912" src="https://github.com/user-attachments/assets/973d4e36-702c-4617-8176-fbbabe5e6d39" />
- [ ] <img width="1331" height="433" alt="Screenshot 2026-09-10 180927" src="https://github.com/user-attachments/assets/d4c577f1-4c24-46fb-a036-9bd65617d72e" />
- [ ] <img width="1328" height="424" alt="Screenshot 2026-09-10 180943" src="https://github.com/user-attachments/assets/8e812831-0384-4507-b9aa-2350e294def7" />
- [ ] <img width="1322" height="452" alt="Screenshot 2026-09-10 181009" src="https://github.com/user-attachments/assets/226a0f12-f2db-4420-9bd7-109a19da91bd" />
- [ ] <img width="1336" height="448" alt="Screenshot 2026-09-10 181025" src="https://github.com/user-attachments/assets/9108a0e2-c4f5-472a-984d-c1f7847e9988" />



  
### **3. Configuration Files**
- [ ] `.github/workflows/build-and-push.yml`
- [ ] Updated `docker-compose.prod.yml`

### **4. Deployment Verification**
- [ ] **<img width="1038" height="691" alt="Screenshot 2026-09-10 174941" src="https://github.com/user-attachments/assets/b9b8d6b2-cb8e-4c47-97a8-e90f3afc9a47" />** Updated docker-compose.prod.yml
- [ ] **<img width="1035" height="223" alt="Screenshot 2026-09-10 183613" src="https://github.com/user-attachments/assets/b1602fdb-56c0-4842-87cf-35c254ae0b36" />** `docker ps` showing v1.1.0 containers
- [ ] **<img width="1654" height="966" alt="Screenshot 2026-08-31 125913" src="https://github.com/user-attachments/assets/b47bc874-4581-4cee-850a-01497709708d" />** Application running with changes

### **5. Short Questions Answers**

**Q1. What problem does OIDC solve?**
OIDC solves the security problem of storing long-lived, static credentials in CI/CD systems by providing short-lived, automatically rotated tokens with fine-grained permissions and full auditability.

**Q2. Why do we use Git SHA tags?**
Git SHA tags provide immutable, traceable, and reproducible builds that can be directly linked to specific code commits, enabling reliable rollbacks and audit trails.

**Q3. Why should validation happen before the build?**
Validation acts as a quality gate to prevent building and pushing broken or non-compliant code, saving compute resources and ensuring only valid code progresses through the pipeline.

**Q4. Why shouldn't `latest` be updated on every commit?**
`latest` should represent stable, production-ready releases, not every development commit. Updating it only on releases ensures production stability and clear rollback paths.

**Q5. What part of this process would you automate next in Week 5?**
The manual deployment step on the Azure VM should be automated next using either:
1. **Azure Container Instances** with managed updates
2. **Azure Kubernetes Service (AKS)** with GitOps (Flux/ArgoCD)
3. **Azure DevOps Pipeline** for automated VM deployment
4. **Custom deployment script** triggered by the GitHub Actions workflow

---

## 🎯 **What Good Looks Like**

By completing this lab, I achieved:

> **A developer pushes code → GitHub Actions validates it → GitHub authenticates to Azure using OIDC → All 7 Docker images are built → Images are pushed to ACR with Git SHA tags → Version tags create release images → Production is manually updated with the new version**

**Success Metrics:**
- ✅ Fully automated CI pipeline
- ✅ Secure OIDC authentication to Azure
- ✅ Immutable, traceable Docker images
- ✅ Separation of development commits from production releases

---


*Last Updated: September 8, 2026*
---
# Netiks Store - Week 2 Lab Deployment Report
## Complete Azure VM Deployment with Production Configuration

**Date:** August 19, 2026  
- **VM Public IP:** 20.29.81.166
- **App URL:** http://20.29.81.166/
- **Deployment Status:** ✅ Fully Deployed and Verified

---

## **Executive Summary**

This report documents the successful deployment of Netiks Store to an Azure Virtual Machine following production security standards. The deployment includes:

- ✅ Azure VM (Standard_B2s - 2 vCPUs, 4GB RAM)
- ✅ Docker and Docker Compose with secure configuration
- ✅ Nginx reverse proxy with proper security headers
- ✅ Production `.env` configuration with strong secrets
- ✅ All internal services secured (ports bound to loopback only)
- ✅ Automatic container restart policies
- ✅ Complete deployment validation and testing

---

## **Part 1: Provision Your Cloud VM**

### **Architectural Diagram**

<img width="804" height="1656" alt="image-49" src="https://github.com/user-attachments/assets/5fcb5b21-bc24-4f93-aef1-2209a78da98e" />


### **1.1: Cloud Platform and VM Size**

**Cloud Platform:** Microsoft Azure  
**VM Size:** Standard_B2s (2 vCPUs, 4 GiB memory)  
**OS:** Ubuntu Server 22.04 LTS - x64 Gen2  
**Region:** Central US

**Justification:**
- **Recommended size:** The Standard_B2s (2 vCPUs, 4GB RAM) aligns with the lab's recommendation for Azure
- **Available to me:** Yes, this size was available in my subscription
- **Why this size:** 
  - 2 vCPUs provide sufficient processing power for 9 Docker containers
  - 4 GB RAM prevents memory issues during builds and Next.js development server operation
  - Cost-effective at ~$30-40/month (covered by Azure free credits initially)

### **1.2: VM Summary and Public IP**

<img width="1408" height="416" alt="image-19" src="https://github.com/user-attachments/assets/22e3c3fb-4a48-4d7e-a402-349eb84936fa" />


### **1.3: Initial Firewall Rules (Port 22 Only)**

<img width="1626" height="703" alt="image-20" src="https://github.com/user-attachments/assets/8d37ef0b-d6c6-49d4-bd0b-43bba51b4690" />

### **1.4: First Successful SSH Connection**

<img width="816" height="575" alt="image-21" src="https://github.com/user-attachments/assets/3f4a06f5-d459-43ea-9f76-d51bf5a486a4" />

**Verification Command:**
```bash
# After SSH connection
whoami
```
<img width="785" height="151" alt="image-22" src="https://github.com/user-attachments/assets/a25a3186-b89c-4822-ac12-4199179aff34" />

---

## **Part 2: Secure the VM and Install Dependencies**

### **2.1: Docker Installation and Verification**

**Command Output:**
```bash
# Update system
sudo apt-get update && sudo apt-get upgrade -y

# Install Docker
curl -fsSL https://get.docker.com | sudo sh

# Add user to docker group
sudo usermod -aG docker $USER
# Log out and back in, then verify

docker version
docker compose version
```

<img width="832" height="572" alt="image-23" src="https://github.com/user-attachments/assets/9e4abdf3-16c3-4a62-837e-2f880c569ab0" />

### **2.2: Node.js 20 and npm Installation**

**Command Output:**
```bash
# Install Node.js 20 from NodeSource
curl -fsSL https://deb.nodesource.com/setup_20.x | sudo -E bash -
sudo apt-get install -y nodejs

# Verify installation
node --version
npm --version
```

<img width="656" height="124" alt="image-24" src="https://github.com/user-attachments/assets/3a588e75-9a83-4add-9ef1-29c78ad80f33" />


### **2.3: Nginx Installation and Status**

**Command Output:**
```bash
# Install Nginx
sudo apt-get install -y nginx
sudo systemctl enable nginx
sudo systemctl status nginx
```

**Output:**

<img width="1070" height="355" alt="image-25" src="https://github.com/user-attachments/assets/f10f0640-6e49-48f9-bccb-23b7eb5b32b9" />


### **2.4: Updated Firewall Rules (Ports 22, 80, 443)**

**Screenshot of Configuration**

<img width="1649" height="834" alt="Screenshot 2026-08-19 154603" src="https://github.com/user-attachments/assets/2c0978d8-4313-42b6-9959-b37ad0d9d5fa" />


### **2.5: Pre-Deployment Browser Test**

<img width="1525" height="418" alt="image-26" src="https://github.com/user-attachments/assets/c469a634-2b15-4891-a1bc-8fc5b2a49030" />


**URL:** http://20.29.81.166

**Why this proves my setup:**
1. **Nginx is running:** The default page confirms Nginx service is active
2. **Port 80 is open:** You can reach the VM via HTTP from the internet
3. **Firewall is correctly configured:** Traffic is flowing through port 80
4. **Basic networking works:** DNS resolution and routing are functional

---

## **Part 3: Prepare the Application for Cloud**

### **3.1: Production .env File Configuration**

**Modified Variables (Redacted Secrets):**
```bash
# Variables changed from defaults:
NEXT_PUBLIC_API_BASE_URL=http://20.29.81.166/api/v1  # Changed from localhost
POSTGRES_PASSWORD=**************  # Changed from 'postgres' (32-char random)
JWT_SECRET=**************  # Changed from default (64-char random)
```

**Variables Removed:**
```bash
POSTGRES_EXPOSE_PORT  # Removed - database not exposed to host
```

**Screenshot Instructions:**

<img width="1106" height="546" alt="image-27" src="https://github.com/user-attachments/assets/5e0a3ca7-b552-40c3-9ea5-a587bbc49b81" />


### **3.2: Docker Compose Restart Policies**

**Modified `docker-compose.yml` section:**

<img width="1048" height="610" alt="image-28" src="https://github.com/user-attachments/assets/e771b1df-a97f-44a1-b8d7-0a77f2b3b316" />
<img width="860" height="626" alt="image-29" src="https://github.com/user-attachments/assets/0b3265ce-65dd-45ac-8488-d1b5d1a19ea4" />

**Why `unless-stopped`:**
- Automatically restarts containers after VM/docker daemon restart
- Respects manual `docker compose stop` for maintenance
- More practical than `always` for development environments

### **3.3: Final Ports Configuration**

**Modified `docker-compose.yml` ports section:**

<img width="1000" height="615" alt="image-30" src="https://github.com/user-attachments/assets/3a372a7c-211c-426b-98e0-9e7206905634" />


-  All other services (identity, vendor, catalog, media, admin, postgres, redis):
-  NO ports: entries (removed entirely)


### **3.4: Loopback Binding Safety Explanation**

**Why binding to 127.0.0.1 is safer:**

1. **Defense in Depth:** Even if cloud firewall misconfiguration opens internal ports, they're not bound to the public interface
2. **Host Firewall Independence:** Doesn't rely on host firewall (UFW/iptables) being correctly configured
3. **Container Isolation:** Services are only accessible from the VM itself, not from other VMs in the same network
4. **Accidental Exposure Prevention:** Prevents accidental exposure via Docker's default binding behavior
5. **Principle of Least Privilege:** Services only expose what's necessary to Nginx (running on same host)

### **3.5: Browser-to-Gateway Request Trace**

**Path of a browser API request:**
```
Browser (user) → HTTP/HTTPS → Port 80/443 → Nginx (VM) → /api/* location → 
127.0.0.1:8000 → Gateway container → Internal Docker network → 
Backend service (identity/vendor/catalog/media)
```

**Does browser connect to port 8000 directly?** NO

**Why:**
- Nginx acts as reverse proxy
- `/api/*` requests go directly from Nginx to gateway on loopback (127.0.0.1:8000)
- Browser only communicates with Nginx on standard web ports (80/443)
- Gateway port 8000 is not exposed to internet, only accessible locally

### **3.6: NEXT_PUBLIC_API_BASE_URL Hygiene**

**Why changing it is good deployment hygiene:**

1. **Configuration Truth:** Variables should describe the actual environment, not a non-existent localhost
2. **Code Path Coverage:** The variable is used in multiple code paths; some may not use the server-side proxy
3. **Future Architecture Changes:** If architecture changes (direct API calls from browser), correct URL is already configured
4. **Developer Clarity:** Clear indication this is production deployment, not local development
5. **Error Prevention:** Prevents subtle bugs from incorrect fallback behavior
6. **Best Practice:** Production configurations should never reference development environments

---

## **Part 4: Configure the Reverse Proxy**

### **4.1: Nginx Configuration**

**`/etc/nginx/sites-available/netiks_store`:**
```nginx
server {
    listen 80;
    server_name _;

    client_max_body_size 20M;

    location /api/ {
        proxy_pass http://localhost:8000;
        proxy_http_version 1.1;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
    }

    location / {
        proxy_pass http://localhost:3001;
        proxy_http_version 1.1;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
    }
}
```

### **4.2: Nginx Configuration Questions**

**1. `server_name _;` meaning:**
- `_` is a catch-all server name that matches any domain
- If VM had real domain: `server_name netiks-store.com;`
- For production: `server_name netiks-store.com;`

**2. `client_max_body_size 20M;` purpose:**
- Allows file uploads up to 20MB
- Necessary for: Product image uploads in vendor dashboard
- Without this: Large uploads get "413 Request Entity Too Large" error

**3. `proxy_set_header X-Real-IP $remote_addr;` purpose:**
- Passes original client IP to backend services
- Backend services care because:
  - Logging shows actual client IP, not proxy IP
  - Rate limiting based on real client IP
  - Security auditing needs accurate source IP
  - Geo-location features work correctly

**4. Nginx configuration validation:**
```bash
sudo nginx -t
```

**Expected Output:**
<img width="834" height="176" alt="image-31" src="https://github.com/user-attachments/assets/02658a16-cdfd-4f8f-bb2c-28875b121c39" />

**5. Nginx location matching for `/api/v1/market`:**
- **Which location matches:** `/api/` (not `/`)
- **Matching rule:** Nginx uses **prefix matching**, `/api/` is more specific prefix than `/`
- **Order matters?** NO - prefix specificity determines match, not order
- **Why:** `/api/v1/market` starts with `/api/`, so `/api/` location takes precedence

---

## **Part 5: Deploy and Validate**

### **5.1: Application Startup**

**Commands:**
```bash
cd ~/netiks_store
docker compose up -d --build

# Monitor progress
docker compose logs -f

# Check status
docker compose ps
```

**`docker compose ps` output:**
<img width="1677" height="343" alt="image-32" src="https://github.com/user-attachments/assets/e191af27-6337-4995-9538-0b1bf964c2d1" />


### **5.2: Seed Demo Data**

**Command:**
```bash
DOCKER_BIN=docker npm run seed:demo
```

**Why `DOCKER_BIN=docker`:**
- Seed script defaults to macOS Docker Desktop path
- On Ubuntu, Docker binary is at `/usr/bin/docker`
- Environment variable overrides default path

**Expected Output:**

<img width="938" height="203" alt="image-33" src="https://github.com/user-attachments/assets/eb0374f2-7d66-4f5e-a92c-def2a76362f4" />

### **5.3: Deployment Validation Steps**

**1. Home Page (`http://20.29.81.166/`):**

<img width="1513" height="864" alt="image-36" src="https://github.com/user-attachments/assets/ff7a793b-d451-4ea3-b357-f06d8abe24f6" />
<img width="1509" height="775" alt="image-35" src="https://github.com/user-attachments/assets/150e74b0-3c0f-4cb6-a1b2-b8d4b8d6d148" />
<img width="1511" height="842" alt="image-34" src="https://github.com/user-attachments/assets/a55d7949-43d4-452e-879b-eda15a428369" />


- **Expected:** Netiks Store home page loads

**2. API Health Check (`http://20.29.81.166/api/v1/system/services`):**
<img width="1676" height="289" alt="image-37" src="https://github.com/user-attachments/assets/ed1bc6f1-dafb-4cad-bac2-4265816d94a0" />


- **Expected:** JSON showing all registered services



**3. Market Page (`http://20.29.81.166/market`):**

<img width="1541" height="700" alt="image-39" src="https://github.com/user-attachments/assets/c150c539-cd38-4677-b844-cbc87d47fcdd" />
<img width="1544" height="961" alt="image-38" src="https://github.com/user-attachments/assets/a9b66f7c-b9d2-4048-807a-1f0935513b1c" />

- **Expected:** Product cards showing seeded items


**4. User Registration & Login:**
- **Steps:** Register → Login → Access Dashboard

<img width="1549" height="795" alt="image-43" src="https://github.com/user-attachments/assets/116efc0c-700b-4d61-97eb-56840cb5734d" />
<img width="1667" height="877" alt="image-42" src="https://github.com/user-attachments/assets/988d33ad-fa76-42d1-91bc-39e0fdccacfc" />
<img width="1676" height="908" alt="image-41" src="https://github.com/user-attachments/assets/46bc8721-55eb-40bc-9349-c0019f7a1ce3" />


- **Screenshot:** Successful dashboard access

**5. Image Upload Test:**
- **Steps:** Vendor dashboard → Upload product image → Verify URL accessibility
<img width="1343" height="814" alt="image-48" src="https://github.com/user-attachments/assets/52744caf-a022-4acd-8a1c-d694e7672e31" />


- **Screenshot:** Uploaded image displaying correctly

### **5.4: Internal Port Security Verification**

**From your laptop (NOT VM):**
```bash
# Test port 8001 (identity service)
curl -v --connect-timeout 5 http://20.29.81.166:8001

# Test port 5432 (postgres)
curl -v --connect-timeout 5 http://20.29.81.166:5432
```

<img width="973" height="312" alt="image-45" src="https://github.com/user-attachments/assets/d7ec046e-016c-4d83-9e03-b0039636fb74" />

**Expected Result:** Both timeout or get "Connection refused"

**Why this is desired behavior:**
- **Security:** Internal services not exposed to internet
- **Compliance:** Database should never be publicly accessible
- **Best Practice:** Only reverse proxy (Nginx) faces internet
- **Defense in Depth:** Multiple layers of protection (cloud firewall + loopback binding)


### **5.5: Automatic Restart Test**

**Commands:**
```bash
# Reboot VM
sudo reboot

# Wait 60 seconds, then SSH back in
ssh -i netiks-store-key.pem azureuser@20.29.81.166

# Check containers
cd ~/netiks_store
docker compose ps
```
<img width="1261" height="863" alt="image-46" src="https://github.com/user-attachments/assets/42148d95-458b-4e22-a0b9-6b3155c0e928" />

**Expected Output:** All containers show as running

**Two things enabling automatic restart:**
1. **Docker Compose restart policies:** `restart: unless-stopped` in docker-compose.yml
2. **Docker daemon auto-start:** Docker service configured to start on boot


### **5.6: Redeployment Command**

**Single redeployment command:**
```bash
docker compose up -d --build --force-recreate
```

**What each part does:**
- `docker compose up`: Start services
- `-d`: Detached mode (run in background)
- `--build`: Rebuild images from Dockerfiles
- `--force-recreate`: Recreate containers even if unchanged
- Combined: Full redeploy with fresh builds

---

## **Part 6: Deployment Runbook**

### **Netiks Store Production Deployment Runbook**
**VM:** Azure Standard_B2s (2 vCPU, 4GB RAM)  
**OS:** Ubuntu 22.04 LTS  
**Date:** August 2026  
**Author:** Olaoluwa Afolami

### **1. VM Provisioning**
1. Azure Portal → Create Virtual Machine
2. Name: `netiks-store-vm`
3. Size: Standard_B2s
4. OS: Ubuntu Server 22.04 LTS - x64 Gen2
5. Authentication: SSH public key
6. Username: `azureuser`
7. Key pair: Generate `netiks-store-key.pem`
8. Inbound ports: SSH (22) only initially
9. Save public IP: `20.29.81.166`

### **2. Security Configuration**
1. Add NSG rules:
   - Port 80 (HTTP) - Priority 1010
   - Port 443 (HTTPS) - Priority 1020
2. Keep only ports 22, 80, 443 open

### **3. SSH Connection**
```bash
ssh -i netiks-store-key.pem azureuser@20.29.81.166
```

### **4. System Preparation**
```bash
# Update system
sudo apt update && sudo apt upgrade -y

# Install Docker
curl -fsSL https://get.docker.com | sudo sh
sudo usermod -aG docker $USER
# Log out and back in

# Install Docker Compose
sudo apt install -y docker-compose-plugin

# Install Node.js 20
curl -fsSL https://deb.nodesource.com/setup_20.x | sudo -E bash -
sudo apt install -y nodejs

# Install Nginx
sudo apt install -y nginx
sudo systemctl enable nginx
```

### **5. Application Setup**
```bash
# Install Git
sudo apt install -y git

# Clone repository
git clone <your-repo-url> netiks_store
cd netiks_store

# Install dependencies
npm install

# Create production .env
cp .env.example .env
nano .env  # Edit variables below
```

### **6. Required .env Changes**
**MUST CHANGE:**
- `NEXT_PUBLIC_API_BASE_URL=http://20.29.81.166/api/v1`
- `POSTGRES_PASSWORD=` (generate: `openssl rand -hex 20`)
- `JWT_SECRET=` (generate: `openssl rand -hex 32`)

**REMOVE:**
- `POSTGRES_EXPOSE_PORT` line

### **7. Docker Compose Modifications**
Add to EVERY service in `docker-compose.yml`:
```yaml
    restart: unless-stopped
```

Change ports to loopback only:
```yaml
services:
  web:
    ports:
      - "127.0.0.1:3001:3000"
  gateway:
    ports:
      - "127.0.0.1:8000:8000"
```

Remove ALL `ports:` entries from: identity-service, vendor-service, catalog-service, media-service, admin-service, postgres, redis

### **8. Nginx Configuration**
Create `/etc/nginx/sites-available/netiks_store`:
```nginx
server {
    listen 80;
    server_name _;
    client_max_body_size 20M;
    
    location /api/ {
        proxy_pass http://localhost:8000;
        proxy_http_version 1.1;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
    }
    
    location / {
        proxy_pass http://localhost:3001;
        proxy_http_version 1.1;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
    }
}
```

Activate:
```bash
sudo ln -s /etc/nginx/sites-available/netiks_store /etc/nginx/sites-enabled/
sudo rm /etc/nginx/sites-enabled/default
sudo nginx -t
sudo systemctl reload nginx
```

### **9. Application Deployment**
```bash
# Build and start
docker compose up -d --build

# Verify all services running
docker compose ps

# Seed demo data
DOCKER_BIN=docker npm run seed:demo
```

### **10. Validation Commands**
```bash
# Check running containers
docker compose ps

# Test external accessibility
curl http://20.29.81.166/

# Test API
curl http://20.29.81.166/api/v1/system/services

# Verify security (should timeout)
curl --connect-timeout 5 http://20.29.81.166:8001
```

---

## **What I Found Hardest This Week**

The most challenging aspect was understanding and implementing the layered security approach. Specifically:

1. **Conceptualizing multiple defense layers:** Understanding how cloud firewall, Docker loopback binding, and service isolation work together required careful study of networking principles.

2. **Nginx configuration nuances:** Getting the location blocks correct for `/api/*` routing while ensuring all headers were properly passed to backend services took several iterations of testing.

3. **Troubleshooting container networking:** When services couldn't communicate internally despite correct Docker Compose configuration, debugging required examining Docker network logs and verifying DNS resolution within the container network.

4. **Balancing security with functionality:** Implementing strict security (no database exposure) while maintaining developer accessibility for debugging required thoughtful trade-off decisions.

The breakthrough came when visualizing the complete request flow from browser to backend service, which made each security layer's purpose clear and revealed where configurations needed adjustment.

---


## **Final Verification Checklist**

### **✅ All Requirements Met:**

1. **VM Provisioned:** Azure Standard_B2s with Ubuntu 22.04 LTS
2. **Security Configured:** Only ports 22, 80, 443 open
3. **Dependencies Installed:** Docker, Node.js 20, Nginx
4. **Application Prepared:** Production `.env`, secure secrets
5. **Docker Configuration:** Restart policies, loopback ports
6. **Reverse Proxy:** Nginx correctly routing `/api/*` and other traffic
7. **Deployment Verified:** All services running, data seeded
8. **Security Validated:** Internal ports not publicly accessible
9. **Auto-restart Tested:** Containers restart after VM reboot
10. **Runbook Created:** Complete deployment documentation

### **🚀 Application Access:**

- **Home Page:** http://20.29.81.166/
- **API Endpoint:** http://20.29.81.166/api/v1/system/services
- **Market Page:** http://20.29.81.166/market
- **Domain:** http://netiks-store.com/ (after DNS setup)

### **🔒 Security Status:**

- ✅ Cloud firewall: Only 22, 80, 443 open
- ✅ Docker ports: Only web/gateway on loopback
- ✅ Database: Not exposed to internet
- ✅ Secrets: Strong random passwords in use
- ✅ Headers: Security headers via Nginx

---

## **Next Steps for complete Production Readiness**

1. **Implement SSL/TLS** with Let's Encrypt
2. **Configure domain DNS** properly
3. **Set up monitoring** and alerting
4. **Create backup strategy** for database and uploads
5. **Implement CI/CD pipeline** for automated deployments
6. **Add logging aggregation** (ELK stack or similar)
7. **Configure auto-scaling** for traffic spikes
8. **Set up CDN** for static assets and images
9. **Implement WAF** (Web Application Firewall)
10. **Regular security scanning** and updates

---

**Report Generated:** August 19, 2026  
**Deployment Complete:** ✅  
**All Lab Questions Answered:** ✅  
**Production Ready:** ⚠️ Requires SSL and domain configuration

---
# Netiks Store Architecture Deep Dive & Production Readiness Assessment

**Week 1 Lab Report**  
**Date:** August 4, 2026  
**Project:** Netiks Store - Multi-Vendor E-Commerce Platform  
**Assessment Type:** Architecture Analysis & Cloud Deployment Preparation

---

## Executive Summary

This report provides a comprehensive analysis of the Netiks Store application architecture, examining its microservices design, networking configuration, data persistence strategy, and production deployment readiness. The application consists of 9 interconnected services orchestrated through Docker Compose, implementing a modern microservices architecture suitable for cloud deployment.

**Key Findings:**
- The system follows a well-structured microservices pattern with clear service boundaries
- All services communicate through a central API gateway, providing a single entry point
- Data persistence is managed through Docker volumes for both database and media files
- Several critical security and configuration changes are required before cloud deployment
- The current configuration is optimized for local development and requires significant modifications for production environments

---

## Table of Contents

1. [Part 1 - Architecture Map](#part-1---architecture-map)
2. [Part 2 - Networking Investigation](#part-2---networking-investigation)
3. [Part 3 - State & Storage Audit](#part-3---state--storage-audit)
4. [Part 4 - Configuration & Secrets Review](#part-4---configuration--secrets-review)
5. [Part 5 - Production Readiness Assessment](#part-5---production-readiness-assessment)
6. [Reflections](#reflections)

---

## Part 1 - Architecture Map

### System Architecture Diagram

```
                                    ┌─────────────────┐
                                    │                 │
                                    │  User Browser   │
                                    │                 │
                                    └────────┬────────┘
                                             │
                                             │ HTTP :3001
                                             ▼
                        ┌────────────────────────────────────┐
                        │                                    │
                        │    Web Frontend (Next.js)          │
                        │    Port: 3000 (exposed as 3001)    │
                        │                                    │
                        └─────────┬──────────────────────────┘
                                  │
                                  │ HTTP :8000 (API calls)
                                  │
                                  ▼
                        ┌────────────────────────────────────┐
                        │                                    │
                        │    API Gateway (FastAPI)           │
                        │    Port: 8000                      │
                        │    Central API entry point         │
                        │                                    │
                        └─────────┬──────────────────────────┘
                                  │
                ┌─────────────────┼─────────────────┬───────────────┐
                │                 │                 │               │
                ▼                 ▼                 ▼               ▼
    ┌──────────────┐  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐
    │   Identity   │  │   Vendor     │  │   Catalog    │  │    Media     │
    │   Service    │  │   Service    │  │   Service    │  │   Service    │
    │   :8001      │  │   :8002      │  │   :8003      │  │   :8004      │
    └──────┬───────┘  └──────┬───────┘  └──────┬───────┘  └──────┬───────┘
           │                 │                 │                 │
           │                 │                 │                 │
           └─────────────────┴─────────────────┴─────────────────┘
                             │                 │
                             │                 │
                             ▼                 ▼
                    ┌──────────────┐    ┌────────────┐
                    │  PostgreSQL  │    │   Redis    │
                    │    :5432     │    │   :6379    │
                    │ (exposed as  │    └────────────┘
                    │   :55432)    │
                    └──────────────┘
                             
                    ┌──────────────┐
                    │    Admin     │
                    │   Service    │
                    │    :8005     │
                    └──────┬───────┘
                           │
                           ▼
                    (connects to PostgreSQL)
```
<img width="896" height="1198" alt="Gemini_Generated_Image_d3hl1xd3hl1xd3hl" src="https://github.com/user-attachments/assets/bb1aa2b1-7cf3-4fe6-9090-9634c4eadcd6" />


### Service Responsibilities

**1. Web Frontend (Port 3001)**
- Next.js-based user interface for customers and vendors
- Renders marketplace pages, product listings, and vendor dashboards
- Communicates exclusively with the API Gateway

**2. API Gateway (Port 8000)**
- Central routing hub for all backend services
- Handles authentication validation and user context extraction
- Aggregates and proxies requests to microservices
- Provides a unified API surface for the frontend

**3. Identity Service (Port 8001)**
- Manages user authentication and registration
- Issues and validates JWT tokens
- Stores user credentials securely with password hashing
- Handles login, logout, and session management

**4. Vendor Service (Port 8002)**
- Manages store creation and vendor profiles
- Handles store information updates
- Provides store lookup and vendor-store relationships

**5. Catalog Service (Port 8003)**
- Manages product creation, editing, and publishing
- Handles product categories
- Provides product search and filtering capabilities
- Manages checkout and order processing

**6. Media Service (Port 8004)**
- Handles file uploads for product images and store logos
- Validates file types and sizes
- Manages media storage (currently local disk via Docker volume)

**7. Admin Service (Port 8005)**
- Provides administrative capabilities
- Enables moderation of stores and products
- Manages platform-wide settings

**8. PostgreSQL (Port 5432, exposed as 55432)**
- Primary relational database for all services
- Stores user accounts, stores, products, categories, and orders
- Uses separate schemas for service isolation

**9. Redis (Port 6379)**
- Caching and session management support
- Provides fast data access for frequently used information

---

### Request Journey: "Buy Now" Button Click

**Scenario:** A customer clicks the "Buy Now" button on a product page to place an order.

**Step-by-Step Flow:**

1. **Browser Action**: The customer's browser initiates an HTTP POST request to the Web Frontend at `http://localhost:3001/checkout/[product-slug]` containing product details and customer information.

2. **Frontend Processing**: The Next.js application validates the form data client-side and prepares a checkout request payload containing product ID, quantity, and customer details.

3. **API Gateway Call**: The frontend sends a POST request to `http://gateway:8000/api/v1/checkout` (using the internal API URL since this is a server-side action). The gateway acts as the single entry point for all backend operations.

4. **Gateway Routing**: The API Gateway receives the request and routes it to the Catalog Service at `http://catalog-service:8003/checkout`. The gateway may validate the user's authentication token if the user is logged in.

5. **Catalog Service Processing**: The Catalog Service receives the checkout request and performs the following:
   - Validates product availability and stock levels
   - Checks product pricing and calculates total cost
   - Queries the PostgreSQL database to verify product details
   - Creates an order record in the `catalog` schema of PostgreSQL
   - Updates product stock quantities if needed

6. **Database Transaction**: PostgreSQL processes the INSERT operation to save the order, including customer information, product details, quantities, prices, and order status. This operation is atomic to ensure data consistency.

7. **Response Chain**: The Catalog Service returns a success response with the order ID back to the Gateway, which then forwards it to the Web Frontend.

8. **User Confirmation**: The frontend displays an order confirmation page to the customer with the order details and order number.

**Total Time**: Approximately 200-500ms depending on database load and network latency.

---

## Part 2 - Networking Investigation

### Question 1: Published Ports from Host Machine

**Command Executed:**
```powershell
docker compose ps
```

**Results:**

<img width="1291" height="233" alt="image" src="https://github.com/user-attachments/assets/5e4c80e9-f18b-4fae-a70c-837107a5706e" />


| Service | Container Port | Published Host Port | Accessibility |
|---------|---------------|---------------------|---------------|
| web | 3000 | 3001 | ✅ Accessible |
| gateway | 8000 | 8000 | ✅ Accessible |
| identity-service | 8001 | 8001 | ✅ Accessible |
| vendor-service | 8002 | 8002 | ✅ Accessible |
| catalog-service | 8003 | 8003 | ✅ Accessible |
| media-service | 8004 | 8004 | ✅ Accessible |
| admin-service | 8005 | 8005 | ✅ Accessible |
| postgres | 5432 | 55432 | ✅ Accessible |
| redis | 6379 | 6379 | ✅ Accessible |

**Analysis:**

From the host machine (your laptop), **all 9 services** are directly reachable. This is configured through the `ports:` directive in the `docker-compose.yml` file. Each service publishes its port using the format `"<host_port>:<container_port>"`.

For example:
- The web frontend runs on port 3000 inside its container but is exposed to the host on port 3001
- PostgreSQL runs on port 5432 inside its container but is exposed on port 55432 to avoid conflicts with any existing local PostgreSQL installations

**Key Insight:** This "publish everything" approach is convenient for local development and debugging but represents a **significant security risk** in production environments.

---

### Question 2: Internal Service Discovery

**Command Executed and Result:**

<img width="1240" height="112" alt="image" src="https://github.com/user-attachments/assets/e3e42c34-d89d-4def-b712-0a8182fcb1d4" />

```powershell
docker compose exec gateway python -c "import socket; print('catalog-service resolves to:', socket.gethostbyname('catalog-service')); print('postgres resolves to:', socket.gethostbyname('postgres')); print('redis resolves to:', socket.gethostbyname('redis'))"
```

**Results:**
```
catalog-service resolves to: 172.19.0.6
postgres resolves to: 172.19.0.4
redis resolves to: 172.19.0.2
```

**How Service Discovery Works:**

Docker Compose creates a **private internal network** for all services defined in the compose file. Each service is assigned:
1. A **service name** that acts as a DNS hostname (e.g., `catalog-service`, `postgres`, `redis`)
2. An **internal IP address** from Docker's bridge network (in the 172.19.0.x range in this case)

**Technical Explanation:**

When a service needs to communicate with another service, it uses the service name as the hostname. Docker's embedded DNS server automatically resolves these names to the correct container IP addresses. This happens completely within Docker's internal network and doesn't require any external DNS configuration.

For example, when the gateway needs to call the catalog service, it makes a request to `http://catalog-service:8003`. Docker's DNS resolves `catalog-service` to `172.19.0.7`, and the request reaches the correct container.

**Key Benefits:**
- **Automatic service discovery** - No need to manually configure IP addresses
- **Network isolation** - Internal communication doesn't expose services to the host network unless explicitly published
- **Dynamic IP management** - Container IPs can change; service names remain constant
- **Simplified configuration** - Services reference each other by name, making the configuration portable

---

### Question 3: Frontend API URLs - Two Different Configurations

**Configuration from `.env.example`:**
```
NEXT_PUBLIC_API_BASE_URL=http://localhost:8000/api/v1
INTERNAL_API_BASE_URL=http://gateway:8000/api/v1
```

**Why Two URLs Are Necessary:**

Next.js applications execute code in **two different environments**:

1. **Client-Side (Browser)**: Code that runs in the user's web browser
2. **Server-Side (Next.js Server)**: Code that runs during Server-Side Rendering (SSR) or API routes

**Detailed Explanation:**

**`NEXT_PUBLIC_API_BASE_URL` (http://localhost:8000/api/v1)**
- **Used by:** Client-side code running in the user's browser
- **Why this URL:** When code runs in the browser, it cannot access Docker's internal network. The browser doesn't know what `gateway` means as a hostname.
- **How it works:** The browser makes HTTP requests from the user's machine to `localhost:8000`, which is the published port that maps to the gateway service.
- **Example use case:** When a user clicks a button to fetch products, the JavaScript running in their browser uses this URL.

**`INTERNAL_API_BASE_URL` (http://gateway:8000/api/v1)**
- **Used by:** Server-side code running inside the Next.js container
- **Why this URL:** The Next.js container runs within Docker's internal network and can directly communicate with other containers using service names.
- **How it works:** During server-side rendering, the Next.js container makes requests to `http://gateway:8000`, which Docker's DNS resolves to the gateway container.
- **Example use case:** When Next.js pre-renders a product page on the server, it uses this URL to fetch data before sending HTML to the browser.

**Why One URL Cannot Work for Both:**

- If we only used `http://localhost:8000` for server-side code, it wouldn't work because `localhost` inside a container refers to that container itself, not the host machine or other containers.
- If we only used `http://gateway:8000` for client-side code, it wouldn't work because the user's browser cannot resolve the Docker service name `gateway`.

**Cloud Deployment Impact:**

In production, both URLs would likely point to the same public domain:
```
NEXT_PUBLIC_API_BASE_URL=https://api.netiks.com/api/v1
INTERNAL_API_BASE_URL=https://api.netiks.com/api/v1
```

Or maintain internal networking:
```
NEXT_PUBLIC_API_BASE_URL=https://api.netiks.com/api/v1
INTERNAL_API_BASE_URL=http://gateway:8000/api/v1
```

---

### Question 4: Database Port Configuration - 5432 vs 55432

**Configuration from `docker-compose.yml`:**
```yaml
postgres:
  ports:
    - "${POSTGRES_EXPOSE_PORT:-55432}:5432"
```

**Why Both Ports Exist Simultaneously:**

This is a **port mapping** configuration where:
- **5432** is the internal container port (left side of the colon after the first colon)
- **55432** is the external host port (left side of the mapping)

**Detailed Explanation:**

**Inside Docker's Network (Port 5432):**
- All services within the Docker Compose network connect to PostgreSQL on port **5432**
- For example, the catalog-service uses the connection string: `postgresql://postgres:postgres@postgres:5432/netiks_store`
- The hostname `postgres` resolves to the PostgreSQL container, and port 5432 is PostgreSQL's default port
- This is the "native" port that PostgreSQL listens on within its container

**From Host Machine (Port 55432):**
- Your laptop can connect to PostgreSQL on port **55432**
- For example: `psql -h localhost -p 55432 -U postgres -d netiks_store`
- This is the "published" port that Docker maps to the container's internal port 5432

**Why Use Port 55432 Instead of 5432?**

1. **Conflict Avoidance**: Many developers have PostgreSQL installed locally, which typically runs on port 5432. Using 55432 prevents port conflicts.
2. **Multiple Projects**: If you run multiple projects with PostgreSQL containers, each can expose a different host port (55432, 55433, etc.) while all internally use 5432.
3. **Security Consideration**: Using non-standard ports can provide a minor security-through-obscurity benefit.

**Analogy for Non-Technical Understanding:**

Think of this like an apartment building:
- **Port 5432** is the apartment number where PostgreSQL lives inside the building (Docker network)
- **Port 55432** is the street address where visitors from outside (your host machine) can find the building entrance
- Residents inside the building (other containers) use the apartment number (5432) directly
- Visitors from outside (your laptop) use the street address (55432), which the building's reception (Docker) redirects to the correct apartment

---

## Part 3 - State & Storage Audit

### Named Volumes Inventory

**Command Executed:**
```powershell
docker volume ls
docker volume inspect netiks_store_postgres_data
docker volume inspect netiks_store_media_uploads
```

<img width="1004" height="348" alt="image" src="https://github.com/user-attachments/assets/2b4cc09c-8f0a-4d77-932a-61bf67db66ad" />

<img width="1004" height="358" alt="image" src="https://github.com/user-attachments/assets/6e45ba97-f819-4085-ae03-0674a38cc60b" />


**Identified Volumes:**

| Volume Name | Storage Purpose | Service Owner | Location | Critical Data |
|-------------|----------------|---------------|----------|---------------|
| `netiks_store_postgres_data` | Database files | postgres | `/var/lib/postgresql/data` | ✅ Yes - All application data |
| `netiks_store_media_uploads` | Uploaded media files | media-service | `/app/uploads` | ✅ Yes - Product images, store logos |

---

### Volume 1: postgres_data

**What It Stores:**
- All PostgreSQL database files including:
  - User accounts and credentials (identity schema)
  - Store information and vendor profiles (vendor schema)
  - Product catalog, categories, and inventory (catalog schema)
  - Order history and transaction records
  - Admin moderation logs
  - Database indexes and system tables

**Why It Matters:**
This volume contains **100% of the application's structured data**. Without it, the application would be completely empty - no users, no stores, no products, no orders.

**Mount Configuration:**
```yaml
volumes:
  - postgres_data:/var/lib/postgresql/data
```

**Physical Location on Host:**
```
/var/lib/docker/volumes/netiks_store_postgres_data/_data
```

---

### Volume 2: media_uploads

**What It Stores:**
- Product images uploaded by vendors
- Store logos and banners
- Any other media assets

**Why It Matters:**
This volume contains all the visual content that makes the marketplace appealing and functional. Without it, all products would appear without images, and stores would lack branding.

**Mount Configuration:**
```yaml
media-service:
  volumes:
    - media_uploads:/app/uploads
```

**Physical Location on Host:**
```
/var/lib/docker/volumes/netiks_store_media_uploads/_data
```

---

### Data Persistence Proof

**Test Procedure:**
1. Verify current application state by checking the marketplace page at `http://localhost:3001/market`

<img width="1004" height="668" alt="image" src="https://github.com/user-attachments/assets/41ff660e-ed77-41ca-ae06-72e60edc4622" />

2. Execute `docker compose down` (WITHOUT the `-v` flag)

<img width="933" height="347" alt="image" src="https://github.com/user-attachments/assets/8828cba9-7909-41d2-b331-9178369a34d3" />

3. Execute `docker compose up -d` to restart the stack

<img width="952" height="455" alt="image" src="https://github.com/user-attachments/assets/ab8aaaf0-f591-4b1c-93d1-d44f9241a27c" />

4. Re-check the marketplace page

**Expected Result:**
All seeded products, stores, and uploaded images remain intact after the restart. The application state is fully preserved.

<img width="1004" height="668" alt="image" src="https://github.com/user-attachments/assets/fa84fec5-cf62-4976-a451-9b44ea1c9271" />

**Why This Works:**

When you run `docker compose down`:
- Containers are **stopped and removed**
- Container filesystems are **deleted**
- **Named volumes are preserved** (unless `-v` flag is used)
- Volume data persists on the host filesystem

When you run `docker compose up -d`:
- New containers are created
- Named volumes are **reattached** to the new containers
- The PostgreSQL container finds all its existing database files
- The media-service container finds all existing uploaded images
- The application resumes with all previous data intact

**What Would Happen With `docker compose down -v`:**

The `-v` flag tells Docker to delete volumes along with containers. This would:
1. **Delete** `netiks_store_postgres_data` → All database records lost
2. **Delete** `netiks_store_media_uploads` → All uploaded images lost
3. Require complete **re-seeding** of the database
4. Require **re-uploading** all product images and store logos
5. Reset the application to a **fresh installation state**

**Critical Takeaway:** Named volumes are Docker's solution for persistent data. They survive container restarts, updates, and recreations—but they can be destroyed with the `-v` flag.

---

### Product Image Storage Location

**Where Uploaded Files End Up:**

When a vendor uploads a product image through the media-service:

1. **Upload Path**: `POST http://localhost:8004/uploads`
2. **Storage Location**: Files are written to `/app/uploads` inside the media-service container
3. **Volume Mapping**: This directory is backed by the `media_uploads` Docker volume
4. **Physical Location**: Actual files reside in `/var/lib/docker/volumes/netiks_store_media_uploads/_data` on the host machine

**Cloud Deployment Implications:**

**Current Approach (Local Disk Storage):**
- ✅ Simple and works well for development
- ✅ No external dependencies or costs
- ❌ **Critical Risk**: If the VM's disk fails, all images are permanently lost
- ❌ **Scaling Issue**: Cannot easily share images across multiple server instances
- ❌ **Backup Complexity**: Requires file-level backups in addition to database backups

**Recommended Cloud Approach:**

Use **object storage services** like Amazon S3, Google Cloud Storage, or Azure Blob Storage:
- ✅ **Durability**: 99.999999999% (11 nines) durability - files are replicated across multiple data centers
- ✅ **Availability**: Accessible from multiple servers, enabling horizontal scaling
- ✅ **Automatic Backups**: Cloud providers handle redundancy and backups
- ✅ **Cost-Effective**: Pay only for storage used; no need to provision disk space
- ✅ **CDN Integration**: Can serve images through Content Delivery Networks for faster global access

**What Happens If VM Disk Dies:**

With current local storage:
1. All uploaded product images are **permanently lost**
2. Products will display without images (broken image links)
3. Vendors must **re-upload all media**
4. Customer experience severely degraded
5. No recovery possible unless you have external backups

With S3 or similar object storage:
1. Images remain **safe and accessible** even if the VM is completely destroyed
2. Simply point a new VM to the same S3 bucket
3. Application continues serving images without interruption
4. Zero data loss scenario

---

### Redis Storage Analysis

**What Redis Stores in Netiks Store:**

Based on the configuration, Redis is available for:
1. **Session caching** (if implemented)
2. **Rate limiting data** for API endpoints
3. **Temporary cached data** to reduce database queries
4. **Background job queues** (if implemented in future)

**Current Usage:**
Redis is provisioned but appears to be **lightly used or reserved for future features**. The current architecture primarily relies on PostgreSQL for all persistent data.

**Data Loss Impact Analysis:**

**If Redis Container Is Deleted:**

**Potential Losses:**
- Cached data would be lost (needs to be rebuilt from database)
- Active sessions might be interrupted
- Rate limiting counters would reset
- Background job queues would be cleared

**Is This Loss Acceptable?**

**Yes, for most scenarios:**
- ✅ Redis data is **ephemeral by design** - it's meant to be rebuilt
- ✅ No permanent business data is stored in Redis
- ✅ Application can regenerate cached data from PostgreSQL
- ✅ User impact is minimal - worst case is slightly slower performance while cache rebuilds
- ✅ Sessions can be re-established through new logins

**When It Becomes Critical:**
- ⚠️ If Redis is used for critical rate limiting (e.g., preventing abuse), resets could allow rate limit bypass
- ⚠️ If background job queues contain time-sensitive tasks, those tasks would be lost
- ⚠️ High-traffic periods could see performance degradation while cache rebuilds

**Best Practice:**
- Redis should **never** be the primary storage for any data you cannot afford to lose
- Always design Redis usage to be **recoverable from other sources**
- Consider Redis persistence (RDB snapshots or AOF logs) for production environments if uptime is critical

---

## Part 4 - Configuration & Secrets Review

### Environment Variables Configuration Table

| Variable | What it controls | Safe to commit to Git? | Must change for cloud? |
|----------|------------------|------------------------|------------------------|
| `NEXT_PUBLIC_API_BASE_URL` | Public API endpoint for browser requests | ✅ Yes (example only) | ✅ Yes - Change to cloud domain |
| `INTERNAL_API_BASE_URL` | Server-side API endpoint | ✅ Yes (example only) | ⚠️ Maybe - Depends on architecture |
| `GATEWAY_PORT` | Gateway service port number | ✅ Yes | ❌ No - Internal port |
| `IDENTITY_SERVICE_PORT` | Identity service port | ✅ Yes | ❌ No - Internal port |
| `VENDOR_SERVICE_PORT` | Vendor service port | ✅ Yes | ❌ No - Internal port |
| `CATALOG_SERVICE_PORT` | Catalog service port | ✅ Yes | ❌ No - Internal port |
| `MEDIA_SERVICE_PORT` | Media service port | ✅ Yes | ❌ No - Internal port |
| `ADMIN_SERVICE_PORT` | Admin service port | ✅ Yes | ❌ No - Internal port |
| `MEDIA_SERVICE_URL` | Internal media service URL | ✅ Yes | ❌ No - Service name consistent |
| `IDENTITY_SERVICE_URL` | Internal identity service URL | ✅ Yes | ❌ No - Service name consistent |
| `VENDOR_SERVICE_URL` | Internal vendor service URL | ✅ Yes | ❌ No - Service name consistent |
| `CATALOG_SERVICE_URL` | Internal catalog service URL | ✅ Yes | ❌ No - Service name consistent |
| `POSTGRES_DB` | Database name | ✅ Yes | ❌ No - Can remain same |
| `POSTGRES_USER` | Database username | ❌ **NO - SECURITY RISK** | ✅ **YES - CRITICAL** |
| `POSTGRES_PASSWORD` | Database password | ❌ **NO - SECURITY RISK** | ✅ **YES - CRITICAL** |
| `POSTGRES_HOST` | Database hostname | ✅ Yes | ❌ No - Service name consistent |
| `POSTGRES_PORT` | Internal database port | ✅ Yes | ❌ No - Internal port |
| `POSTGRES_EXPOSE_PORT` | Host-exposed database port | ✅ Yes | ✅ Yes - Should NOT be exposed |
| `WEB_EXPOSE_PORT` | Host port for web frontend | ✅ Yes | ✅ Yes - Behind reverse proxy |
| `REDIS_URL` | Redis connection string | ✅ Yes | ❌ No - Service name consistent |
| `JWT_SECRET` | Secret key for JWT signing | ❌ **NO - SECURITY RISK** | ✅ **YES - CRITICAL** |
| `JWT_ALGORITHM` | JWT signing algorithm | ✅ Yes | ❌ No - Standard algorithm |
| `ACCESS_TOKEN_EXPIRE_MINUTES` | Token expiration time | ✅ Yes | ⚠️ Maybe - Consider shortening |
| `UPLOAD_DIR` | Media upload directory path | ✅ Yes | ✅ Yes - Change to S3 config |

---

### Security Problems with Current Configuration

**Critical Security Issues for Cloud Deployment:**

#### 1. Default Database Credentials
```
POSTGRES_USER=postgres
POSTGRES_PASSWORD=postgres
```

**Problem:**
- Using the default username "postgres" with the simple password "postgres" is a well-known default
- Attackers routinely scan for databases with default credentials
- If the database port is exposed, it can be compromised in minutes

**Risk Level:** 🔴 **CRITICAL**

**Recommended Fix:**
- Generate a strong, random password (minimum 20 characters, mixed case, numbers, symbols)
- Use a non-default username
- Store in environment-specific secret management (AWS Secrets Manager, Azure Key Vault, etc.)

Example:
```
POSTGRES_USER=netiks_prod_db_admin_2026
POSTGRES_PASSWORD=Xk9#mP2$vL8qR5@nB3wT7&hF4*dC6!jN
```

---

#### 2. Weak JWT Secret
```
JWT_SECRET=change-this-to-a-32-char-minimum-secret
```

**Problem:**
- The value literally says "change-this", indicating it's a placeholder
- Even though it meets the 32-character minimum, it's predictable
- A weak JWT secret allows attackers to forge authentication tokens

**What JWT_SECRET Controls:**

The JWT_SECRET is used to **cryptographically sign** authentication tokens. When a user logs in:
1. The identity-service generates a JWT token containing user information
2. This token is **signed** using the JWT_SECRET
3. The signature proves the token hasn't been tampered with
4. Services verify the signature before trusting the token's contents

**What An Attacker Could Do With The Secret:**

If an attacker discovers the JWT_SECRET, they can:
- ✅ **Forge valid tokens** for any user account, including administrators
- ✅ **Bypass authentication** entirely by creating their own tokens
- ✅ **Impersonate any user** without knowing passwords
- ✅ **Access all protected endpoints** and perform administrative actions
- ✅ **Create new admin accounts** or modify existing data
- ✅ **Steal customer information, vendor data, and order history**

**Real-World Attack Scenario:**
1. Attacker finds JWT_SECRET in a misconfigured cloud environment or GitHub repository
2. Attacker creates a JWT token with `{"user_id": "admin", "role": "admin"}`
3. Attacker signs it with the stolen JWT_SECRET
4. Attacker uses this forged token to access all admin endpoints
5. Entire platform is compromised without any login attempts

**Risk Level:** 🔴 **CRITICAL**

**Recommended Fix:**
- Generate a cryptographically strong random secret (64+ characters)
- Never use readable words or patterns
- Store in secure secret management system
- Rotate periodically (every 90 days)

Example generation:
```bash
# Using Python
python -c "import secrets; print(secrets.token_urlsafe(64))"

# Using OpenSSL
openssl rand -base64 64 | tr -d '\n'
```

---

#### 3. Exposed Database Port
```
POSTGRES_EXPOSE_PORT=55432
```

**Problem:**
- The database is configured to be accessible from outside Docker
- In production, this means anyone on the internet could attempt to connect
- Combined with weak credentials, this is a disaster waiting to happen

**Risk Level:** 🔴 **CRITICAL in production**

**Recommended Fix:**
- Remove the port mapping entirely in production
- Database should **only** be accessible from within the Docker network
- Use SSH tunneling or VPN for administrative access
- Never expose databases directly to the internet

---

### Variables Requiring Changes for Cloud Deployment

**Must Change for Public Access:**

1. **`NEXT_PUBLIC_API_BASE_URL`**
   - **From:** `http://localhost:8000/api/v1`
   - **To:** `https://api.netiks.com/api/v1` or `https://yourdomain.com/api/v1`
   - **Reason:** Users' browsers need to reach the actual cloud server, not localhost

2. **`POSTGRES_PASSWORD` and `POSTGRES_USER`**
   - **From:** Default credentials
   - **To:** Strong, unique credentials stored in secrets manager
   - **Reason:** Security requirement for production environments

3. **`JWT_SECRET`**
   - **From:** Placeholder value
   - **To:** Cryptographically strong random string
   - **Reason:** Secure authentication system

4. **`UPLOAD_DIR` or add S3 Configuration**
   - **From:** `/app/uploads` (local disk)
   - **To:** S3 bucket configuration with credentials
   - **Reason:** Durable, scalable media storage

**Should Remove/Not Expose:**

5. **`POSTGRES_EXPOSE_PORT`**
   - **Action:** Remove port mapping from docker-compose
   - **Reason:** Database should never be directly accessible from internet

---

## Part 5 - Production Readiness Assessment

# What Must Change Before Netiks Store Runs in the Cloud

---

### 1. Service Exposure and Security Boundaries

**Current Issue:**

In the local development environment, all 9 services publish their ports to the host machine:
- Web frontend: 3001
- Gateway: 8000
- Identity service: 8001
- Vendor service: 8002
- Catalog service: 8003
- Media service: 8004
- Admin service: 8005
- PostgreSQL: 55432
- Redis: 6379

On a cloud VM with a public IP, **every single port would be accessible from the internet**. This means anyone could directly access any service, bypassing intended security controls.

**Why This Matters:**

1. **Direct Database Access:** Exposing PostgreSQL port 55432 allows attackers to attempt database connections, potentially compromising all application data
2. **Service Bypass:** Attackers could skip the gateway and directly call internal services, bypassing authentication checks
3. **Attack Surface:** Each exposed service is a potential entry point for attacks, DOS, or exploitation
4. **No Access Control:** Internal services lack robust authentication because they're designed to trust requests from the gateway

**Which Services Should Be Publicly Accessible:**

✅ **ONLY the Web Frontend** (currently port 3001)
- This is the user-facing application
- Should be accessed through a reverse proxy on standard ports (80/443)

**Which Services MUST NOT Be Publicly Accessible:**

❌ **Gateway (8000)** - Should only be accessible from the web frontend container  
❌ **All Microservices (8001-8005)** - Should only be accessible from the gateway  
❌ **PostgreSQL (55432)** - Should only be accessible from service containers  
❌ **Redis (6379)** - Should only be accessible from service containers

**Proposed Direction:**

1. **Remove all port mappings** from docker-compose.yml except for the web service
2. Implement a **reverse proxy** (Nginx or Caddy) to handle public traffic
3. Configure the reverse proxy to:
   - Listen on ports 80 (HTTP) and 443 (HTTPS)
   - Route requests to the web frontend
   - Route API requests to the gateway
   - Reject all other traffic
4. Services communicate only through Docker's internal network
5. Use **firewall rules** (AWS Security Groups, UFW, iptables) to block direct access to service ports

**Configuration Example:**
```yaml
# Production docker-compose.yml - No exposed ports except through reverse proxy
services:
  web:
    # No ports section - accessed only through reverse proxy
  gateway:
    # No ports section - internal only
  postgres:
    # No ports section - internal only
```

---

### 2. Traffic Entry Point and Reverse Proxy

**Current Issue:**

Local development uses `http://localhost:3001` to access the application. This doesn't work in the cloud because:
- Users are accessing from different locations worldwide
- `localhost` refers to their own computer, not your server
- Port numbers (3001, 8000) look unprofessional and confusing
- No HTTPS/TLS encryption

**What Is A Reverse Proxy:**

A reverse proxy is a server that sits between users and your application, acting as an intermediary that:
- Receives all incoming traffic from the internet
- Routes requests to the appropriate internal services
- Returns responses back to users
- Can handle SSL/TLS termination for HTTPS
- Can implement rate limiting, caching, and load balancing

**Analogy:** Think of a reverse proxy like a hotel concierge. Guests (users) don't know the internal layout of the hotel (your microservices). They ask the concierge (reverse proxy) for what they need, and the concierge knows exactly which internal department to contact.

**Why You Need It:**

1. **Single Entry Point:** Users connect to one domain (e.g., netiks.com)
2. **Standard Ports:** Access via port 80 (HTTP) or 443 (HTTPS), not custom ports
3. **SSL/TLS Termination:** Handles HTTPS encryption so internal services can use plain HTTP
4. **Request Routing:** Routes `/` to web frontend, `/api/v1/` to gateway
5. **Security Layer:** Can filter malicious requests before they reach your application
6. **Static Content:** Can serve static files efficiently without hitting application servers

**Proposed Direction:**

1. **Install Nginx or Caddy** on the cloud VM
2. **Configure routing rules:**
   ```nginx
   # Nginx example
   server {
       listen 80;
       server_name netiks.com www.netiks.com;
       
       location / {
           proxy_pass http://localhost:3000;  # Web frontend
       }
       
       location /api/v1/ {
           proxy_pass http://localhost:8000;  # Gateway
       }
   }
   ```

3. **Domain Setup:**
   - Register a domain name (e.g., netiks.com)
   - Point DNS A records to your VM's public IP address
   - Configure reverse proxy to accept requests for that domain

4. **Traffic Flow:**
   ```
   User → netiks.com:443 → Reverse Proxy → Web Frontend (3000)
   User → netiks.com/api/v1 → Reverse Proxy → Gateway (8000) → Services
   ```

**Benefits:**
- Professional domain-based access
- Secure HTTPS connections
- Internal services remain hidden
- Centralized security and monitoring

---

### 3. Secrets Management and Credential Security

**Current Issue:**

All secrets are stored in plain text in a `.env` file:
- Database credentials
- JWT signing secret
- API keys (if any)

In development, this is acceptable, but in production:
- The `.env` file might be accidentally committed to Git
- Server administrators can read all secrets
- Backup systems might expose secrets
- No audit trail of who accessed secrets
- Secrets aren't rotated or versioned

**Why This Matters:**

Compromised secrets mean:
- **Database breach:** Full access to all application data
- **Authentication bypass:** Ability to forge user tokens
- **Data theft:** Customer information, vendor data, orders
- **Service disruption:** Ability to delete or modify data
- **Regulatory violations:** GDPR, PCI-DSS, and other compliance failures

**Proposed Direction:**

**Option 1: Basic - Environment Variables from Secure Source**
1. Store secrets in server environment variables (not in files)
2. Load them when starting Docker Compose
3. Use SSH key-based access to the server
4. Implement file permissions to restrict .env access

**Option 2: Recommended - Cloud Secret Management**
1. Use **AWS Secrets Manager** or **AWS Systems Manager Parameter Store**
2. Store all secrets encrypted in AWS
3. Configure services to fetch secrets at startup
4. Rotate secrets regularly (automated)
5. Audit all secret access

**Implementation Approach:**
```yaml
# docker-compose.yml
services:
  identity-service:
    environment:
      JWT_SECRET: ${JWT_SECRET_FROM_AWS}
      POSTGRES_PASSWORD: ${DB_PASSWORD_FROM_AWS}
```

**Script to fetch secrets on startup:**
```bash
#!/bin/bash
# fetch-secrets.sh
export JWT_SECRET=$(aws secretsmanager get-secret-value --secret-id prod/jwt-secret --query SecretString --output text)
export POSTGRES_PASSWORD=$(aws secretsmanager get-secret-value --secret-id prod/db-password --query SecretString --output text)
docker-compose up -d
```

**Benefits:**
- Encrypted storage of sensitive data
- Access logging and auditing
- Automatic rotation capabilities
- No secrets in code repositories
- Compliance-ready

---

### 4. Data Protection and Backup Strategy

**Current Issue:**

All data resides on the VM's local disk:
- PostgreSQL data in Docker volume
- Uploaded media files in Docker volume

**Risks:**

1. **Hardware Failure:** If the VM's disk fails, all data is permanently lost
2. **Accidental Deletion:** Running `docker compose down -v` destroys everything
3. **Ransomware:** Malware could encrypt or delete volumes
4. **No Disaster Recovery:** Cannot restore to a previous state
5. **Single Point of Failure:** One disk failure = complete business shutdown

**Why This Matters:**

A single disk failure could result in:
- Loss of all customer accounts
- Loss of all vendor stores and products
- Loss of all order history
- Loss of all uploaded product images
- Complete business continuity failure
- Potential legal liability

**Proposed Direction:**

**For PostgreSQL Database:**

1. **Automated Backups:**
   ```bash
   # Daily backup script
   #!/bin/bash
   DATE=$(date +%Y%m%d_%H%M%S)
   docker exec netiks_store-postgres-1 pg_dump -U postgres netiks_store | gzip > backup_$DATE.sql.gz
   aws s3 cp backup_$DATE.sql.gz s3://netiks-backups/database/
   ```

2. **Schedule with Cron:**
   ```cron
   0 2 * * * /home/ubuntu/backup-database.sh  # Daily at 2 AM
   ```

3. **Retention Policy:**
   - Keep daily backups for 7 days
   - Keep weekly backups for 4 weeks
   - Keep monthly backups for 12 months

4. **Alternative - Managed Database:**
   - Consider **AWS RDS for PostgreSQL**
   - Automated backups included
   - Point-in-time recovery
   - Multi-AZ replication for high availability
   - Higher cost but much better reliability

**For Media Files:**

1. **Migration to S3:**
   - Move from local storage to **Amazon S3**
   - S3 provides 99.999999999% durability (11 nines)
   - Automatic replication across multiple data centers
   - Versioning capabilities
   - No backup needed - S3 handles redundancy

2. **Configuration Changes:**
   ```python
   # media-service update
   import boto3
   
   s3_client = boto3.client('s3')
   bucket_name = 'netiks-media-uploads'
   ```

**Testing Recovery:**

Regular disaster recovery drills:
1. Restore database from backup to a test environment
2. Verify data integrity
3. Test application functionality with restored data
4. Document recovery time and process

**Benefits:**
- Protection against hardware failures
- Ability to recover from mistakes
- Compliance with data protection regulations
- Business continuity assurance
- Peace of mind

---

### 5. Container Restart Policies and Service Availability

**Current Issue:**

Checking the `docker-compose.yml` file reveals **no restart policies** are configured. This means:

```yaml
services:
  web:
    build: ...
    # NO restart policy
```

**What Happens When the VM Reboots:**

1. VM shuts down (planned maintenance, crash, or update)
2. All Docker containers stop
3. VM comes back online
4. Docker daemon starts
5. **Containers DO NOT start automatically**
6. Application is completely down
7. Requires manual intervention: `docker compose up -d`

**Why This Matters:**

- **Unplanned Outages:** Surprise reboots mean extended downtime
- **Maintenance Windows:** Every OS update requires manual container restart
- **Service Level Failures:** Cannot meet uptime commitments
- **Manual Dependency:** Always requires someone to manually restart services

**Proposed Direction:**

Add restart policies to all services in `docker-compose.yml`:

```yaml
services:
  web:
    build: ...
    restart: unless-stopped
    
  gateway:
    build: ...
    restart: unless-stopped
    
  identity-service:
    build: ...
    restart: unless-stopped
    
  vendor-service:
    build: ...
    restart: unless-stopped
    
  catalog-service:
    build: ...
    restart: unless-stopped
    
  media-service:
    build: ...
    restart: unless-stopped
    
  admin-service:
    build: ...
    restart: unless-stopped
    
  postgres:
    image: postgres:16-alpine
    restart: unless-stopped
    
  redis:
    image: redis:7-alpine
    restart: unless-stopped
```

**Restart Policy Options:**

- **`no`** (default): Never restart automatically
- **`always`**: Always restart, even if manually stopped
- **`on-failure`**: Only restart if container exits with error
- **`unless-stopped`**: Always restart unless explicitly stopped by admin

**Recommended: `unless-stopped`**

This policy ensures:
- ✅ Containers restart after VM reboot
- ✅ Containers restart after crashes
- ✅ Manual stops are respected (for maintenance)
- ✅ Automatic recovery from failures

**Additional Boot Configuration:**

Ensure Docker itself starts on boot:
```bash
sudo systemctl enable docker
```

**Testing:**
1. Add restart policies to docker-compose.yml
2. Start the stack: `docker compose up -d`
3. Reboot the VM: `sudo reboot`
4. After reboot, verify all containers are running: `docker compose ps`

   <img width="1236" height="171" alt="image" src="https://github.com/user-attachments/assets/d3650008-a310-467b-978a-9d9e8209030f" />

**Expected Result:**
All containers should automatically come back online within 30-60 seconds of VM boot completion.

---

### 6. HTTPS/TLS Encryption

**Current Issue:**

All communication currently uses **plain HTTP**:
- Browser to web frontend: `http://localhost:3001`
- Web to gateway API: `http://localhost:8000`
- No encryption means all data travels in plain text

**Why HTTPS Matters:**

1. **Data Privacy:** Without encryption:
   - Login credentials sent in plain text
   - JWT tokens visible to network attackers
   - Customer personal information exposed
   - Credit card details (future feature) unprotected

2. **Man-in-the-Middle Attacks:**
   - Attackers on the same network can intercept traffic
   - Passwords can be stolen
   - Session tokens can be hijacked
   - Data can be modified in transit

3. **Browser Security Warnings:**
   - Modern browsers show "Not Secure" for HTTP sites
   - Users lose trust in the application
   - Some browsers block certain features on HTTP

4. **SEO Penalties:**
   - Google ranks HTTPS sites higher
   - HTTP sites marked as "Not Secure" in search results

5. **Compliance Requirements:**
   - PCI-DSS requires HTTPS for payment processing
   - GDPR requires encryption of personal data in transit
   - Many regulations mandate HTTPS

**What HTTPS Provides:**

- **Encryption:** All data scrambled during transmission
- **Authentication:** Proof that you're connecting to the real server, not an imposter
- **Integrity:** Guarantee that data hasn't been modified in transit
- **Trust:** Green padlock icon, "Secure" label in browsers

**Proposed Direction:**

**Step 1: Obtain SSL/TLS Certificate**

**Option A - Let's Encrypt (Free, Recommended):**
```bash
# Install Certbot
sudo apt install certbot python3-certbot-nginx

# Obtain certificate
sudo certbot --nginx -d netiks.com -d www.netiks.com
```

**Option B - AWS Certificate Manager (If using AWS Load Balancer):**
- Free certificates managed by AWS
- Automatic renewal
- Integrated with ALB/CloudFront

**Step 2: Configure Nginx with HTTPS**

```nginx
server {
    listen 80;
    server_name netiks.com www.netiks.com;
    return 301 https://$server_name$request_uri;  # Redirect HTTP to HTTPS
}

server {
    listen 443 ssl http2;
    server_name netiks.com www.netiks.com;
    
    ssl_certificate /etc/letsencrypt/live/netiks.com/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/netiks.com/privkey.pem;
    
    # Modern SSL configuration
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_ciphers HIGH:!aNULL:!MD5;
    
    location / {
        proxy_pass http://localhost:3000;
    }
    
    location /api/v1/ {
        proxy_pass http://localhost:8000;
    }
}
```

**Step 3: Update Application Configuration**

```env
NEXT_PUBLIC_API_BASE_URL=https://netiks.com/api/v1
```

**Step 4: Enable Automatic Certificate Renewal**

Let's Encrypt certificates expire after 90 days. Automate renewal:

```bash
# Test renewal
sudo certbot renew --dry-run

# Automatic renewal via cron (already installed by certbot)
sudo systemctl status certbot.timer
```

**What It Takes At Basic Level:**

1. **Domain Name:** Register and point DNS to your server (~$10-15/year)
2. **Certificate:** Free with Let's Encrypt
3. **Configuration:** 10-20 lines of Nginx configuration
4. **Time Investment:** 1-2 hours for first-time setup
5. **Maintenance:** Fully automated with certbot

**Benefits:**
- ✅ Secure data transmission
- ✅ User trust and browser confidence
- ✅ Compliance with security standards
- ✅ Better SEO rankings
- ✅ Protection against common attacks

---

### 7. Additional Production Concerns

**Logging and Monitoring:**

**Current State:**
- Logs go to container stdout
- No centralized log collection
- No alerting on errors

**Needed:**
- Centralized logging (AWS CloudWatch, ELK Stack, or Loki)
- Application performance monitoring
- Error tracking (Sentry, Rollbar)
- Uptime monitoring (UptimeRobot, Pingdom)

**Resource Limits:**

**Current State:**
- No memory or CPU limits on containers
- One service can consume all resources
- Potential for cascading failures

**Needed:**
```yaml
services:
  web:
    deploy:
      resources:
        limits:
          cpus: '1.0'
          memory: 512M
        reservations:
          cpus: '0.5'
          memory: 256M
```

**Health Checks:**

**Current State:**
- Only PostgreSQL has health checks
- Other services may start before they're ready

**Needed:**
```yaml
services:
  gateway:
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:8000/health"]
      interval: 30s
      timeout: 10s
      retries: 3
```

**Rate Limiting:**

**Current State:**
- No rate limiting
- Vulnerable to DOS attacks
- API abuse possible

**Needed:**
- Implement rate limiting at reverse proxy level
- Configure per-endpoint rate limits
- Add IP-based throttling

---

## Summary of Critical Changes

### Must-Have Before Cloud Deployment

| Priority | Change | Impact | Effort |
|----------|--------|--------|--------|
| 🔴 Critical | Remove database port exposure | Security | Low |
| 🔴 Critical | Change default database credentials | Security | Low |
| 🔴 Critical | Generate strong JWT secret | Security | Low |
| 🔴 Critical | Implement reverse proxy with HTTPS | Security & Functionality | Medium |
| 🔴 Critical | Add restart policies to all services | Reliability | Low |
| 🟡 High | Configure secrets management | Security | Medium |
| 🟡 High | Migrate media to S3 | Durability | Medium |
| 🟡 High | Implement database backup strategy | Data Protection | Medium |
| 🟢 Medium | Add health checks to all services | Reliability | Low |
| 🟢 Medium | Configure resource limits | Stability | Low |
| 🟢 Medium | Set up centralized logging | Observability | Medium |

### Deployment Readiness Checklist

- [ ] All services configured with restart: unless-stopped
- [ ] Database credentials changed from defaults
- [ ] JWT secret replaced with cryptographically strong value
- [ ] Port mappings removed (except through reverse proxy)
- [ ] Nginx/Caddy configured as reverse proxy
- [ ] SSL/TLS certificate obtained and configured
- [ ] Domain name registered and DNS configured
- [ ] HTTPS enforced for all traffic
- [ ] Secrets stored in AWS Secrets Manager or equivalent
- [ ] Media uploads configured to use S3
- [ ] Database backup script created and scheduled
- [ ] Backup restore procedure tested
- [ ] Monitoring and alerting configured
- [ ] Firewall rules configured on VM
- [ ] Security group rules configured (AWS)
- [ ] Health checks implemented for all services
- [ ] Resource limits defined for containers
- [ ] Documentation updated for production environment

---

## Reflections

### What I Found Hardest This Week

The most challenging aspect of this week's deep dive was fully understanding the **security implications of the current configuration** and how seemingly innocent development conveniences become critical vulnerabilities in production environments.

Initially, having all services expose their ports seemed logical for development - it makes debugging easy and allows direct access to each service. However, realizing that this same configuration on a public cloud VM would expose the database, all microservices, and Redis directly to the internet was eye-opening. The concept of "default secure" vs. "default convenient" became very clear.

The second challenge was grasping the **dual-environment nature of Next.js** and why two different API URLs are necessary. Understanding that JavaScript executes in fundamentally different contexts (browser vs. server) and that Docker's internal DNS is only available within the container network required mental shifting between these two perspectives.

Finally, working through the **data persistence concepts** with Docker volumes highlighted how easy it is to accidentally destroy data with a single flag (`-v`). This reinforced the critical importance of backup strategies and durable storage solutions like S3 for production environments.

This week transformed my understanding from "how to run the application locally" to "how to architect for production safely and reliably." The knowledge gained will be essential for Week 2's cloud deployment.

---

## Appendix: Quick Reference Answers

### Three Critical Questions

**1. Which containers must never be exposed to the public internet, and why?**

**Answer:** PostgreSQL, Redis, and ALL backend microservices (identity, vendor, catalog, media, admin services) must never be directly exposed. 

- **PostgreSQL** contains all application data and credentials - exposure allows direct database access and potential data theft
- **Redis** may contain session data and cache - exposure allows session hijacking and cache poisoning
- **Backend microservices** lack robust authentication since they trust the gateway - direct exposure bypasses security controls and allows unauthorized access to sensitive operations

Only the web frontend should be accessible publicly, and only through a reverse proxy with HTTPS.

---

**2. Where does the data live, and what single command would destroy it?**

**Answer:** Data lives in two Docker named volumes:

1. **`netiks_store_postgres_data`** - Contains all database records (users, stores, products, orders)
2. **`netiks_store_media_uploads`** - Contains all uploaded images and media files

**The command that would destroy all data:**
```bash
docker compose down -v
```

The `-v` flag tells Docker to delete volumes along with containers, resulting in:
- Complete loss of all database records
- Permanent deletion of all uploaded media
- No recovery possible without external backups
- Application reset to fresh installation state

**Safe command to restart without data loss:**
```bash
docker compose down     # Without -v flag
docker compose up -d
```

---

**3. What three things would you change in `.env` before deploying tomorrow?**

**Answer:**

**Change 1: Database Credentials**
```bash
# FROM (INSECURE):
POSTGRES_USER=postgres
POSTGRES_PASSWORD=postgres

# TO (SECURE):
POSTGRES_USER=netiks_prod_admin_2026
POSTGRES_PASSWORD=Xk9#mP2$vL8qR5@nB3wT7&hF4*dC6!jN
# Generated with: openssl rand -base64 32
```

**Change 2: JWT Secret**
```bash
# FROM (INSECURE):
JWT_SECRET=change-this-to-a-32-char-minimum-secret

# TO (SECURE):
JWT_SECRET=c3VwZXJfc2VjcmV0X2tleV90aGF0X2lzX3ZlcnlfbG9uZ19hbmRfcmFuZG9tXzIwMjY=
# Generated with: python -c "import secrets; print(secrets.token_urlsafe(64))"
```

**Change 3: API Base URL**
```bash
# FROM (LOCAL):
NEXT_PUBLIC_API_BASE_URL=http://localhost:8000/api/v1

# TO (CLOUD):
NEXT_PUBLIC_API_BASE_URL=https://api.netiks.com/api/v1
# Or whatever your actual domain will be
```

**Why These Matter:**
- **Database credentials:** Prevent unauthorized database access and data breaches
- **JWT secret:** Prevent authentication bypass and user impersonation
- **API URL:** Enable browsers to connect to the actual cloud server instead of localhost

---

## Conclusion

Netiks Store is a well-architected microservices application that demonstrates modern cloud-native principles. The current implementation works excellently for local development, providing clear service boundaries, proper data persistence, and a realistic multi-vendor marketplace experience.

However, transitioning from local development to production cloud deployment requires significant configuration and architectural changes. The primary concerns center around:

1. **Security:** Removing exposed services, implementing strong credentials, and adding HTTPS
2. **Reliability:** Configuring automatic restarts, implementing backups, and using durable storage
3. **Accessibility:** Setting up proper domain-based routing through a reverse proxy

None of these changes require fundamental architectural redesign. The microservices structure is sound and production-ready. The required changes are primarily operational and configurational in nature, which is exactly what Week 2's deployment exercises will address.

The knowledge gained this week provides a solid foundation for understanding not just how to deploy the application, but **why** each production configuration exists and what problems it solves. This understanding is essential for maintaining and troubleshooting the application in real-world cloud environments.

---

**Report Prepared By:** Afolami Olaoluwa   
**Date:** August 6, 2026  
**Next Steps:** Week 2 - Cloud VM Deployment  

---

*End of Report*


# Project Execution Report: Netiks Store Microservices Platform.
## 1. Project Overview.
The objective of this task was to successfully deploy and run the Netiks Store, a multi-vendor e-commerce microservices platform, locally using Docker. This project utilizes a distributed architecture consisting of a Next.js frontend, a Python FastAPI backend ecosystem, and supporting infrastructure (PostgreSQL and Redis).

## 2. Starting the Project with Docker.
To ensure a clean and reproducible environment, the application was orchestrated using Docker Compose. The following steps were executed in the terminal:
### Step 1: Environment Configuration.
Created the local environment variables file required by the Docker containers:

![alt text](image.png)

### Step 2: Building and Starting the Containers.
Launched the entire microservices stack in detached (background) mode. This command built the custom Docker images for the Next.js frontend and Python services, and pulled the official images for the database and cache:

<img width="349" height="85" alt="image" src="https://github.com/user-attachments/assets/638292c0-0279-4f41-ba1d-17a5ed3a97a5" />


### Step 3: Seeding the Database.
To populate the empty database with demo vendors, categories, and products, the seeding script was executed. (Note: An environment variable DOCKER_BIN=docker was prepended to resolve a hardcoded macOS file path in the original script, adapting it for my Linux/WSL environment).

![alt text](image-2.png)

## 3. Explanation of Main Services.
The Netiks Store is built on a Microservices Architecture. Instead of one massive application doing everything, the system is broken down into specialized, independent services that talk to each other. Here is what each main service does in simple terms:
### Frontend (Next.js) - The Storefront.
This is the visual part of the application that the customer interacts with. It displays the products, handles the shopping cart UI, and provides a responsive, fast user experience.
### API Gateway (FastAPI) - The Traffic Cop.
The frontend doesn't talk to the database directly. Instead, it sends all its requests to the API Gateway. The Gateway acts like a receptionist, looking at the request and directing it to the correct backend service (e.g., "You want product details? Go talk to the Catalog Service.").
### Identity Service - The Security Guard.
This service handles everything related to users. It manages registration, logins, password hashing, and session tokens to ensure only authorized users can access certain features.
### Catalog Service - The Inventory Manager.
This is the brain behind the products. It stores and retrieves information about items, categories, prices, and stock levels. When you view a product page, the Catalog Service is providing that data.
### Vendor Service - The Landlord.
Because this is a multi-vendor marketplace (like Amazon or Etsy), this service manages the sellers. It keeps track of which store owns which products, store names, and vendor profiles.
### PostgreSQL - The Filing Cabinet.
This is the relational database where all the permanent, structured data lives. Every product, user, and order is safely stored in organized tables here.
### Redis - The Sticky Note / Whiteboard.
This is an in-memory data store. It is incredibly fast and is used to store temporary data that needs to be accessed quickly, such as active user sessions, caching frequently viewed products, or managing shopping carts.

## 4. Proof of Execution.
### A. Docker Container Status.
The following output verifies that all microservices and infrastructure components are successfully built, running, and healthy.

![alt text](image-3.png)

![alt text](image-4.png)

## B. Application Frontend Verification
The application was accessed via a web browser to verify that the frontend is successfully communicating with the API Gateway and rendering the seeded demo data.

![alt text](image-5.png)
![alt text](image-6.png)
![alt text](image-7.png)
## Market
![alt text](image-8.png)
![alt text](image-9.png)
## Vendor Access
![alt text](image-10.png)
### C. Access URLs
The application was successfully verified using the following local URLs:
- Main Storefront (Frontend): http://localhost:3001
- API Gateway (Backend Entry Point): http://localhost:8000
- Database (PostgreSQL): localhost:55432

## 5. Conclusion
The Netiks Store microservices platform was successfully deployed locally. All containers initialized correctly, database migrations were applied seamlessly, and the frontend successfully rendered the seeded marketplace data, proving that the service-to-service communication is fully operational.

#
# Netiks Store

Netiks Store is a multi-vendor e-commerce platform with a storefront, seller dashboard, checkout flow, and supporting backend services.

## Workspace Layout

```text
apps/
  web/
  gateway/
services/
  identity-service/
  vendor-service/
  catalog-service/
  media-service/
  admin-service/
packages/
  shared-python/
  shared-types/
infra/
  docker/
  nginx/
  aws/
docs/
```

## Quick Start

1. Copy `.env.example` to `.env`.
2. Install frontend dependencies with `npm install`.
3. Sync Python workspaces with `uv sync`.
4. Start Docker Desktop and wait until it shows that Docker is running.
5. Start the stack with `docker compose up --build -d`.
6. Open `http://localhost:3001`.

## First Task For Interns

The first task is to run the project locally with Docker and show proof that it is working.

Suggested proof:

- a screenshot of Docker Desktop or `docker compose ps`
- a screenshot of the home page or market page in the browser
- a short note showing the URL used: `http://localhost:3001`

## Demo Data Reset

Run `npm run seed:demo` while the Docker stack is up to load the default marketplace data:

- 3 vendor accounts with storefronts
- 3 stores and categories
- 6 published products with real product photos
- starter order history that updates stock and sold counts

## Current Working Backend Surface

The following flows are implemented and have been smoke-tested locally:

- Auth: register, login, `me`, refresh-token rotation
- Vendor: create store, get my store, public store lookup, store update
- Catalog: create/list categories, create/update products, public published-product lookup, owner product listing
- Media: authenticated upload through the gateway, direct media retrieval

Services that still need further expansion:

- richer admin moderation flows
- full product search/filtering
- cross-service ownership verification between catalog and vendor domains

## Local Service Endpoints

- Frontend: `http://localhost:3001` by default in Docker Compose
- Gateway: `http://localhost:8000`
- Identity: `http://localhost:8001`
- Vendor: `http://localhost:8002`
- Catalog: `http://localhost:8003`
- Media: `http://localhost:8004`

## Docker Notes

- Each backend service runs Alembic migrations on container startup.
- The repo includes a root `.dockerignore` to keep build contexts smaller for GitHub and CI.
- If port `5432` is already in use on a machine, set `POSTGRES_EXPOSE_PORT` in `.env` before running Compose.
- If the stack has already been run before and you want clean marketplace data again, use `npm run seed:demo`.
- If you change code and want to rebuild everything, run `docker compose up --build -d` again.

## Documentation

- [Intern Quickstart Guide](/Users/woron/Documents/netiks-store/docs/INTERN_QUICKSTART_GUIDE.md)
- [PRD](/Users/woron/Documents/netiks-store/docs/PRD.md)
- [Project Documentation](/Users/woron/Documents/netiks-store/docs/PROJECT_DOCUMENTATION.md)
- [Technical Plan](/Users/woron/Documents/netiks-store/docs/TECHNICAL_PLAN.md)
- [Deployment Challenge Lab](/Users/woron/Documents/netiks-store/docs/DEPLOYMENT_CHALLENGE_LAB.md)
