#!/bin/bash
# =============================================================================
# Danger Emergence System — Server Deployment Script
# =============================================================================
# Run this script ON THE SERVER (root@vmi3167366) to:
#   1. Fix docker-compose.yml to use named volumes (no bind mounts)
#   2. Initialize config volumes with docker cp
#   3. Build and start all containers
#   4. Verify all services are healthy
#
# Usage:
#   chmod +x deploy/scripts/deploy-server.sh
#   ./deploy/scripts/deploy-server.sh
# =============================================================================

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"

echo "============================================================"
echo "  Danger Emergence System — Server Deployment"
echo "  Project: $PROJECT_DIR"
echo "============================================================"
echo ""

# ── Step 1: Check docker-compose.yml for bind mounts ────────────
echo "[1/7] Checking docker-compose.yml for bind mounts..."

if grep -q "\.\/deploy\/" "$PROJECT_DIR/docker-compose.yml" 2>/dev/null; then
    echo "  ⚠️  Bind mounts detected! The local docker-compose.yml needs updating."
    echo "  The server's /var/www filesystem is read-only for Docker bind mounts."
    echo "  We'll replace bind mounts with named volumes + docker cp."
    
    # Backup original
    cp "$PROJECT_DIR/docker-compose.yml" "$PROJECT_DIR/docker-compose.yml.backup"
    echo "  ✅ Backup created: docker-compose.yml.backup"
else
    echo "  ✅ No bind mounts found — docker-compose.yml is already using named volumes."
fi

# ── Step 2: Fix YAML syntax if broken ───────────────────────────
echo ""
echo "[2/7] Validating docker-compose.yml syntax..."

if docker-compose -f "$PROJECT_DIR/docker-compose.yml" config > /dev/null 2>&1; then
    echo "  ✅ docker-compose.yml syntax is valid."
else
    echo "  ⚠️  YAML syntax error detected. Attempting to fix..."
    
    # Check if the file has the named volumes version (our local version)
    if grep -q "mosquitto_config:" "$PROJECT_DIR/docker-compose.yml" 2>/dev/null && \
       grep -q "nginx_config:" "$PROJECT_DIR/docker-compose.yml" 2>/dev/null; then
        echo "  ✅ File already has named volumes. Checking for hidden characters..."
        # Remove any Windows-style line endings or hidden chars
        sed -i 's/\r$//' "$PROJECT_DIR/docker-compose.yml"
        echo "  ✅ Fixed line endings."
    else
        echo "  ❌ File needs manual fix. Writing corrected version..."
        # The file will be written in Step 3
    fi
fi

# ── Step 3: Write corrected docker-compose.yml ──────────────────
echo ""
echo "[3/7] Writing corrected docker-compose.yml (named volumes only)..."

cat > "$PROJECT_DIR/docker-compose.yml" << 'DOCKERCOMPOSE'
services:
  # PostgreSQL Database
  postgres:
    image: postgres:16-alpine
    container_name: danger-emergence-db
    environment:
      POSTGRES_DB: danger_emergence
      POSTGRES_USER: postgres
      POSTGRES_PASSWORD: ${DB_PASSWORD:-postgres}
    ports:
      - "5432:5432"
    volumes:
      - postgres_data:/var/lib/postgresql/data
    networks:
      - danger-emergence-network
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U postgres"]
      interval: 10s
      timeout: 5s
      retries: 5
    restart: unless-stopped

  # Redis Cache
  redis:
    image: redis:7-alpine
    container_name: danger-emergence-redis
    ports:
      - "6379:6379"
    volumes:
      - redis_data:/data
    networks:
      - danger-emergence-network
    healthcheck:
      test: ["CMD", "redis-cli", "ping"]
      interval: 10s
      timeout: 5s
      retries: 5
    restart: unless-stopped

  # MQTT Broker for IoT/Mesh communication
  mosquitto:
    image: eclipse-mosquitto:2
    container_name: danger-emergence-mqtt
    ports:
      - "1883:1883"
      - "8883:8883"
    volumes:
      - mosquitto_data:/mosquitto/data
      - mosquitto_log:/mosquitto/log
      - mosquitto_config:/mosquitto/config
    networks:
      - danger-emergence-network
    restart: unless-stopped

  # Spring Boot Backend
  backend:
    build:
      context: ./backend
      dockerfile: Dockerfile
    container_name: danger-emergence-backend
    environment:
      DB_USERNAME: postgres
      DB_PASSWORD: ${DB_PASSWORD:-postgres}
      REDIS_HOST: redis
      REDIS_PORT: 6379
      ML_SERVICE_URL: http://ml-service:8000
      MQTT_BROKER: tcp://mosquitto:1883
      SPRING_PROFILES_ACTIVE: ${SPRING_PROFILES_ACTIVE:-prod}
    ports:
      - "8080:8080"
    depends_on:
      postgres:
        condition: service_healthy
      redis:
        condition: service_healthy
      ml-service:
        condition: service_started
    networks:
      - danger-emergence-network
    restart: unless-stopped

  # FastAPI ML Service
  ml-service:
    build:
      context: ./ml_service
      dockerfile: Dockerfile
    container_name: danger-emergence-ml
    environment:
      MODEL_NAME: ${MODEL_NAME:-facebook/bart-large-mnli}
      REDIS_HOST: redis
      REDIS_PORT: 6379
    ports:
      - "8000:8000"
    depends_on:
      redis:
        condition: service_healthy
    networks:
      - danger-emergence-network
    restart: unless-stopped

  # Nginx Reverse Proxy
  nginx:
    image: nginx:alpine
    container_name: danger-emergence-nginx
    ports:
      - "8081:80"
    volumes:
      - nginx_config:/etc/nginx
      - nginx_html:/usr/share/nginx/html
    depends_on:
      - backend
      - ml-service
    networks:
      - danger-emergence-network
    restart: unless-stopped

networks:
  danger-emergence-network:
    driver: bridge

volumes:
  postgres_data:
  redis_data:
  mosquitto_data:
  mosquitto_log:
  mosquitto_config:
  nginx_config:
  nginx_html:
DOCKERCOMPOSE

echo "  ✅ docker-compose.yml written successfully."

# ── Step 4: Stop all containers and remove old config volumes ────
echo ""
echo "[4/7] Stopping containers and cleaning up old volumes..."

# Stop everything (ignore errors if already stopped)
docker-compose -f "$PROJECT_DIR/docker-compose.yml" down 2>/dev/null || true

# Remove old config volumes so we can seed them fresh
docker volume rm sectop_mosquitto_config sectop_nginx_config sectop_nginx_html 2>/dev/null || true
echo "  ✅ Old config volumes removed."

# ── Step 5: Initialize config volumes with docker cp ────────────
echo ""
echo "[5/7] Seeding config volumes with docker cp..."

# --- Mosquitto Config ---
echo "  → Seeding mosquitto_config volume..."
docker container create --name temp_mqtt -v mosquitto_config:/mosquitto/config alpine:3.18 2>/dev/null

# Copy mosquitto.conf
if [ -f "$PROJECT_DIR/deploy/mosquitto/mosquitto.conf" ]; then
    docker cp "$PROJECT_DIR/deploy/mosquitto/mosquitto.conf" temp_mqtt:/mosquitto/config/
    echo "    ✅ mosquitto.conf copied"
else
    echo "    ⚠️  mosquitto.conf not found at $PROJECT_DIR/deploy/mosquitto/mosquitto.conf"
fi

# Copy ACL file
if [ -f "$PROJECT_DIR/deploy/mosquitto/acl" ]; then
    docker cp "$PROJECT_DIR/deploy/mosquitto/acl" temp_mqtt:/mosquitto/config/
    echo "    ✅ acl copied"
else
    echo "    ⚠️  acl file not found"
fi

docker rm temp_mqtt > /dev/null
echo "  ✅ mosquitto_config volume seeded."

# --- Nginx Config ---
echo "  → Seeding nginx_config volume..."
docker container create --name temp_nginx -v nginx_config:/etc/nginx alpine:3.18 2>/dev/null

# Copy nginx.conf
if [ -f "$PROJECT_DIR/deploy/nginx/nginx.conf" ]; then
    docker cp "$PROJECT_DIR/deploy/nginx/nginx.conf" temp_nginx:/etc/nginx/
    echo "    ✅ nginx.conf copied"
else
    echo "    ⚠️  nginx.conf not found"
fi

# Copy SSL directory if it exists
if [ -d "$PROJECT_DIR/deploy/nginx/ssl" ]; then
    docker cp "$PROJECT_DIR/deploy/nginx/ssl" temp_nginx:/etc/nginx/
    echo "    ✅ SSL certs copied"
fi

docker rm temp_nginx > /dev/null
echo "  ✅ nginx_config volume seeded."

# --- Nginx HTML (basic index.html) ---
echo "  → Seeding nginx_html volume..."
docker container create --name temp_html -v nginx_html:/usr/share/nginx/html alpine:3.18 2>/dev/null

# Create a basic index.html placeholder
cat > /tmp/index.html << 'HTML'
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Danger Emergence System</title>
    <style>
        body { font-family: Arial, sans-serif; margin: 0; padding: 40px; background: #1a1a2e; color: #eee; }
        h1 { color: #e94560; }
        .status { background: #16213e; padding: 20px; border-radius: 8px; margin-top: 20px; }
        .online { color: #4ecca3; }
    </style>
</head>
<body>
    <h1>🚨 Danger Emergence System</h1>
    <div class="status">
        <p>Status: <span class="online">✅ Online</span></p>
        <p>API: <a href="/api/">/api/</a></p>
        <p>Health: <a href="/health">/health</a></p>
    </div>
</body>
</html>
HTML

docker cp /tmp/index.html temp_html:/usr/share/nginx/html/
rm /tmp/index.html
echo "    ✅ index.html copied"

docker rm temp_html > /dev/null
echo "  ✅ nginx_html volume seeded."

# ── Step 6: Build and start all containers ──────────────────────
echo ""
echo "[6/7] Building and starting all containers..."
echo "  (This may take several minutes for backend and ml-service builds)"
echo ""

cd "$PROJECT_DIR"
docker-compose up -d --build

echo ""
echo "  ✅ All containers started."

# ── Step 7: Verify all services ─────────────────────────────────
echo ""
echo "[7/7] Verifying services..."
echo ""

# Wait a moment for services to initialize
sleep 5

# Check container status
echo "  Container Status:"
docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}" | head -20

echo ""
echo "  Service Health Checks:"

# PostgreSQL
if docker exec danger-emergence-db pg_isready -U postgres 2>/dev/null; then
    echo "    ✅ PostgreSQL: healthy"
else
    echo "    ❌ PostgreSQL: not responding"
fi

# Redis
if docker exec danger-emergence-redis redis-cli ping 2>/dev/null | grep -q PONG; then
    echo "    ✅ Redis: healthy"
else
    echo "    ❌ Redis: not responding"
fi

# Backend API
sleep 3
if curl -sf http://localhost:8080/api/v1/alerts/count > /dev/null 2>&1; then
    echo "    ✅ Backend API (port 8080): responding"
elif curl -sf http://localhost:8080/ > /dev/null 2>&1; then
    echo "    ✅ Backend API (port 8080): responding (root)"
else
    echo "    ⚠️  Backend API (port 8080): not yet ready (may still be starting)"
fi

# ML Service
if curl -sf http://localhost:8000/health > /dev/null 2>&1; then
    echo "    ✅ ML Service (port 8000): healthy"
else
    echo "    ⚠️  ML Service (port 8000): not yet ready (may still be starting)"
fi

# Nginx
if curl -sf http://localhost:8081/health > /dev/null 2>&1; then
    echo "    ✅ Nginx (port 8081): responding"
else
    echo "    ⚠️  Nginx (port 8081): not yet ready"
fi

echo ""
echo "============================================================"
echo "  Deployment Complete!"
echo "============================================================"
echo ""
echo "  Services:"
echo "    PostgreSQL :5432  ✅ (if running)"
echo "    Redis      :6379  ✅ (if running)"
echo "    Mosquitto  :1883  ✅ (if running)"
echo "    Backend    :8080  ✅ (if running)"
echo "    ML Service :8000  ✅ (if running)"
echo "    Nginx      :8081  ✅ (if running)"
echo ""
echo "  To check logs:"
echo "    docker-compose logs -f backend"
echo "    docker-compose logs -f ml-service"
echo "    docker-compose logs -f nginx"
echo ""
echo "  To restart a single service:"
echo "    docker-compose restart <service-name>"
echo ""
echo "  To stop everything:"
echo "    docker-compose down"
echo ""

# Show any containers that failed
FAILED=$(docker ps -a --filter "status=exited" --format "{{.Names}}" 2>/dev/null)
if [ -n "$FAILED" ]; then
    echo "  ⚠️  The following containers exited:"
    echo "$FAILED" | while read name; do
        echo "    - $name"
        echo "    Logs: docker logs $name --tail 20"
    done
fi
