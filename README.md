# K8S-Deploy01
# Infrastructure Requirements

### 1. Compute (Azure)
* **Instance Type:** Standard_B2s (2 vCPUs, 4GB RAM recommended)
* **OS:** Ubuntu 24.04 LTS
* **Storage:** 30GB Root Volume

### 2. Orchestration & Tools
* **MicroK8s:** v1.30+
* **Add-ons:** - metrics-server (for Project 2)
    - dashboard (for UI Management)
    - dns
* **Kubectl:** Version compatible with K8s v1.30

### 3. Network Configuration (Azure NSG)
| Port | Protocol | Purpose |
|------|----------|---------|
| 22   | TCP      | SSH Access |
| 80   | TCP      | HTTP Traffic |
| 32000| TCP      | K8S NodePort Service |
| 8001 | TCP      | K8S Dashboard Proxy |

### 4. Version Control
* **Git:** 2.x+
* **Authentication:** SSH ED25519 Key
