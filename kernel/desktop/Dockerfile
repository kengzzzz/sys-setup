ARG ARCH_IMAGE_DIGEST

FROM archlinux@${ARCH_IMAGE_DIGEST} AS cachyos-base

ARG CACHYOS_REPO_FLAVOR=auto

COPY common/assets/cachyos-signing-key.asc /usr/local/share/cachyos-signing-key.asc
COPY desktop/scripts/setup-cachyos-repo.sh /usr/local/bin/setup-cachyos-repo

RUN pacman -Syy --noconfirm --needed gcc && \
    pacman-key --init && \
    chmod 0755 /usr/local/bin/setup-cachyos-repo && \
    CACHYOS_REPO_FLAVOR="${CACHYOS_REPO_FLAVOR}" setup-cachyos-repo && \
    echo -e "\n[multilib]\nInclude = /etc/pacman.d/mirrorlist" >> /etc/pacman.conf && \
    pacman -Syu --noconfirm cachyos-keyring archlinux-keyring

FROM cachyos-base AS kernel-toolchain

ARG KERNEL_GIT_REMOTE=https://github.com/CachyOS/linux-cachyos.git
ARG KERNEL_REF
ARG KERNEL_SOURCE_SUBDIR

RUN pacman -Syyu --noconfirm --needed \
    base-devel sudo git wget bc cpio pahole xmlto kmod libelf python-sphinx pacman-contrib \
    rust rust-bindgen rust-src ncurses llvm && \
    pacman -Scc --noconfirm && \
    rm -rf /var/lib/pacman/sync/* && \
    useradd -m -G wheel builder && \
    echo "%wheel ALL=(ALL) NOPASSWD: ALL" > /etc/sudoers.d/builder && \
    chmod 0440 /etc/sudoers.d/builder

# Declared after the toolchain so all kernel stages share one clang (Propeller profiles depend on it).
ARG PATCH_FILE

WORKDIR /src

RUN test -n "${KERNEL_REF}" && \
    test -n "${PATCH_FILE}" && \
    git init && \
    git remote add origin "${KERNEL_GIT_REMOTE}" && \
    git fetch --depth 1 origin "${KERNEL_REF}" && \
    git checkout FETCH_HEAD

COPY desktop/scripts/check-profile-inputs.sh /usr/local/bin/check-profile-inputs
COPY desktop/scripts/check-profile-inputs.sh /usr/local/bin/check-profile-inputs
COPY desktop/patches/variants/${PATCH_FILE} ${KERNEL_SOURCE_SUBDIR}/pkgbuild.patch
COPY desktop/profiles/ ${KERNEL_SOURCE_SUBDIR}/

RUN cd "${KERNEL_SOURCE_SUBDIR}" && patch --batch --fuzz=0 -p1 < pkgbuild.patch && \
    bash /usr/local/bin/check-profile-inputs PKGBUILD

FROM cachyos-base AS autofdo-profiler

ARG LOAD_KERNEL_VERSION=7.3
ARG LOAD_KERNEL_SHA256=87363c24f10e06321eb362765521094e94471f6bff8bce2d6b3e40f39f004953

RUN pacman -Syyu --noconfirm --needed \
    perf llvm binutils python zstd tar stress-ng rt-tests ripgrep ffmpeg pipewire-audio libglvnd base-devel bc libelf && \
    pacman -Scc --noconfirm && \
    rm -rf /var/lib/pacman/sync/*

RUN mkdir /usr/src/linux && \
    curl -fsSL "https://cdn.kernel.org/pub/linux/kernel/v7.x/linux-${LOAD_KERNEL_VERSION}.tar.xz" -o /tmp/linux.tar.xz && \
    echo "${LOAD_KERNEL_SHA256}  /tmp/linux.tar.xz" | sha256sum -c - && \
    tar -xJf /tmp/linux.tar.xz -C /usr/src/linux --strip-components=1 && \
    rm /tmp/linux.tar.xz

COPY desktop/scripts/autofdo-gpu-load.c /tmp/autofdo-gpu-load.c

RUN gcc -O2 -Wall -Wextra /tmp/autofdo-gpu-load.c -o /usr/local/bin/autofdo-gpu-load -lEGL -lGLESv2 && \
    rm /tmp/autofdo-gpu-load.c && \
    mkdir -p /usr/local/share/autofdo && \
    ffmpeg -hide_banner -loglevel error \
      -f lavfi -i testsrc2=size=2560x1440:rate=60 -t 5 \
      -c:v libx264 -preset ultrafast -crf 28 -pix_fmt yuv420p \
      /usr/local/share/autofdo/1440p60.mp4

WORKDIR /build
