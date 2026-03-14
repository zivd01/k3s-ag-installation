#!/bin/bash

# ==============================================================================
# K3s Single Node Installation Script for RHEL 9
# ==============================================================================

# Define log file path for installation output
LOG_FILE="/var/log/k3s_install.log"
# Define path for the final text report summarizing the installation
REPORT_FILE="/root/k3s_install_report.txt"

# Ensure script is run as root (using Effective User ID representation)
if [ "$EUID" -ne 0 ]; then
  echo "Please run as root" # Exit if not root since kubernetes needs elevated privileges
  exit 1
fi

# Function to log messages to the console and to the log file appending a timestamp
log() {
    echo -e "$1" # Print to standard output
    echo -e "$(date '+%Y-%m-%d %H:%M:%S') - $1" &>> "$LOG_FILE" # Append formatted date and message to log file
}

# Function to check the exit status of the previously executed command
check_success() {
    # $? contains the exit code of the last run command (0 means success)
    if [ $? -eq 0 ]; then
        log "[\e[32mOK\e[0m] $1" # Print OK in green text
    else
        log "[\e[31mFAIL\e[0m] $1" # Print FAIL in red text
        log "Installation aborted due to failure: $1"
        exit 1 # Stop execution of script entirely
    fi
}

# Print the starting banner and mirror it simultaneously to the log file
echo "=====================================================================" | tee -a "$LOG_FILE"
echo "           Starting K3s Setup on RHEL 9                              " | tee -a "$LOG_FILE"
echo "=====================================================================" | tee -a "$LOG_FILE"
echo ""

# ------------------------------------------------------------------------------
# 1. Prerequisites Check (OS & Hardware)
# ------------------------------------------------------------------------------
log "=> Checking OS and Hardware..."
# Try to source the OS release file to extract system information
if [ -f /etc/os-release ]; then
    . /etc/os-release # Load variables like NAME and VERSION_ID into current shell execution
    OS_NAME=$NAME
    OS_VERSION=$VERSION_ID
    log "OS Detected: $OS_NAME $OS_VERSION"
else
    log "OS Check: Failed to detect OS, proceeding anyway."
fi

# Use nproc command to get the number of processing cores
CPU_CORES=$(nproc)
# Read total memory from /proc/meminfo into variables and convert to MB and GB using awk and arithmetic expansion
RAM_KB=$(grep MemTotal /proc/meminfo | awk '{print $2}')
RAM_MB=$((RAM_KB / 1024))
RAM_GB=$((RAM_MB / 1024))

log "System Resources Detected: CPU: $CPU_CORES Cores, RAM: ${RAM_GB}GB"

# ------------------------------------------------------------------------------
# 2. Automated Sizing Profile Selection
# ------------------------------------------------------------------------------
log "=> Adapting installation profile to available infrastructure..."

# Assign a suitable profile string based on CPU cores and RAM size values comparing using -ge (greater or equal)
if [ "$CPU_CORES" -ge 8 ] && [ "$RAM_GB" -ge 16 ]; then
    INSTALL_SIZE="Large (8 vCPUs, 16 GB RAM - Up to 250 nodes HA or ~1800 agents)"
elif [ "$CPU_CORES" -ge 4 ] && [ "$RAM_GB" -ge 8 ]; then
    INSTALL_SIZE="Medium (4 vCPUs, 8 GB RAM - Up to 100 nodes HA or ~900 agents)"
elif [ "$CPU_CORES" -ge 2 ] && [ "$RAM_GB" -ge 4 ]; then
    INSTALL_SIZE="Small (2 vCPUs, 4 GB RAM - Up to 10 nodes HA or ~350 agents)"
elif [ "$CPU_CORES" -ge 2 ] && [ "$RAM_GB" -ge 2 ]; then
    INSTALL_SIZE="Minimum (2 vCPUs, 2 GB RAM - Up to 10 nodes if using DB)"
else
    INSTALL_SIZE="Custom (Under minimum recommendations: $CPU_CORES Cores, ${RAM_GB}GB RAM)"
fi

log "Selected Size Profile automatically: $INSTALL_SIZE"

# ------------------------------------------------------------------------------
# 3. Server Roles Menu
# ------------------------------------------------------------------------------
echo ""
echo "Select Server Role Configuration:"
echo "--------------------------------------------------------------------"
echo "1) All-in-one Server (Control-Plane + Embedded etcd + Workloads) [Default]"
echo "2) Dedicated etcd (--disable-apiserver --disable-controller-manager --disable-scheduler)"
echo "3) Dedicated Control-Plane (--disable-etcd) [Requires pointing to existing etcd]"
# Use read -p to prompt user input and store response in role_choice variable
read -p "Enter choice (default 1): " role_choice
# If user just pressed enter (empty string), default to choice 1
[ -z "$role_choice" ] && role_choice=1

INSTALL_EXEC_FLAGS=""
# Handle user logic using a case statement for configuration string flags
case $role_choice in
    1)
        ROLE="All-in-one Server"
        # Standard server flags with standard kubeconfig rights for normal users
        INSTALL_EXEC_FLAGS="server --write-kubeconfig-mode 644"
        ;;
    2)
        ROLE="Dedicated etcd"
        # Start cluster with disabled control-plane, only leaving etcd
        INSTALL_EXEC_FLAGS="server --cluster-init --disable-apiserver --disable-controller-manager --disable-scheduler --write-kubeconfig-mode 644"
        ;;
    3)
        ROLE="Dedicated Control-Plane"
        # Since this lacks etcd, grab the token and server URL to reach it
        read -p "Enter etcd token: " cluster_token
        read -p "Enter etcd node URL (e.g., https://10.0.0.10:6443): " etcd_url
        if [ -z "$cluster_token" ] || [ -z "$etcd_url" ]; then
             log "Error: Token and URL are required for dedicated control-plane."
             exit 1
        fi
        # Append connection details to flags to join existing etcd cluster
        INSTALL_EXEC_FLAGS="server --disable-etcd --token ${cluster_token} --server ${etcd_url} --write-kubeconfig-mode 644"
        ;;
    *)
        ROLE="All-in-one Server"
        INSTALL_EXEC_FLAGS="server --write-kubeconfig-mode 644"
        ;;
esac
log "Selected Role: $ROLE"

# ------------------------------------------------------------------------------
# 4. Private Registry Configuration Menu
# ------------------------------------------------------------------------------
echo ""
echo "Configure Private Registry?"
echo "--------------------------------------------------------------------"
echo "1) No"
echo "2) Yes (will create /etc/rancher/k3s/registries.yaml template)"
read -p "Enter choice (default 1): " reg_choice
[ -z "$reg_choice" ] && reg_choice=1

REGISTRY_CONF="No"
if [ "$reg_choice" == "2" ]; then
    REGISTRY_CONF="Yes"
    # Make sure installation configuration directory exists
    mkdir -p /etc/rancher/k3s
    check_success "Created /etc/rancher/k3s directory"

    # Use a heredoc (cat <<EOF) to output multiple lines of templated yaml straight into the file
    cat <<EOF > /etc/rancher/k3s/registries.yaml
mirrors:
  "*":
    endpoint:
      - "https://registry.example.com:5000"
configs:
  "registry.example.com:5000":
    auth:
      username: myuser
      password: mypassword
    tls:
      insecure_skip_verify: true
EOF
    check_success "Created registries.yaml template"
    log "NOTE: Please manually edit /etc/rancher/k3s/registries.yaml to match your environment."
fi

# ------------------------------------------------------------------------------
# 5. Firewalld Configuration
# ------------------------------------------------------------------------------
echo ""
echo "Select Firewalld Action:"
echo "--------------------------------------------------------------------"
echo "1) Turn off firewalld (Recommended by K3s)"
echo "2) Keep firewalld enabled & open minimum required ports"
read -p "Enter choice (default 1): " fw_choice
[ -z "$fw_choice" ] && fw_choice=1

if [ "$fw_choice" == "1" ]; then
    # Completely disable the firewall service right away to ensure zero network interference
    systemctl disable firewalld --now >> "$LOG_FILE" 2>&1
    check_success "Disabled and stopped firewalld"
else
    # Register the master component communications port mapping
    firewall-cmd --permanent --add-port=6443/tcp >> "$LOG_FILE" 2>&1
    check_success "Added port 6443/tcp (apiserver) to firewall"
    
    # Enable internal UDP mapping for Flannel VXLAN backend traffic
    firewall-cmd --permanent --add-port=8472/udp >> "$LOG_FILE" 2>&1
    # Enable ingress port for gathering kubelet metrics
    firewall-cmd --permanent --add-port=10250/tcp >> "$LOG_FILE" 2>&1

    # Route default network zones for pods overlay network (trusted traffic)
    firewall-cmd --permanent --zone=trusted --add-source=10.42.0.0/16 >> "$LOG_FILE" 2>&1
    # Route default network zones for services overlay network (trusted traffic)
    firewall-cmd --permanent --zone=trusted --add-source=10.43.0.0/16 >> "$LOG_FILE" 2>&1
    
    if [ "$role_choice" == "2" ] || [ "$role_choice" == "3" ]; then
        # If separated nodes, enable inter-node DB communications network mapping for etcd
        firewall-cmd --permanent --add-port=2379-2380/tcp >> "$LOG_FILE" 2>&1
    fi

    # Trigger hot-reload of firewall maps in the kernel
    firewall-cmd --reload >> "$LOG_FILE" 2>&1
    check_success "Reloaded firewall rules"
fi

# ------------------------------------------------------------------------------
# 6. Install K3s
# ------------------------------------------------------------------------------
echo ""
log "=> Triggering K3s installation via get.k3s.io..."
log "Installation Flags: $INSTALL_EXEC_FLAGS"

# Download the script natively matching architecture and pipe straightforwardly to shell, exposing custom configurations inside INSTALL_K3S_EXEC env variable
curl -sfL https://get.k3s.io | INSTALL_K3S_EXEC="$INSTALL_EXEC_FLAGS" sh -s - >> "$LOG_FILE" 2>&1
check_success "K3s installation command executed"

# ------------------------------------------------------------------------------
# 7. Post-Installation Verification
# ------------------------------------------------------------------------------
log "=> Waiting for K3s service to initialize (20s)..."
# Pause execution ensuring background services get bootstrapped before querying endpoints
sleep 20

# Query service system manager ensuring core backend stays up
systemctl is-active --quiet k3s
check_success "K3s service is active and running"

log "=> Checking node status..."
# Explicitly force kubelet interaction via pre-generated identity yaml
export KUBECONFIG=/etc/rancher/k3s/k3s.yaml
# Evaluate base connection to print node properties and connection topology
k3s kubectl get nodes >> "$LOG_FILE" 2>&1
check_success "kubectl get nodes executed successfully"

# ------------------------------------------------------------------------------
# 8. Generate Installation Report
# ------------------------------------------------------------------------------
# Use heredoc variable expansion to form a printable textual report capturing run data
cat <<EOF > "$REPORT_FILE"
===========================================================
           K3s Installation Report
===========================================================
Date                      : $(date)
OS Information            : $OS_NAME $OS_VERSION
Hardware Resources        : $CPU_CORES Cores, ${RAM_GB}GB RAM
Selected Size Profile     : $INSTALL_SIZE
Server Role               : $ROLE
Private Registry Config/ed: $REGISTRY_CONF
Log File Location         : $LOG_FILE

Installation Status       : SUCCESS
===========================================================
To view nodes, run:
  sudo k3s kubectl get nodes

To view pods in kube-system, run:
  sudo k3s kubectl get pods -n kube-system
===========================================================
EOF

check_success "Generated installation report"

echo ""
# Display generated report on console screen
cat "$REPORT_FILE"
log "Setup completed! Have a great day."
