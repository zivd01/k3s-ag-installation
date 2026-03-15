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
  METRICS=$(k3s kubectl get --raw /apis/metrics.k8s.io/v1beta1/pods 2>/dev/null || echo '{"items":[]}')
  
  TS=$(date -Iseconds)
  
  # Inject them into a temporary file to avoid partial reads on the frontend
  cat <<EOF > "$OUT_DIR/data.temp.json"
{
  "timestamp": "$TS",
  "nodes": $NODES,
  "pods": $PODS,
  "events": $EVENTS,
  "metrics": $METRICS
}
EOF

  # Move temp to actual atomically
  mv "$OUT_DIR/data.temp.json" "$OUT_DIR/data.json"
  
  # Track history for graphing (store timestamp and just the metrics)
  # Limit history to 1200 lines (~100 mins at 5 sec intervals)
  echo "{\"timestamp\":\"$TS\",\"metrics\":$METRICS}" >> "$OUT_DIR/history.jsonl"
  tail -n 1200 "$OUT_DIR/history.jsonl" > "$OUT_DIR/history.tmp" && mv "$OUT_DIR/history.tmp" "$OUT_DIR/history.jsonl"
  
  # Poll every 5 seconds
  sleep 5
done
