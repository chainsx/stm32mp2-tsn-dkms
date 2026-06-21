# MYiR STM32MP257x Ethernet Switch device-tree compatibility

Target device tree:

```text
arch/arm64/boot/dts/st/myb-stm32mp257x-1GB-ethswitch.dts
```

The selected DTS defines `ETH_SWITCH_ENABLE 1`, includes
`myb-stm32mp257x-ethswitch.dtsi`, enables `switch0`, configures RGMII, and
enables the ETH1/ETH2 controllers. The package therefore does not install a
DTB, overlay, or DTS patch.

The OpenSTLinux EDGE recipe passes the main TSN bridge interface to the module
through `DEFAULT_ETHERNET_MAIN_TSN_BRIDGE_INTERFACE`. This Debian 13 package
mirrors that behaviour with:

```text
/etc/modprobe.d/stm32mp257-tsn-edge.conf
```

Default content:

```text
softdep edgx_pfm_lkm: stmmac stm32_deip
options edgx_pfm_lkm netif="end1:0"
```

On Debian 13, verify the actual interface name using `ip -br link` before
loading `edgx_pfm_lkm`. Update only the `netif` option when the MAC is not
named `end1`.

## ACM remains optional

A Switch-enabled DTS does not establish the presence of the ACM device node or
all ACM-related board resources. Install ACM packages only after inspecting the
actual booted FDT and validating the required hardware integration.
