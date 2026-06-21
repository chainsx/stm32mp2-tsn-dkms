#!/usr/bin/env bash
set -Eeuo pipefail
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
. "$SCRIPT_DIR/lib.sh"

source_dir= version= revision=1 out_dir=dist/debian
maintainer='STM32MP257 TSN Packaging <noreply@example.invalid>'
with_userspace=false with_acm=false edge_interface=end1
while [[ $# -gt 0 ]]; do
  case "$1" in
    --source) source_dir=$2; shift 2;;
    --version) version=$2; shift 2;;
    --revision) revision=$2; shift 2;;
    --out) out_dir=$2; shift 2;;
    --maintainer) maintainer=$2; shift 2;;
    --with-userspace) with_userspace=$2; shift 2;;
    --with-acm) with_acm=$2; shift 2;;
    --edge-interface) edge_interface=$2; shift 2;;
    -h|--help) exit 0;;
    *) die "unknown argument: $1";;
  esac
done
[[ -n "$source_dir" && -n "$version" ]] || die '--source and --version are required'
valid_version "$version"; valid_revision "$revision"; valid_bool "$with_userspace"; valid_bool "$with_acm"; valid_interface "$edge_interface"
mkdir -p "$out_dir"
"$SCRIPT_DIR/build-dkms.sh" --source "$source_dir" --version "$version" --revision "$revision" --out "$out_dir" --maintainer "$maintainer" --with-acm "$with_acm" --edge-interface "$edge_interface"
if [[ "$with_userspace" == true ]]; then
  "$SCRIPT_DIR/build-userspace.sh" --source "$source_dir" --version "$version" --revision "$revision" --out "$out_dir" --maintainer "$maintainer" --with-acm "$with_acm"
fi
"$SCRIPT_DIR/build-meta.sh" --version "$version" --revision "$revision" --out "$out_dir" --maintainer "$maintainer" --with-userspace "$with_userspace" --with-acm "$with_acm"
