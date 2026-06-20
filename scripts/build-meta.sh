#!/usr/bin/env bash
set -Eeuo pipefail
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
. "$SCRIPT_DIR/lib.sh"
version= out_dir=dist/debian maintainer='STM32MP257 TSN Packaging <noreply@example.invalid>' with_userspace=false with_acm=false
while [[ $# -gt 0 ]]; do
  case "$1" in
    --version) version=$2; shift 2;;
    --out) out_dir=$2; shift 2;;
    --maintainer) maintainer=$2; shift 2;;
    --with-userspace) with_userspace=$2; shift 2;;
    --with-acm) with_acm=$2; shift 2;;
    -h|--help) exit 0;;
    *) die "unknown argument: $1";;
  esac
done
[[ -n "$version" ]] || die '--version is required'
valid_version "$version"; valid_bool "$with_userspace"; valid_bool "$with_acm"
need dpkg-deb
work="$(mktemp -d)"; trap 'rm -rf "$work"' EXIT
mkdir -p "$out_dir"
make_meta() {
  local package=$1 depends=$2 description=$3 root
  root="$work/$package"
  mkdir -p "$root/DEBIAN"
  write_control "$root/DEBIAN/control" "$package" "${version}-1" all "$depends" "$description" "$maintainer"
  build_deb "$root" "$out_dir/${package}_${version}-1_all.deb"
}
base="stm32mp257-tsn-deip-dkms (= ${version}-1), stm32mp257-tsn-edge-dkms (= ${version}-1), stm32mp257-tsn-edge-runtime (= ${version}-1)"
if [[ "$with_userspace" == true ]]; then
  base+=", stm32mp257-tsn-libtsn (= ${version}-1), stm32mp257-tsntool (= ${version}-1), stm32mp257-tsn-deptp (= ${version}-1)"
fi
make_meta stm32mp257-tsn-switch "$base" 'STM32MP257 Ethernet Switch / TSN stack'
if [[ "$with_acm" == true ]]; then
  acm="stm32mp257-tsn-switch (= ${version}-1), stm32mp257-tsn-acm-dkms (= ${version}-1), stm32mp257-tsn-acm-runtime (= ${version}-1)"
  [[ "$with_userspace" == true ]] && acm+=", stm32mp257-tsn-acm-config (= ${version}-1)"
  make_meta stm32mp257-tsn-acm "$acm" 'STM32MP257 TSN Acceleration Module stack'
fi
