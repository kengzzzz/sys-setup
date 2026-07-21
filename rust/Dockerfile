ARG ARCH_IMAGE_DIGEST

FROM archlinux@${ARCH_IMAGE_DIGEST} AS rust-toolchain

SHELL ["/bin/bash", "-lc"]

RUN pacman -Syu --noconfirm --needed \
        rust \
        rust-analyzer \
        gcc \
        git \
        pkgconf \
        openssl \
        which && \
    pacman -Scc --noconfirm

ARG LOCAL_UID=1000
ARG LOCAL_GID=1000
RUN mkdir -p /cargo /target /home/dev /work /out && \
    chown -R "${LOCAL_UID}:${LOCAL_GID}" /cargo /target /home/dev /work /out

ENV CARGO_HOME=/cargo \
    CARGO_TARGET_DIR=/target \
    HOME=/home/dev \
    CARGO_TERM_COLOR=always \
    PATH=/cargo/bin:$PATH

WORKDIR /work
