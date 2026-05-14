ARG UBUNTU_IMAGE_DIGEST
ARG ARCH_IMAGE_DIGEST

FROM ubuntu@${UBUNTU_IMAGE_DIGEST} AS propeller-builder

ARG LLVM_GPG_FINGERPRINT
ARG PROPELLER_COMMIT_HASH

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update && apt-get install -y \
    wget lsb-release software-properties-common gnupg \
    git cmake ninja-build \
    libelf-dev libssl-dev libzstd-dev && \
    install -m 0755 -d /etc/apt/keyrings && \
    wget -qO /tmp/llvm.key https://apt.llvm.org/llvm-snapshot.gpg.key && \
    gpg --show-keys /tmp/llvm.key | grep -q "${LLVM_GPG_FINGERPRINT}" && \
    gpg --dearmor -o /etc/apt/keyrings/llvm.gpg /tmp/llvm.key && \
    rm /tmp/llvm.key && \
    OS_CODENAME=$(lsb_release -cs) && \
    echo "deb [signed-by=/etc/apt/keyrings/llvm.gpg] http://apt.llvm.org/${OS_CODENAME}/ llvm-toolchain-${OS_CODENAME}-19 main" > /etc/apt/sources.list.d/llvm.list && \
    apt-get update && \
    apt-get install -y clang-19 lldb-19 lld-19 clangd-19

WORKDIR /build

RUN git init && \
    git remote add origin https://github.com/google/llvm-propeller.git && \
    git fetch --depth 1 origin "${PROPELLER_COMMIT_HASH}" && \
    git checkout FETCH_HEAD && \
    git submodule update --init --recursive && \
    cmake -G Ninja -B build \
          -DCMAKE_C_COMPILER=clang-19 \
          -DCMAKE_CXX_COMPILER=clang++-19 \
          -DCMAKE_BUILD_TYPE=Release && \
    ninja -C build generate_propeller_profiles

FROM archlinux@${ARCH_IMAGE_DIGEST} AS cachyos-base

ARG CACHYOS_COMMIT_HASH

RUN pacman -Syy --noconfirm --needed curl git && \
    pacman-key --init && \
    mkdir -p /tmp/cachyos-setup && cd /tmp/cachyos-setup && \
    git init && \
    git remote add origin https://github.com/CachyOS/cachyos-repo-add-script.git && \
    git fetch --depth 1 origin "${CACHYOS_COMMIT_HASH}" && \
    git checkout FETCH_HEAD && \
    yes | ./cachyos-repo.sh && \
    echo -e "\n[multilib]\nInclude = /etc/pacman.d/mirrorlist" >> /etc/pacman.conf && \
    pacman -Syu --noconfirm cachyos-keyring archlinux-keyring

FROM cachyos-base AS kernel-toolchain

ARG KERNEL_COMMIT_HASH
ARG FLAVOR
ARG PATCH_FILE="${FLAVOR}.patch"

RUN pacman -Syyu --noconfirm --needed \
    base-devel sudo wget bc cpio pahole xmlto kmod libelf python-sphinx pacman-contrib \
    rust rust-bindgen rust-src ncurses llvm && \
    pacman -Scc --noconfirm && \
    rm -rf /var/lib/pacman/sync/* && \
    useradd -m -G wheel builder && \
    echo "%wheel ALL=(ALL) NOPASSWD: ALL" > /etc/sudoers.d/builder && \
    chmod 0440 /etc/sudoers.d/builder

WORKDIR /src

RUN git init && \
    git remote add origin https://github.com/CachyOS/linux-cachyos.git && \
    git fetch --depth 1 origin "${KERNEL_COMMIT_HASH}" && \
    git checkout FETCH_HEAD

COPY patches/${PATCH_FILE} linux-cachyos/pkgbuild.patch
COPY patches/fragnesia-skb-shared-frag.patch linux-cachyos/
COPY profiles/* linux-cachyos/

RUN cd linux-cachyos && patch PKGBUILD < pkgbuild.patch

FROM cachyos-base AS autofdo-profiler

RUN pacman -Syyu --noconfirm --needed \
    perf zstd tar bash llvm

WORKDIR /build

FROM cachyos-base AS propeller-profiler

RUN pacman -Syyu --noconfirm --needed \
    perf zstd tar bash

COPY --from=propeller-builder /build/build/propeller/generate_propeller_profiles /usr/local/bin/generate_propeller_profiles

WORKDIR /build
