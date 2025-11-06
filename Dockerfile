# Kothar Agent Docker Image
FROM debian:trixie-slim
ARG COSIGN_VERSION=v3.0.2
ARG TARGETARCH

ARG DEBIAN_FRONTEND=noninteractive
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
    ca-certificates \
    curl \
    unzip && \
    rm -rf /var/lib/apt/lists/*

RUN update-ca-certificates

RUN base_url="https://github.com/sigstore/cosign/releases/download/${COSIGN_VERSION}/cosign-linux-${TARGETARCH}" && \
    curl -sSfL "${base_url}" -o /usr/local/bin/cosign && \
    chmod +x /usr/local/bin/cosign

RUN useradd -m kothar
RUN mkdir -p /opt/runtimes && chown kothar /opt/runtimes
RUN mkdir -p /opt/agents && chown kothar /opt/agents
COPY --chown=kothar entrypoint.sh /bin/entrypoint
RUN chmod +x /bin/entrypoint

ARG KOTHAR_AGENT_DOCKER_IMAGE_VERSION=dev
ARG OCI_IMAGE_DESCRIPTION="Kothar Agent image that can be used to execute scripts in the Workshop app - https://kotharcomputing.com."
LABEL org.opencontainers.image.description="${OCI_IMAGE_DESCRIPTION}"
LABEL org.opencontainers.image.version="${KOTHAR_AGENT_DOCKER_IMAGE_VERSION}"
LABEL org.opencontainers.image.source="https://github.com/KotharComputing/agent"

USER kothar
ENV KOTHAR_AGENT_DOCKER_IMAGE_VERSION=${KOTHAR_AGENT_DOCKER_IMAGE_VERSION}

# Initialize cosign for offline signature validation
RUN cosign initialize

ENTRYPOINT ["/bin/entrypoint"]
