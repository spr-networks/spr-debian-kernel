# Raspberry Pi Kernel Builder — Raspbian Trixie (rpi-6.18.y)
#
# Builds the full RPi kernel with SPR networking stack support:
#   ath12k, mt7915e/mt7916, r8169, KVM/VFIO, virtio, BPF, nftables
#
# Usage:
#   ./build.sh
#
# Build args:
#   DEFCONFIG — kernel defconfig (default: bcm2712_defconfig for Pi 5)
#               Use bcm2711_defconfig for Pi 4

FROM debian:trixie

ENV DEBIAN_FRONTEND=noninteractive

# ── Build dependencies ─────────────────────────────────────────────
RUN apt-get update && apt-get install -y --no-install-recommends \
    # Core build tools
    build-essential bc bison flex \
    # Kernel build deps
    libssl-dev libelf-dev libncurses-dev libdw-dev \
    kmod cpio rsync dwarves \
    # Cross-compilation toolchain (arm64)
    crossbuild-essential-arm64 \
    # Rust toolchain — required for modern production kernel builds
    rustc rust-src bindgen libclang-dev llvm \
    # Debian kernel packaging
    debhelper \
    # SCM & utilities
    git python3 wget curl ca-certificates xz-utils \
    && rm -rf /var/lib/apt/lists/*

ARG DEFCONFIG=bcm2712_defconfig
ENV DEFCONFIG=${DEFCONFIG}

COPY spr.config /spr.config

WORKDIR /build/linux

CMD set -ex && \
    # ── Merge defconfig with SPR config fragment ─────────────────── \
    make ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu- ${DEFCONFIG} && \
    ./scripts/kconfig/merge_config.sh -m .config /spr.config && \
    make ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu- olddefconfig && \
    # Verify key configs \
    grep 'CONFIG_ATH12K=m' .config && \
    grep 'CONFIG_MT7915E=m' .config && \
    grep 'CONFIG_R8169=m' .config && \
    grep 'CONFIG_KVM=y' .config && \
    grep 'CONFIG_VFIO=y' .config && \
    grep 'CONFIG_VIRTIO=y' .config && \
    # ── Build full kernel as .deb packages ───────────────────────── \
    make -j$(nproc) ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu- \
        KDEB_PKGVERSION=1~rpi~trixie \
        "DPKG_FLAGS=-d -j$(nproc)" \
        bindeb-pkg && \
    # ── Collect artifacts ────────────────────────────────────────── \
    mkdir -p /output && \
    mv /build/*.deb /output/ && \
    echo "=== Build complete. Artifacts in /output/ ==="
