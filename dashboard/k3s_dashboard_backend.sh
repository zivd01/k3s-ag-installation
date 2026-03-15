#!/bin/bash
# Gather data from k3s and write to JSON for the dashboard
export KUBECONFIG=/etc/rancher/k3s/k3s.yaml
OUT_DIR="/var/www/k3s-dashboard"
mkdir -p "$OUT_DIR"

echo "Starting K3s stats collection..."

while true; do
  # Fetch data in JSON format directly from kubernetes API
  NODES=$(k3s kubectl get nodes -o json 2>/dev/null || echo '{"items":[]}')
  PODS=$(k3s kubectl get pods -A -o json 2>/dev/null || echo '{"items":[]}')
  EVENTS=$(k3s kubectl get events -A --sort-by='.metadata.creationTimestamp' -o json 2>/dev/null | jq '{items: [.items[-20:]]}' 2>/dev/null || echo '{"items":[]}')
  
  # Inject them into a temporary file to avoid partial reads on the frontend
  cat <<EOF > "$OUT_DIR/data.temp.json"
{
  "timestamp": "$(date -Iseconds)",
  "nodes": $NODES,
  "pods": $PODS,
  "events": $EVENTS
}
EOF

  # Move temp to actual atomically
  mv "$OUT_DIR/data.temp.json" "$OUT_DIR/data.json"
  
  # Poll every 3 seconds
  sleep 3
done
