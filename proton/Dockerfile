FROM archlinux@sha256:5ba8bb318666baef4d33afefc0e65db80f38b23503cb8e7b150d315cc2d4d5da AS cachyos-base

RUN pacman -Syy --noconfirm --needed curl && \
    pacman-key --init && \
    curl -L https://mirror.cachyos.org/cachyos-repo.tar.xz | tar xJ && \
    cd cachyos-repo && \
    yes | ./cachyos-repo.sh && \
    echo -e "\n[multilib]\nInclude = /etc/pacman.d/mirrorlist" >> /etc/pacman.conf && \
    pacman -Syu --noconfirm cachyos-keyring archlinux-keyring
    
FROM cachyos-base

ARG COMMIT_HASH=d88ab005d9b53c2e2f2f2dde66b14e78c7647b8d

RUN pacman -Syyu --noconfirm --needed \
    base-devel git sudo wget cmake python meson ninja \
    ffmpeg gstreamer gst-plugins-base-libs \
    libpulse lib32-libpulse \
    mingw-w64-gcc mingw-w64-binutils mingw-w64-crt mingw-w64-headers \
    rust lib32-rust-libs vulkan-headers \
    fontforge python-fonttools unzip curl ccache \
    lib32-glibc lib32-gcc-libs lib32-libx11 lib32-vulkan-icd-loader \
    lib32-wayland lib32-libxkbcommon sdl2 lib32-sdl2 \
    glu libxmu openal libxslt glib2-devel gst-plugins-good samba opencl-headers alsa-plugins dosbox \
    schedtool python-pefile gst-plugins-ugly libxpresent yasm jq lib32-attr lib32-lcms2 lib32-libxrandr \
    lib32-libxdamage lib32-gettext lib32-glu lib32-libsm lib32-libpcap lib32-giflib lib32-libxinerama \
    lib32-libxcomposite lib32-libxmu lib32-mpg123 lib32-openal lib32-v4l-utils lib32-libxslt lib32-gtk3 \
    lib32-ocl-icd lib32-alsa-plugins && \
    pacman -U --noconfirm --nodeps \
    "https://archive.archlinux.org/repos/2026/03/30/multilib/os/x86_64/lib32-gstreamer-1.28.1-3-x86_64.pkg.tar.zst" \
    "https://archive.archlinux.org/repos/2026/03/30/multilib/os/x86_64/lib32-gst-plugins-base-1.28.1-3-x86_64.pkg.tar.zst" \
    "https://archive.archlinux.org/repos/2026/03/30/multilib/os/x86_64/lib32-gst-plugins-base-libs-1.28.1-3-x86_64.pkg.tar.zst" \
    "https://archive.archlinux.org/repos/2026/03/30/multilib/os/x86_64/lib32-gst-plugins-good-1.24.1-1-x86_64.pkg.tar.zst" && \
    pacman -Scc --noconfirm && rm -rf /var/lib/pacman/sync/* && \
    useradd -m -G wheel builder && \
    echo "%wheel ALL=(ALL) NOPASSWD: ALL" > /etc/sudoers.d/builder && \
    chmod 0440 /etc/sudoers.d/builder

WORKDIR /src

RUN git init && \
    git remote add origin https://github.com/Frogging-Family/wine-tkg-git.git && \
    git fetch --depth 1 origin "${COMMIT_HASH}" && \
    git checkout FETCH_HEAD 

ENV BUILDDIR=/build