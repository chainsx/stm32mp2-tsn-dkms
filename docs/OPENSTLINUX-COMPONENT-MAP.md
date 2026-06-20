# OpenSTLinux component map

| Repository/layer | OpenSTLinux recipe/component | Repository package | Classification |
|---|---|---|---|
| `meta-st-stm32mp-tsn-swch` | `kernel-module-st-stm32-deip` | `stm32mp257-tsn-deip-dkms` | External GPL kernel module, `stm32_deip.ko` |
| `meta-st-stm32mp-tsn-swch` | `kernel-module-edge` | `stm32mp257-tsn-edge-dkms` + runtime | External GPL kernel module, `edgx_pfm_lkm.ko` |
| `meta-st-stm32mp-tsn-swch` | `tsntool_release` | `stm32mp257-tsn-libtsn`, `stm32mp257-tsntool` | TTTech-licensed Switch user-space API/tool |
| `meta-st-stm32mp-tsn-swch` | `de-ptp-bin_release` | `stm32mp257-tsn-deptp` | TTTech binary PTP daemon; gated by EULA/redistribution confirmation |
| `meta-st-stm32mp-tsn-acm` | `kernel-module-tsn-acm` | `stm32mp257-tsn-acm-dkms` + runtime | Optional GPL ACM kernel module, `acm.ko` |
| `meta-st-stm32mp-tsn-acm` | `libacmconfig` | `stm32mp257-tsn-acm-config` | Optional TTTech ACM user-space configuration library |

The ACM layer additionally contains an ACM demo, monitoring client, a Netopeer2
sysrepo plug-in, and YANG definitions. They are integration/demo components,
not generic user-space drivers. They require OpenSTLinux's sysrepo/libyang/
netopeer2 stack and board-specific ACM device-tree deployment, so this generic
Ubuntu/Debian repository deliberately does not claim to package them.
