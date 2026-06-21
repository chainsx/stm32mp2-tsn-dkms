#!/usr/bin/env bash
set -Eeuo pipefail
source_dir= packages= out= version= revision= with_userspace=false with_acm=false
while [[ $# -gt 0 ]]; do
  case "$1" in
    --source) source_dir=$2; shift 2;;
    --packages) packages=$2; shift 2;;
    --out) out=$2; shift 2;;
    --version) version=$2; shift 2;;
    --revision) revision=$2; shift 2;;
    --with-userspace) with_userspace=$2; shift 2;;
    --with-acm) with_acm=$2; shift 2;;
    *) echo "unknown argument: $1" >&2; exit 64;;
  esac
done
[[ -n "$source_dir" && -n "$packages" && -n "$out" && -n "$version" && -n "$revision" ]] || { echo 'missing required manifest argument' >&2; exit 64; }
mkdir -p "$(dirname "$out")"
{
  echo 'STM32MP257 TSN Build Manifest'
  echo 'Target: Debian GNU/Linux 13 (trixie) arm64'
  echo "Version: $version-$revision"
  echo "Userspace included: $with_userspace"
  echo "ACM included: $with_acm"
  [[ -f "$source_dir/SWITCH_COMMIT" ]] && echo "TTTech switch source commit: $(cat "$source_dir/SWITCH_COMMIT")"
  [[ -f "$source_dir/ACM_COMMIT" ]] && echo "TTTech ACM source commit: $(cat "$source_dir/ACM_COMMIT")"
  echo
  echo 'Packages:'
  for p in "$packages"/*.deb; do
    dpkg-deb -f "$p" Package Version Architecture
  done
  echo
  echo 'SHA256:'
  sha256sum "$packages"/*.deb
} > "$out"
