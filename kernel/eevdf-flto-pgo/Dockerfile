ARG ARCH_IMAGE_DIGEST

FROM archlinux@${ARCH_IMAGE_DIGEST} AS cachyos-base

ARG CACHYOS_REPO_FLAVOR

COPY assets/cachyos-signing-key.asc /usr/local/share/cachyos-signing-key.asc
COPY scripts/setup-cachyos-repo.sh /usr/local/bin/setup-cachyos-repo

RUN pacman -Syy --noconfirm --needed gcc && \
    pacman-key --init && \
    chmod 0755 /usr/local/bin/setup-cachyos-repo && \
    CACHYOS_REPO_FLAVOR="${CACHYOS_REPO_FLAVOR}" setup-cachyos-repo && \
    echo -e "\n[multilib]\nInclude = /etc/pacman.d/mirrorlist" >> /etc/pacman.conf && \
    pacman -Syu --noconfirm cachyos-keyring archlinux-keyring

FROM cachyos-base AS kernel-toolchain

ARG KERNEL_COMMIT_HASH
ARG FLAVOR
ARG PATCH_FILE="${FLAVOR}.patch"

RUN pacman -Syyu --noconfirm --needed \
    base-devel sudo git wget bc cpio pahole xmlto kmod libelf python-sphinx pacman-contrib \
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

COPY patches/${PATCH_FILE} linux-cachyos-lts/pkgbuild.patch
COPY profiles/ linux-cachyos-lts/

RUN cd linux-cachyos-lts && patch PKGBUILD < pkgbuild.patch

FROM cachyos-base AS autofdo-profiler

RUN pacman -Syyu --noconfirm --needed \
    perf zstd tar bash llvm

WORKDIR /build
