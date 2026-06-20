#!/usr/bin/env bash
set -Eeuo pipefail

die() { echo "error: $*" >&2; exit 1; }
need() { command -v "$1" >/dev/null 2>&1 || die "missing required command: $1"; }
valid_version() { [[ "$1" =~ ^[0-9][0-9A-Za-z.+:~_-]*$ ]] || die "invalid Debian version: $1"; }
valid_bool() { [[ "$1" == true || "$1" == false ]] || die "expected true or false, got: $1"; }
repo_root() { cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd; }
write_control() {
  local path=$1 package=$2 version=$3 arch=$4 depends=$5 description=$6 maintainer=$7
  cat > "$path" <<CTRL
Package: $package
Version: $version
Section: misc
Priority: optional
Architecture: $arch
Maintainer: $maintainer
Depends: $depends
Description: $description
 OpenSTLinux-compatible STM32MP257 Ethernet Switch / TSN component.
CTRL
}
build_deb() {
  local root=$1 out=$2
  dpkg-deb --root-owner-group --build "$root" "$out" >/dev/null
}
copy_tree_contents() {
  local from=$1 to=$2
  mkdir -p "$to"
  # Keep source packages reproducible and avoid embedding the upstream .git object store.
  ( cd "$from" && tar --exclude=.git -cf - . ) | ( cd "$to" && tar -xf - )
}
