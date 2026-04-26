FROM archlinux@sha256:5ba8bb318666baef4d33afefc0e65db80f38b23503cb8e7b150d315cc2d4d5da AS cachyos-base

RUN pacman -Syy --noconfirm --needed curl git && \
    pacman-key --init && \
    mkdir -p /tmp/cachyos-setup && cd /tmp/cachyos-setup && \
    git init && \
    git remote add origin https://github.com/CachyOS/cachyos-repo-add-script.git && \
    git fetch --depth 1 origin 063f193f1983df869e1884466b84d8fa13e5fce5 && \
    git checkout FETCH_HEAD && \
    yes | ./cachyos-repo.sh && \
    echo -e "\n[multilib]\nInclude = /etc/pacman.d/mirrorlist" >> /etc/pacman.conf && \
    pacman -Syu --noconfirm cachyos-keyring archlinux-keyring
    
FROM cachyos-base

RUN pacman -Syu --noconfirm && \
    pacman -S --noconfirm dav1d x265 stress-ng time ffmpeg sysbench p7zip \
    git make gcc rt-tests

RUN mkdir -p /tmp/schbench && cd /tmp/schbench && \
    git init && \
    git remote add origin https://git.kernel.org/pub/scm/linux/kernel/git/mason/schbench.git && \
    git fetch --depth 1 origin 6300b8f3a8922c61ea6bb2cdfa1901a42c0cc6fc && \
    git checkout FETCH_HEAD && \
    make && cp schbench /usr/local/bin/ && rm -rf /tmp/schbench

RUN ffmpeg -f lavfi -i testsrc=duration=30:size=1920x1080:rate=60 -pix_fmt yuv420p -c:v rawvideo /test.y4m && \
    ffmpeg -i /test.y4m -c:v libaom-av1 -cpu-used 8 /test.ivf