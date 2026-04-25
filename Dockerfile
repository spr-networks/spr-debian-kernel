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
    make ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu- hardening.config && \
    ./scripts/kconfig/merge_config.sh -m .config /spr.config && \
    make ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu- olddefconfig && \
    # Verify key configs \
    grep 'CONFIG_MT7915E=m' .config && \
    grep 'CONFIG_R8169=m' .config && \
    grep 'CONFIG_BRCMFMAC_AP_VLAN=y' .config && \
    grep 'CONFIG_KVM=y' .config && \
    grep 'CONFIG_VFIO=y' .config && \
    grep 'CONFIG_VIRTIO=y' .config && \
    # ── Build full kernel as .deb packages ───────────────────────── \
    make -j$(nproc) ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu- \
        KDEB_PKGVERSION=1~rpi~trixie \
        "DPKG_FLAGS=-d -j$(nproc)" \
        bindeb-pkg && \
    # ── Build ath12k out-of-tree from kvalo/ath main ─────────────── \
    KVER=$(cat include/config/kernel.release) && \
    ATH12K_SRC=/build/ath/drivers/net/wireless/ath/ath12k && \
    make -j$(nproc) ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu- \
        M=$ATH12K_SRC \
        CONFIG_ATH12K=m \
        CONFIG_ATH12K_DEBUGFS=y \
        CONFIG_ATH12K_TRACING=y \
        modules && \
    # ── Package ath12k.ko as a separate .deb ─────────────────────── \
    ATH12K_STAGE=/tmp/ath12k-module && \
    ATH12K_VERSION="1.0-kvalo-main~rpi~trixie" && \
    rm -rf "$ATH12K_STAGE" && \
    mkdir -p "$ATH12K_STAGE/lib/modules/$KVER/updates" "$ATH12K_STAGE/DEBIAN" && \
    cp $ATH12K_SRC/ath12k.ko "$ATH12K_STAGE/lib/modules/$KVER/updates/" && \
    aarch64-linux-gnu-strip --strip-debug "$ATH12K_STAGE/lib/modules/$KVER/updates/ath12k.ko" && \
    printf 'Package: ath12k-module-%s\nVersion: %s\nSection: kernel\nPriority: optional\nArchitecture: arm64\nMaintainer: SPR <build@supernetworks.org>\nDescription: Out-of-tree ath12k driver from kvalo/ath (main)\n Built from git.codelinaro.org/clo/qsdk/kvalo/ath branch korg-kvalo/main.\n' "$KVER" "$ATH12K_VERSION" > "$ATH12K_STAGE/DEBIAN/control" && \
    printf '#!/bin/sh\nset -e\ndepmod -a %s\n' "$KVER" > "$ATH12K_STAGE/DEBIAN/postinst" && \
    chmod 755 "$ATH12K_STAGE/DEBIAN/postinst" && \
    dpkg-deb --build "$ATH12K_STAGE" /build/ath12k-module-${KVER}_${ATH12K_VERSION}_arm64.deb && \
    # ── Collect artifacts ────────────────────────────────────────── \
    mkdir -p /output && \
    mv /build/*.deb /output/ && \
    echo "=== Build complete. Artifacts in /output/ ==="
