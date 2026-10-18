# spr-debian-kernel

Raspberry Pi kernel builder for Raspbian Trixie (rpi-6.18.y, 6.18.55).

Cross-compiles the full kernel with the following enabled on top of the
Raspberry Pi defconfig:
- ath12k (Qualcomm WiFi 7 / WiFi 6E)
- r8169 (RTL8125B 2.5GbE)
- KVM + VFIO (PCIe passthrough)
- Virtio (net, blk, scsi, fs, vsock, 9p)

## Build locally

```bash
./build.sh                              # Pi 5, 16 KB pages (output/16k)
DEFCONFIG=bcm2711_defconfig ./build.sh  # Pi 4, 4 KB pages (output/4k)
```

Each page-size build uses a separate Docker volume. Source is cloned into a
volume, not the working tree — 12 netfilter
sources differ only in case (`xt_DSCP.c` vs `xt_dscp.c`) and a case-insensitive
host filesystem like macOS APFS clobbers them. Builds for the host arch by
default; override with `PLATFORM=linux/amd64 ./build.sh`. The source is pinned
to Raspberry Pi commit `af73e0836bf0b6c0218a18131b9a975c319d8e2a` so a
release tag always builds the same kernel version.

## CI build

Push a tag to build both page sizes:

```bash
git tag v6.18.55-2
git push origin v6.18.55-2
```

```
https://github.com/spr-networks/spr-debian-kernel/releases/download/latest/
https://github.com/spr-networks/spr-debian-kernel/releases/tag/pi4-v6.18.55-2
```

The versioned release and the `latest` alias contain only the Pi 5 16 KB
packages. The separate `pi4-<version-tag>` prerelease contains the Pi 4 4 KB
packages. This keeps existing consumers of the latest release on 16 KB.

## Output

- `output/16k/linux-image-*.deb` — Pi 5 kernel + modules
- `output/4k/linux-image-*.deb` — Pi 4 kernel + modules
- Each output directory also has matching `linux-headers-*.deb` and
  `linux-libc-dev_*.deb` packages.

## Install on Pi

```bash
sudo dpkg -i output/4k/linux-image-*.deb output/4k/linux-headers-*.deb
# On Pi 5, use output/16k instead.
sudo reboot
```

The Pi 4 needs `kernel8.img` from the 4 KB package; Pi 5 uses
`kernel_2712.img` from the 16 KB package. An image supporting both boards must
install both kernels and place each image under the correct firmware filename.
