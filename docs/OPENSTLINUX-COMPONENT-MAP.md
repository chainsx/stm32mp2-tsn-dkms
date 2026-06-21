# OpenSTLinux Scarthgap TSN-to-Debian 13 component map

| ST layer recipe/component | Debian 13 arm64 package | Packaging rule retained from ST | Debian-specific adaptation |
|---|---|---|---|
| `kernel-module-st-stm32-deip` | `stm32mp257-tsn-deip-dkms` | `stm32_deip.ko`; external module source | DKMS source package; strict arm64/aarch64 gate; revision is part of DKMS version. |
| `kernel-module-edge` | `stm32mp257-tsn-edge-dkms` | `edgx_pfm_lkm.ko`; `sched=fsc sid=sid` make arguments | DKMS module package plus `stm32mp257-tsn-edge-dev` for `edge.h`. |
| `edgx_sw_modload.conf` | `stm32mp257-tsn-edge-runtime` | Loads `sch_mqprio`, `sch_prio`, `bridge`, `8021q`, `edgx_pfm_lkm` | `/etc/modules-load.d/` conffile. |
| `edgx_sw_modprobe.conf` | `stm32mp257-tsn-edge-runtime` | `softdep edgx_pfm_lkm: stmmac stm32_deip` | `/etc/modprobe.d/` conffile; `netif="end1:0"` is explicit and editable. |
| `tsntool_release`: `libtsn` | `stm32mp257-tsn-libtsn` | `lib*.so.*` runtime split | Uses a Debian `shlibs` file generated from the installed SONAMEs. |
| `tsntool_release`: `libtsn-dev` | `stm32mp257-tsn-libtsn-dev` | `include/libtsn/*.h` plus unversioned `lib*.so` | Exact version dependency on the runtime package. |
| `tsntool_release`: `libtsn-staticdev` | `stm32mp257-tsn-libtsn-staticdev` | `lib*.a` split | Created only when the upstream install actually contains a static archive. |
| `tsntool_release` CLI | `stm32mp257-tsntool` | `/usr/bin/tsntool` and man page | Exact runtime library dependency. |
| `de-ptp-bin_release` | `stm32mp257-tsn-deptp` | Vendor AArch64 payload; service and `ptp_config.xml` | The service is shipped but not enabled; XML is a conffile; all ELF dependencies must resolve on Debian 13 arm64. |
| `kernel-module-tsn-acm` | `stm32mp257-tsn-acm-dkms` | Optional `acm.ko` | Disabled from the default Switch meta-package. |
| `libacmconfig` | `stm32mp257-tsn-acm-config` | Optional ACM user-space payload | Full staged payload is preserved; unresolved ELF dependencies abort the build. |
| TSN rootfs initialization, sysrepo/Netopeer, lldpd, mstpd | not bundled | OpenSTLinux image-level integration | Excluded intentionally: network topology and board policy are not generic Debian package defaults. |
