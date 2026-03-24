ARG BUILD_FROM=ghcr.io/home-assistant/aarch64-base:3.18
FROM ${BUILD_FROM}

# Install dependencies (Alpine Linux packages)
RUN apk add --no-cache \
    go \
    git \
    build-base \
    opus-dev \
    opus \
    sox-dev \
    sox \
    pkgconfig \
    avahi-dev \
    avahi \
    openssl \
    openssl-dev \
    nginx \
    bash \
    curl \
    wget \
    unzip \
    ca-certificates \
    python3 \
    py3-pip \
    py3-setuptools \
    && rm -rf /var/cache/apk/*

WORKDIR /app

# Clone wire-pod
RUN git clone --depth 1 https://github.com/kercre123/wire-pod.git

# Build chipper (wire-pod server)
WORKDIR /app/wire-pod/chipper
RUN go mod download

# Build main chipper binary (default STT config - coqui)
RUN go build -tags nolibopusfile -ldflags="-s -w" -o /usr/local/bin/chipper ./cmd/coqui/main.go

# Create directories
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
