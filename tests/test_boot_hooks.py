"""Boot-file and Debian package regression tests; no kernel build required.

Run on Linux with python3, dpkg, dpkg-deb and coreutils installed:
    python3 -m unittest discover -s tests -v
"""
import hashlib
import os
from pathlib import Path
import subprocess
import tempfile
import unittest


REPO = Path(__file__).resolve().parents[1]
PI4 = "6.18.60-v8+"
PI5 = "6.18.60-v8-16k+"


def run(*args, **kwargs):
    return subprocess.run(args, text=True, capture_output=True, check=True, **kwargs)


class BootHooksTest(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.boot = self.root / "boot/firmware"
        self.boot.mkdir(parents=True)
        (self.boot / "config.txt").write_text("[all]\nauto_initramfs=1\n# custom settings\n")

    def kernel(self, version):
        dtbs = self.root / f"usr/lib/linux-image-{version}"
        (dtbs / "broadcom").mkdir(parents=True)
        (dtbs / "overlays").mkdir()
        for board in ("bcm2711-rpi-4-b", "bcm2712-rpi-5-b", "bcm2712-rpi-cm5-cm5io"):
            (dtbs / f"broadcom/{board}.dtb").write_text(f"{board}: {version}")
        for name in ("test.dtbo", "overlay_map.dtb", "README"):
            (dtbs / f"overlays/{name}").write_text(version)
        for name in ("vmlinuz", "initrd.img"):
            (self.root / f"boot/{name}-{version}").write_text(f"{name}: {version}")
        pages = "16K" if "-16k" in version else "4K"
        (self.root / f"boot/config-{version}").write_text(f"CONFIG_ARM64_{pages}_PAGES=y\n")
        (self.root / f"lib/modules/{version}").mkdir(parents=True)
        return dtbs

    def sync(self, version):
        return run("bash", str(REPO / "packaging/spr-update-boot"), version, str(self.root))

    def assert_boot(self, version, image, initramfs):
        self.assertEqual((self.boot / image).read_bytes(),
                         (self.root / f"boot/vmlinuz-{version}").read_bytes())
        self.assertEqual((self.boot / initramfs).read_bytes(),
                         (self.root / f"boot/initrd.img-{version}").read_bytes())

    def test_pi5_kernel_initramfs_device_trees_and_overlays(self):
        self.kernel(PI5)
        (self.boot / "overlays").mkdir()
        (self.boot / "overlays/custom.dtbo").write_text("keep")
        config = (self.boot / "config.txt").read_bytes()
        self.sync(PI5)
        self.assert_boot(PI5, "kernel_2712.img", "initramfs_2712")
        self.assertTrue((self.boot / "bcm2712-rpi-cm5-cm5io.dtb").is_file())
        self.assertFalse((self.boot / "bcm2711-rpi-4-b.dtb").exists())
        self.assertEqual((self.boot / "overlays/overlay_map.dtb").read_text(), PI5)
        self.assertEqual((self.boot / "overlays/README").read_text(), PI5)
        self.assertEqual((self.boot / "overlays/custom.dtbo").read_text(), "keep")
        self.assertEqual((self.boot / "config.txt").read_bytes(), config)
        self.assertFalse(list(self.boot.glob(".spr-kernel.*")))

    def test_pi4_and_pi5_coexist_in_either_install_order(self):
        # A multi-package dpkg transaction unpacks both before configuring.
        self.kernel(PI4)
        self.kernel(PI5)
        for order in ((PI4, PI5), (PI5, PI4)):
            with self.subTest(order=order):
                for version in order:
                    self.sync(version)
                self.assert_boot(PI4, "kernel8.img", "initramfs8")
                self.assert_boot(PI5, "kernel_2712.img", "initramfs_2712")
                self.assertTrue((self.boot / "bcm2711-rpi-4-b.dtb").is_file())
                self.assertEqual((self.boot / "overlays/test.dtbo").read_text(), PI5)

    def test_initramfs_regeneration_updates_firmware_copy(self):
        self.kernel(PI5)
        self.sync(PI5)
        (self.root / f"boot/initrd.img-{PI5}").write_text("regenerated with new modules")
        self.sync(PI5)
        self.assert_boot(PI5, "kernel_2712.img", "initramfs_2712")

    def test_old_kernel_does_not_downgrade_boot_files(self):
        old = "6.18.59-v8-16k+"
        self.kernel(old)
        self.kernel(PI5)
        self.sync(PI5)
        self.sync(old)
        self.assert_boot(PI5, "kernel_2712.img", "initramfs_2712")
        self.assertEqual((self.boot / "overlays/test.dtbo").read_text(), PI5)

    def test_older_other_flavour_does_not_downgrade_shared_overlays(self):
        old_pi5 = "6.18.59-v8-16k+"
        self.kernel(PI4)
        self.kernel(old_pi5)
        self.sync(PI4)
        self.sync(old_pi5)
        self.assert_boot(old_pi5, "kernel_2712.img", "initramfs_2712")
        self.assert_boot(PI4, "kernel8.img", "initramfs8")
        self.assertEqual((self.boot / "overlays/test.dtbo").read_text(), PI4)

    def test_missing_initramfs_preserves_previous_boot_files(self):
        self.kernel(PI5)
        (self.boot / "kernel_2712.img").write_text("previous kernel")
        (self.boot / "initramfs_2712").write_text("previous initramfs")
        (self.root / f"boot/initrd.img-{PI5}").unlink()
        with self.assertRaises(subprocess.CalledProcessError) as error:
            self.sync(PI5)
        self.assertIn("missing initramfs", error.exception.stderr)
        self.assertEqual((self.boot / "kernel_2712.img").read_text(), "previous kernel")
        self.assertEqual((self.boot / "initramfs_2712").read_text(), "previous initramfs")

    def test_wrong_page_size_fails_before_writing_firmware(self):
        self.kernel(PI4)
        (self.root / f"boot/config-{PI4}").write_text("CONFIG_ARM64_16K_PAGES=y\n")
        with self.assertRaises(subprocess.CalledProcessError):
            self.sync(PI4)
        self.assertFalse((self.boot / "kernel8.img").exists())

    def test_copy_failure_keeps_previous_kernel_and_initramfs(self):
        self.kernel(PI5)
        (self.boot / "kernel_2712.img").write_text("previous kernel")
        (self.boot / "initramfs_2712").write_text("previous initramfs")
        commands = self.root / "test-bin"
        commands.mkdir()
        copy = commands / "cp"
        copy.write_text('#!/bin/sh\ncase "$1" in */initrd.img-*) exit 1;; esac\nexec /bin/cp "$@"\n')
        copy.chmod(0o755)
        with self.assertRaises(subprocess.CalledProcessError):
            run("bash", str(REPO / "packaging/spr-update-boot"), PI5, str(self.root),
                env={**os.environ, "PATH": str(commands) + ":" + os.environ["PATH"]})
        self.assertEqual((self.boot / "kernel_2712.img").read_text(), "previous kernel")
        self.assertEqual((self.boot / "initramfs_2712").read_text(), "previous initramfs")
        self.assertFalse(list(self.boot.glob(".spr-kernel.*")))

    def test_missing_device_trees_fails_before_writing_firmware(self):
        dtbs = self.kernel(PI4)
        (dtbs / "broadcom/bcm2711-rpi-4-b.dtb").unlink()
        with self.assertRaises(subprocess.CalledProcessError):
            self.sync(PI4)
        self.assertFalse((self.boot / "kernel8.img").exists())


class PackagingTest(unittest.TestCase):
    def test_both_debs_have_owned_executable_hooks_and_dependencies(self):
        with tempfile.TemporaryDirectory() as work:
            work = Path(work)
            manifests = []
            for version in (PI4, PI5):
                pkg = work / version
                (pkg / "DEBIAN").mkdir(parents=True)
                (pkg / f"usr/lib/linux-image-{version}").mkdir(parents=True)
                (pkg / "DEBIAN/control").write_text(
                    f"Package: linux-image-{version}\nVersion: 1~rpi~trixie\n"
                    "Architecture: arm64\nMaintainer: SPR <test@example.com>\n"
                    "Description: test kernel fixture\n"
                )
                postinst = "#!/bin/sh\n# existing upstream maintainer script\nexit 0\n"
                (pkg / "DEBIAN/postinst").write_text(postinst)
                (pkg / "DEBIAN/postinst").chmod(0o755)
                deb = work / f"{version}.deb"
                run("dpkg-deb", "--root-owner-group", "--build", str(pkg), str(deb))
                run("bash", str(REPO / "packaging/add-boot-hooks.sh"), str(deb))
                self.assertEqual(run("dpkg-deb", "-f", str(deb), "Depends").stdout.strip(),
                                 "initramfs-tools, kmod")
                extracted = work / f"extracted-{version}"
                run("dpkg-deb", "--raw-extract", str(deb), str(extracted))
                self.assertEqual((extracted / "DEBIAN/postinst").read_text(), postinst)
                helper = extracted / f"usr/lib/linux-image-{version}/spr-update-boot"
                self.assertTrue(os.access(helper, os.X_OK))
                self.assertEqual(helper.read_bytes(), (REPO / "packaging/spr-update-boot").read_bytes())
                for directory in ("etc/kernel/postinst.d", "etc/initramfs/post-update.d"):
                    hooks = run("run-parts", "--test", str(extracted / directory)).stdout.splitlines()
                    self.assertEqual(len(hooks), 1)
                    self.assertIn(f'exec "/usr/lib/linux-image-{version}/spr-update-boot" "{version}"',
                                  Path(hooks[0]).read_text())
                    # A hook belonging to another version must be a no-op.
                    run(hooks[0], "6.12.47+rpt-rpi-2712")
                    # Abort/remove paths must not try to install boot files.
                    for action in ("abort-upgrade", "remove", "'abort-upgrade'"):
                        run(hooks[0], version, env={**os.environ, "DEB_MAINT_PARAMS": action})
                checksums = (extracted / "DEBIAN/md5sums").read_text().splitlines()
                self.assertEqual(len(checksums), 3)
                for line in checksums:
                    digest, filename = line.split(maxsplit=1)
                    self.assertEqual(digest, hashlib.md5((extracted / filename).read_bytes()).hexdigest())
                manifests.append({str(p.relative_to(extracted)) for p in extracted.rglob("*")
                                  if p.is_file() and "DEBIAN" not in p.parts})
            self.assertFalse(manifests[0] & manifests[1], "Pi 4 and Pi 5 packages must not own the same files")


if __name__ == "__main__":
    unittest.main()
