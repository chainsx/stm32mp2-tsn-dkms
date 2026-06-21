# Debian 13 arm64 validation procedure

## 1. Verify the packaging target and DKMS status

```bash
. /etc/os-release
printf '%s %s\n' "$ID" "$VERSION_ID"
dpkg --print-architecture
sudo dkms status
```

Expected target values are `debian 13` and `arm64`. `dkms status` must show
`stm32mp2-tsn-deip` and `stm32mp2-tsn-edge` for the running kernel.

If installation fails, inspect the fatal DKMS log that is printed by package
post-installation and is retained below:

```bash
/var/lib/dkms/stm32mp2-tsn-*/<version>/build/make.log
```

## 2. Verify the ST module ordering and selected interface

```bash
cat /etc/modules-load.d/stm32mp2-tsn-edge.conf
cat /etc/modprobe.d/stm32mp2-tsn-edge.conf
ip -br link
sudo modprobe stm32_deip
sudo modprobe edgx_pfm_lkm
lsmod | grep -E 'stm32_deip|edgx'
```

The module-load file must list `sch_mqprio`, `sch_prio`, `bridge`, `8021q`, then
`edgx_pfm_lkm`. The modprobe file must contain the `stmmac stm32_deip` soft
dependency and the correct `netif="<main-interface>:0"` value.

## 3. Verify the `libtsn` split and runtime closure

```bash
dpkg -L stm32mp2-tsn-libtsn
dpkg -L stm32mp2-tsn-libtsn-dev
ldconfig -p | grep libtsn
ldd /usr/bin/tsntool
/usr/bin/tsntool --help
```

The runtime package owns versioned `lib*.so.*` files; the development package
owns the headers and unversioned linker name. `ldd` must not print `not found`.
Each package includes `/usr/share/doc/<package>/PAYLOAD-MAP.tsv` for file and
symlink audit.

## 4. Verify DE-gPTP without enabling it implicitly

```bash
systemctl is-enabled deptp.service || true
systemctl cat deptp.service
sudo test -r /etc/deptp/ptp_config.xml
ldd /usr/sbin/deptp
```

The expected initial state is `disabled`. Review the PTP configuration and
network policy before enabling the daemon:

```bash
sudo systemctl enable --now deptp.service
journalctl -u deptp.service -b --no-pager
```

## 5. Optional ACM verification

Only after the deployed FDT contains the ACM node:

```bash
sudo apt install stm32mp2-tsn-acm
sudo modprobe acm
sudo dkms status | grep stm32mp2-tsn-acm
```

The ACM package depends on the matching EDGE DKMS package. During ACM build, the
package rebuilds EDGE in an isolated temporary directory for the running kernel
and supplies its `Module.symvers` via `KBUILD_EXTRA_SYMBOLS`. This is required
for ACM's `edgx_ktime_get_worker_ptp` reference to pass `modpost`.

Do not treat module installation alone as evidence of an ACM hardware path; use
a board-specific ACM application and verify its device-node, interrupts, and
switch integration separately.
