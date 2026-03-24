# spr-debian-kernel

Raspberry Pi kernel builder for Raspbian Trixie (rpi-6.18.y).

Cross-compiles the full kernel with the following enabled on top of `bcm2712_defconfig`:
- ath12k (Qualcomm WiFi 7 / WiFi 6E)
- r8169 (RTL8125B 2.5GbE)
- KVM + VFIO (PCIe passthrough)
- Virtio (net, blk, scsi, fs, gpu, vsock, 9p)

## Build locally

```bash
./build.sh
```

## CI build

Push a tag to trigger the GitHub Actions workflow:

```bash
git tag v6.18.18-1
git push origin v6.18.18-1
```

The workflow builds the kernel on a self-hosted runner and publishes the `.deb` packages as a GitHub release. A `latest` release is also maintained for automated consumption:

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
