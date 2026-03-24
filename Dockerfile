FROM ghcr.io/kercre123/wire-pod:main

# Install additional dependencies for MQTT bridge
RUN apk add --no-cache \
    bash \
    curl \
    wget \
    ca-certificates \
    go \
    git \
    && rm -rf /var/cache/apk/*

# Create directories for HA Add-on
RUN mkdir -p /data/wire-pod /data/vector/certs /data/vector/models /var/www/html /etc/nginx

# Copy our custom files
COPY run.sh /
COPY mqtt-bridge/ /app/mqtt-bridge/
COPY nginx.conf /etc/nginx/nginx.conf
COPY setup-vector.sh /usr/local/bin/

# Build MQTT bridge
WORKDIR /app/mqtt-bridge
RUN go mod tidy && \
    go build -ldflags="-s -w" -o /usr/local/bin/wire-pod-mqtt .

# Make scripts executable
RUN chmod a+x /run.sh /usr/local/bin/setup-vector.sh

EXPOSE 8080 8081

CMD ["/run.sh"]
