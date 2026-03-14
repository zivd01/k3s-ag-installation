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
Start by granting execution rights on the file, then run it passing administrative (`sudo`/`root`) permissions.

```bash
chmod +x install_k3s.sh
sudo ./install_k3s.sh
```

Follow the interactive prompts that let you tune your server roles, firewall preferences, and registry endpoints.

### Logs and Reporting
The script logs thoroughly its execution details. You can review the logs output directly:
- **System Execution Logs**: `/var/log/k3s_install.log`
- **Installation Summary Form**: `/root/k3s_install_report.txt`

If encountering node joining issues or misconfigured firewalls, check these logs to discover misalignments or check if any network component got blocked or improperly routed.
