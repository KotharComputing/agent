# Kothar Agent Docker Image

This repository contains the Docker build definition for the Kothar Agent runtime image, published at [`ghcr.io/kotharcomputing/agent`](https://ghcr.io/kotharcomputing/agent). The image bundles the dependencies required for running Kothar agents and bootstraps the latest agent binary at container start-up.

## Highlights

- **Multi-architecture image** built for `linux/amd64` and `linux/arm64` using Docker Buildx.
- **Automatic agent updates**: the entrypoint downloads the latest agent binary and handles in-place upgrades.
- **Sigstore signing & provenance**: every published image is keylessly signed with Cosign and accompanied by a BuildKit provenance attestation.

## Usage

Please follow the instructions at https://workshop.kotharcomputing.com to run the agent.

## Verifying signatures and provenance

Consumers can validate what they pull from GHCR with Cosign:

```bash
COSIGN_EXPERIMENTAL=1 cosign verify --keyless ghcr.io/kotharcomputing/agent:latest
COSIGN_EXPERIMENTAL=1 cosign verify-attestation --type slsa ghcr.io/kotharcomputing/agent:latest
```

(Ensure you have [`cosign`](https://docs.sigstore.dev/system_config/installation/) installed.)
