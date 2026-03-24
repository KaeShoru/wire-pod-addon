FROM golang:1.21 AS builder

WORKDIR /app
COPY mqtt-bridge/ .
RUN go build -mod=readonly -ldflags="-s -w" -o wire-pod-mqtt .

FROM ghcr.io/kercre123/wire-pod:main

# Create directories for HA Add-on
RUN mkdir -p /data/wire-pod /data/vector/certs /data/vector/models /var/www/html /etc/nginx

# Copy compiled MQTT bridge from builder
COPY --from=builder /app/wire-pod-mqtt /usr/local/bin/

# Copy our custom files
COPY run.sh /
COPY nginx.conf /etc/nginx/nginx.conf
COPY setup-vector.sh /usr/local/bin/

# Make scripts executable
RUN chmod a+x /run.sh /usr/local/bin/setup-vector.sh /usr/local/bin/wire-pod-mqtt

EXPOSE 8080 8081

CMD ["/run.sh"]
