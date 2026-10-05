# spr-debian-kernel

Raspberry Pi kernel builder for Raspbian Trixie (rpi-6.18.y, 6.18.54).

Cross-compiles the full kernel with the following enabled on top of `bcm2712_defconfig`:
- ath12k (Qualcomm WiFi 7 / WiFi 6E)
- r8169 (RTL8125B 2.5GbE)
- KVM + VFIO (PCIe passthrough)
- Virtio (net, blk, scsi, fs, vsock, 9p)

## Build locally

```bash
./build.sh
```

Source is cloned into a Docker volume, not the working tree — 12 netfilter
sources differ only in case (`xt_DSCP.c` vs `xt_dscp.c`) and a case-insensitive
host filesystem like macOS APFS clobbers them. Builds for the host arch by
default; override with `PLATFORM=linux/amd64 ./build.sh`. The source is pinned
to Raspberry Pi commit `8946ad8626ecacee8a8a9cffa433a23f0b118dcd` so a
release tag always builds the same kernel version.

## CI build

Push a tag to trigger the GitHub Actions workflow:

```bash
git tag v6.18.54-1
git push origin v6.18.54-1
```

```
https://github.com/<org>/spr-debian-kernel/releases/download/latest/
```

## Output

- `linux-image-*.deb` — kernel + all modules
- `linux-headers-*.deb` — headers for out-of-tree module builds
- `linux-libc-dev-*.deb` — kernel headers for userspace

## Install on Pi

```bash
sudo dpkg -i linux-image-*.deb linux-headers-*.deb
sudo reboot
```
