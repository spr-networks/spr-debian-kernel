#!/bin/bash
# Add boot integration to upstream bindeb-pkg's linux-image packages.
set -euo pipefail
script_dir=$(cd "$(dirname "$0")" && pwd)
test "$#" -gt 0 || { echo "usage: $0 <linux-image.deb> [...]" >&2; exit 1; }

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
for deb in "$@"; do
    package=$(dpkg-deb -f "$deb" Package)
    case "$package" in
        linux-image-*-dbg) continue ;;
        linux-image-*) kver=${package#linux-image-} ;;
        *) echo "unexpected kernel package: $package" >&2; exit 1 ;;
    esac
    [[ "$kver" =~ ^[0-9]+\.[0-9]+\.[0-9]+-v8(-16k)?\+$ ]] || {
        echo "unsupported SPR kernel package: $package" >&2
        exit 1
    }
    pkg="$work/$package"
    dpkg-deb --raw-extract "$deb" "$pkg"
    helper="/usr/lib/linux-image-$kver/spr-update-boot"
    install -m 755 "$script_dir/spr-update-boot" "$pkg$helper"

    # Per-version names avoid file ownership conflicts when two flavours or
    # several kernel releases are installed. Dots and '+' are not accepted
    # in run-parts names, so sanitize them; retain the exact version inside.
    hook="zz-spr-kernel-${kver//[.+]/_}"
    for dir in etc/kernel/postinst.d etc/initramfs/post-update.d; do
        mkdir -p "$pkg/$dir"
        cat > "$pkg/$dir/$hook" <<EOF
#!/bin/sh
set -e
[ "\${1-}" = "$kver" ] || exit 0
if [ -n "\${DEB_MAINT_PARAMS:-}" ]; then
    eval set -- "\$DEB_MAINT_PARAMS"
    [ "\${1-}" = configure ] || exit 0
fi
exec "$helper" "$kver"
EOF
        chmod 755 "$pkg/$dir/$hook"
    done

    # Generic bindeb-pkg omits this dependency. Its standard kernel hook
    # generates the initramfs before zz-spr-kernel synchronizes boot files.
    python3 - "$pkg/DEBIAN/control" <<'PY'
import pathlib, re, subprocess, sys
path = pathlib.Path(sys.argv[1])
control = path.read_text()
match = re.search(r'^Depends:([^\n]*(?:\n[ \t][^\n]*)*)', control, re.M)
if match:
    control = control[:match.start()] + 'Depends: initramfs-tools, kmod, ' + match[1].strip() + control[match.end():]
else:
    control = re.sub(r'^(Package:.*)$', r'\1\nDepends: initramfs-tools, kmod', control, count=1, flags=re.M)
size = subprocess.check_output(['du', '-sk', '--exclude=DEBIAN', str(path.parent.parent)], text=True).split()[0]
if re.search(r'^Installed-Size:', control, re.M):
    control = re.sub(r'^Installed-Size:.*$', 'Installed-Size: ' + size, control, flags=re.M)
else:
    control += 'Installed-Size: ' + size + '\n'
path.write_text(control)
PY
    # Refresh checksums after adding package-owned files, then publish only
    # the repacked deb. CI attestations are generated after this step.
    (cd "$pkg" && find . -type f ! -path './DEBIAN/*' -printf '%P\0' |
        sort -z | xargs -0 md5sum > DEBIAN/md5sums)
    dpkg-deb --root-owner-group --build "$pkg" "$work/repacked.deb"
    mv "$work/repacked.deb" "$deb"
done
