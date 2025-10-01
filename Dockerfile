# Kothar Agent Docker Image

FROM debian:trixie-slim AS build_local_libs
ARG HDF5_VERSION=1.14.6

ARG DEBIAN_FRONTEND=noninteractive
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
    ca-certificates \
    cmake \
    build-essential \
    git \
    libcurl4-openssl-dev \
    libyajl-dev \
    ninja-build \
    unzip \
    wget \
    zlib1g-dev

RUN mkdir -p /tmp/hdf5 && \
    cd /tmp/hdf5 && \
    wget https://github.com/HDFGroup/hdf5/releases/download/hdf5_${HDF5_VERSION}/hdf5-${HDF5_VERSION}.zip -O hdf5.zip && unzip hdf5.zip && \
    cd hdf5-${HDF5_VERSION} && \
    cmake -G Ninja -DCMAKE_BUILD_TYPE:STRING=Release -DBUILD_SHARED_LIBS:BOOL=ON -DHDF5_BUILD_CPP_LIB=ON -DBUILD_TESTING:BOOL=OFF -DHDF5_BUILD_TOOLS:BOOL=ON -DCMAKE_INSTALL_PREFIX=/usr/local -B./build && \
    cmake --build ./build --config Release && \
    cmake --install ./build

RUN git clone --depth 1 https://github.com/HDFGroup/vol-rest /tmp/hdf5-vol-rest && \
    cd /tmp/hdf5-vol-rest && \
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

USER kothar
ENV AGENT_DOCKER_IMAGE_VERSION=1
ENV HDF5_PLUGIN_PATH=/usr/local/lib
ENV HDF5_VOL_CONNECTOR=REST

ENTRYPOINT ["/bin/entrypoint"]
