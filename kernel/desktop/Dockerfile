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
ARG PATCH_FILE

RUN pacman -Syyu --noconfirm --needed \
    base-devel sudo git wget bc cpio pahole xmlto kmod libelf python-sphinx pacman-contrib \
    rust rust-bindgen rust-src ncurses llvm && \
    pacman -Scc --noconfirm && \
    rm -rf /var/lib/pacman/sync/* && \
    useradd -m -G wheel builder && \
    echo "%wheel ALL=(ALL) NOPASSWD: ALL" > /etc/sudoers.d/builder && \
    chmod 0440 /etc/sudoers.d/builder

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
COPY desktop/patches/nvidia/fix-dp-detach-unplugged-1359.patch ${KERNEL_SOURCE_SUBDIR}/fix-dp-detach-unplugged-1359.patch
COPY desktop/patches/nvidia/fix-hdmi-frl-reassessment-after-reconnect.patch ${KERNEL_SOURCE_SUBDIR}/fix-hdmi-frl-reassessment-after-reconnect.patch
COPY desktop/profiles/ ${KERNEL_SOURCE_SUBDIR}/

RUN cd "${KERNEL_SOURCE_SUBDIR}" && patch --batch --fuzz=0 -p1 < pkgbuild.patch && \
    bash /usr/local/bin/check-profile-inputs PKGBUILD

FROM cachyos-base AS autofdo-profiler

RUN pacman -Syyu --noconfirm --needed \
    perf zstd tar bash llvm binutils python binutils python

WORKDIR /build
