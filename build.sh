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

# Build the Docker image
echo "=== Building Docker image ==="
docker build -t "${IMAGE_NAME}" "${SCRIPT_DIR}"

# Run the kernel build
echo "=== Starting kernel build ==="
mkdir -p "${SCRIPT_DIR}/output"
docker run --rm \
    -v "${SCRIPT_DIR}/linux:/build/linux" \
    -v "${SCRIPT_DIR}/output:/output" \
    "${IMAGE_NAME}"

echo "=== Done. Packages in ${SCRIPT_DIR}/output/ ==="
ls -lh "${SCRIPT_DIR}/output/"
