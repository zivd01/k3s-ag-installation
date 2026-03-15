#!/bin/bash
# ==============================================================================
# K3s Dashboard Installation Script
# ==============================================================================

if [ "$EUID" -ne 0 ]; then
  echo "Please run as root"
  exit 1
fi

echo "Installing K3s Observatory Dashboard..."

# 1. Prepare directories
mkdir -p /opt/k3s-dashboard
mkdir -p /var/www/k3s-dashboard

# 2. Copy components
echo "Copying scripts and html..."
cp k3s_dashboard_backend.sh /opt/k3s-dashboard/
chmod +x /opt/k3s-dashboard/k3s_dashboard_backend.sh

cp index.html /var/www/k3s-dashboard/

# 3. Setup services
echo "Setting up SystemD Services..."
cp k3s-dashboard-backend.service /etc/systemd/system/
cp k3s-dashboard-ui.service /etc/systemd/system/

systemctl daemon-reload
systemctl enable --now k3s-dashboard-backend.service
systemctl enable --now k3s-dashboard-ui.service

# 4. Open firewall
if systemctl is-active --quiet firewalld; then
    echo "Configuring Firewalld for port 8080..."
    firewall-cmd --permanent --add-port=8080/tcp
    firewall-cmd --reload
fi

# 5. Dependency check
if ! command -v jq &> /dev/null; then
    echo "Installing JSON Processor 'jq'..."
    dnf install -y jq
fi

echo ""
echo "====================================================="
echo " Dashboard deployed successfully!"
echo " It might take ~5 seconds for the first metrics to sync."
echo " Access URL: http://<SERVER_IP>:8080"
echo "====================================================="
