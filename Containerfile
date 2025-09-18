FROM registry.access.redhat.com/ubi10/ubi-minimal@sha256:53de6ac7c3e830b0ddfc9867ff6a8092785bcf156ab4e63dfa9af83c880fd988 AS squid-base

ENV NAME="konflux-ci/squid"
ENV SUMMARY="The Squid proxy caching server for Konflux CI"
ENV DESCRIPTION="\
    Squid is a high-performance proxy caching server for Web clients, \
    supporting FTP, gopher, and HTTP data objects. Unlike traditional \
    caching software, Squid handles all requests in a single, \
    non-blocking, I/O-driven process. Squid keeps metadata and especially \
    hot objects cached in RAM, caches DNS lookups, supports non-blocking \
    DNS lookups, and implements negative caching of failed requests."

ENV SQUID_VERSION="6.10-5.el10"

LABEL name="$NAME"
LABEL summary="$SUMMARY"
LABEL description="$DESCRIPTION"
LABEL usage="podman run -d --name squid -p 3128:3128 $NAME"
LABEL maintainer="bkorren@redhat.com"
LABEL com.redhat.component="konflux-ci-squid-container"
LABEL io.k8s.description="$DESCRIPTION"
LABEL io.k8s.display-name="konflux-ci-squid"
LABEL io.openshift.expose-services="3128:squid"
LABEL io.openshift.tags="squid"

# default port providing cache service
EXPOSE 3128

# default port for communication with cache peers
EXPOSE 3130

COPY LICENSE /licenses/

RUN microdnf install -y "squid-${SQUID_VERSION}" && microdnf clean all

COPY --chmod=0755 container-entrypoint.sh /usr/sbin/container-entrypoint.sh

# move location of pid file to a directory where squid user can recreate it
RUN echo "pid_filename /run/squid/squid.pid" >> /etc/squid/squid.conf && \
    sed -i "s/# http_access allow localnet/http_access allow localnet/g" /etc/squid/squid.conf && \
    chown -R root:root /etc/squid/squid.conf /var/log/squid /var/spool/squid /run/squid && \
    chmod g=u /etc/squid/squid.conf /run/squid /var/spool/squid /var/log/squid

# ==========================================
# Stage 2: Go builder base (toolchain + deps cache)
# ==========================================
FROM registry.access.redhat.com/ubi10/ubi-minimal@sha256:53de6ac7c3e830b0ddfc9867ff6a8092785bcf156ab4e63dfa9af83c880fd988 AS go-builder

# Install required packages for Go build
RUN microdnf install -y \
    tar \
    gzip \
    gcc \
    curl \
    ca-certificates \
    git && \
    microdnf clean all

# Install Go (version-locked)
ARG GO_VERSION=1.24.4
ARG GO_SHA256=77e5da33bb72aeaef1ba4418b6fe511bc4d041873cbf82e5aa6318740df98717
SHELL ["/bin/bash", "-o", "pipefail", "-c"]
RUN curl -fsSL "https://golang.org/dl/go${GO_VERSION}.linux-amd64.tar.gz" -o go.tar.gz && \
    echo "${GO_SHA256}  go.tar.gz" | sha256sum -c - && \
    tar -C /usr/local -xzf go.tar.gz && \
    rm go.tar.gz

# Set Go environment
ENV PATH="/usr/local/go/bin:/root/go/bin:$PATH"
ENV GOPATH="/root/go"
ENV GOCACHE="/tmp/go-cache"

# ==========================================
# Stage 3: Build squid-exporter
# ==========================================
FROM go-builder AS squid-exporter-builder
WORKDIR /workspace
RUN CGO_ENABLED=0 GOOS=linux go install github.com/boynux/squid-exporter@v1.13.0 && \
    cp /root/go/bin/squid-exporter /workspace/squid-exporter

# ==========================================
# Stage 4: Build squid per-site exporter
# ==========================================
FROM go-builder AS per-site-exporter-builder

# Pre-fetch deps
WORKDIR /workspace
COPY go.mod go.sum ./
RUN --mount=type=cache,target=/tmp/go-cache \
    go mod download

# Copy source and build the per-site exporter
COPY ./cmd/squid-per-site-exporter ./cmd/squid-per-site-exporter
RUN --mount=type=cache,target=/tmp/go-cache \
    CGO_ENABLED=0 GOOS=linux go build -o /workspace/per-site-exporter ./cmd/squid-per-site-exporter

# ==========================================
# Final Stage: Squid with integrated exporters
# ==========================================
FROM squid-base

# Copy squid-exporter binary from builder stage
COPY --from=squid-exporter-builder /workspace/squid-exporter /usr/local/bin/squid-exporter

# Set permissions for squid-exporter
RUN chmod +x /usr/local/bin/squid-exporter

# Copy per-site exporter binary from builder stage
COPY --from=per-site-exporter-builder /workspace/per-site-exporter /usr/local/bin/per-site-exporter

# Set permissions for per-site exporter
RUN chmod +x /usr/local/bin/per-site-exporter

# Expose exporters' metrics ports
EXPOSE 9301
EXPOSE 9302

USER 1001

ENTRYPOINT ["/usr/sbin/container-entrypoint.sh"]
