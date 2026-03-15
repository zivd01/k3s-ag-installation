# K3s Automated Installation Script for RHEL 9

This shell script automates the installation and configuration of a K3s (Lightweight Kubernetes) cluster on a Single Node (Red Hat Enterprise Linux 9 or compatible architecture).

## Overview
The script performs the following core actions automatically:
- **Environment Checks**: Gathers OS release, total CPU count, and accessible memory amounts.
- **Resource Sizing Auto-Detection**: Automatically scales and recommends the node capacity profile (ranging from "Minimum" to "Large") relying entirely on the native server's processing metrics without pausing for user intervention.
- **Role Selection**: Offers an interactive menu to specify if the server deploys as an All-in-one controller, a Dedicated backend database (etcd), or a Dedicated Control-Plane.
- **Container Registry**: Simplifies the generation of the K3s registry mirror YAML block (`registries.yaml`), easing bootstrapping of components through private corporate image repos.
- **Firewall Provisioning**: Lets you turn `firewalld` cleanly off or configure its internal networking paths automatically mapping out `flannel`, `kubectl`, and `pod`-centric connection limits across valid endpoints.
- **Installation Execution**: Fetches the upstream K3s installer script (`get.k3s.io`) securely and executes it with given topology attributes mapped through K3s explicit `INSTALL_K3S_EXEC` variable.
- **Validation and Reporting**: Checks if the daemons booted OK, connects against Kubernetes' master plane locally to probe node configurations, then logs a robust final summary file to `/root/k3s_install_report.txt`.

## Getting Started

### Prerequisites
- A system running **RHEL 9**, or a compatible RHEL 9 distribution (AlmaLinux, Rocky Linux, etc.).
- Root access or explicitly runnable as a superuser.
- Outbound connectivity towards `https://get.k3s.io` & upstream registry endpoints depending on your selected setup.

### Usage
Start by granting execution rights on the scripts, then run them passing administrative (`sudo`/`root`) permissions.

#### 1. Installation
```bash
chmod +x install_k3s.sh
sudo ./install_k3s.sh
```
Follow the interactive prompts that let you tune your server roles, firewall preferences, and registry endpoints.

#### 2. Health Checking & Diagnostics
To verify your cluster's health or troubleshoot issues (e.g. failing pods, high CPU/RAM usage), use the included health check script:
```bash
chmod +x check_k3s_health.sh
sudo ./check_k3s_health.sh
```
This script acts as a diagnostic tool checking:
- Node and Control Plane (API) readiness
- Resource usage down to the Top 10 heavy Pods
- Problematic, evicted, or crashing workloads
- Important K3s backend paths (Logs, Config files, Binaries)
- Storage / Disk Pressure warnings

#### 3. Real-Time Web Dashboard
To deploy a lightweight, real-time HTML monitoring dashboard over port 8080 without external dependencies:
```bash
cd dashboard
chmod +x install_dashboard.sh
sudo ./install_dashboard.sh
```

**How to Access & Use the Dashboard:**
1. Open a web browser on any machine that can reach your K3s server.
2. Navigate to: `http://<SERVER_IP>:8080`
3. The dashboard UI will automatically refresh its data **every 3 seconds** without needing to manually reload the page.

**Dashboard Features:**
- **Live Node Metrics**: View your server's assigned CPU and Memory allocations dynamically.
- **Top Workloads**: View up-to-date pods, their underlying Node, and the time they were created.
- **Filtering**: Two dropdowns allow slicing the pods by **Namespace** (e.g. `kube-system`) or **Health Status** ("Running" vs "Failing").
- **Interactive Restart Counters**: Instantly spot pods stuck in `CrashLoopBackOff` from the Restarts column.
- **Real-Time Warnings**: A dedicated Event log at the bottom aggregates cluster warnings (e.g., DiskPressure, FailedScheduling, ImagePull errors).

### Logs and Reporting
The scripts log thoroughly their execution details. You can review the output directly:
- **System Installation Logs**: `/var/log/k3s_install.log`
- **Installation Summary**: `/root/k3s_install_report.txt`
- **Health Check Report**: `/root/k3s_health_report_YYYYMMDD_HHMMSS.txt`

### Key K3s Paths Reference
If you need to administer the cluster manually post-installation:
- **Kubeconfig**: `/etc/rancher/k3s/k3s.yaml`
- **Containerd Logs**: `/var/lib/rancher/k3s/agent/containerd/containerd.log`
- **Data directory**: `/var/lib/rancher/k3s/`
- **Binary Directory**: `/usr/local/bin/k3s`

If encountering node joining issues or misconfigured firewalls, check these logs to discover misalignments or check if any network component got blocked or improperly routed.
