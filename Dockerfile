# Kothar Agent Docker Image

FROM debian:trixie-slim AS build_local_libs
ARG HDF5_VERSION=1.14.6
ARG HDF5_SHA256=67c25c5e1196b3c02687722d30cda605f40a1ea64be2affaf98130ea99c7417a
ARG HDF5_VOL_REST_COMMIT=97fec4c

ARG DEBIAN_FRONTEND=noninteractive
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
    ca-certificates \
    cmake \
    curl \
    build-essential \
    git \
    libcurl4-openssl-dev \
    libyajl-dev \
    ninja-build \
    unzip \
    zlib1g-dev

RUN mkdir -p /tmp/hdf5 && \
    cd /tmp/hdf5 && \
    curl -fsSL https://github.com/HDFGroup/hdf5/releases/download/hdf5_${HDF5_VERSION}/hdf5-${HDF5_VERSION}.zip -o hdf5.zip && \
    echo "${HDF5_SHA256}  hdf5.zip" | sha256sum -c - && \
    unzip hdf5.zip && \
    cd hdf5-${HDF5_VERSION} && \
    cmake -G Ninja -DCMAKE_BUILD_TYPE:STRING=Release -DBUILD_SHARED_LIBS:BOOL=ON -DHDF5_BUILD_CPP_LIB=ON -DBUILD_TESTING:BOOL=OFF -DHDF5_BUILD_TOOLS:BOOL=ON -DCMAKE_INSTALL_PREFIX=/usr/local -B./build && \
    cmake --build ./build --config Release && \
    cmake --install ./build

RUN git clone https://github.com/HDFGroup/vol-rest /tmp/hdf5-vol-rest && \
    cd /tmp/hdf5-vol-rest && \
    git checkout "${HDF5_VOL_REST_COMMIT}" && \
    rm -rf .git && \
    cmake -G Ninja -DCMAKE_BUILD_TYPE=Release -DBUILD_TESTING=OFF -DHDF5_VOL_REST_ENABLE_EXAMPLES=OFF -DYAJL_USE_STATIC_LIBRARIES=ON -DCURL_USE_STATIC_LIBRARIES=ON -DCMAKE_INSTALL_PREFIX=/usr/local -B./build && \
    cmake --build ./build --config Release && \
    cmake --install ./build

FROM debian:trixie-slim

ARG DEBIAN_FRONTEND=noninteractive
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
    ca-certificates \
    curl \
    git && \
    rm -rf /var/lib/apt/lists/*

RUN update-ca-certificates

RUN useradd -m kothar
RUN mkdir -p /opt/runtimes && chown kothar /opt/runtimes
RUN mkdir -p /opt/agents && chown kothar /opt/agents
COPY --chown=kothar --from=build_local_libs  /usr/local/lib /usr/local/lib
COPY --chown=kothar entrypoint.sh /bin/entrypoint
RUN chmod +x /bin/entrypoint

ARG KOTHAR_AGENT_DOCKER_IMAGE_VERSION=dev
ARG OCI_IMAGE_DESCRIPTION="Kothar Agent image that can be used to execute scripts in the Workshop app - https://kotharcomputing.com."
LABEL org.opencontainers.image.description="${OCI_IMAGE_DESCRIPTION}"
LABEL org.opencontainers.image.version="${KOTHAR_AGENT_DOCKER_IMAGE_VERSION}"
LABEL org.opencontainers.image.source="https://github.com/KotharComputing/agent"
USER kothar
ENV KOTHAR_AGENT_DOCKER_IMAGE_VERSION=${KOTHAR_AGENT_DOCKER_IMAGE_VERSION}
ENV HDF5_PLUGIN_PATH=/usr/local/lib
ENV HDF5_VOL_CONNECTOR=REST

ENTRYPOINT ["/bin/entrypoint"]
