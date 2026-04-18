FROM debian@sha256:4ffb3a1511099754cddc70eb1b12e50ffdb67619aa0ab6c13fcd800a78ef7c7a

RUN apt-get update && apt-get install -y \
    build-essential git bc bison flex libssl-dev make libc6-dev libncurses-dev \
    kmod cpio pahole clang lld llvm rsync fakeroot sudo ca-certificates python3 zstd \
    && apt-get clean && rm -rf /var/lib/apt/lists/*

RUN groupadd wheel && \
    useradd -m -G wheel -s /bin/bash builder && \
    echo "%wheel ALL=(ALL) NOPASSWD: ALL" > /etc/sudoers.d/builder && \
    chmod 0440 /etc/sudoers.d/builder

USER builder
WORKDIR /build