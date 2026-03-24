# Raspberry Pi Kernel Builder — Raspbian Trixie (rpi-6.18.y)
#
# Builds the full RPi kernel with ath12k, r8169 (RTL8125B), KVM, and virtio support,
# producing installable .deb packages.
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

WORKDIR /build/linux

CMD set -ex && \
    # ── Configure kernel ─────────────────────────────────────────── \
    make ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu- ${DEFCONFIG} && \
    # Enable ath12k (Qualcomm WiFi 7 / WiFi 6E) and dependencies \
    scripts/config \
        --module CFG80211 \
        --module MAC80211 \
        --enable QRTR \
        --module QRTR_MHI \
        --enable MHI_BUS \
        --enable MHI_BUS_PCI_GENERIC \
        --module ATH12K && \
    # Ensure r8169 is modular (in-tree driver covers RTL8125B) \
    scripts/config --module R8169 && \
    # KVM hypervisor support \
    scripts/config \
        --enable VIRTUALIZATION \
        --enable KVM \
        --enable VHOST_NET \
        --enable VHOST_VSOCK && \
    # Virtio guest/host drivers \
    scripts/config \
        --enable VIRTIO \
        --enable VIRTIO_PCI \
        --enable VIRTIO_MMIO \
        --module VIRTIO_NET \
        --module VIRTIO_BLK \
        --module VIRTIO_SCSI \
        --module VIRTIO_CONSOLE \
        --module VIRTIO_BALLOON \
        --module VIRTIO_INPUT \
        --module VIRTIO_FS && \
    # VM sockets and 9P file sharing \
    scripts/config \
        --module VSOCK \
        --module NET_9P_VIRTIO \
        --module VIRTIO_GPU \
        --enable IRQ_BYPASS && \
    # VFIO for PCIe device passthrough to VMs \
    scripts/config \
        --enable VFIO \
        --enable VFIO_PCI \
        --enable VFIO_IOMMU_TYPE1 \
        --enable IOMMU_SUPPORT \
        --enable ARM_SMMU_V3 && \
    # Resolve all kconfig dependencies \
    make ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu- olddefconfig && \
    # Verify configs \
    grep 'CONFIG_ATH12K' .config && \
    grep 'CONFIG_R8169' .config && \
    grep 'CONFIG_KVM=y' .config && \
    grep 'CONFIG_VFIO=y' .config && \
    grep 'CONFIG_VIRTIO=y' .config && \
    # ── Build full kernel as .deb packages ───────────────────────── \
    make -j$(nproc) ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu- \
        LOCALVERSION=-rpi-trixie \
        KDEB_PKGVERSION=1~rpi~trixie \
        "DPKG_FLAGS=-d -j$(nproc)" \
        bindeb-pkg && \
    # ── Collect artifacts ────────────────────────────────────────── \
    mkdir -p /output && \
    mv /build/*.deb /output/ && \
    echo "=== Build complete. Artifacts in /output/ ==="
