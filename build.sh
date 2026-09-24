#!/bin/bash
set -e

KERNEL_REF="${KERNEL_REF:-d9e1735f53397e2f9f51b4215da341613f8f8b1b}"
EXPECTED_KERNEL_VERSION="${EXPECTED_KERNEL_VERSION:-6.18.53}"
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
echo "=== Preparing kernel source (${KERNEL_REF}) ==="
docker run --rm --platform "${PLATFORM}" \
    -v "${SRC_VOLUME}:/build/linux" \
    -v "${SCRIPT_DIR}/patches:/patches:ro" \
    -w /build/linux \
    -e KERNEL_REF="${KERNEL_REF}" \
    -e KERNEL_REPO="${KERNEL_REPO}" \
    -e EXPECTED_KERNEL_VERSION="${EXPECTED_KERNEL_VERSION}" \
    --entrypoint bash "${IMAGE_NAME}" -c '
set -e
if [ ! -d .git ]; then
    git init .
    git remote add origin "${KERNEL_REPO}"
fi
git fetch --depth=1 origin "${KERNEL_REF}"
git reset --hard FETCH_HEAD
actual_version=$(make kernelversion)
echo "  Kernel version: ${actual_version}"
test "${actual_version}" = "${EXPECTED_KERNEL_VERSION}"
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
