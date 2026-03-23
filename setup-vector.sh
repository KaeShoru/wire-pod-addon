#!/bin/bash
# setup-vector.sh - Setup Vector certificates and STT models

set -e

log() {
    echo "[setup-vector] $*"
}

# Generate Vector SDK certificates if they don't exist
generate_certificates() {
    log "Generating Vector SDK certificates..."
    
    CERT_DIR="/data/vector/certs"
    mkdir -p "$CERT_DIR"
    
    # Check if certificates already exist
    if [ -f "$CERT_DIR/cert.pem" ] && [ -f "$CERT_DIR/key.pem" ]; then
        log "Certificates already exist, skipping generation."
        return 0
    fi
    
    # Generate self-signed certificates for Vector SDK
    openssl req -x509 -newkey rsa:4096 \
        -keyout "$CERT_DIR/key.pem" \
        -out "$CERT_DIR/cert.pem" \
        -days 3650 \
        -nodes \
        -subj "/CN=wire-pod-addon" \
        2>/dev/null
    
    log "Certificates generated successfully in $CERT_DIR"
}

# Download VOSK models
download_vosk_models() {
    log "Checking VOSK models..."
    
    MODEL_DIR="/data/vector/models"
    mkdir -p "$MODEL_DIR"
    
    # Default language: English
    MODEL_NAME="vosk-model-small-en-us-0.15"
    MODEL_URL="https://alphacephei.com/vosk/${MODEL_NAME}.zip"
    MODEL_PATH="$MODEL_DIR/$MODEL_NAME"
    
    # Check if model already exists
    if [ -d "$MODEL_PATH" ]; then
        log "Model already exists in $MODEL_PATH, skipping download."
        return 0
    fi
    
    log "Downloading VOSK model: $MODEL_NAME (this may take a few minutes)..."
    
    cd "$MODEL_DIR"
    
    if command -v wget >/dev/null 2>&1; then
        wget -q --show-progress -O "${MODEL_NAME}.zip" "$MODEL_URL"
    elif command -v curl >/dev/null 2>&1; then
        curl -L -o "${MODEL_NAME}.zip" "$MODEL_URL"
    else
        log "Error: Neither wget nor curl is available"
        return 1
    fi
    
    log "Extracting model..."
    unzip -q "${MODEL_NAME}.zip"
    rm "${MODEL_NAME}.zip"
    
    log "Model downloaded and extracted to $MODEL_PATH"
    
    # Create symlink for wire-pod to find the model
    mkdir -p /app/wire-pod/chipper/pkg/stt/vosk/models
    ln -sf "$MODEL_PATH" /app/wire-pod/chipper/pkg/stt/vosk/models/en-us
}

# Setup configuration
setup_config() {
    log "Setting up Vector configuration..."
    
    CONF_DIR="/data/wire-pod/config"
    mkdir -p "$CONF_DIR"
    
    # Default settings
    cat > "$CONF_DIR/wire-pod.conf" << EOF
[general]
cert_path=/data/vector/certs/cert.pem
key_path=/data/vector/certs/key.pem
model_path=/data/vector/models/vosk-model-small-en-us-0.15
EOF
    
    log "Configuration saved to $CONF_DIR/wire-pod.conf"
}

# Main setup
main() {
    log "Starting Vector setup..."
    generate_certificates
    download_vosk_models
    setup_config
    log "Vector setup completed successfully!"
}

main "$@"
