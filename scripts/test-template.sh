#!/usr/bin/env bash
set -Eeuo pipefail
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
for s in "$ROOT"/scripts/*.sh; do bash -n "$s"; done
python3 - <<'PY'
from pathlib import Path
p = Path('.github/workflows/build-publish.yml')
assert p.exists()
text = p.read_text()
for needle in ('contents: write', 'Commit generated APT repository to main', 'debian/', 'ubuntu-24.04-arm'):
    assert needle in text, needle
PY
work="$(mktemp -d)"; trap 'rm -rf "$work"' EXIT
mkdir -p "$work/upstream/switch/st.stm32-deip" "$work/upstream/switch/tsn_sw_base.edge-lkm" "$work/upstream/acm/ngn.ngn-dd/acm"
for f in "$work/upstream/switch/st.stm32-deip/Makefile" "$work/upstream/switch/tsn_sw_base.edge-lkm/Makefile" "$work/upstream/acm/ngn.ngn-dd/Makefile" "$work/upstream/acm/ngn.ngn-dd/acm/Makefile"; do echo '# mock' > "$f"; done
"$ROOT/scripts/build-dkms.sh" --source "$work/upstream" --version 1.6.8 --out "$work/out" --with-acm true --maintainer 'Test <test@example.invalid>'
"$ROOT/scripts/build-meta.sh" --version 1.6.8 --out "$work/out" --with-userspace false --with-acm true --maintainer 'Test <test@example.invalid>'
for d in "$work/out"/*.deb; do dpkg-deb -I "$d" >/dev/null; done
count="$(find "$work/out" -name '*.deb' | wc -l)"
[[ "$count" -eq 7 ]] || { echo "unexpected package count: $count" >&2; exit 1; }
dpkg-deb -f "$work/out/stm32mp257-tsn-switch_1.6.8-1_all.deb" Depends | grep -q 'stm32mp257-tsn-edge-dkms'
dpkg-deb -f "$work/out/stm32mp257-tsn-acm_1.6.8-1_all.deb" Depends | grep -q 'stm32mp257-tsn-acm-dkms'
echo 'template checks passed'
