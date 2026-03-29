#!/bin/bash
set -e

KERNEL_BRANCH="${KERNEL_BRANCH:-rpi-6.18.y}"
KERNEL_REPO="https://github.com/raspberrypi/linux.git"
IMAGE_NAME="rpi-kernel-builder"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# Clone kernel source if not present
if [ ! -d "${SCRIPT_DIR}/linux" ]; then
    echo "=== Cloning kernel source (${KERNEL_BRANCH}) ==="
    git clone --branch "${KERNEL_BRANCH}" --depth=1 "${KERNEL_REPO}" "${SCRIPT_DIR}/linux"
fi

# Apply patches
if [ -d "${SCRIPT_DIR}/patches" ]; then
    echo "=== Applying patches ==="
    for p in "${SCRIPT_DIR}/patches/"*.patch; do
        echo "  Applying $(basename "$p")"
        git -C "${SCRIPT_DIR}/linux" apply "$p"
    done
fi

# Build the Docker image (x86_64 for cross-compilation)
echo "=== Building Docker image ==="
docker build --platform linux/amd64 -t "${IMAGE_NAME}" "${SCRIPT_DIR}"

# Run the kernel build
echo "=== Starting kernel build ==="
mkdir -p "${SCRIPT_DIR}/output"
docker run --rm --platform linux/amd64 \
    -v "${SCRIPT_DIR}/linux:/build/linux" \
    -v "${SCRIPT_DIR}/output:/output" \
    "${IMAGE_NAME}"

echo "=== Done. Packages in ${SCRIPT_DIR}/output/ ==="
ls -lh "${SCRIPT_DIR}/output/"
