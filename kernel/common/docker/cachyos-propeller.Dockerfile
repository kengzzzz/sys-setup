ARG ARCH_IMAGE_DIGEST=sha256:1047e6e7878d58e4ee47e1cd6459a32fab41246b0efc4109e11b7ef16f50b14d
ARG UBUNTU_IMAGE_DIGEST=sha256:c4a8d5503dfb2a3eb8ab5f807da5bc69a85730fb49b5cfca2330194ebcc41c7b

FROM ubuntu@${UBUNTU_IMAGE_DIGEST} AS propeller-builder

ARG LLVM_GPG_FINGERPRINT=6084F3CF814B57C1CF12EFD515CF4D18AF4F7421
ARG PROPELLER_REF

ENV DEBIAN_FRONTEND=noninteractive

RUN test -n "${PROPELLER_REF}" && \
    apt-get update && apt-get install -y \
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
    git fetch --depth 1 origin "${PROPELLER_REF}" && \
    git checkout FETCH_HEAD && \
    git submodule update --init --recursive && \
    cmake -G Ninja -B build \
          -DCMAKE_C_COMPILER=clang-19 \
          -DCMAKE_CXX_COMPILER=clang++-19 \
          -DCMAKE_BUILD_TYPE=Release && \
    ninja -C build generate_propeller_profiles

FROM archlinux@${ARCH_IMAGE_DIGEST} AS cachyos-base

ARG CACHYOS_REPO_FLAVOR=auto

COPY common/assets/cachyos-signing-key.asc /usr/local/share/cachyos-signing-key.asc
COPY common/scripts/cachyos/setup-cachyos-repo.sh /usr/local/bin/setup-cachyos-repo

RUN pacman -Syy --noconfirm --needed gcc && \
    pacman-key --init && \
    chmod 0755 /usr/local/bin/setup-cachyos-repo && \
    CACHYOS_REPO_FLAVOR="${CACHYOS_REPO_FLAVOR}" setup-cachyos-repo && \
    echo -e "\n[multilib]\nInclude = /etc/pacman.d/mirrorlist" >> /etc/pacman.conf && \
    pacman -Syu --noconfirm cachyos-keyring archlinux-keyring

FROM cachyos-base AS propeller-profiler

RUN pacman -Syyu --noconfirm --needed \
    perf zstd tar bash

COPY --from=propeller-builder /build/build/propeller/generate_propeller_profiles /usr/local/bin/generate_propeller_profiles

WORKDIR /build
