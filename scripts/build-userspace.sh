#!/usr/bin/env bash
set -Eeuo pipefail
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
. "$SCRIPT_DIR/lib.sh"
ROOT="$(repo_root)"

source_dir= version= revision=1 out_dir=dist/debian
maintainer='STM32MP257 TSN Packaging <noreply@example.invalid>' with_acm=false
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
    -h|--help) usage; exit 0;;
    *) die "unknown argument: $1";;
  esac
done
[[ -n "$source_dir" && -n "$version" ]] || { usage >&2; exit 64; }
valid_version "$version"; valid_revision "$revision"; valid_bool "$with_acm"
[[ "$(dpkg --print-architecture)" == arm64 ]] || die 'user-space packages must be built in a Debian 13 arm64 environment'
need dpkg-deb; need dpkg-query; need file; need find; need ldd; need make; need readelf; need sh
mkdir -p "$out_dir"
work="$(mktemp -d)"; trap 'rm -rf "$work"' EXIT
deb_ver="$(deb_version "$version" "$revision")"
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
make -C "$tool_src" TSNTOOL_VERSION="$version" all
stage="$work/tsntool-stage"
make -C "$tool_src" TSNTOOL_VERSION="$version" install DESTDIR="$stage"
[[ -x "$stage/usr/bin/tsntool" ]] || die 'tsntool install did not produce /usr/bin/tsntool'
assert_only_paths "$stage" \
  '^/usr/bin/tsntool$' \
  '^/usr/share/man/man8/tsntool\.8(\.gz)?$' \
  '^/usr/(lib|lib64|lib/aarch64-linux-gnu)/lib[^/]+\.so(\..+)?$' \
  '^/usr/(lib|lib64|lib/aarch64-linux-gnu)/lib[^/]+\.a$' \
  '^/usr/include/libtsn/[^/]+\.h$'

libroot="$work/libtsn"
mkdir -p "$libroot/DEBIAN"
copy_libclass "$stage" "$libroot" '^lib[^/]+\.so\..+$'
compgen -G "$libroot$archlib/lib*.so.*" >/dev/null || die 'tsntool install produced no versioned libtsn runtime library'
write_debian13_preinst "$libroot/DEBIAN/preinst" stm32mp257-tsn-libtsn
write_ldconfig_scripts "$libroot"
assert_no_missing_elf_deps "$libroot" "$libroot$archlib"
lib_deps="$(debian_runtime_dependencies "$libroot" "$libroot$archlib")"
write_control "$libroot/DEBIAN/control" stm32mp257-tsn-libtsn "$deb_ver" arm64 "$lib_deps" 'TTTech TSN Switch runtime API library' "$maintainer" 'Multi-Arch: same'
write_shlibs_from_root "$libroot" stm32mp257-tsn-libtsn "$deb_ver" "$libroot$archlib"
add_doc_payload_map "$libroot" stm32mp257-tsn-libtsn "$libroot"
build_deb "$libroot" "$out_dir/stm32mp257-tsn-libtsn_${deb_ver}_arm64.deb"

devroot="$work/libtsn-dev"
mkdir -p "$devroot/DEBIAN" "$devroot/usr/include/libtsn"
copy_libclass "$stage" "$devroot" '^lib[^/]+\.so$'
if [[ -d "$stage/usr/include/libtsn" ]]; then
  copy_tree_contents "$stage/usr/include/libtsn" "$devroot/usr/include/libtsn"
fi
compgen -G "$devroot$archlib/lib*.so" >/dev/null || die 'tsntool install produced no unversioned development library symlink'
find "$devroot/usr/include/libtsn" -type f -name '*.h' -print -quit | grep -q . || die 'tsntool install produced no libtsn development header'
write_debian13_preinst "$devroot/DEBIAN/preinst" stm32mp257-tsn-libtsn-dev
write_control "$devroot/DEBIAN/control" stm32mp257-tsn-libtsn-dev "$deb_ver" arm64 "stm32mp257-tsn-libtsn (= $deb_ver)" 'TTTech TSN Switch API development headers and link library' "$maintainer" 'Multi-Arch: same'
add_doc_payload_map "$devroot" stm32mp257-tsn-libtsn-dev "$devroot"
build_deb "$devroot" "$out_dir/stm32mp257-tsn-libtsn-dev_${deb_ver}_arm64.deb"

staticroot="$work/libtsn-staticdev"
mkdir -p "$staticroot/DEBIAN"
copy_libclass "$stage" "$staticroot" '^lib[^/]+\.a$'
if compgen -G "$staticroot$archlib/lib*.a" >/dev/null; then
  write_debian13_preinst "$staticroot/DEBIAN/preinst" stm32mp257-tsn-libtsn-staticdev
  write_control "$staticroot/DEBIAN/control" stm32mp257-tsn-libtsn-staticdev "$deb_ver" arm64 "stm32mp257-tsn-libtsn-dev (= $deb_ver)" 'TTTech TSN Switch static API library' "$maintainer" 'Multi-Arch: same'
  add_doc_payload_map "$staticroot" stm32mp257-tsn-libtsn-staticdev "$staticroot"
  build_deb "$staticroot" "$out_dir/stm32mp257-tsn-libtsn-staticdev_${deb_ver}_arm64.deb"
fi

toolroot="$work/tsntool"
mkdir -p "$toolroot/DEBIAN" "$toolroot/usr/bin" "$toolroot/usr/share"
copy_item "$stage/usr/bin/tsntool" "$toolroot/usr/bin/tsntool"
[[ -d "$stage/usr/share/man" ]] && copy_tree_contents "$stage/usr/share/man" "$toolroot/usr/share/man"
write_debian13_preinst "$toolroot/DEBIAN/preinst" stm32mp257-tsntool
assert_no_missing_elf_deps "$toolroot" "$libroot$archlib"
tool_deps="$(debian_runtime_dependencies "$toolroot" "$libroot$archlib")"
write_control "$toolroot/DEBIAN/control" stm32mp257-tsntool "$deb_ver" arm64 "stm32mp257-tsn-libtsn (= $deb_ver), $tool_deps" 'TTTech TSN Ethernet Switch configuration utility' "$maintainer"
add_doc_payload_map "$toolroot" stm32mp257-tsntool "$toolroot"
build_deb "$toolroot" "$out_dir/stm32mp257-tsntool_${deb_ver}_arm64.deb"

# The official binary recipe explicitly requires EULA acceptance, installs the
# supplied service/configuration, and deliberately disables automatic startup.
deptp_dir="$source_dir/switch/de-ptp"
installer="$(find "$deptp_dir" -maxdepth 1 -type f -name 'TTTECH-de-ptp-aarch64-*.bin' -print -quit || true)"
[[ -n "$installer" ]] || die 'DE-PTP installer was not found in the pinned upstream source'
( cd "$deptp_dir" && sh "$(basename "$installer")" --auto-accept )
[[ -x "$deptp_dir/aarch64/usr/sbin/deptp" ]] || die 'DE-PTP installer did not produce expected aarch64 payload'
deptproot="$work/deptp"
mkdir -p "$deptproot/DEBIAN"
copy_tree_contents "$deptp_dir/aarch64" "$deptproot"
install -D -m 0644 "$ROOT/packaging/userspace/deptp/deptp.service" "$deptproot/lib/systemd/system/deptp.service"
install -D -m 0644 "$ROOT/packaging/userspace/deptp/ptp_config.xml" "$deptproot/etc/deptp/ptp_config.xml"
printf '%s\n' /etc/deptp/ptp_config.xml > "$deptproot/DEBIAN/conffiles"
write_debian13_preinst "$deptproot/DEBIAN/preinst" stm32mp257-tsn-deptp
write_ldconfig_scripts "$deptproot"
assert_no_missing_elf_deps "$deptproot" "$deptproot/usr/lib" "$deptproot$archlib"
deptp_deps="$(debian_runtime_dependencies "$deptproot" "$deptproot/usr/lib" "$deptproot$archlib")"
write_control "$deptproot/DEBIAN/control" stm32mp257-tsn-deptp "$deb_ver" arm64 "$deptp_deps, systemd" 'TTTech DE-gPTP daemon for STM32MP257 TSN Switch' "$maintainer"
write_shlibs_from_root "$deptproot" stm32mp257-tsn-deptp "$deb_ver" "$deptproot/usr/lib"
add_doc_payload_map "$deptproot" stm32mp257-tsn-deptp "$deptproot"
build_deb "$deptproot" "$out_dir/stm32mp257-tsn-deptp_${deb_ver}_arm64.deb"

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
  write_debian13_preinst "$acmroot/DEBIAN/preinst" stm32mp257-tsn-acm-config
  write_ldconfig_scripts "$acmroot"
  assert_no_missing_elf_deps "$acmroot" "$acmroot/usr/lib" "$acmroot$archlib"
  acm_deps="$(debian_runtime_dependencies "$acmroot" "$acmroot/usr/lib" "$acmroot$archlib")"
  write_control "$acmroot/DEBIAN/control" stm32mp257-tsn-acm-config "$deb_ver" arm64 "$acm_deps, stm32mp257-tsn-edge-runtime (= $deb_ver)" 'TTTech ACM user-space configuration interface' "$maintainer"
  [[ -f "$acmroot/etc/default/config_acm" ]] && printf '%s\n' /etc/default/config_acm > "$acmroot/DEBIAN/conffiles"
  write_shlibs_from_root "$acmroot" stm32mp257-tsn-acm-config "$deb_ver" "$acmroot/usr/lib"
  add_doc_payload_map "$acmroot" stm32mp257-tsn-acm-config "$acmroot"
  build_deb "$acmroot" "$out_dir/stm32mp257-tsn-acm-config_${deb_ver}_arm64.deb"
fi
