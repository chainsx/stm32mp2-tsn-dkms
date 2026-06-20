#!/usr/bin/env bash
set -Eeuo pipefail
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
. "$SCRIPT_DIR/lib.sh"
ROOT="$(repo_root)"

source_dir= version= out_dir=dist/debian maintainer='STM32MP257 TSN Packaging <noreply@example.invalid>' with_acm=false
usage() {
  cat <<USAGE
Usage: $0 --source DIR --version VERSION [options]
  --source DIR
  --version VERSION
  --out DIR
  --maintainer VALUE
  --with-acm true|false
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
need dpkg-deb; need sed
mkdir -p "$out_dir"
work="$(mktemp -d)"; trap 'rm -rf "$work"' EXIT

package_module() {
  local package=$1 src=$2 template=$3 module=$4 description=$5 extra_depends=${6:-dkms}
  [[ -d "$src" ]] || die "missing source tree for $package: $src"
  local root srcdst
  root="$work/$package"
  srcdst="$root/usr/src/${package}-${version}"
  mkdir -p "$root/DEBIAN" "$srcdst"
  copy_tree_contents "$src" "$srcdst"
  sed "s/@VERSION@/$version/g" "$template" > "$srcdst/dkms.conf"
  install -m 0644 "$ROOT/NOTICE-REDISTRIBUTION.md" "$srcdst/NOTICE-REDISTRIBUTION.md"
  write_control "$root/DEBIAN/control" "${package}-dkms" "${version}-1" all "$extra_depends" "$description" "$maintainer"
  build_deb "$root" "$out_dir/${package}-dkms_${version}-1_all.deb"
}

package_module stm32mp257-tsn-deip \
  "$source_dir/switch/st.stm32-deip" \
  "$ROOT/packaging/dkms/deip/dkms.conf.in" \
  stm32_deip \
  'STM32 DEIP glue kernel module (DKMS)'

package_module stm32mp257-tsn-edge \
  "$source_dir/switch/tsn_sw_base.edge-lkm" \
  "$ROOT/packaging/dkms/edge/dkms.conf.in" \
  edgx_pfm_lkm \
  'TTTech EDGE Ethernet Switch kernel module (DKMS)'
edge_root="$work/stm32mp257-tsn-edge-runtime"
mkdir -p "$edge_root/DEBIAN" "$edge_root/etc/modules-load.d" "$edge_root/etc/modprobe.d" "$edge_root/usr/share/doc/stm32mp257-tsn-edge"
cat > "$edge_root/etc/modules-load.d/stm32mp257-tsn-edge.conf" <<'CONF'
sch_mqprio
sch_prio
bridge
8021q
edgx_pfm_lkm
CONF
cat > "$edge_root/etc/modprobe.d/stm32mp257-tsn-edge.conf" <<'CONF'
# OpenSTLinux uses predictable interface names, so ETH1 is normally end1.
# Change end1:0 if your rootfs uses another name for the ETH1 MAC.
softdep edgx_pfm_lkm: stmmac stm32_deip
options edgx_pfm_lkm netif="end1:0"
CONF
cat > "$edge_root/usr/share/doc/stm32mp257-tsn-edge/README.Debian" <<'DOC'
The default EDGE instance is associated with OpenSTLinux's ETH1 predictable
name, end1. For distributions naming this NIC eth0 or eth1, edit
/etc/modprobe.d/stm32mp257-tsn-edge.conf, then reload the module.
DOC
write_control "$edge_root/DEBIAN/control" stm32mp257-tsn-edge-runtime "$version-1" all "stm32mp257-tsn-edge-dkms (= $version-1), kmod" 'EDGE automatic load and module options' "$maintainer"
build_deb "$edge_root" "$out_dir/stm32mp257-tsn-edge-runtime_${version}-1_all.deb"

if [[ "$with_acm" == true ]]; then
  package_module stm32mp257-tsn-acm \
    "$source_dir/acm/ngn.ngn-dd" \
    "$ROOT/packaging/dkms/acm/dkms.conf.in" \
    acm \
    'TTTech Acceleration Module kernel module (DKMS)' \
    "dkms, stm32mp257-tsn-edge-dkms (= $version-1)"
  acm_root="$work/stm32mp257-tsn-acm-runtime"
  mkdir -p "$acm_root/DEBIAN" "$acm_root/etc/modules-load.d" "$acm_root/etc/modprobe.d"
  printf '%s\n' acm > "$acm_root/etc/modules-load.d/stm32mp257-tsn-acm.conf"
  printf '%s\n' 'softdep acm: stmmac stm32_deip edgx_pfm_lkm' > "$acm_root/etc/modprobe.d/stm32mp257-tsn-acm.conf"
  write_control "$acm_root/DEBIAN/control" stm32mp257-tsn-acm-runtime "$version-1" all "stm32mp257-tsn-acm-dkms (= $version-1), stm32mp257-tsn-edge-runtime (= $version-1), kmod" 'ACM automatic load and module dependencies' "$maintainer"
  build_deb "$acm_root" "$out_dir/stm32mp257-tsn-acm-runtime_${version}-1_all.deb"
fi
