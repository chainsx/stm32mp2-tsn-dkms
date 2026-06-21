#!/usr/bin/env bash
set -Eeuo pipefail
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
. "$SCRIPT_DIR/lib.sh"

version= revision=1 out_dir=dist/debian
maintainer='STM32MP257 TSN Packaging <noreply@example.invalid>' with_userspace=false with_acm=false
usage() {
  cat <<USAGE
Usage: $0 --version VERSION [options]
  --revision N              Debian package revision, default: 1
  --out DIR
  --maintainer VALUE
  --with-userspace true|false
  --with-acm true|false
USAGE
}
while [[ $# -gt 0 ]]; do
  case "$1" in
    --version) version=$2; shift 2;;
    --revision) revision=$2; shift 2;;
    --out) out_dir=$2; shift 2;;
    --maintainer) maintainer=$2; shift 2;;
    --with-userspace) with_userspace=$2; shift 2;;
    --with-acm) with_acm=$2; shift 2;;
    -h|--help) usage; exit 0;;
    *) die "unknown argument: $1";;
  esac
done
[[ -n "$version" ]] || die '--version is required'
valid_version "$version"; valid_revision "$revision"; valid_bool "$with_userspace"; valid_bool "$with_acm"
need dpkg-deb
work="$(mktemp -d)"; trap 'rm -rf "$work"' EXIT
mkdir -p "$out_dir"
deb_ver="$(deb_version "$version" "$revision")"

make_meta() {
  local package=$1 depends=$2 description=$3 root
  root="$work/$package"
  mkdir -p "$root/DEBIAN" "$root/usr/share/doc/$package"
  write_debian13_preinst "$root/DEBIAN/preinst" "$package"
  cat > "$root/usr/share/doc/$package/README.Debian" <<DOC
This is a Debian GNU/Linux 13 arm64 meta-package. It does not install the
OpenSTLinux rootfs automation, sysrepo, Netopeer2, lldpd, or mstpd integration.
Install and configure those components separately only when the corresponding
board and network integration has been validated.
DOC
  write_control "$root/DEBIAN/control" "$package" "$deb_ver" arm64 "$depends" "$description" "$maintainer"
  build_deb "$root" "$out_dir/${package}_${deb_ver}_arm64.deb"
}

base="stm32mp257-tsn-deip-dkms (= ${deb_ver}), stm32mp257-tsn-edge-dkms (= ${deb_ver}), stm32mp257-tsn-edge-runtime (= ${deb_ver})"
if [[ "$with_userspace" == true ]]; then
  base+=", stm32mp257-tsn-libtsn (= ${deb_ver}), stm32mp257-tsntool (= ${deb_ver}), stm32mp257-tsn-deptp (= ${deb_ver})"
fi
make_meta stm32mp257-tsn-switch "$base" 'STM32MP257 Ethernet Switch / TSN base stack'
if [[ "$with_acm" == true ]]; then
  acm="stm32mp257-tsn-switch (= ${deb_ver}), stm32mp257-tsn-acm-dkms (= ${deb_ver}), stm32mp257-tsn-acm-runtime (= ${deb_ver})"
  [[ "$with_userspace" == true ]] && acm+=", stm32mp257-tsn-acm-config (= ${deb_ver})"
  make_meta stm32mp257-tsn-acm "$acm" 'STM32MP257 optional TSN Acceleration Module stack'
fi
