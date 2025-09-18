FROM registry.access.redhat.com/ubi10/ubi-minimal@sha256:53de6ac7c3e830b0ddfc9867ff6a8092785bcf156ab4e63dfa9af83c880fd988

# Install required packages for Go and testing (version-locked)
# Note: curl-minimal is already present in ubi10-minimal
RUN microdnf install -y \
    tar-2:1.35-7.el10 \
    gzip-1.13-3.el10 \
    which-2.21-44.el10_0 \
    procps-ng-4.0.4-7.el10 \
    gcc-14.2.1-7.el10 && \
    microdnf clean all

SHELL ["/bin/bash", "-o", "pipefail", "-c"]

# Install Go (version-locked)
ARG GO_VERSION=1.24.4
ARG GO_SHA256=77e5da33bb72aeaef1ba4418b6fe511bc4d041873cbf82e5aa6318740df98717
RUN curl -fsSL "https://golang.org/dl/go${GO_VERSION}.linux-amd64.tar.gz" -o go.tar.gz && \
    echo "${GO_SHA256}  go.tar.gz" | sha256sum -c - && \
    tar -C /usr/local -xzf go.tar.gz && \
    rm go.tar.gz

# Install Helm (version-locked)
ARG HELM_VERSION=v3.18.6
ARG HELM_SHA256=3f43c0aa57243852dd542493a0f54f1396c0bc8ec7296bbb2c01e802010819ce
RUN curl -fsSL "https://get.helm.sh/helm-${HELM_VERSION}-linux-amd64.tar.gz" -o helm.tar.gz && \
    echo "${HELM_SHA256}  helm.tar.gz" | sha256sum -c - && \
    mkdir -p /tmp/helm && \
    tar -C /tmp/helm -xzf helm.tar.gz && \
    mv /tmp/helm/linux-amd64/helm /usr/local/bin/helm && \
    rm -rf /tmp/helm helm.tar.gz

# Set Go environment
ENV PATH="/usr/local/go/bin:/root/go/bin:$PATH"
ENV GOPATH="/root/go"
ENV GOCACHE="/tmp/go-cache"

# Install Ginkgo CLI (version-locked)
RUN go install github.com/onsi/ginkgo/v2/ginkgo@v2.23.4

# Create working directory
WORKDIR /app

# Copy module files first
COPY go.mod go.sum ./

# Copy test source files maintaining directory structure
COPY tests/ ./tests/

# Copy squid chart
COPY squid/ ./squid/

# Set up Go module and compile tests and testserver at build time
RUN go mod download && \
    go mod tidy && \
    ginkgo build ./tests/e2e && \
    CGO_ENABLED=1 go build -o /app/testserver ./tests/testserver

# Create a non-root user for running tests
RUN adduser --uid 1001 --gid 0 --shell /bin/bash --create-home testuser
USER 1001

LABEL name="Konflux CI Squid Tester"
LABEL summary="Konflux CI Squid Tester"
LABEL description="Konflux CI Squid Tester"
LABEL maintainer="bkorren@redhat.com"
LABEL com.redhat.component="konflux-ci-squid-tester"
LABEL io.k8s.description="Konflux CI Squid Tester"
LABEL io.k8s.display-name="konflux-ci-squid-tester"
LABEL io.openshift.expose-services="3128:squid"
LABEL io.openshift.tags="squid-tester"

# Default command runs the compiled test binary
CMD ["./tests/e2e/e2e.test", "-ginkgo.v"] 
