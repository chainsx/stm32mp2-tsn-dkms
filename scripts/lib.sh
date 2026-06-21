#!/usr/bin/env bash
set -Eeuo pipefail

die() { echo "error: $*" >&2; exit 1; }
need() { command -v "$1" >/dev/null 2>&1 || die "missing required command: $1"; }
valid_version() { [[ "$1" =~ ^[0-9][0-9A-Za-z.+:~_-]*$ ]] || die "invalid Debian upstream version: $1"; }
valid_revision() { [[ "$1" =~ ^[1-9][0-9]*$ ]] || die "package revision must be a positive integer: $1"; }
valid_bool() { [[ "$1" == true || "$1" == false ]] || die "expected true or false, got: $1"; }
valid_interface() { [[ "$1" =~ ^[A-Za-z0-9_.:-]+$ ]] || die "invalid network interface name: $1"; }
repo_root() { cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd; }
deb_version() { printf '%s-%s' "$1" "$2"; }
dkms_version() { printf '%s+deb%s' "$1" "$2"; }
arch_libdir() { printf '%s' /usr/lib/aarch64-linux-gnu; }

write_control() {
  local path=$1 package=$2 version=$3 arch=$4 depends=$5 description=$6 maintainer=$7
  shift 7
  cat > "$path" <<CTRL
Package: $package
Version: $version
Section: misc
Priority: optional
Architecture: $arch
Maintainer: $maintainer
Depends: $depends
Description: $description
 OpenSTLinux-aligned STM32MP2 TSN component for Debian GNU/Linux 13 (trixie) arm64.
CTRL
  for field in "$@"; do
    [[ -n "$field" ]] && printf '%s\n' "$field" >> "$path"
  done
}

build_deb() {
  local root=$1 out=$2
  dpkg-deb --root-owner-group --build "$root" "$out" >/dev/null
}

copy_tree_contents() {
  local from=$1 to=$2
  mkdir -p "$to"
  ( cd "$from" && tar --exclude=.git -cf - . ) | ( cd "$to" && tar -xf - )
}

copy_item() {
  local source=$1 destination=$2
  mkdir -p "$(dirname -- "$destination")"
  cp -a -- "$source" "$destination"
}

copy_relative_item() {
  local source_root=$1 item=$2 destination_root=$3
  local relative=${item#"$source_root"/}
  copy_item "$item" "$destination_root/$relative"
}

write_debian13_preinst() {
  local path=$1 package=$2
  cat > "$path" <<SCRIPT
#!/bin/sh
set -eu
case "\${1:-}" in
  install|upgrade)
    if [ ! -r /etc/os-release ]; then
      echo '$package requires Debian GNU/Linux 13 (trixie) on arm64.' >&2
      exit 1
    fi
    . /etc/os-release
    if [ "\${ID:-}" != debian ] || [ "\${VERSION_ID:-}" != 13 ]; then
      echo '$package supports only Debian GNU/Linux 13 (trixie) on arm64.' >&2
      exit 1
    fi
    if [ "\$(dpkg --print-architecture)" != arm64 ]; then
      echo '$package supports only arm64.' >&2
      exit 1
    fi
    ;;
esac
exit 0
SCRIPT
  chmod 0755 "$path"
}

write_ldconfig_scripts() {
  local root=$1
  cat > "$root/DEBIAN/postinst" <<'SCRIPT'
#!/bin/sh
set -eu
case "${1:-}" in
  configure|abort-upgrade|abort-remove|abort-deconfigure) ldconfig ;;
esac
exit 0
SCRIPT
  cat > "$root/DEBIAN/postrm" <<'SCRIPT'
#!/bin/sh
set -eu
case "${1:-}" in
  remove|purge|abort-install|disappear) ldconfig ;;
esac
exit 0
SCRIPT
  chmod 0755 "$root/DEBIAN/postinst" "$root/DEBIAN/postrm"
}

assert_no_missing_elf_deps() {
  # Usage: assert_no_missing_elf_deps SEARCH_ROOT [extra-library-dir ...]
  local root=$1
  shift
  local library_path= d output elf
  for d in "$@"; do
    [[ -d "$d" ]] || continue
    library_path="${library_path:+$library_path:}$d"
  done
  while IFS= read -r -d '' elf; do
    file -b "$elf" | grep -q 'ELF 64-bit.*aarch64' || continue
    output="$(LD_LIBRARY_PATH="$library_path${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}" ldd "$elf" 2>&1 || true)"
    if grep -q 'not found' <<<"$output"; then
      printf '%s\n' "----- unresolved dependencies: $elf -----" >&2
      printf '%s\n' "$output" >&2
      die "unresolved dynamic dependency in $elf"
    fi
  done < <(find "$root" \( -type f -o -type l \) -print0)
}

assert_only_paths() {
  # Usage: assert_only_paths ROOT REGEX ...
  local root=$1
  shift
  local item rel allowed pattern
  while IFS= read -r -d '' item; do
    rel=/${item#"$root"/}
    allowed=false
    for pattern in "$@"; do
      if [[ "$rel" =~ $pattern ]]; then allowed=true; break; fi
    done
    "$allowed" || die "upstream install produced an unmapped payload path: $rel"
  done < <(find "$root" \( -type f -o -type l \) -print0)
}

payload_map() {
  local source=$1 output=$2 prefix=${3:-}
  {
    printf 'type\tpath\tsha256-or-target\n'
    while IFS= read -r -d '' item; do
      local rel=${item#"$source"/}
      if [ -L "$item" ]; then
        printf 'symlink\t%s%s\t-> %s\n' "$prefix" "$rel" "$(readlink "$item")"
      elif [ -f "$item" ]; then
        printf 'file\t%s%s\t%s\n' "$prefix" "$rel" "$(sha256sum "$item" | awk '{print $1}')"
      else
        printf 'other\t%s%s\t-\n' "$prefix" "$rel"
      fi
    done < <(find "$source" -mindepth 1 \
      -path "$source/DEBIAN" -prune -o \
      -print0 | sort -z)
  } > "$output"
}

write_shlibs_from_root() {
  # Usage: write_shlibs_from_root PACKAGE_ROOT PACKAGE VERSION LIBDIR
  local root=$1 package=$2 version=$3 libdir=$4 lib soname name major
  : > "$root/DEBIAN/shlibs"
  while IFS= read -r -d '' lib; do
    file -b "$lib" | grep -q 'ELF 64-bit.*aarch64' || continue
    soname="$(readelf -d "$lib" 2>/dev/null | awk -F'[][]' '/SONAME/ {print $2; exit}')"
    [[ -n "$soname" ]] || continue
    name=${soname%%.so*}
    major=${soname#*.so.}
    major=${major%%.*}
    [[ "$major" =~ ^[0-9]+$ ]] || continue
    printf '%s %s %s (>= %s)\n' "$name" "$major" "$package" "$version" >> "$root/DEBIAN/shlibs"
  done < <(find "$libdir" \( -type f -o -type l \) -name 'lib*.so.*' -print0 2>/dev/null)
  [[ -s "$root/DEBIAN/shlibs" ]] || rm -f "$root/DEBIAN/shlibs"
}

debian_runtime_dependencies() {
  # Usage: debian_runtime_dependencies ROOT [owned-library-dir ...]
  # Resolve each non-owned ELF dependency to its installed Debian 13 package.
  # This is intentionally evaluated inside the Debian 13 arm64 build container.
  local root=$1
  shift
  local owned_dirs=("$@") elf output line path canonical_path owner
  local -A seen=()
  while IFS= read -r -d '' elf; do
    file -b "$elf" | grep -q 'ELF 64-bit.*aarch64' || continue
    output="$(LD_LIBRARY_PATH="$(IFS=:; echo "${owned_dirs[*]}")${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}" ldd "$elf" 2>&1 || true)"
    while IFS= read -r line; do
      path=
      case "$line" in
        *' => /'*) path=${line#* => }; path=${path%% *} ;;
        [[:space:]]/*) path=${line#${line%%[![:space:]]*}}; path=${path%% *} ;;
      esac
      [[ -n "$path" && -e "$path" ]] || continue
      local owned=false d
      for d in "${owned_dirs[@]}"; do
        [[ -n "$d" && "$path" == "$d"/* ]] && { owned=true; break; }
      done
      "$owned" && continue
      # Debian 13 uses usrmerge: ldd may report /lib/... while dpkg's file
      # database records the same object below /usr/lib/....  Resolve the
      # dependency before querying ownership, then retain the original path as
      # a fallback for non-symlinked loader paths.
      canonical_path="$(readlink -f -- "$path" 2>/dev/null || true)"
      owner=
      if [[ -n "$canonical_path" ]]; then
        owner="$(dpkg-query -S -- "$canonical_path" 2>/dev/null | head -n1 | cut -d: -f1 || true)"
      fi
      if [[ -z "$owner" && "$canonical_path" != "$path" ]]; then
        owner="$(dpkg-query -S -- "$path" 2>/dev/null | head -n1 | cut -d: -f1 || true)"
      fi
      [[ -n "$owner" ]] || die "cannot map runtime dependency $path of $elf to a Debian 13 package"
      seen["$owner"]=1
    done <<<"$output"
  done < <(find "$root" \( -type f -o -type l \) -print0)
  # A package with no ELF payload still gets a valid dependency field.
  if [[ ${#seen[@]} -eq 0 ]]; then
    printf '%s' 'libc6'
  else
    local IFS=', '
    printf '%s' "${!seen[*]}"
  fi
}
