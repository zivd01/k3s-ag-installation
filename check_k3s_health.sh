#!/bin/bash

# ==============================================================================
# K3s Cluster Health Check & Diagnostic Script
# ==============================================================================

REPORT_FILE="/root/k3s_health_report_$(date +%Y%m%d_%H%M%S).txt"
K_CMD="k3s kubectl"
export KUBECONFIG=/etc/rancher/k3s/k3s.yaml

# Ensure script is run as root
if [ "$EUID" -ne 0 ]; then
  echo "Please run as root"
  exit 1
fi

echo "Gathering cluster metrics and health status... This may take a few seconds."

{
echo "==============================================================================="
echo "                  K3S CLUSTER HEALTH REPORT                                    "
echo "                  Date: $(date)                                        "
echo "==============================================================================="
echo ""

# ------------------------------------------------------------------------------
# 1. K3s Service Status
# ------------------------------------------------------------------------------
echo "--- [1] K3S SERVICE STATUS ---"
if systemctl is-active --quiet k3s; then
    echo "STATUS: K3s systemd service is active and running."
else
    echo "WARNING: K3s systemd service is NOT active!"
    echo "Recommendation: Run 'systemctl status k3s' or 'journalctl -xeu k3s' to investigate."
fi
echo ""

# ------------------------------------------------------------------------------
# 2. Node Health & Status
# ------------------------------------------------------------------------------
echo "--- [2] NODE STATUS ---"
$K_CMD get nodes -o wide
echo ""
BAD_NODES=$($K_CMD get nodes | grep -v 'Ready' | grep -v 'NAME')
if [ -n "$BAD_NODES" ]; then
    echo "WARNING: The following nodes are NOT in Ready state:"
    echo "$BAD_NODES"
    echo "Recommendation: Describe the node using 'kubectl describe node <name>' to find conditions like DiskPressure or MemoryPressure."
else
    echo "STATUS: All nodes are in Ready state."
fi
echo ""

# ------------------------------------------------------------------------------
# 3. Node Resource Usage (CPU & Memory)
# ------------------------------------------------------------------------------
echo "--- [3] NODE RESOURCES CAPACITY & UTILIZATION ---"
echo "Node Level Top (Requires metrics-server):"
if $K_CMD top nodes &>/dev/null; then
    $K_CMD top nodes
else
    echo "WARNING: metrics-server is not responding or not installed."
    echo "Recommendation: Wait a few minutes if newly installed, or verify metrics-server pod."
fi
echo ""
echo "Host OS Disk Usage (Root Partition):"
df -h /
echo ""
echo "Host OS Memory Usage:"
free -m
echo ""

# ------------------------------------------------------------------------------
# 4. Namespace Resource Usage
# ------------------------------------------------------------------------------
echo "--- [4] CPU/MEM USAGE BY NAMESPACE ---"
if $K_CMD top pods -A &>/dev/null; then
    echo "Top 10 Pods consuming CPU/MEM across all namespaces:"
    $K_CMD top pods -A --sort-by=cpu | head -n 11
else
    echo "WARNING: metrics-server not available. Cannot fetch per-pod metrics."
fi
echo ""

# ------------------------------------------------------------------------------
# 5. Problematic Pods Analysis
# ------------------------------------------------------------------------------
echo "--- [5] PROBLEMATIC PODS ---"
# Check for pods that are not Running or Succeeded
BAD_PODS=$($K_CMD get pods -A --field-selector=status.phase!=Running,status.phase!=Succeeded | grep -iv "Completed")
if [ -z "$BAD_PODS" ] || [[ "$BAD_PODS" == *"No resources found"* ]]; then
    echo "STATUS: All pods are functionally healthy (Running/Completed)."
else
    echo "WARNING: Found pods in abnormal states (CrashLoopBackOff, Error, Pending, Evicted):"
    echo "$BAD_PODS"
fi
echo ""

# Also check for CrashLoopBackOff or Error explicitly across all states
CRASHING_PODS=$($K_CMD get pods -A | awk '$4 ~ /CrashLoopBackOff|Error|OOMKilled|ImagePullBackOff|ErrImagePull/')
if [ -n "$CRASHING_PODS" ]; then
    echo "WARNING: Pods actively crashing or failing to start:"
    echo "$CRASHING_PODS"
    echo "Recommendation: Check logs with 'kubectl logs <pod-name> -n <namespace> --previous' and 'kubectl describe pod <pod-name> -n <namespace>'."
fi
echo ""

# ------------------------------------------------------------------------------
# 6. Cluster Events (Warnings)
# ------------------------------------------------------------------------------
echo "--- [6] RECENT CLUSTER WARNINGS (Last 15) ---"
$K_CMD get events -A --sort-by='.metadata.creationTimestamp' | grep -i warning | tail -n 15
if [ $? -ne 0 ]; then
    echo "No recent warning events found."
fi
echo ""

# ------------------------------------------------------------------------------
# 7. Control Plane Components Status (API Server)
# ------------------------------------------------------------------------------
echo "--- [7] CONTROL PLANE HEATH ---"
if $K_CMD get --raw='/readyz' &>/dev/null; then
    echo "API Server /readyz : ok"
else
    echo "API Server /readyz : FAILED"
fi

if $K_CMD get --raw='/livez' &>/dev/null; then
    echo "API Server /livez  : ok"
else
    echo "API Server /livez  : FAILED"
fi
echo ""

# ------------------------------------------------------------------------------
# 8. Important K3s Paths & Directories
# ------------------------------------------------------------------------------
echo "--- [8] IMPORTANT K3S SYSTEM PATHS ---"
echo "Kubeconfig File       : /etc/rancher/k3s/k3s.yaml"
echo "K3s Binary            : /usr/local/bin/k3s"
echo "K3s Configuration Dir : /etc/rancher/k3s/"
echo "Additional Configs    : /etc/rancher/k3s/config.yaml.d/"
echo "Data Directory        : /var/lib/rancher/k3s/"
echo "Containerd Logs       : /var/lib/rancher/k3s/agent/containerd/containerd.log"
echo "Kubelet Configuration : /var/lib/rancher/k3s/agent/etc/kubelet.conf.d/"
echo "K3s Systemd Logs      : journalctl -u k3s"
echo "Container CLI Tool    : crictl (configured for k3s containerd)"
echo ""

# ------------------------------------------------------------------------------
# 9. Summary & Recommendations
# ------------------------------------------------------------------------------
echo "==============================================================================="
echo "                       RECOMMENDATIONS                                         "
echo "==============================================================================="
RECOMMENDATIONS_GIVEN=0

# Detect CPU/Mem pressure heuristically
SYS_CPU_IDLE=$(top -bn1 | grep "Cpu(s)" | awk '{print $8}' | cut -d'.' -f1)
if [[ -n "$SYS_CPU_IDLE" && "$SYS_CPU_IDLE" -lt 20 ]]; then
    echo "- The Node CPU is under heavy load (over 80% usage). Consider scaling up the server or limiting pod resources."
    RECOMMENDATIONS_GIVEN=1
fi

SYS_MEM_FREE=$(free -m | awk '/^Mem:/{print $4+$6}')
SYS_MEM_TOTAL=$(free -m | awk '/^Mem:/{print $2}')
SYS_MEM_PERCENT=$(( SYS_MEM_FREE * 100 / SYS_MEM_TOTAL ))
if [[ "$SYS_MEM_PERCENT" -lt 15 ]]; then
    echo "- The Node Memory is dangerously low (less than 15% free). Consider adding RAM or reviewing workloads to avoid OOMKills."
    RECOMMENDATIONS_GIVEN=1
fi

DISK_USE_PERCENT=$(df -h / | tail -1 | awk '{print $5}' | sed 's/%//')
if [[ "$DISK_USE_PERCENT" -gt 85 ]]; then
    echo "- The Root disk is over 85% full. Kubelet may start evicting pods (DiskPressure) soon. Clean up unused images with 'crictl rmi --prune' or expand the disk."
    RECOMMENDATIONS_GIVEN=1
fi

if [ -n "$CRASHING_PODS" ] || [ -n "$BAD_PODS" ]; then
    echo "- You have pods in failure states (Error/CrashLoopBackOff). Inspect their logs immediately using 'kubectl logs' to identify application or configuration errors."
    RECOMMENDATIONS_GIVEN=1
fi

if [ "$RECOMMENDATIONS_GIVEN" -eq 0 ]; then
    echo "- The cluster appears to be operating normally. No immediate corrective actions are required."
fi

echo "==============================================================================="
echo "Report generated and saved to: ${REPORT_FILE}"

} | tee "$REPORT_FILE"

# Make sure permissions restrict viewing to root
chmod 600 "$REPORT_FILE"
