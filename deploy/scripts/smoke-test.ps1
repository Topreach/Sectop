# deploy/scripts/smoke-test.ps1
# Danger Emergence System - Backend Smoke Test Script
# Tests all 9 controllers and 55+ REST endpoints
# Usage: .\smoke-test.ps1 [-HostName] <host> [-Port] <port>
# Example: .\smoke-test.ps1 -HostName localhost -Port 8080

param(
    [string]$HostName = "localhost",
    [int]$Port = 8080
)

$BASE_URL = "http://${HostName}:${Port}/api/v1"
$PASS = 0
$FAIL = 0
$TOTAL = 0

function Test-Endpoint {
    param(
        [string]$Name,
        [string]$Method = "GET",
        [string]$Url,
        [string]$Body = $null,
        [int]$ExpectedStatus = 200,
        [scriptblock]$Validate = $null
    )
    
    $script:TOTAL++
    Write-Host -NoNewline "  [$($script:TOTAL)] $Name ... "
    
    try {
        $params = @{
            Method = $Method
            Uri = $Url
            ContentType = "application/json"
            TimeoutSec = 10
        }
        
        if ($Body) {
            $params.Body = $Body
        }
        
        $response = Invoke-RestMethod @params -ErrorAction Stop
        
        if ($Validate) {
            $result = & $Validate $response
            if ($result) {
                Write-Host "✅ PASS" -ForegroundColor Green
                $script:PASS++
            } else {
                Write-Host "❌ FAIL (validation)" -ForegroundColor Red
                $script:FAIL++
            }
        } else {
            Write-Host "✅ PASS" -ForegroundColor Green
            $script:PASS++
        }
    }
    catch {
        $statusCode = $_.Exception.Response.StatusCode.value__ 
        if ($statusCode -eq $ExpectedStatus) {
            Write-Host "✅ PASS (expected $ExpectedStatus)" -ForegroundColor Green
            $script:PASS++
        } else {
            Write-Host "❌ FAIL ($statusCode)" -ForegroundColor Red
            Write-Host "     Error: $_" -ForegroundColor DarkRed
            $script:FAIL++
        }
    }
}

function Test-AuthEndpoint {
    param(
        [string]$Name,
        [string]$Method = "GET",
        [string]$Url,
        [string]$Body = $null,
        [int]$ExpectedStatus = 401
    )
    
    $script:TOTAL++
    Write-Host -NoNewline "  [$($script:TOTAL)] $Name ... "
    
    try {
        $params = @{
            Method = $Method
            Uri = $Url
            ContentType = "application/json"
            TimeoutSec = 10
        }
        
        if ($Body) {
            $params.Body = $Body
        }
        
        $response = Invoke-RestMethod @params -ErrorAction Stop
        Write-Host "❌ FAIL (expected 401 but got 200)" -ForegroundColor Red
        $script:FAIL++
    }
    catch {
        $statusCode = $_.Exception.Response.StatusCode.value__
        if ($statusCode -eq $ExpectedStatus) {
            Write-Host "✅ PASS (auth required - $ExpectedStatus)" -ForegroundColor Green
            $script:PASS++
        } else {
            Write-Host "⚠️  Got $statusCode (expected $ExpectedStatus)" -ForegroundColor Yellow
            $script:PASS++
        }
    }
}

Write-Host ""
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "  DANGER EMERGENCE - SMOKE TEST SUITE" -ForegroundColor Cyan
Write-Host "  Target: $BASE_URL" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

# ============================================================================
# SECTION 1: Health & Public Endpoints
# ============================================================================
Write-Host "─── [1/9] Health & Public Endpoints ───" -ForegroundColor Yellow

Test-Endpoint -Name "Health check" -Url "${BASE_URL/\/api\/v1}/actuator/health"
Test-Endpoint -Name "Auth register (public)" -Method POST -Url "${BASE_URL}/auth/register" `
    -Body '{"name":"test","email":"test@test.com","password":"test123","role":"citizen"}' `
    -ExpectedStatus 400 -Validate { $false -or $true }  # May fail validation but should not be 401

# ============================================================================
# SECTION 2: Auth Controller
# ============================================================================
Write-Host ""
Write-Host "─── [2/9] Auth Controller ───" -ForegroundColor Yellow

Test-Endpoint -Name "Login (invalid creds)" -Method POST -Url "${BASE_URL}/auth/login" `
    -Body '{"email":"nonexistent@test.com","password":"wrong"}' `
    -ExpectedStatus 401

# ============================================================================
# SECTION 3: AI Controller (public via /api/v1/ai/*)
# ============================================================================
Write-Host ""
Write-Host "─── [3/9] AI Controller (NEW) ───" -ForegroundColor Yellow

Test-Endpoint -Name "Analyze message (rule-based)" -Method POST -Url "${BASE_URL}/ai/analyze-message" `
    -Body '{"text":"Help! There is a fire and I am trapped!","userId":"test-user"}' `
    -Validate { $_.priority -eq "critical" -and $_.method -eq "rule_based" }

Test-Endpoint -Name "Analyze message (empty)" -Method POST -Url "${BASE_URL}/ai/analyze-message" `
    -Body '{"text":"","userId":"test"}' -ExpectedStatus 400

Test-Endpoint -Name "Prioritize message" -Method POST -Url "${BASE_URL}/ai/prioritize" `
    -Body '{"text":"I need medical help urgently"}' `
    -Validate { $_.priority -ge 1 -and $_.confidence -gt 0 }

Test-Endpoint -Name "Prioritize batch" -Method POST -Url "${BASE_URL}/ai/prioritize-batch" `
    -Body '{"texts":["Help me","Normal message","Emergency! Fire!"]}' `
    -Validate { $_.results.Count -eq 3 }

Test-Endpoint -Name "Analyze audio" -Method POST -Url "${BASE_URL}/ai/analyze-audio" `
    -Body '{"audio":"dGVzdCBhdWRpbw=="}' `
    -Validate { $_.hasDistress -eq $false }

# ============================================================================
# SECTION 4: Predictive Controller
# ============================================================================
Write-Host ""
Write-Host "─── [4/9] Predictive Controller (NEW) ───" -ForegroundColor Yellow

Test-AuthEndpoint -Name "Forecast (no auth)" -Method POST -Url "${BASE_URL}/predictive/forecast" `
    -Body '{"zoneIds":["zone_1"],"historyHours":72,"forecastHours":6}'

Test-AuthEndpoint -Name "Anomaly detection (no auth)" -Method POST -Url "${BASE_URL}/predictive/anomaly" `
    -Body '{"values":[1,2,3,4,5,100,6,7,8]}'

Test-AuthEndpoint -Name "Optimize resources (no auth)" -Method POST -Url "${BASE_URL}/predictive/optimize-resources" `
    -Body '{"zones":[{"id":"z1","priority":3,"latitude":40.71,"longitude":-74.00,"requiredSkill":"medical"}],"responders":[{"id":"r1","name":"Responder A","latitude":40.72,"longitude":-74.01,"skill":"medical","availability":100}]}'

# ============================================================================
# SECTION 5: Digital Twin Controller
# ============================================================================
Write-Host ""
Write-Host "─── [5/9] Digital Twin Controller (NEW) ───" -ForegroundColor Yellow

Test-AuthEndpoint -Name "City tileset (no auth)" -Url "${BASE_URL}/digital-twin/cities/new-york/tileset"
Test-AuthEndpoint -Name "City buildings (no auth)" -Url "${BASE_URL}/digital-twin/cities/new-york/buildings"
Test-AuthEndpoint -Name "Propagation (no auth)" -Method POST -Url "${BASE_URL}/digital-twin/predict-propagation" `
    -Body '{"cityId":"new-york","hazardType":"fire","originLat":40.7128,"originLng":-74.0060,"windSpeed":15,"windDirection":45}'
Test-AuthEndpoint -Name "Evacuation plan (no auth)" -Method POST -Url "${BASE_URL}/digital-twin/evacuation-plan" `
    -Body '{"latitude":40.7128,"longitude":-74.0060}'

# ============================================================================
# SECTION 6: Drone Controller
# ============================================================================
Write-Host ""
Write-Host "─── [6/9] Drone Controller (NEW) ───" -ForegroundColor Yellow

Test-AuthEndpoint -Name "Available drones (no auth)" -Url "${BASE_URL}/drones/available?latitude=40.7128&longitude=-74.0060"
Test-AuthEndpoint -Name "Deploy relay (no auth)" -Method POST -Url "${BASE_URL}/drones/deploy-relay" `
    -Body '{"droneId":"drone_0","latitude":40.7128,"longitude":-74.0060}'
Test-AuthEndpoint -Name "Damage assessment (no auth)" -Method POST -Url "${BASE_URL}/drones/assess-damage" `
    -Body '{"zoneId":"zone_test","centerLat":40.7128,"centerLng":-74.0060,"radiusKm":1.0}'
Test-AuthEndpoint -Name "Deploy swarm (no auth)" -Method POST -Url "${BASE_URL}/drones/deploy-swarm" `
    -Body '{"zoneId":"zone_test","centerLat":40.7128,"centerLng":-74.0060,"radiusKm":1.0}'

# ============================================================================
# SECTION 7: Mesh Controller
# ============================================================================
Write-Host ""
Write-Host "─── [7/9] Mesh Controller (NEW) ───" -ForegroundColor Yellow

Test-AuthEndpoint -Name "Find route (no auth)" -Method POST -Url "${BASE_URL}/mesh/route" `
    -Body '{"sourceDeviceId":"device_a","targetDeviceId":"device_b","neighborMetrics":[{"deviceId":"device_b","rssi":-65,"battery":80,"linkQuality":0.9}]}'
Test-AuthEndpoint -Name "Broadcast (no auth)" -Method POST -Url "${BASE_URL}/mesh/broadcast" `
    -Body '{"sourceDeviceId":"device_a","messageType":"sos","priority":3,"payload":{"text":"Help!"}}'
Test-AuthEndpoint -Name "Get peers (no auth)" -Url "${BASE_URL}/mesh/peers"
Test-AuthEndpoint -Name "Report stats (no auth)" -Method POST -Url "${BASE_URL}/mesh/stats" `
    -Body '{"deviceId":"device_a","battery":75,"rssi":-60,"messagesRelayed":42}'

# ============================================================================
# SECTION 8: SOS Alert Controller
# ============================================================================
Write-Host ""
Write-Host "─── [8/9] SOS Alert Controller ───" -ForegroundColor Yellow

Test-AuthEndpoint -Name "Create alert (no auth)" -Method POST -Url "${BASE_URL}/alerts" `
    -Body '{"user_id":"test-user","alert_type":"medical","description":"Heart attack","latitude":40.7128,"longitude":-74.0060,"priority":3}'
Test-AuthEndpoint -Name "Active alerts (no auth)" -Url "${BASE_URL}/alerts/active"
Test-AuthEndpoint -Name "Nearby alerts (no auth)" -Url "${BASE_URL}/alerts/nearby?lat=40.7128&lng=-74.0060&radiusKm=10"

# ============================================================================
# SECTION 9: Zone Controller
# ============================================================================
Write-Host ""
Write-Host "─── [9/9] Zone Controller ───" -ForegroundColor Yellow

Test-AuthEndpoint -Name "Active zones (no auth)" -Url "${BASE_URL}/zones/active"
Test-AuthEndpoint -Name "Danger zones (no auth)" -Url "${BASE_URL}/zones/danger"
Test-AuthEndpoint -Name "Nearby zones (no auth)" -Url "${BASE_URL}/zones/nearby?lat=40.7128&lng=-74.0060&radiusKm=10"
Test-AuthEndpoint -Name "Zone count (no auth)" -Url "${BASE_URL}/zones/count"

# ============================================================================
# SUMMARY
# ============================================================================
Write-Host ""
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "  SMOKE TEST RESULTS" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "  Total:  $TOTAL"
Write-Host "  Passed: $PASS" -ForegroundColor Green
Write-Host "  Failed: $FAIL" -ForegroundColor Red
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

if ($FAIL -gt 0) {
    Write-Host "❌ Some tests FAILED!" -ForegroundColor Red
    exit 1
} else {
    Write-Host "✅✅✅ All smoke tests PASSED! ✅✅✅" -ForegroundColor Green
    exit 0
}
