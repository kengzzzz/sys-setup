FROM archlinux@sha256:5ba8bb318666baef4d33afefc0e65db80f38b23503cb8e7b150d315cc2d4d5da

RUN pacman -Syu --noconfirm && \
    pacman -S --noconfirm --needed \
      archlinux-keyring bash coreutils dav1d ffmpeg fio gcc git jq make openssl p7zip python \
      rt-tests stress-ng sysbench time x265 zstd && \
    pacman -Scc --noconfirm

RUN mkdir -p /tmp/schbench && \
    cd /tmp/schbench && \
    git init && \
    git remote add origin https://git.kernel.org/pub/scm/linux/kernel/git/mason/schbench.git && \
    git fetch --depth 1 origin 6300b8f3a8922c61ea6bb2cdfa1901a42c0cc6fc && \
    git checkout FETCH_HEAD && \
    make && \
    cp schbench /usr/local/bin/schbench && \
    rm -rf /tmp/schbench

RUN ffmpeg -hide_banner -loglevel error \
      -f lavfi -i testsrc=duration=30:size=1920x1080:rate=60 \
      -pix_fmt yuv420p -c:v rawvideo /test.y4m && \
    ffmpeg -hide_banner -loglevel error \
      -i /test.y4m -c:v libaom-av1 -cpu-used 8 /test.ivf && \
    dd if=/dev/urandom of=/compress.bin bs=1M count=256 status=none

WORKDIR /benchmark

COPY scripts/ /scripts/

ENTRYPOINT ["/scripts/run-benchmark.sh"]
