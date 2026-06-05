#!/bin/bash
# deploy/scripts/smoke-test.sh

HOST=${1:-"localhost"}
BASE_URL="https://$HOST/api/v1"

echo "Running smoke tests against $BASE_URL"

# Test 1: Health check
echo "Test 1: Health check..."
HEALTH=$(curl -s -o /dev/null -w "%{http_code}" "$BASE_URL/actuator/health")
if [ "$HEALTH" != "200" ]; then
  echo "❌ Health check failed"
  exit 1
fi
echo "✅ Health check passed"

# Test 2: SOS creation
echo "Test 2: SOS alert creation..."
SOS_RESPONSE=$(curl -s -X POST "$BASE_URL/sos" \
  -H "Content-Type: application/json" \
  -d '{"userId":"test-user","location":{"lat":40.7128,"lng":-74.0060},"type":"medical"}')
SOS_ID=$(echo $SOS_RESPONSE | jq -r '.id')

if [ "$SOS_ID" == "null" ] || [ -z "$SOS_ID" ]; then
  echo "❌ SOS creation failed"
  exit 1
fi
echo "✅ SOS created with ID: $SOS_ID"

# Test 3: Message sync
echo "Test 3: Message sync..."
SYNC=$(curl -s "$BASE_URL/messages/sync?userId=test-user&lastSync=0")
SYNC_COUNT=$(echo $SYNC | jq '.messages | length')
if [ "$SYNC_COUNT" -lt 1 ]; then
  echo "❌ Message sync failed"
  exit 1
fi
echo "✅ Synced $SYNC_COUNT messages"

# Test 4: Zone query
echo "Test 4: Zone query..."
ZONES=$(curl -s "$BASE_URL/zones/nearby?lat=40.7128&lng=-74.0060&radius=1000")
ZONE_COUNT=$(echo $ZONES | jq '. | length')
echo "✅ Found $ZONE_COUNT zones"

# Test 5: WebSocket connection
echo "Test 5: WebSocket connection..."
timeout 5 wscat -c "wss://$HOST/ws" -x '{"type":"ping"}' || {
  echo "❌ WebSocket connection failed"
  exit 1
}
echo "✅ WebSocket connected"

echo "✅✅✅ All smoke tests passed! ✅✅✅"
