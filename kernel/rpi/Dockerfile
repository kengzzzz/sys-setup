ARG DEBIAN_IMAGE_DIGEST
ARG COMMIT_HASH

FROM debian@${DEBIAN_IMAGE_DIGEST}

RUN apt-get update && apt-get upgrade -y && apt-get install -y \
    build-essential git bc bison flex libssl-dev make libc6-dev libncurses-dev \
    kmod cpio pahole clang lld llvm rsync fakeroot sudo ca-certificates python3 zstd \
    && apt-get clean && rm -rf /var/lib/apt/lists/*

RUN groupadd wheel && \
    useradd -m -G wheel -s /bin/bash builder && \
    echo "%wheel ALL=(ALL) NOPASSWD: ALL" > /etc/sudoers.d/builder && \
    chmod 0440 /etc/sudoers.d/builder

WORKDIR /src

RUN git init && \
    git remote add origin https://github.com/raspberrypi/linux.git && \
    git fetch --depth 1 origin "${COMMIT_HASH}" && \
    git checkout FETCH_HEAD

ENV LLVM=1 \
    KERNEL=kernel_2712