FROM archlinux@sha256:5ba8bb318666baef4d33afefc0e65db80f38b23503cb8e7b150d315cc2d4d5da AS cachyos-base

RUN pacman -Syy --noconfirm --needed curl && \
    pacman-key --init && \
    curl -L https://mirror.cachyos.org/cachyos-repo.tar.xz | tar xJ && \
    cd cachyos-repo && \
    yes | ./cachyos-repo.sh && \
    echo -e "\n[multilib]\nInclude = /etc/pacman.d/mirrorlist" >> /etc/pacman.conf && \
    pacman -Syu --noconfirm cachyos-keyring archlinux-keyring
    
FROM cachyos-base

ARG COMMIT_HASH=1c61dfd1c3ad7762faa0db8b06c6af6c59cc4340

RUN pacman -Syyu --noconfirm --needed \
    base-devel git sudo wget bc cpio pahole xmlto kmod libelf python-sphinx pacman-contrib \
    rust rust-bindgen rust-src ncurses llvm \
    && pacman -Scc --noconfirm \
    && rm -rf /var/lib/pacman/sync/* && \
    useradd -m -G wheel builder && \
    echo "%wheel ALL=(ALL) NOPASSWD: ALL" > /etc/sudoers.d/builder && \
    chmod 0440 /etc/sudoers.d/builder

WORKDIR /src

RUN git init && \
    git remote add origin https://github.com/CachyOS/linux-cachyos.git && \
    git fetch --depth 1 origin "${COMMIT_HASH}" && \
    git checkout FETCH_HEAD && \
    cd linux-cachyos && \
    sed -i 's/_cpusched:=[^}]*/_cpusched:=bore/' PKGBUILD && \
    sed -i 's/: "${_processor_opt:=}"/: "${_processor_opt:=native}"/' PKGBUILD && \
    sed -i 's/_use_llvm_lto:=[^}]*/_use_llvm_lto:=full/' PKGBUILD && \
    sed -i 's/_use_lto_suffix:=[^}]*/_use_lto_suffix:=yes/' PKGBUILD && \
    sed -i 's/_build_nvidia_open:=[^}]*/_build_nvidia_open:=yes/' PKGBUILD && \
    sed -i 's/: "${_autofdo:=no}"/: "${_autofdo:=yes}"/' PKGBUILD && \
    sed -i 's/: "${_autofdo_profile_name:=}"/: "${_autofdo_profile_name:=kernel.afdo}"/' PKGBUILD && \
    sed -i 's/: "${_propeller:=no}"/: "${_propeller:=yes}"/' PKGBUILD && \
    sed -i 's/: "${_propeller_profiles:=no}"/: "${_propeller_profiles:=yes}"/' PKGBUILD && \
    sed -i -E 's/_pkgsuffix=cachyos([-a-z]*)/_pkgsuffix="cachyos-${_cpusched}\1"/g' PKGBUILD && \
    sed -i "s/pkgdesc='Linux EEVDF/pkgdesc='Linux BORE/" PKGBUILD && \
    sed -i 's/linux-cachyos-lto/linux-cachyos-bore-lto/g' PKGBUILD

COPY conf/kernel.afdo linux-cachyos/
COPY conf/propeller_cc_profile.txt linux-cachyos/
COPY conf/propeller_ld_profile.txt linux-cachyos/

ENV LLVM=1 \
    LLVM_IAS=1 \
    BUILDDIR=/build