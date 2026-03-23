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
    ca-certificates \
    && rm -rf /var/cache/apk/*

WORKDIR /app

# Clone wire-pod
RUN git clone --depth 1 https://github.com/kercre123/wire-pod.git

# Build chipper (wire-pod server)
WORKDIR /app/wire-pod/chipper
RUN go mod download

# Build for VOSK STT with CGO flags
RUN CGO_CFLAGS="-I/usr/local/include" CGO_LDFLAGS="-L/usr/local/lib -lvosk" \
    go build -tags nolibopusfile -ldflags="-s -w" -o /usr/local/bin/chipper ./cmd/vosk/main.go

# Create directories
RUN mkdir -p /data/wire-pod /data/vector/certs /data/vector/models /var/www/html /etc/nginx

# Copy our custom files
COPY run.sh /
RUN go build -tags nolibopusfile -ldflags="-s -w" -o /usr/local/bin/chipper ./cmd/noop/main.go
COPY nginx.conf /etc/nginx/nginx.conf
COPY setup-vector.sh /usr/local/bin/

# Build MQTT bridge
WORKDIR /app/mqtt-bridge
RUN go mod tidy && \
    go build -ldflags="-s -w" -o /usr/local/bin/wire-pod-mqtt .

# Make scripts executable
RUN chmod a+x /run.sh /usr/local/bin/setup-vector.sh

# Set library path for runtime
ENV LD_LIBRARY_PATH=/usr/local/lib:$LD_LIBRARY_PATH

EXPOSE 8080 8081

CMD ["/run.sh"]
