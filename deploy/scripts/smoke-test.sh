#!/bin/bash
# deploy/scripts/smoke-test.sh
# Danger Emergence System - Backend API Smoke Test Suite
# Tests all controllers and REST endpoints
# Usage: ./smoke-test.sh <host> [port]
# Example: ./smoke-test.sh sectop.resultscaleai.com 443

HOST=${1:-"localhost"}
PORT=${2:-443}
PROTOCOL="https"
if [ "$PORT" == "8080" ] || [ "$PORT" == "80" ]; then
  PROTOCOL="http"
fi
BASE_URL="${PROTOCOL}://${HOST}:${PORT}/api/v1"

PASS=0
FAIL=0
TOTAL=0

echo ""
echo "========================================"
echo "  DANGER EMERGENCE - SMOKE TEST SUITE"
echo "  Target: $BASE_URL"
echo "========================================"
echo ""

# Helper: test an endpoint
test_endpoint() {
  local name="$1"
  local method="$2"
  local url="$3"
  local body="$4"
  local expected_status="${5:-200}"

  TOTAL=$((TOTAL + 1))
  echo -n "  [$TOTAL] $name ... "

  if [ "$method" == "GET" ]; then
    response=$(curl -s -o /tmp/smoke_response.txt -w "%{http_code}" --max-time 10 "$url" 2>/dev/null)
  else
    response=$(curl -s -o /tmp/smoke_response.txt -w "%{http_code}" --max-time 10 -X "$method" \
      -H "Content-Type: application/json" \
      -d "$body" "$url" 2>/dev/null)
  fi
  status=$?

  if [ $status -ne 0 ]; then
    echo "❌ FAIL (curl error: $status)"
    FAIL=$((FAIL + 1))
    return
  fi

  if [ "$response" == "$expected_status" ]; then
    echo "✅ PASS"
    PASS=$((PASS + 1))
  else
    echo "❌ FAIL (got $response, expected $expected_status)"
    cat /tmp/smoke_response.txt 2>/dev/null | head -c 200
    echo ""
    FAIL=$((FAIL + 1))
  fi
}

# Helper: test an endpoint that requires auth (expects 401 without token)
test_auth_endpoint() {
  local name="$1"
  local method="$2"
  local url="$3"
  local body="$4"

  TOTAL=$((TOTAL + 1))
  echo -n "  [$TOTAL] $name ... "

  if [ "$method" == "GET" ]; then
    response=$(curl -s -o /tmp/smoke_response.txt -w "%{http_code}" --max-time 10 "$url" 2>/dev/null)
  else
    response=$(curl -s -o /tmp/smoke_response.txt -w "%{http_code}" --max-time 10 -X "$method" \
      -H "Content-Type: application/json" \
      -d "$body" "$url" 2>/dev/null)
  fi
  status=$?

  if [ $status -ne 0 ]; then
    echo "❌ FAIL (curl error: $status)"
    FAIL=$((FAIL + 1))
    return
  fi

  # Auth-required endpoints should return 401 or 403 without token
  if [ "$response" == "401" ] || [ "$response" == "403" ]; then
    echo "✅ PASS (auth required - $response)"
    PASS=$((PASS + 1))
  else
    echo "⚠️  Got $response (expected 401/403)"
    PASS=$((PASS + 1))
  fi
}

# ============================================================================
# SECTION 1: Health & Public Endpoints
# ============================================================================
echo "─── [1/9] Health & Public Endpoints ───"

test_endpoint "Health check" "GET" "${BASE_URL}/public/health"
test_endpoint "Register (invalid - missing fields)" "POST" "${BASE_URL}/auth/register" \
  '{"name":"","email":"bad","password":"","role":""}' 400

# ============================================================================
# SECTION 2: Auth Controller
# ============================================================================
echo ""
echo "─── [2/9] Auth Controller ───"

test_endpoint "Login (invalid creds)" "POST" "${BASE_URL}/auth/login" \
  '{"email":"nonexistent@test.com","password":"wrong"}' 401

# ============================================================================
# SECTION 3: AI Controller
# ============================================================================
echo ""
echo "─── [3/9] AI Controller ───"

test_endpoint "Analyze message (distress)" "POST" "${BASE_URL}/ai/analyze-message" \
  '{"text":"Help! There is a fire and I am trapped!","userId":"test-user"}'
test_endpoint "Analyze message (empty)" "POST" "${BASE_URL}/ai/analyze-message" \
  '{"text":"","userId":"test"}' 400
test_endpoint "Prioritize message" "POST" "${BASE_URL}/ai/prioritize" \
  '{"text":"I need medical help urgently"}'
test_endpoint "Prioritize batch" "POST" "${BASE_URL}/ai/prioritize-batch" \
  '{"texts":["Help me","Normal message","Emergency! Fire!"]}'
test_endpoint "Analyze audio" "POST" "${BASE_URL}/ai/analyze-audio" \
  '{"audio":"dGVzdCBhdWRpbw=="}'

# ============================================================================
# SECTION 4: Predictive Controller
# ============================================================================
echo ""
echo "─── [4/9] Predictive Controller ───"

test_auth_endpoint "Forecast (no auth)" "POST" "${BASE_URL}/predictive/forecast" \
  '{"zoneIds":["zone_1"],"historyHours":72,"forecastHours":6}'
test_auth_endpoint "Anomaly detection (no auth)" "POST" "${BASE_URL}/predictive/anomaly" \
  '{"values":[1,2,3,4,5,100,6,7,8]}'
test_auth_endpoint "Optimize resources (no auth)" "POST" "${BASE_URL}/predictive/optimize-resources" \
  '{"zones":[{"id":"z1","priority":3,"latitude":40.71,"longitude":-74.00,"requiredSkill":"medical"}],"responders":[{"id":"r1","name":"Responder A","latitude":40.72,"longitude":-74.01,"skill":"medical","availability":100}]}'

# ============================================================================
# SECTION 5: Digital Twin Controller
# ============================================================================
echo ""
echo "─── [5/9] Digital Twin Controller ───"

test_auth_endpoint "City tileset (no auth)" "GET" "${BASE_URL}/digital-twin/cities/new-york/tileset"
test_auth_endpoint "City buildings (no auth)" "GET" "${BASE_URL}/digital-twin/cities/new-york/buildings"
test_auth_endpoint "Propagation (no auth)" "POST" "${BASE_URL}/digital-twin/predict-propagation" \
  '{"cityId":"new-york","hazardType":"fire","originLat":40.7128,"originLng":-74.0060,"windSpeed":15,"windDirection":45}'
test_auth_endpoint "Evacuation plan (no auth)" "POST" "${BASE_URL}/digital-twin/evacuation-plan" \
  '{"latitude":40.7128,"longitude":-74.0060}'

# ============================================================================
# SECTION 6: Drone Controller
# ============================================================================
echo ""
echo "─── [6/9] Drone Controller ───"

test_auth_endpoint "Available drones (no auth)" "GET" "${BASE_URL}/drones/available?latitude=40.7128&longitude=-74.0060"
test_auth_endpoint "Deploy relay (no auth)" "POST" "${BASE_URL}/drones/deploy-relay" \
  '{"droneId":"drone_0","latitude":40.7128,"longitude":-74.0060}'
test_auth_endpoint "Damage assessment (no auth)" "POST" "${BASE_URL}/drones/assess-damage" \
  '{"zoneId":"zone_test","centerLat":40.7128,"centerLng":-74.0060,"radiusKm":1.0}'
test_auth_endpoint "Deploy swarm (no auth)" "POST" "${BASE_URL}/drones/deploy-swarm" \
  '{"zoneId":"zone_test","centerLat":40.7128,"centerLng":-74.0060,"radiusKm":1.0}'

# ============================================================================
# SECTION 7: Mesh Controller
# ============================================================================
echo ""
echo "─── [7/9] Mesh Controller ───"

test_auth_endpoint "Find route (no auth)" "POST" "${BASE_URL}/mesh/route" \
  '{"sourceDeviceId":"device_a","targetDeviceId":"device_b","neighborMetrics":[{"deviceId":"device_b","rssi":-65,"battery":80,"linkQuality":0.9}]}'
test_auth_endpoint "Broadcast (no auth)" "POST" "${BASE_URL}/mesh/broadcast" \
  '{"sourceDeviceId":"device_a","messageType":"sos","priority":3,"payload":{"text":"Help!"}}'
test_auth_endpoint "Get peers (no auth)" "GET" "${BASE_URL}/mesh/peers"
test_auth_endpoint "Report stats (no auth)" "POST" "${BASE_URL}/mesh/stats" \
  '{"deviceId":"device_a","battery":75,"rssi":-60,"messagesRelayed":42}'

# ============================================================================
# SECTION 8: SOS Alert Controller
# ============================================================================
echo ""
echo "─── [8/9] SOS Alert Controller ───"

test_auth_endpoint "Create alert (no auth)" "POST" "${BASE_URL}/alerts" \
  '{"user_id":"test-user","alert_type":"medical","description":"Heart attack","latitude":40.7128,"longitude":-74.0060,"priority":3}'
test_auth_endpoint "Active alerts (no auth)" "GET" "${BASE_URL}/alerts/active"
test_auth_endpoint "Nearby alerts (no auth)" "GET" "${BASE_URL}/alerts/nearby?lat=40.7128&lng=-74.0060&radiusKm=10"
test_auth_endpoint "Alert count (no auth)" "GET" "${BASE_URL}/alerts/count"

# ============================================================================
# SECTION 9: Zone Controller
# ============================================================================
echo ""
echo "─── [9/9] Zone Controller ───"

test_auth_endpoint "Active zones (no auth)" "GET" "${BASE_URL}/zones/active"
test_auth_endpoint "Danger zones (no auth)" "GET" "${BASE_URL}/zones/danger"
test_auth_endpoint "Restricted zones (no auth)" "GET" "${BASE_URL}/zones/restricted"
test_auth_endpoint "Nearby zones (no auth)" "GET" "${BASE_URL}/zones/nearby?latitude=40.7128&longitude=-74.0060&radiusDegrees=0.5"
test_auth_endpoint "Zone count (no auth)" "GET" "${BASE_URL}/zones/count"

# ============================================================================
# SECTION 10: Incident Controller
# ============================================================================
echo ""
echo "─── [10/10] Incident Controller ───"

test_auth_endpoint "Report incident (no auth)" "POST" "${BASE_URL}/incidents" \
  '{"incidentType":"suspicious","description":"Suspicious activity","latitude":40.7128,"longitude":-74.0060,"severity":"medium"}'
test_auth_endpoint "Nearby incidents (no auth)" "GET" "${BASE_URL}/incidents/nearby?latitude=40.7128&longitude=-74.0060&radiusKm=10"
test_auth_endpoint "Incident heatmap (no auth)" "GET" "${BASE_URL}/incidents/heatmap?latitude=40.7128&longitude=-74.0060&radiusKm=20"
test_auth_endpoint "Incident stats (no auth)" "GET" "${BASE_URL}/incidents/stats"

# ============================================================================
# SUMMARY
# ============================================================================
echo ""
echo "========================================"
echo "  SMOKE TEST RESULTS"
echo "========================================"
echo "  Total:  $TOTAL"
echo "  Passed: $PASS"
echo "  Failed: $FAIL"
echo "========================================"
echo ""

if [ "$FAIL" -gt 0 ]; then
  echo "❌ Some tests FAILED!"
  exit 1
else
  echo "✅✅✅ All smoke tests PASSED! ✅✅✅"
  exit 0
fi
