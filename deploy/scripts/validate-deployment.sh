#!/bin/bash
# deploy/scripts/validate-deployment.sh

NAMESPACE="danger-emergence"
CHECK_INTERVAL=5
MAX_RETRIES=12  # 60 seconds total

echo "Validating production deployment..."

# Check pod status
for i in $(seq 1 $MAX_RETRIES); do
  NOT_READY=$(kubectl -n $NAMESPACE get pods -l app=backend -o json | jq '[.items[] | select(.status.phase != "Running")] | length')
  if [ "$NOT_READY" -eq 0 ]; then
    echo "✅ All pods are running"
    break
  fi
  echo "Waiting for pods to be ready... ($NOT_READY not ready)"
  sleep $CHECK_INTERVAL
done

# Check error rate from Prometheus
ERROR_RATE=$(kubectl -n $NAMESPACE exec deployment/prometheus -- \
  wget -qO- 'http://localhost:9090/api/v1/query?query=sum(rate(http_server_requests_seconds_count{status=~"5.."}[5m]))' | \
  jq -r '.data.result[0].value[1] // 0')

if (( $(echo "$ERROR_RATE > 0.05" | bc -l) )); then
  echo "❌ Error rate too high: $ERROR_RATE"
  exit 1
fi
echo "✅ Error rate OK: $ERROR_RATE"

# Check p99 latency
P99_LATENCY=$(kubectl -n $NAMESPACE exec deployment/prometheus -- \
  wget -qO- 'http://localhost:9090/api/v1/query?query=histogram_quantile(0.99, sum(rate(http_server_requests_seconds_bucket[5m])) by (le))' | \
  jq -r '.data.result[0].value[1] // 0')

if (( $(echo "$P99_LATENCY > 1.0" | bc -l) )); then
  echo "⚠️ P99 latency high: ${P99_LATENCY}s"
else
  echo "✅ P99 latency OK: ${P99_LATENCY}s"
fi

# Check database connectivity
kubectl -n $NAMESPACE exec deployment/backend -- \
  curl -s http://localhost:8080/actuator/health/db | grep -q '"status":"UP"'
if [ $? -eq 0 ]; then
  echo "✅ Database connected"
else
  echo "❌ Database connection failed"
  exit 1
fi

echo "✅✅✅ Deployment validation passed! ✅✅✅"
