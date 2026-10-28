# spr-debian-kernel

Raspberry Pi kernel builder for Raspbian Trixie (rpi-6.18.y, 6.18.59).

Cross-compiles the full kernel with the following enabled on top of `bcm2712_defconfig`:
- ath12k (Qualcomm WiFi 7 / WiFi 6E)
- r8169 (RTL8125B 2.5GbE)
- KVM + VFIO (PCIe passthrough)
- Virtio (net, blk, scsi, fs, vsock, 9p)

## Build locally

```bash
./build.sh
DEFCONFIG=bcm2711_defconfig SRC_VOLUME=kernel-src-pi4 \
  OUTPUT_DIR="$PWD/output/pi4" ./build.sh  # Pi 4, 4 KB pages
```

Source is cloned into a Docker volume, not the working tree — 12 netfilter
sources differ only in case (`xt_DSCP.c` vs `xt_dscp.c`) and a case-insensitive
host filesystem like macOS APFS clobbers them. Builds for the host arch by
default; override with `PLATFORM=linux/amd64 ./build.sh`. The source is pinned
to Raspberry Pi commit `b3495ea401d709af0701a85babcba5e3d788a602` so a
release tag always builds the same kernel version.

## CI build

Push a tag to trigger the GitHub Actions workflow:

```bash
git tag v6.18.59-1
git push origin v6.18.59-1
```

```
https://github.com/<org>/spr-debian-kernel/releases/download/latest/
```

The default 16 KB packages remain on the versioned and `latest` releases.
The 4 KB Pi 4 packages are published separately as a `pi4-<version-tag>`
prerelease and stored in `output/pi4/` for local builds.

## Output

- `linux-image-*.deb` — kernel + all modules
- `linux-headers-*.deb` — headers for out-of-tree module builds
- `linux-libc-dev-*.deb` — kernel headers for userspace

## Install on Pi 5

```bash
sudo dpkg -i linux-image-*.deb linux-headers-*.deb
sudo reboot
```
