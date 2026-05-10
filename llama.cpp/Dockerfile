ARG BASE_CUDA_DEV_CONTAINER
ARG LLAMA_CPP_REPO
ARG LLAMA_CPP_COMMIT

FROM ${BASE_CUDA_DEV_CONTAINER} AS source

SHELL ["/bin/bash", "-lc"]

ARG LLAMA_CPP_REPO
ARG LLAMA_CPP_COMMIT

RUN apt-get update && \
    apt-get install -y --no-install-recommends ca-certificates git && \
    rm -rf /var/lib/apt/lists/*

WORKDIR /src

RUN git init llama.cpp && \
    cd llama.cpp && \
    git remote add origin "${LLAMA_CPP_REPO}" && \
    git fetch --depth 1 origin "${LLAMA_CPP_COMMIT}" && \
    git checkout --detach FETCH_HEAD && \
    test "$(git rev-parse HEAD)" = "${LLAMA_CPP_COMMIT}"

FROM ${BASE_CUDA_DEV_CONTAINER} AS build-base

SHELL ["/bin/bash", "-lc"]

ARG CUDA_ARCH
ARG CUDA_COMPRESSION_MODE
ARG LLAMA_CPP_COMMIT
ARG CMAKE_BUILD_PARALLEL_LEVEL

RUN apt-get update && \
    apt-get install -y --no-install-recommends \
        build-essential \
        ca-certificates \
        cmake \
        gcc-14 \
        g++-14 \
        git \
        libssl-dev \
        libgomp1 \
        ninja-build \
        python3 && \
    rm -rf /var/lib/apt/lists/*

ENV CC=gcc-14 \
    CXX=g++-14 \
    CUDAHOSTCXX=g++-14

WORKDIR /src/llama.cpp
COPY --from=source /src/llama.cpp/ ./
COPY scripts/ /scripts/

FROM build-base AS build

RUN set -euo pipefail; \
    cmake -S . -B build-server -G Ninja \
      -DCMAKE_BUILD_TYPE=Release \
      -DCMAKE_CUDA_ARCHITECTURES="${CUDA_ARCH}" \
      -DCMAKE_EXE_LINKER_FLAGS=-Wl,--allow-shlib-undefined \
      -DGGML_NATIVE=ON \
      -DGGML_CUDA=ON \
      -DGGML_CUDA_CUB_3DOT2=ON \
      -DGGML_CUDA_NCCL=OFF \
      -DGGML_CUDA_COMPRESSION_MODE="${CUDA_COMPRESSION_MODE}" \
      -DGGML_BACKEND_DL=OFF \
      -DGGML_CPU_ALL_VARIANTS=OFF \
      -DLLAMA_BUILD_TESTS=OFF \
      -DLLAMA_BUILD_EXAMPLES=OFF \
      -DLLAMA_BUILD_TOOLS=ON \
      -DLLAMA_BUILD_SERVER=ON && \
    cmake --build build-server --target llama-server

RUN /scripts/package-app.sh build-server llama-server /out/server "${LLAMA_CPP_COMMIT}"

FROM build AS rootfs

RUN set -euo pipefail; \
    mkdir -p /server-rootfs/app /server-rootfs/tmp /server-rootfs/etc/ssl/certs /server-rootfs/meta; \
    cp -a /out/server/app/. /server-rootfs/app/; \
    cp -a /out/server/meta/. /server-rootfs/meta/; \
    cp -a /etc/ssl/certs/ca-certificates.crt /server-rootfs/etc/ssl/certs/; \
    printf 'llama:x:1000:1000:llama:/nonexistent:/sbin/nologin\n' > /server-rootfs/etc/passwd; \
    printf 'llama:x:1000:\n' > /server-rootfs/etc/group; \
    chmod 1777 /server-rootfs/tmp; \
    /scripts/build-runtime-rootfs.sh /server-rootfs

FROM scratch AS server

ARG LLAMA_CPP_COMMIT
ARG CUDA_ARCH=89-real
ARG CUDA_COMPRESSION_MODE=speed

COPY --from=rootfs /server-rootfs/ /

WORKDIR /app

ENV LLAMA_ARG_HOST=0.0.0.0 \
    NVIDIA_VISIBLE_DEVICES=all \
    NVIDIA_DRIVER_CAPABILITIES=compute,utility \
    LD_LIBRARY_PATH=/app:/usr/local/cuda/lib64:/usr/local/nvidia/lib:/usr/local/nvidia/lib64 \
    PATH=/app

LABEL org.opencontainers.image.source="https://github.com/ggml-org/llama.cpp" \
      org.opencontainers.image.revision="${LLAMA_CPP_COMMIT}" \
      org.ggml.llama.cuda.arch="${CUDA_ARCH}" \
      org.ggml.llama.cuda.compression_mode="${CUDA_COMPRESSION_MODE}" \
      org.ggml.llama.mode="server"

USER 1000:1000
ENTRYPOINT ["/app/llama-server"]
