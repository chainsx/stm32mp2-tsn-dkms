#!/usr/bin/env bash
set -Eeuo pipefail
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
. "$SCRIPT_DIR/lib.sh"
ROOT="$(repo_root)"

source_dir= version= revision=1 out_dir=dist/debian maintainer='STM32MP257 TSN Packaging <noreply@example.invalid>' with_acm=false edge_interface=end1
usage() {
  cat <<USAGE
Usage: $0 --source DIR --version VERSION [options]
  --source DIR
  --version VERSION
  --revision N              Debian package revision, default: 1
  --edge-interface IFACE    OpenSTLinux-compatible default: end1
  --out DIR
  --maintainer VALUE
  --with-acm true|false
USAGE
}
while [[ $# -gt 0 ]]; do
  case "$1" in
    --source) source_dir=$2; shift 2;;
    --version) version=$2; shift 2;;
    --revision) revision=$2; shift 2;;
    --edge-interface) edge_interface=$2; shift 2;;
    --out) out_dir=$2; shift 2;;
    --maintainer) maintainer=$2; shift 2;;
    --with-acm) with_acm=$2; shift 2;;
    -h|--help) usage; exit 0;;
    *) die "unknown argument: $1";;
  esac
done
[[ -n "$source_dir" && -n "$version" ]] || { usage >&2; exit 64; }
valid_version "$version"; valid_revision "$revision"; valid_bool "$with_acm"; valid_interface "$edge_interface"
need dpkg-deb; need sed; need install
mkdir -p "$out_dir"
work="$(mktemp -d)"; trap 'rm -rf "$work"' EXIT
deb_ver="$(deb_version "$version" "$revision")"
dkms_ver="$(dkms_version "$version" "$revision")"

write_dkms_scripts() {
  local root=$1 source_package=$2
  sed \
    -e "s|@MODULE_NAME@|$source_package|g" \
    -e "s|@SOURCE_PACKAGE@|$source_package|g" \
    -e "s|@DKMS_VERSION@|$dkms_ver|g" \
    "$ROOT/packaging/dkms/common/postinst.in" > "$root/DEBIAN/postinst"
  sed \
    -e "s|@MODULE_NAME@|$source_package|g" \
    -e "s|@DKMS_VERSION@|$dkms_ver|g" \
    "$ROOT/packaging/dkms/common/postrm.in" > "$root/DEBIAN/postrm"
  chmod 0755 "$root/DEBIAN/postinst" "$root/DEBIAN/postrm"
}

package_module() {
  local source_package=$1 src=$2 template=$3 description=$4 depends=${5:-'dkms (>= 3.0.0), build-essential, kmod'}
  [[ -d "$src" ]] || die "missing source tree for $source_package: $src"
  local root srcdst
  root="$work/$source_package"
  srcdst="$root/usr/src/${source_package}-${dkms_ver}"
  mkdir -p "$root/DEBIAN" "$srcdst" "$root/usr/share/doc/${source_package}-dkms"
  copy_tree_contents "$src" "$srcdst"
  sed \
    -e "s|@DKMS_VERSION@|$dkms_ver|g" \
    -e "s|@EDGE_DKMS_VERSION@|$dkms_ver|g" \
    "$template" > "$srcdst/dkms.conf"
  install -m 0644 "$ROOT/NOTICE-REDISTRIBUTION.md" "$srcdst/NOTICE-REDISTRIBUTION.md"
  sed \
    -e "s|@MODULE_NAME@|$source_package|g" \
    -e "s|@DKMS_VERSION@|$dkms_ver|g" \
    "$ROOT/packaging/dkms/common/README.Debian.in" > "$root/usr/share/doc/${source_package}-dkms/README.Debian"
  write_debian13_preinst "$root/DEBIAN/preinst" "${source_package}-dkms"
  write_dkms_scripts "$root" "$source_package"
  write_control "$root/DEBIAN/control" "${source_package}-dkms" "$deb_ver" all "$depends" "$description" "$maintainer"
  build_deb "$root" "$out_dir/${source_package}-dkms_${deb_ver}_all.deb"
}

# The make flags and runtime modprobe/module-load fragments match the
# OpenSTLinux scarthgap kernel-module-st-stm32-deip and kernel-module-edge recipes.
package_module stm32mp257-tsn-deip \
  "$source_dir/switch/st.stm32-deip" \
  "$ROOT/packaging/dkms/deip/dkms.conf.in" \
  'STM32 DEIP glue kernel module (DKMS)'

package_module stm32mp257-tsn-edge \
  "$source_dir/switch/tsn_sw_base.edge-lkm" \
  "$ROOT/packaging/dkms/edge/dkms.conf.in" \
  'TTTech EDGE Ethernet Switch kernel module (DKMS)' \
  "dkms (>= 3.0.0), build-essential, kmod, stm32mp257-tsn-deip-dkms (= $deb_ver)"

edge_src="$source_dir/switch/tsn_sw_base.edge-lkm"
[[ -f "$edge_src/edge.h" ]] || die "OpenSTLinux EDGE header is missing: $edge_src/edge.h"
edge_dev="$work/edge-dev"
mkdir -p "$edge_dev/DEBIAN" "$edge_dev/usr/include/stm32mp257-tsn-edge"
install -m 0644 "$edge_src/edge.h" "$edge_dev/usr/include/stm32mp257-tsn-edge/edge.h"
write_debian13_preinst "$edge_dev/DEBIAN/preinst" stm32mp257-tsn-edge-dev
write_control "$edge_dev/DEBIAN/control" stm32mp257-tsn-edge-dev "$deb_ver" all "stm32mp257-tsn-edge-dkms (= $deb_ver)" 'TTTech EDGE public kernel interface header' "$maintainer"
build_deb "$edge_dev" "$out_dir/stm32mp257-tsn-edge-dev_${deb_ver}_all.deb"

edge_root="$work/edge-runtime"
mkdir -p "$edge_root/DEBIAN" "$edge_root/etc/modules-load.d" "$edge_root/etc/modprobe.d" "$edge_root/usr/share/doc/stm32mp257-tsn-edge-runtime"
# Exact module ordering is carried from edgx_sw_modload.conf.
cat > "$edge_root/etc/modules-load.d/stm32mp257-tsn-edge.conf" <<'CONF'
sch_mqprio
sch_prio
bridge
8021q
edgx_pfm_lkm
CONF
# The soft dependency is carried from edgx_sw_modprobe.conf. The per-board
# netif option corresponds to DEFAULT_ETHERNET_MAIN_TSN_BRIDGE_INTERFACE in ST's layer.
cat > "$edge_root/etc/modprobe.d/stm32mp257-tsn-edge.conf" <<CONF
softdep edgx_pfm_lkm: stmmac stm32_deip
options edgx_pfm_lkm netif="${edge_interface}:0"
CONF
cat > "$edge_root/usr/share/doc/stm32mp257-tsn-edge-runtime/README.Debian" <<DOC
This Debian 13 package mirrors OpenSTLinux EDGE module-load and modprobe
configuration. The selected main TSN MAC is '${edge_interface}', giving the
vendor module parameter netif="${edge_interface}:0".

Verify the name before rebooting:
  ip -br link

To change it, edit /etc/modprobe.d/stm32mp257-tsn-edge.conf and reload EDGE.
DOC
printf '%s\n%s\n' \
  /etc/modules-load.d/stm32mp257-tsn-edge.conf \
  /etc/modprobe.d/stm32mp257-tsn-edge.conf > "$edge_root/DEBIAN/conffiles"
write_debian13_preinst "$edge_root/DEBIAN/preinst" stm32mp257-tsn-edge-runtime
write_control "$edge_root/DEBIAN/control" stm32mp257-tsn-edge-runtime "$deb_ver" all "stm32mp257-tsn-edge-dkms (= $deb_ver), stm32mp257-tsn-deip-dkms (= $deb_ver), kmod" 'OpenSTLinux-aligned EDGE module-load and modprobe configuration' "$maintainer"
build_deb "$edge_root" "$out_dir/stm32mp257-tsn-edge-runtime_${deb_ver}_all.deb"

if [[ "$with_acm" == true ]]; then
  package_module stm32mp257-tsn-acm \
    "$source_dir/acm/ngn.ngn-dd" \
    "$ROOT/packaging/dkms/acm/dkms.conf.in" \
    'TTTech Acceleration Module kernel module (DKMS)' \
    "dkms (>= 3.0.0), build-essential, kmod, stm32mp257-tsn-edge-dkms (= $deb_ver)"

  acm_root="$work/acm-runtime"
  mkdir -p "$acm_root/DEBIAN" "$acm_root/etc/modules-load.d" "$acm_root/etc/modprobe.d" "$acm_root/usr/share/doc/stm32mp257-tsn-acm-runtime"
  printf '%s\n' acm > "$acm_root/etc/modules-load.d/stm32mp257-tsn-acm.conf"
  printf '%s\n' 'softdep acm: stmmac stm32_deip edgx_pfm_lkm' > "$acm_root/etc/modprobe.d/stm32mp257-tsn-acm.conf"
  cat > "$acm_root/usr/share/doc/stm32mp257-tsn-acm-runtime/README.Debian" <<'DOC'
ACM is optional. Install this package only after validating that the deployed
DTB/FDT contains the ACM device node and the required board resources.
DOC
  printf '%s\n%s\n' \
    /etc/modules-load.d/stm32mp257-tsn-acm.conf \
    /etc/modprobe.d/stm32mp257-tsn-acm.conf > "$acm_root/DEBIAN/conffiles"
  write_debian13_preinst "$acm_root/DEBIAN/preinst" stm32mp257-tsn-acm-runtime
  write_control "$acm_root/DEBIAN/control" stm32mp257-tsn-acm-runtime "$deb_ver" all "stm32mp257-tsn-acm-dkms (= $deb_ver), stm32mp257-tsn-edge-runtime (= $deb_ver), kmod" 'ACM automatic load and module dependency configuration' "$maintainer"
  build_deb "$acm_root" "$out_dir/stm32mp257-tsn-acm-runtime_${deb_ver}_all.deb"
fi
