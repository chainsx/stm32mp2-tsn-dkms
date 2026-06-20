#!/usr/bin/env bash
set -Eeuo pipefail
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
. "$SCRIPT_DIR/lib.sh"

out=upstream
switch_ref=28c85fb3a2205766947298eddcdba8149ed37068
acm_ref=23e1ed7d9942136d0526d6f429f0efc3ed2fe35e
with_acm=false
usage() {
  cat <<USAGE
Usage: $0 [options]
  --out DIR
  --switch-ref COMMIT     default: OpenSTLinux scarthgap TSN layer pin
  --acm-ref COMMIT        default: OpenSTLinux scarthgap ACM layer pin
  --with-acm true|false   default: false
USAGE
}
while [[ $# -gt 0 ]]; do
  case "$1" in
    --out) out=$2; shift 2;;
    --switch-ref) switch_ref=$2; shift 2;;
    --acm-ref) acm_ref=$2; shift 2;;
    --with-acm) with_acm=$2; shift 2;;
    -h|--help) usage; exit 0;;
    *) die "unknown argument: $1";;
  esac
done
valid_bool "$with_acm"
need git
rm -rf "$out"
mkdir -p "$out"
fetch() {
  local url=$1 ref=$2 dest=$3
  git clone --filter=blob:none --no-checkout "$url" "$dest"
  git -C "$dest" checkout --detach "$ref"
  git -C "$dest" submodule update --init --recursive
}
fetch https://github.com/STMicroelectronics/tttech-tsn-swch-content.git "$switch_ref" "$out/switch"
printf '%s\n' "$switch_ref" > "$out/SWITCH_COMMIT"
if [[ "$with_acm" == true ]]; then
  fetch https://github.com/STMicroelectronics/tttech-tsn-acm-content.git "$acm_ref" "$out/acm"
  printf '%s\n' "$acm_ref" > "$out/ACM_COMMIT"
fi
