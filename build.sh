#!/bin/bash
set -e

KERNEL_BRANCH="${KERNEL_BRANCH:-rpi-6.18.y}"
KERNEL_REPO="https://github.com/raspberrypi/linux.git"
IMAGE_NAME="rpi-kernel-builder"
SRC_VOLUME="${SRC_VOLUME:-kernel-src}"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PLATFORM="${PLATFORM:-linux/$(docker version --format '{{.Server.Arch}}')}"

docker volume create "${SRC_VOLUME}" >/dev/null

# Build the Docker image
echo "=== Building Docker image (${PLATFORM}) ==="
docker build --platform "${PLATFORM}" -t "${IMAGE_NAME}" "${SCRIPT_DIR}"

# Clone kernel source if not present
echo "=== Preparing kernel source (${KERNEL_BRANCH}) ==="
docker run --rm --platform "${PLATFORM}" \
    -v "${SRC_VOLUME}:/build/linux" \
    -v "${SCRIPT_DIR}/patches:/patches:ro" \
    -w /build/linux \
    --entrypoint bash "${IMAGE_NAME}" -c '
set -e
if [ ! -d .git ]; then
    git clone --branch "'"${KERNEL_BRANCH}"'" --depth=1 "'"${KERNEL_REPO}"'" .
else
    git fetch --depth=1 origin "'"${KERNEL_BRANCH}"'"
fi
git reset --hard FETCH_HEAD 2>/dev/null || git reset --hard origin/"'"${KERNEL_BRANCH}"'"
echo "  Kernel version: $(make kernelversion)"
# Apply patches
for p in /patches/*.patch; do
    echo "  Applying $(basename "$p")"
    git apply "$p"
done
'

# Run the kernel build
echo "=== Starting kernel build ==="
mkdir -p "${SCRIPT_DIR}/output"
docker run --rm --platform "${PLATFORM}" \
    -v "${SRC_VOLUME}:/build/linux" \
    -v "${SCRIPT_DIR}/output:/output" \
    "${IMAGE_NAME}"

echo "=== Done. Packages in ${SCRIPT_DIR}/output/ ==="
ls -lh "${SCRIPT_DIR}/output/"
