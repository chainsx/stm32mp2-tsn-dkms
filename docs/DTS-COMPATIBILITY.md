# MYiR STM32MP257x Ethernet Switch device-tree compatibility

Target device tree:

```text
arch/arm64/boot/dts/st/myb-stm32mp257x-1GB-ethswitch.dts
```

The selected DTS defines `ETH_SWITCH_ENABLE 1`, includes
`myb-stm32mp257x-ethswitch.dtsi`, and that include enables `switch0`. It also
configures the switch for RGMII and enables the ETH1 and ETH2 controller nodes.
The DKMS package therefore does **not** ship a DTS overlay or patch.

The OpenSTLinux TSN layer associates EDGE with the main TSN bridge Ethernet
interface using the systemd predictable name `end1`. The generated
`stm32mp257-tsn-edge-runtime` package installs:

```text
/etc/modprobe.d/stm32mp257-tsn-edge.conf
```

with `netif="end1:0"`. Inspect `ip -br link` after boot. If the ETH1 MAC has a
different name on this rootfs, edit this one option before loading
`edgx_pfm_lkm`.

## ACM is optional

The named MYiR Ethernet-switch DTS confirms a Switch configuration, but this
repository does not infer an ACM device node solely from that fact. Install the
ACM packages only when the final compiled FDT contains the ACM node required by
your board integration. The ACM module has a soft dependency on `stmmac`,
`stm32_deip`, and `edgx_pfm_lkm`; it is not part of the default switch meta
package.
