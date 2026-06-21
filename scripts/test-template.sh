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
userspace = Path('scripts/build-userspace.sh').read_text()
for needle in (
    "TSNTOOL_OPENSTLINUX_PV='1.6.8'",
    "DEPTP_OPENSTLINUX_PV='1.6.7+2.5.2+20240628'",
    "DEPTP_INSTALLER='TTTECH-de-ptp-aarch64-2024-06-28.bin'",
    'make -C "$tool_src" -e clean',
    'make -C "$tool_src" -e all',
    'make -C "$tool_src" -e install DESTDIR="$stage"',
    '--accept-deptp-eula true',
):
    assert needle in userspace, needle
service = Path('packaging/userspace/deptp/deptp.service').read_text()
assert service == """[Unit]
Description=DE-gPTP Edge daemon
After=network.target
Wants=network.target

[Service]
PIDFile=/var/run/deptp.pid
ExecStart=/usr/sbin/deptp /etc/deptp/ptp_config.xml


[Install]
WantedBy=multi-user.target
"""
config = Path('packaging/userspace/deptp/ptp_config.xml').read_text()
assert '<PTP_config xmlns="http://flexibilis.com/schema/ptp/1.0/config">' in config
assert '<Interface name="sw0p2">' in config
assert '<Interface name="sw0p3">' in config
assert '<time_source>internal oscillator</time_source>' in config
assert config.count('\n') == 28
meta = Path('scripts/build-meta.sh').read_text()
assert "DEPTP_OPENSTLINUX_PV='1.6.7+2.5.2+20240628'" in meta
assert 'stm32mp257-tsn-deptp (= ${deptp_deb_ver})' in meta
workflow = Path('.github/workflows/build-publish.yml').read_text()
assert '--accept-deptp-eula true' in workflow
PY

work="$(mktemp -d)"; trap 'rm -rf "$work"' EXIT

# Debian 13 is usrmerged. ldd can report /lib/aarch64-linux-gnu/libc.so.6,
# while dpkg-query records its owner under /usr/lib/aarch64-linux-gnu.
# Exercise the canonical-path fallback without requiring an arm64 host.
runtime_test="$work/runtime-deps"
mkdir -p "$runtime_test/root" "$runtime_test/bin"
: > "$runtime_test/root/libmock.so"
cat > "$runtime_test/bin/file" <<'EOF'
#!/bin/sh
printf '%s\n' 'ELF 64-bit LSB shared object, ARM aarch64'
EOF
cat > "$runtime_test/bin/ldd" <<'EOF'
#!/bin/sh
printf '%s\n' 'libc.so.6 => /lib/aarch64-linux-gnu/libc.so.6 (0x0000000000000000)'
EOF
cat > "$runtime_test/bin/readlink" <<'EOF'
#!/bin/sh
printf '%s\n' '/usr/lib/aarch64-linux-gnu/libc.so.6'
EOF
cat > "$runtime_test/bin/dpkg-query" <<'EOF'
#!/bin/sh
for arg do last=$arg; done
[ "$last" = '/usr/lib/aarch64-linux-gnu/libc.so.6' ] || exit 1
printf '%s\n' 'libc6:arm64: /usr/lib/aarch64-linux-gnu/libc.so.6'
EOF
chmod 0755 "$runtime_test/bin/"*
runtime_deps="$(
  PATH="$runtime_test/bin:$PATH" bash -c '
    set -Eeuo pipefail
    . "$1"
    debian_runtime_dependencies "$2"
  ' _ "$ROOT/scripts/lib.sh" "$runtime_test/root"
)"
[[ "$runtime_deps" == libc6 ]] || {
  echo "usrmerge runtime-dependency ownership resolution failed: $runtime_deps" >&2
  exit 1
}

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

"$ROOT/scripts/build-meta.sh" \
  --version 1.6.8 \
  --revision 7 \
  --out "$work/userspace-meta" \
  --with-userspace true \
  --with-acm false \
  --maintainer 'Test <test@example.invalid>'
dpkg-deb -f "$work/userspace-meta/stm32mp257-tsn-switch_1.6.8-7_arm64.deb" Depends | grep -q 'stm32mp257-tsn-libtsn (= 1.6.8-7)'
dpkg-deb -f "$work/userspace-meta/stm32mp257-tsn-switch_1.6.8-7_arm64.deb" Depends | grep -q 'stm32mp257-tsntool (= 1.6.8-7)'
dpkg-deb -f "$work/userspace-meta/stm32mp257-tsn-switch_1.6.8-7_arm64.deb" Depends | grep -q 'stm32mp257-tsn-deptp (= 1.6.7+2.5.2+20240628-7)'

echo 'Debian 13 TSN template checks passed.'
