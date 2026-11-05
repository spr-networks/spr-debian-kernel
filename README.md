# spr-debian-kernel

Raspberry Pi kernel builder for Raspbian Trixie (rpi-6.18.y, 6.18.60).

Cross-compiles the full kernel with the following enabled on top of `bcm2712_defconfig`:
- ath12k (Qualcomm WiFi 7 / WiFi 6E)
- r8169 (RTL8125B 2.5GbE)
- MACsec (`CONFIG_MACSEC=m`)
- KVM + VFIO (PCIe passthrough)
- Virtio (net, blk, scsi, fs, vsock, 9p)

Revision `v6.18.60-3` also enables mac80211/cfg80211 debugfs and patches
mt7996 TX status handling so fixed-rate frames do not overwrite the cached
station rate used for airtime estimates. It includes the boot-update hooks
described below.

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
to Raspberry Pi commit `a4985478de14b3a83c8e04fed68377c1bdae735d` so a
release tag always builds the same kernel version.

## CI build

Push a tag to trigger the GitHub Actions workflow:

```bash
git tag v6.18.60-3
git push origin v6.18.60-3
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
sudo apt install ./linux-image-*.deb ./linux-headers-*.deb
sudo reboot
```

Image packages include SPR kernel-postinst and initramfs-post-update hooks.
On installation and `update-initramfs` regeneration they copy the kernel,
matching initramfs, board device trees, and overlays into `/boot/firmware`:

| Package flavour | Firmware kernel | Firmware initramfs |
| --- | --- | --- |
| Pi 4 (`-v8+`, 4 KB) | `kernel8.img` | `initramfs8` |
| Pi 5 / CM5 (`-v8-16k+`, 16 KB) | `kernel_2712.img` | `initramfs_2712` |

Raspberry Pi OS's `raspi-firmware` hooks recognize `-rpi-` kernel flavours;
they may still print an unsupported-version warning for SPR kernels. The
separate SPR hooks handle these versions without modifying distro hooks or
changing module/DKMS paths. Older initramfs updates do not replace a newer
installed kernel of the same flavour. The two flavours own separate hook
files and can be installed together.

The firmware partition must be mounted when updating a running Pi. Existing
`config.txt` settings are preserved: they must select the filenames above
and the matching initramfs (normally `auto_initramfs=1`, as in SPR images).
The hooks preserve custom overlay files and copy `overlay_map.dtb` when
provided by the kernel package.

These hooks are included in newly built packages at Debian package revision
`3~rpi~trixie`, so they upgrade earlier package revisions even when
the kernel version is unchanged. Previously published debs are unchanged.
After installing a package containing the fix, verify the
firmware image before rebooting, using the installed version rather than
`uname -r` (which still reports the running kernel):

```bash
KVER=6.18.60-v8-16k+
cmp "/boot/vmlinuz-$KVER" /boot/firmware/kernel_2712.img
cmp "/boot/initrd.img-$KVER" /boot/firmware/initramfs_2712
```

Boot integration regression tests run when building the builder image. They
can also run independently on Linux without compiling the kernel:

```bash
python3 -m unittest discover -s tests -v
```
