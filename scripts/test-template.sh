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
for needle in (
    'workflow_dispatch:',
    'package_revision:',
    'debian:trixie',
    'contents: write',
    'Commit generated APT repository to main',
    'environment:',
    'name: github-pages',
):
    assert needle in text, needle
for p in (
    Path('scripts/build-userspace.sh'),
    Path('scripts/build-dkms.sh'),
    Path('scripts/build-meta.sh'),
):
    assert 'Debian GNU/Linux 13' in p.read_text() or p.name == 'build-dkms.sh'
assert 'BUILD_EXCLUSIVE_ARCH="^(aarch64|arm64)$"' in Path('packaging/dkms/deip/dkms.conf.in').read_text()
assert 'BUILD_EXCLUSIVE_ARCH="^(aarch64|arm64)$"' in Path('packaging/dkms/edge/dkms.conf.in').read_text()
assert 'SYSTEMD_AUTO_ENABLE' not in Path('packaging/userspace/deptp/deptp.service').read_text()
assert 'ConditionPathExists=/etc/deptp/ptp_config.xml' in Path('packaging/userspace/deptp/deptp.service').read_text()
PY

work="$(mktemp -d)"; trap 'rm -rf "$work"' EXIT
mkdir -p \
  "$work/upstream/switch/st.stm32-deip" \
  "$work/upstream/switch/tsn_sw_base.edge-lkm" \
  "$work/upstream/acm/ngn.ngn-dd/acm"
printf '%s\n' '# mock' > "$work/upstream/switch/st.stm32-deip/Makefile"
printf '%s\n' '# mock' > "$work/upstream/switch/tsn_sw_base.edge-lkm/Makefile"
printf '%s\n' '/* OpenSTLinux EDGE public interface mock */' > "$work/upstream/switch/tsn_sw_base.edge-lkm/edge.h"
printf '%s\n' '# mock' > "$work/upstream/acm/ngn.ngn-dd/Makefile"
printf '%s\n' '# mock' > "$work/upstream/acm/ngn.ngn-dd/acm/Makefile"

"$ROOT/scripts/build-dkms.sh" \
  --source "$work/upstream" \
  --version 1.6.8 \
  --revision 7 \
  --out "$work/out" \
  --with-acm true \
  --edge-interface end1 \
  --maintainer 'Test <test@example.invalid>'
"$ROOT/scripts/build-meta.sh" \
  --version 1.6.8 \
  --revision 7 \
  --out "$work/out" \
  --with-userspace false \
  --with-acm true \
  --maintainer 'Test <test@example.invalid>'

for d in "$work/out"/*.deb; do dpkg-deb -I "$d" >/dev/null; done
count="$(find "$work/out" -name '*.deb' | wc -l)"
[[ "$count" -eq 8 ]] || { echo "unexpected package count: $count" >&2; exit 1; }

dpkg-deb -f "$work/out/stm32mp257-tsn-switch_1.6.8-7_arm64.deb" Depends | grep -q 'stm32mp257-tsn-edge-dkms (= 1.6.8-7)'
dpkg-deb -f "$work/out/stm32mp257-tsn-acm_1.6.8-7_arm64.deb" Depends | grep -q 'stm32mp257-tsn-acm-dkms (= 1.6.8-7)'
dpkg-deb -c "$work/out/stm32mp257-tsn-edge-runtime_1.6.8-7_all.deb" | grep -q 'etc/modules-load.d/stm32mp257-tsn-edge.conf'
dpkg-deb -e "$work/out/stm32mp257-tsn-edge-runtime_1.6.8-7_all.deb" "$work/control"
grep -qx '/etc/modules-load.d/stm32mp257-tsn-edge.conf' "$work/control/conffiles"
grep -qx '/etc/modprobe.d/stm32mp257-tsn-edge.conf' "$work/control/conffiles"

dpkg-deb -x "$work/out/stm32mp257-tsn-edge-dkms_1.6.8-7_all.deb" "$work/edge"
grep -q 'sched=fsc sid=sid' "$work/edge/usr/src/stm32mp257-tsn-edge-1.6.8+deb7/dkms.conf"
dpkg-deb -e "$work/out/stm32mp257-tsn-edge-dkms_1.6.8-7_all.deb" "$work/edge-control"
grep -q 'dkms build' "$work/edge-control/postinst"
! grep -q '|| true' "$work/edge-control/postinst"

echo 'Debian 13 TSN template checks passed.'
