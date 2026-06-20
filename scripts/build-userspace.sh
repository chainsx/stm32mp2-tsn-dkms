#!/usr/bin/env bash
set -Eeuo pipefail
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
. "$SCRIPT_DIR/lib.sh"
ROOT="$(repo_root)"

source_dir= version= out_dir=dist/debian maintainer='STM32MP257 TSN Packaging <noreply@example.invalid>' with_acm=false
usage() {
  cat <<USAGE
Usage: $0 --source DIR --version VERSION [options]
  This script must run on an arm64 host/runner.
  --source DIR --version VERSION --out DIR --maintainer VALUE --with-acm true|false
USAGE
}
while [[ $# -gt 0 ]]; do
  case "$1" in
    --source) source_dir=$2; shift 2;;
    --version) version=$2; shift 2;;
    --out) out_dir=$2; shift 2;;
    --maintainer) maintainer=$2; shift 2;;
    --with-acm) with_acm=$2; shift 2;;
    -h|--help) usage; exit 0;;
    *) die "unknown argument: $1";;
  esac
done
[[ -n "$source_dir" && -n "$version" ]] || { usage >&2; exit 64; }
valid_version "$version"; valid_bool "$with_acm"
[[ "$(dpkg --print-architecture)" == arm64 ]] || die 'userspace packages must be built on an arm64 runner'
need dpkg-deb; need make; need sh
mkdir -p "$out_dir"
work="$(mktemp -d)"; trap 'rm -rf "$work"' EXIT

# libtsn + tsntool are the OpenSTLinux user-space switch API and CLI.
tool_src="$source_dir/switch/tsn_sw_base.tsntool"
[[ -d "$tool_src" ]] || die "missing tsntool source: $tool_src"
make -C "$tool_src" clean || true
make -C "$tool_src" TSNTOOL_VERSION="$version" all
stage="$work/tsntool-stage"
make -C "$tool_src" TSNTOOL_VERSION="$version" install DESTDIR="$stage"
[[ -e "$stage/usr/bin/tsntool" ]] || die 'tsntool install did not produce /usr/bin/tsntool'

libroot="$work/libtsn"
mkdir -p "$libroot/DEBIAN" "$libroot/usr"
[[ -d "$stage/usr/lib" ]] && copy_tree_contents "$stage/usr/lib" "$libroot/usr/lib"
[[ -d "$stage/usr/lib64" ]] && copy_tree_contents "$stage/usr/lib64" "$libroot/usr/lib64"
write_control "$libroot/DEBIAN/control" stm32mp257-tsn-libtsn "$version-1" arm64 "libc6" 'TTTech TSN user-space API library' "$maintainer"
build_deb "$libroot" "$out_dir/stm32mp257-tsn-libtsn_${version}-1_arm64.deb"

toolroot="$work/tsntool"
mkdir -p "$toolroot/DEBIAN" "$toolroot/usr"
[[ -d "$stage/usr/bin" ]] && copy_tree_contents "$stage/usr/bin" "$toolroot/usr/bin"
[[ -d "$stage/usr/share" ]] && copy_tree_contents "$stage/usr/share" "$toolroot/usr/share"
write_control "$toolroot/DEBIAN/control" stm32mp257-tsntool "$version-1" arm64 "stm32mp257-tsn-libtsn (= $version-1), libc6, libbsd0" 'TTTech TSN Ethernet Switch configuration utility' "$maintainer"
build_deb "$toolroot" "$out_dir/stm32mp257-tsntool_${version}-1_arm64.deb"

# DE-PTP is a separate aarch64 binary payload in the official TSN source tree.
deptp_dir="$source_dir/switch/de-ptp"
installer="$(find "$deptp_dir" -maxdepth 1 -type f -name 'TTTECH-de-ptp-aarch64-*.bin' -print -quit || true)"
[[ -n "$installer" ]] || die 'DE-PTP installer was not found in the pinned upstream source'
( cd "$deptp_dir" && sh "$(basename "$installer")" --auto-accept )
[[ -x "$deptp_dir/aarch64/usr/sbin/deptp" ]] || die 'DE-PTP installer did not produce expected aarch64 rootfs payload'
deptproot="$work/deptp"
mkdir -p "$deptproot/DEBIAN"
copy_tree_contents "$deptp_dir/aarch64" "$deptproot"
install -D -m 0644 "$ROOT/packaging/userspace/deptp/deptp.service" "$deptproot/lib/systemd/system/deptp.service"
install -D -m 0644 "$ROOT/packaging/userspace/deptp/ptp_config.xml" "$deptproot/etc/deptp/ptp_config.xml"
write_control "$deptproot/DEBIAN/control" stm32mp257-tsn-deptp "$version-1" arm64 "libc6" 'TTTech DE-gPTP daemon for TSN Ethernet Switch' "$maintainer"
build_deb "$deptproot" "$out_dir/stm32mp257-tsn-deptp_${version}-1_arm64.deb"

# ACM's actual user-space driver is libacmconfig. Demos and the Netopeer2
# plugin are intentionally not made generic Ubuntu packages: they depend on
# OpenSTLinux's sysrepo/netopeer2 stack and board-specific ACM device tree.
if [[ "$with_acm" == true ]]; then
  acm_src="$source_dir/acm/ngn.acm-config"
  [[ -d "$acm_src" ]] || die "missing ACM config library source: $acm_src"
  make -C "$acm_src" clean || true
  make -C "$acm_src" EXTERNAL_LIBRARY_VERSION="$version" all
  acm_stage="$work/acm-stage"
  make -C "$acm_src" EXTERNAL_LIBRARY_VERSION="$version" install DESTDIR="$acm_stage"
  acmroot="$work/acm-config"
  mkdir -p "$acmroot/DEBIAN" "$acmroot/usr"
  [[ -d "$acm_stage/usr/lib" ]] && copy_tree_contents "$acm_stage/usr/lib" "$acmroot/usr/lib"
  [[ -d "$acm_stage/usr/lib64" ]] && copy_tree_contents "$acm_stage/usr/lib64" "$acmroot/usr/lib64"
  [[ -d "$acm_stage/usr/share" ]] && copy_tree_contents "$acm_stage/usr/share" "$acmroot/usr/share"
  mkdir -p "$acmroot/etc/default"
  cat > "$acmroot/etc/default/config_acm" <<'CONF'
# Default ACM configuration file installed from OpenSTLinux metadata.
# Board-specific ACM parameters must be supplied by the product integration.
CONF
  write_control "$acmroot/DEBIAN/control" stm32mp257-tsn-acm-config "$version-1" arm64 "libc6" 'TTTech ACM user-space configuration interface library' "$maintainer"
  build_deb "$acmroot" "$out_dir/stm32mp257-tsn-acm-config_${version}-1_arm64.deb"
fi
