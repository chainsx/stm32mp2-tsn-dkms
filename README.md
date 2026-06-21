# STM32MP2 Ethernet Switch / TSN packages for Debian 13 arm64

This repository converts the STM32MP257 TSN Switch components selected by the
OpenSTLinux Scarthgap layers into a signed APT repository for **Debian GNU/Linux
13 (trixie) arm64 only**. It targets the MYiR device tree:

```text
chainsx/linux-stm32mp2:linux-6.6
arch/arm64/boot/dts/st/myb-stm32mp257x-1GB-ethswitch.dts
```

The DTS enables the Ethernet Switch (`ETH_SWITCH_ENABLE=1` and `switch0`
`status = "okay"`). This repository does not ship a device-tree overlay or make
an ACM assumption from Switch enablement alone.

## OpenSTLinux-to-Debian package map

The package split follows the ST Scarthgap recipes rather than placing every
file in one opaque archive:

```text
OpenSTLinux component                    Debian 13 package
---------------------------------------  -------------------------------------------
kernel-module-st-stm32-deip              stm32mp2-tsn-deip-dkms
                                         -> stm32_deip.ko
kernel-module-edge                       stm32mp2-tsn-edge-dkms
                                         -> edgx_pfm_lkm.ko
edge runtime fragments                   stm32mp2-tsn-edge-runtime
                                         -> exact module-load and softdep rules
edge public header                       stm32mp2-tsn-edge-dev
libtsn: lib*.so.*                        stm32mp2-tsn-libtsn
libtsn-dev: headers + lib*.so            stm32mp2-tsn-libtsn-dev
libtsn-staticdev: lib*.a                 stm32mp2-tsn-libtsn-staticdev, when present
tsntool                                  stm32mp2-tsntool
de-ptp-bin_release                       stm32mp2-tsn-deptp
kernel-module-tsn-acm (optional)         stm32mp2-tsn-acm-dkms
libacmconfig (optional)                  stm32mp2-tsn-acm-config
```

`stm32mp2-tsn-switch` is the base meta-package. It installs the two DKMS
modules and the board configuration. When the manual workflow enables
`include_userspace`, it also depends on `libtsn`, `tsntool`, and DE-gPTP.
`stm32mp2-tsn-acm` remains separate because a Switch-enabled FDT does not by
itself prove that the ACM hardware node and board resources are available.

For user-space builds, the upstream revisions are deliberately fixed to the
OpenSTLinux scarthgap recipes: `tsntool_release` is `1.6.8`, while
`de-ptp-bin_release` is the independent `1.6.7-2.5.2-2024-06-28` vendor
release. Consequently, `include_userspace=true` requires `tsn_version=1.6.8`;
the resulting DE-PTP Debian package is versioned
`1.6.7+2.5.2+20240628-<revision>`. Local `build-userspace.sh` and
`build-all.sh` invocations must explicitly pass `--accept-deptp-eula true`.

## What is intentionally not packaged as a generic Debian service

The ST layer includes rootfs automation, systemd-networkd configuration,
sysrepo/Netopeer integration, lldpd, mstpd, and time-synchronization policy.
Those pieces are coupled to the OpenSTLinux image and network topology. This
repository preserves the module, library, CLI, DE-gPTP service, and configuration
boundaries, but it does **not** claim that its generic Debian package can safely
apply ST's complete rootfs automation.

The `deptp.service` unit is shipped but remains disabled after installation,
matching the ST recipe. `/etc/deptp/ptp_config.xml` is a Debian conffile. Review
that configuration and the selected interface before enabling DE-gPTP.

## Build input and safeguards

The workflow pins the switch and optional ACM content commits used by the ST
Scarthgap layers. User-space publication is opt-in because the ST recipes label
these payloads as TTTech licensed, and DE-PTP requires explicit EULA acceptance.
The workflow requires both acknowledgements before user-space artifacts are
built or published.

All runtime user-space packages are built inside a native **Debian 13 arm64**
container. Before a package is emitted, the builder:

- rejects payload files not mapped by the OpenSTLinux component split;
- runs `ldd` on every AArch64 ELF file and fails on `not found`;
- derives the Debian runtime dependencies from the Debian 13 arm64 build
  environment;
- records every copied payload file and symlink in `PAYLOAD-MAP.tsv`.

DKMS packages use `BUILD_EXCLUSIVE_ARCH="^(aarch64|arm64)$"`, include the Debian
revision in `PACKAGE_VERSION`, and make a failed `dkms build`/`dkms install`
fatal while printing the associated `make.log`. When ACM is selected, its DKMS
build creates an isolated EDGE build for the target kernel and passes EDGE's
`Module.symvers` through `KBUILD_EXTRA_SYMBOLS`; this resolves the exported
`edgx_ktime_get_worker_ptp` dependency during `modpost`.

## Install and validate on the target

The target must run Debian GNU/Linux 13 arm64 with a Linux 6.6-based kernel and
matching headers:

```bash
sudo apt install dkms build-essential linux-headers-$(uname -r)
```

Install the published key/source, then install the base stack:

On the STM32MP2 ARM64 target:

```bash
curl -fsSL https://chainsx.github.io/stm32mp2-tsn-dkms/KEY.gpg \
  | gpg --dearmor \
  | sudo tee /usr/share/keyrings/stm32mp2-tsn-archive-keyring.gpg >/dev/null

sudo tee /etc/apt/sources.list.d/stm32mp2-tsn.sources >/dev/null <<'EOF2'
Types: deb
URIs: https://chainsx.github.io/stm32mp2-tsn-dkms/debian
Suites: ./
Architectures: arm64
Signed-By: /usr/share/keyrings/stm32mp2-tsn-archive-keyring.gpg
EOF2
```

```bash
sudo apt update
sudo apt install stm32mp2-tsn-switch
```

Do **not** install `stm32mp2-tsn*` with an APT glob. That pattern also selects
the optional ACM stack, development headers, and static library packages. Install
ACM only after its device-tree node and board resources are validated:

```bash
sudo apt install stm32mp2-tsn-acm
```

DKMS package removal is transactional: the package removes its DKMS registration
in `prerm`, while its `/usr/src` tree is still present. If a build or install
fails, `postinst` removes the partial DKMS registration before returning an
error; this prevents a later `apt purge` from being blocked by a missing DKMS
source-directory symlink.

### Migration from the legacy package prefix

Earlier repository publications used the `stm32mp257-tsn-*` package namespace.
Remove those packages before installing the new `stm32mp2-tsn-*` packages: both
namespaces install the same DKMS modules and must not coexist.

```bash
sudo apt purge 'stm32mp257-tsn-*'
sudo apt autoremove
sudo apt update
sudo apt install stm32mp2-tsn-switch
```

The runtime configuration uses the OpenSTLinux default `end1:0`. Check the
actual MAC name before loading the switch stack:

```bash
ip -br link
cat /etc/modprobe.d/stm32mp2-tsn-edge.conf
sudo modprobe stm32_deip
sudo modprobe edgx_pfm_lkm
sudo dkms status
lsmod | grep -E 'stm32_deip|edgx'
```

Review `/etc/deptp/ptp_config.xml` first. Enable DE-gPTP only when the PTP
network and its interface configuration are known:

```bash
sudo systemctl enable --now deptp.service
systemctl status deptp.service
```

Detailed verification, including module configuration, user-space closure, and
DE-gPTP service checks, is in `docs/DEBIAN13-VALIDATION.md`.

## Local template test

```bash
./scripts/test-template.sh
```

It validates shell and workflow structure and mock-builds all DKMS, runtime,
header, and meta package templates with a non-default Debian revision.

## Licensing and redistribution

Kernel-source packaging follows the GPL-licensed upstream components. TSN
user-space and DE-gPTP inputs are separately controlled by ST/TTTech terms.
Read `NOTICE-REDISTRIBUTION.md`; do not enable user-space publication without the
required licence acceptance and distribution rights.
