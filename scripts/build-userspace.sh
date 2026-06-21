#!/usr/bin/env bash
set -Eeuo pipefail
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
. "$SCRIPT_DIR/lib.sh"
ROOT="$(repo_root)"

# OpenSTLinux scarthgap recipe pins these user-space payload revisions.  Keep
# their Debian package versions separate: tsntool is 1.6.8, whereas DE-PTP
# is the independently released 1.6.7-2.5.2 binary dated 2024-06-28.
readonly TSNTOOL_OPENSTLINUX_PV='1.6.8'
readonly DEPTP_OPENSTLINUX_PV='1.6.7+2.5.2+20240628'
readonly DEPTP_INSTALLER='TTTECH-de-ptp-aarch64-2024-06-28.bin'

source_dir= version= revision=1 out_dir=dist/debian
maintainer='STM32MP257 TSN Packaging <noreply@example.invalid>' with_acm=false accept_deptp_eula=false
usage() {
  cat <<USAGE
Usage: $0 --source DIR --version VERSION [options]
Build OpenSTLinux-aligned TSN user-space packages for Debian GNU/Linux 13 arm64.
  --source DIR
  --version VERSION
  --revision N              Debian package revision, default: 1
  --out DIR
  --maintainer VALUE
  --with-acm true|false
  --accept-deptp-eula true|false
                            Required: acknowledge the DE-PTP EULA before the
                            vendor installer is invoked.
USAGE
}
while [[ $# -gt 0 ]]; do
  case "$1" in
    --source) source_dir=$2; shift 2;;
    --version) version=$2; shift 2;;
    --revision) revision=$2; shift 2;;
    --out) out_dir=$2; shift 2;;
    --maintainer) maintainer=$2; shift 2;;
    --with-acm) with_acm=$2; shift 2;;
    --accept-deptp-eula) accept_deptp_eula=$2; shift 2;;
    -h|--help) usage; exit 0;;
    *) die "unknown argument: $1";;
  esac
done
[[ -n "$source_dir" && -n "$version" ]] || { usage >&2; exit 64; }
valid_version "$version"; valid_revision "$revision"; valid_bool "$with_acm"; valid_bool "$accept_deptp_eula"
[[ "$version" == "$TSNTOOL_OPENSTLINUX_PV" ]] || die "OpenSTLinux scarthgap tsntool is pinned to $TSNTOOL_OPENSTLINUX_PV; got $version"
[[ "$accept_deptp_eula" == true ]] || die 'DE-PTP requires explicit EULA acceptance: pass --accept-deptp-eula true'
[[ "$(dpkg --print-architecture)" == arm64 ]] || die 'user-space packages must be built in a Debian 13 arm64 environment'
need dpkg-deb; need dpkg-query; need file; need find; need ldd; need make; need readelf; need readlink; need sh; need sync
mkdir -p "$out_dir"
work="$(mktemp -d)"; trap 'rm -rf "$work"' EXIT
tsntool_deb_ver="$(deb_version "$TSNTOOL_OPENSTLINUX_PV" "$revision")"
deptp_deb_ver="$(deb_version "$DEPTP_OPENSTLINUX_PV" "$revision")"
archlib="$(arch_libdir)"

copy_libclass() {
  # Copy source libraries into a canonical Debian arm64 lib directory.
  # $1 source stage, $2 destination package root, $3 extended-regex basename.
  local stage=$1 root=$2 regex=$3 item base
  mkdir -p "$root$archlib"
  while IFS= read -r -d '' item; do
    base=$(basename -- "$item")
    [[ "$base" =~ $regex ]] || continue
    copy_item "$item" "$root$archlib/$base"
  done < <(find "$stage/usr" \( -type f -o -type l \) -name 'lib*' -print0 2>/dev/null)
}

add_doc_payload_map() {
  local root=$1 package=$2 map_source=$3
  local doc="$root/usr/share/doc/$package"
  mkdir -p "$doc"
  payload_map "$map_source" "$doc/PAYLOAD-MAP.tsv"
  install -m 0644 "$ROOT/NOTICE-REDISTRIBUTION.md" "$doc/NOTICE-REDISTRIBUTION.md"
}

# The official tsntool recipe splits runtime lib*.so.*, unversioned lib*.so +
# headers, static archives, and the CLI. Do the same rather than copying the
# whole install tree into one package.
tool_src="$source_dir/switch/tsn_sw_base.tsntool"
[[ -d "$tool_src" ]] || die "missing tsntool source: $tool_src"
# Match tsntool_release.bb: clean through the environment-preserving make
# mode, synchronize generated files, then build and stage the upstream install.
make -C "$tool_src" -e clean
sync
make -C "$tool_src" -e all
stage="$work/tsntool-stage"
rm -rf "$stage"
make -C "$tool_src" -e install DESTDIR="$stage"
[[ -x "$stage/usr/bin/tsntool" ]] || die 'tsntool install did not produce /usr/bin/tsntool'
assert_only_paths "$stage" \
  '^/usr/bin/tsntool$' \
  '^/usr/share/man/man8/tsntool\.8$' \
  '^/usr/(lib|lib64|lib/aarch64-linux-gnu)/libtsn\.so(\..+)?$' \
  '^/usr/(lib|lib64|lib/aarch64-linux-gnu)/libtsn\.a$' \
  '^/usr/include/libtsn/[^/]+\.h$'

libroot="$work/libtsn"
mkdir -p "$libroot/DEBIAN"
copy_libclass "$stage" "$libroot" '^libtsn\.so\..+$'
compgen -G "$libroot$archlib/libtsn.so.*" >/dev/null || die 'tsntool install produced no versioned libtsn runtime library'
write_debian13_preinst "$libroot/DEBIAN/preinst" stm32mp2-tsn-libtsn
write_ldconfig_scripts "$libroot"
assert_no_missing_elf_deps "$libroot" "$libroot$archlib"
lib_deps="$(debian_runtime_dependencies "$libroot" "$libroot$archlib")"
write_control "$libroot/DEBIAN/control" stm32mp2-tsn-libtsn "$tsntool_deb_ver" arm64 "$lib_deps" 'TTTech TSN Switch runtime API library' "$maintainer" 'Multi-Arch: same'
write_shlibs_from_root "$libroot" stm32mp2-tsn-libtsn "$tsntool_deb_ver" "$libroot$archlib"
add_doc_payload_map "$libroot" stm32mp2-tsn-libtsn "$libroot"
build_deb "$libroot" "$out_dir/stm32mp2-tsn-libtsn_${tsntool_deb_ver}_arm64.deb"

devroot="$work/libtsn-dev"
mkdir -p "$devroot/DEBIAN" "$devroot/usr/include/libtsn"
copy_libclass "$stage" "$devroot" '^libtsn\.so$'
if [[ -d "$stage/usr/include/libtsn" ]]; then
  copy_tree_contents "$stage/usr/include/libtsn" "$devroot/usr/include/libtsn"
fi
compgen -G "$devroot$archlib/libtsn.so" >/dev/null || die 'tsntool install produced no unversioned development library symlink'
find "$devroot/usr/include/libtsn" -type f -name '*.h' -print -quit | grep -q . || die 'tsntool install produced no libtsn development header'
write_debian13_preinst "$devroot/DEBIAN/preinst" stm32mp2-tsn-libtsn-dev
write_control "$devroot/DEBIAN/control" stm32mp2-tsn-libtsn-dev "$tsntool_deb_ver" arm64 "stm32mp2-tsn-libtsn (= $tsntool_deb_ver)" 'TTTech TSN Switch API development headers and link library' "$maintainer" 'Multi-Arch: same'
add_doc_payload_map "$devroot" stm32mp2-tsn-libtsn-dev "$devroot"
build_deb "$devroot" "$out_dir/stm32mp2-tsn-libtsn-dev_${tsntool_deb_ver}_arm64.deb"

staticroot="$work/libtsn-staticdev"
mkdir -p "$staticroot/DEBIAN"
copy_libclass "$stage" "$staticroot" '^libtsn\.a$'
if compgen -G "$staticroot$archlib/libtsn.a" >/dev/null; then
  write_debian13_preinst "$staticroot/DEBIAN/preinst" stm32mp2-tsn-libtsn-staticdev
  write_control "$staticroot/DEBIAN/control" stm32mp2-tsn-libtsn-staticdev "$tsntool_deb_ver" arm64 "stm32mp2-tsn-libtsn-dev (= $tsntool_deb_ver)" 'TTTech TSN Switch static API library' "$maintainer" 'Multi-Arch: same'
  add_doc_payload_map "$staticroot" stm32mp2-tsn-libtsn-staticdev "$staticroot"
  build_deb "$staticroot" "$out_dir/stm32mp2-tsn-libtsn-staticdev_${tsntool_deb_ver}_arm64.deb"
fi

toolroot="$work/tsntool"
mkdir -p "$toolroot/DEBIAN" "$toolroot/usr/bin" "$toolroot/usr/share"
copy_item "$stage/usr/bin/tsntool" "$toolroot/usr/bin/tsntool"
[[ -d "$stage/usr/share/man" ]] && copy_tree_contents "$stage/usr/share/man" "$toolroot/usr/share/man"
write_debian13_preinst "$toolroot/DEBIAN/preinst" stm32mp2-tsntool
assert_no_missing_elf_deps "$toolroot" "$libroot$archlib"
tool_deps="$(debian_runtime_dependencies "$toolroot" "$libroot$archlib")"
write_control "$toolroot/DEBIAN/control" stm32mp2-tsntool "$tsntool_deb_ver" arm64 "stm32mp2-tsn-libtsn (= $tsntool_deb_ver), $tool_deps" 'TTTech TSN Ethernet Switch configuration utility' "$maintainer"
add_doc_payload_map "$toolroot" stm32mp2-tsntool "$toolroot"
build_deb "$toolroot" "$out_dir/stm32mp2-tsntool_${tsntool_deb_ver}_arm64.deb"

# The official binary recipe explicitly requires EULA acceptance, installs the
# supplied service/configuration, and deliberately disables automatic startup.
deptp_dir="$source_dir/switch/de-ptp"
installer="$deptp_dir/$DEPTP_INSTALLER"
[[ -f "$installer" ]] || die "DE-PTP installer required by OpenSTLinux scarthgap was not found: $DEPTP_INSTALLER"
( cd "$deptp_dir" && sh "$DEPTP_INSTALLER" --auto-accept )
[[ -x "$deptp_dir/aarch64/usr/sbin/deptp" ]] || die 'DE-PTP installer did not produce expected aarch64 payload'
deptproot="$work/deptp"
mkdir -p "$deptproot/DEBIAN"
copy_tree_contents "$deptp_dir/aarch64" "$deptproot"
install -D -m 0644 "$ROOT/packaging/userspace/deptp/deptp.service" "$deptproot/lib/systemd/system/deptp.service"
install -D -m 0644 "$ROOT/packaging/userspace/deptp/ptp_config.xml" "$deptproot/etc/deptp/ptp_config.xml"
printf '%s\n' /etc/deptp/ptp_config.xml > "$deptproot/DEBIAN/conffiles"
write_debian13_preinst "$deptproot/DEBIAN/preinst" stm32mp2-tsn-deptp
write_ldconfig_scripts "$deptproot"
assert_no_missing_elf_deps "$deptproot" "$deptproot/usr/lib" "$deptproot$archlib"
deptp_deps="$(debian_runtime_dependencies "$deptproot" "$deptproot/usr/lib" "$deptproot$archlib")"
write_control "$deptproot/DEBIAN/control" stm32mp2-tsn-deptp "$deptp_deb_ver" arm64 "$deptp_deps, systemd" 'TTTech DE-gPTP daemon for STM32MP257 TSN Switch' "$maintainer"
write_shlibs_from_root "$deptproot" stm32mp2-tsn-deptp "$deptp_deb_ver" "$deptproot/usr/lib"
add_doc_payload_map "$deptproot" stm32mp2-tsn-deptp "$deptproot"
build_deb "$deptproot" "$out_dir/stm32mp2-tsn-deptp_${deptp_deb_ver}_arm64.deb"

# ACM carries its own board integration and is never selected by the default
# switch meta-package. Preserve every payload file and reject missing ELF deps.
if [[ "$with_acm" == true ]]; then
  acm_src="$source_dir/acm/ngn.acm-config"
  [[ -d "$acm_src" ]] || die "missing ACM config library source: $acm_src"
  make -C "$acm_src" EXTERNAL_LIBRARY_VERSION="$version" all
  acm_stage="$work/acm-stage"
  make -C "$acm_src" EXTERNAL_LIBRARY_VERSION="$version" install DESTDIR="$acm_stage"
  acmroot="$work/acm-config"
  mkdir -p "$acmroot/DEBIAN"
  copy_tree_contents "$acm_stage" "$acmroot"
  write_debian13_preinst "$acmroot/DEBIAN/preinst" stm32mp2-tsn-acm-config
  write_ldconfig_scripts "$acmroot"
  assert_no_missing_elf_deps "$acmroot" "$acmroot/usr/lib" "$acmroot$archlib"
  acm_deps="$(debian_runtime_dependencies "$acmroot" "$acmroot/usr/lib" "$acmroot$archlib")"
  write_control "$acmroot/DEBIAN/control" stm32mp2-tsn-acm-config "$tsntool_deb_ver" arm64 "$acm_deps, stm32mp2-tsn-edge-runtime (= $tsntool_deb_ver)" 'TTTech ACM user-space configuration interface' "$maintainer"
  [[ -f "$acmroot/etc/default/config_acm" ]] && printf '%s\n' /etc/default/config_acm > "$acmroot/DEBIAN/conffiles"
  write_shlibs_from_root "$acmroot" stm32mp2-tsn-acm-config "$tsntool_deb_ver" "$acmroot/usr/lib"
  add_doc_payload_map "$acmroot" stm32mp2-tsn-acm-config "$acmroot"
  build_deb "$acmroot" "$out_dir/stm32mp2-tsn-acm-config_${tsntool_deb_ver}_arm64.deb"
fi
