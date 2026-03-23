#!/usr/bin/with-contenv bashio

set -e

bashio::log.info "========================================"
bashio::log.info "  Wire-Pod for Vector - Add-on v1.0.0"
bashio::log.info "========================================"

# Read configuration from HA UI
MQTT_HOST=$(bashio::config 'mqtt_broker_host')
MQTT_PORT=$(bashio::config 'mqtt_broker_port')
MQTT_USER=$(bashio::config 'mqtt_username')
MQTT_PASS=$(bashio::config 'mqtt_password')
MQTT_PREFIX=$(bashio::config 'mqtt_topic_prefix')
MQTT_DISCOVERY=$(bashio::config 'mqtt_discovery')
DISCOVERY_PREFIX=$(bashio::config 'mqtt_discovery_prefix')
TELEMETRY_INTERVAL=$(bashio::config 'telemetry_interval')
VECTOR_ESN=$(bashio::config 'vector_esn')
STT_SERVICE=$(bashio::config 'stt_service')
LANGUAGE=$(bashio::config 'language')
WEB_UI_ENABLED=$(bashio::config 'web_ui_enabled')

bashio::log.info "Configuration loaded:"
bashio::log.info "  MQTT Broker: ${MQTT_HOST}:${MQTT_PORT}"
bashio::log.info "  Topic Prefix: ${MQTT_PREFIX}"
bashio::log.info "  STT Service: ${STT_SERVICE}"
bashio::log.info "  Language: ${LANGUAGE}"
bashio::log.info "  Vector ESN: ${VECTOR_ESN}"

# Create data directories
mkdir -p /data/wire-pod/config /data/vector/certs /data/vector/models

# Run Vector setup (certificates + models) on first run
if [ ! -f "/data/vector/.setup_complete" ]; then
    bashio::log.info "First run detected. Setting up Vector..."
    /usr/local/bin/setup-vector.sh
    
    # Mark setup as complete
    touch /data/vector/.setup_complete
    bashio::log.info "Vector setup complete!"
else
    bashio::log.info "Already setup. Skipping initialization."
fi

# Generate source.sh for wire-pod
cat > /data/wire-pod/source.sh << EOF
export STT_SERVICE="${STT_SERVICE}"
export USE_INBUILT_BLE="false"
export LANGUAGE="${LANGUAGE}"
export CERT_PATH="/data/vector/certs/cert.pem"
export KEY_PATH="/data/vector/certs/key.pem"
export MODEL_PATH="/data/vector/models/vosk-model-small-en-us-0.15"
EOF

chmod +x /data/wire-pod/source.sh

# Generate MQTT bridge config
cat > /data/mqtt-config.json << EOF
{
  "broker": "${MQTT_HOST}",
  "port": ${MQTT_PORT},
  "username": "${MQTT_USER}",
  "password": "${MQTT_PASS}",
  "topic_prefix": "${MQTT_PREFIX}",
  "discovery": ${MQTT_DISCOVERY},
  "discovery_prefix": "${DISCOVERY_PREFIX}",
  "telemetry_interval": ${TELEMETRY_INTERVAL},
  "vector_esn": "${VECTOR_ESN}"
}
EOF

bashio::log.info "Configuration files created"

# Export for child processes
export MQTT_BROKER_HOST="${MQTT_HOST}"
export MQTT_BROKER_PORT="${MQTT_PORT}"
export MQTT_USERNAME="${MQTT_USER}"
export MQTT_PASSWORD="${MQTT_PASS}"
export MQTT_TOPIC_PREFIX="${MQTT_PREFIX}"

# Function to handle shutdown
cleanup() {
    bashio::log.info "Shutting down Wire-Pod..."
    pkill -f chipper || true
    pkill -f wire-pod-mqtt || true
    exit 0
}

trap cleanup SIGTERM SIGINT

# Start MQTT bridge in background
bashio::log.info "Starting MQTT bridge..."
/usr/local/bin/wire-pod-mqtt -config /data/mqtt-config.json &
MQTT_PID=$!
bashio::log.info "MQTT bridge started (PID: ${MQTT_PID})"

# Wait a moment for MQTT to connect
sleep 2

# Check if we have a Vector ESN
if [ -z "$VECTOR_ESN" ]; then
    bashio::log.warning "No Vector ESN configured! Vector features will be limited."
    bashio::log.warning "Please configure the Vector ESN in the add-on options."
fi

# Start wire-pod (chipper)
bashio::log.info "Starting Wire-Pod server..."
bashio::log.info "This may take a moment to initialize..."

cd /app/wire-pod/chipper
source /data/wire-pod/source.sh

export GOTAGS="nolibopusfile"

# Run chipper
exec /usr/local/bin/chipper
