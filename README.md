# STM32MP257 Ethernet Switch / TSN DKMS and APT repository

This repository packages the **out-of-tree** Ethernet Switch / TSN modules used
by OpenSTLinux for an STM32MP257 and publishes a signed flat Debian/Ubuntu APT
repository. It targets the MYiR device tree:

```text
chainsx/linux-stm32mp2:linux-6.6
arch/arm64/boot/dts/st/myb-stm32mp257x-1GB-ethswitch.dts
```

That DTS enables the Ethernet Switch (`ETH_SWITCH_ENABLE=1` and `switch0`
status `okay`). See [docs/DTS-COMPATIBILITY.md](docs/DTS-COMPATIBILITY.md).

## Packages

The default `stm32mp257-tsn-switch` meta package installs:

```text
stm32mp257-tsn-deip-dkms      -> stm32_deip.ko
stm32mp257-tsn-edge-dkms      -> edgx_pfm_lkm.ko
stm32mp257-tsn-edge-runtime   -> modules-load/modprobe configuration
```

When the workflow is run with **include_userspace=true**, it also builds:

```text
stm32mp257-tsn-libtsn         -> libtsn shared library
stm32mp257-tsntool            -> TSN Switch configuration CLI
stm32mp257-tsn-deptp          -> DE-gPTP daemon
```

When **include_acm=true**, the optional ACM stack is also produced:

```text
stm32mp257-tsn-acm-dkms       -> acm.ko
stm32mp257-tsn-acm-runtime    -> ACM module load configuration
stm32mp257-tsn-acm-config     -> libacmconfig user-space library
stm32mp257-tsn-acm            -> ACM meta package
```

ACM is deliberately separate: Ethernet Switch enablement in the MYiR DTS does
not by itself establish that the final FDT contains an ACM device node.

## Source pins

The build scripts default to the exact commits used by the OpenSTLinux
Scarthgap layers:

```text
TTTech switch content: 28c85fb3a2205766947298eddcdba8149ed37068
TTTech ACM content:    23e1ed7d9942136d0526d6f429f0efc3ed2fe35e
```

Build input is fetched in GitHub Actions; no upstream source or vendor binary
is committed into this repository.

## Build and publish in GitHub Actions

1. Create an archive signing key locally:

   ```bash
   ./scripts/bootstrap-signing-key.sh \
     --name 'STM32MP257 TSN APT Archive' \
     --email 'cchainsx@gmail.com' \
     --out .secrets
   ```

2. Add `.secrets/private-key.asc` as the repository Actions secret
   `APT_GPG_PRIVATE_KEY`. Keep the private key out of git.

3. In **Settings → Actions → General**, set **Workflow permissions** to
   **Read and write permissions**. In **Settings → Pages**, choose
   **GitHub Actions**.

4. Run **Build, commit and publish STM32MP257 TSN APT repository** from the
   `main` branch.

The workflow builds source DKMS `.deb` files on `ubuntu-24.04`, builds arm64
user-space `.deb` files on `ubuntu-24.04-arm`, creates `Packages`, `Release`,
`InRelease`, `Release.gpg`, and `KEY.gpg`, then commits them into `main`:

```text
main/
├── debian/
│   ├── *.deb
│   ├── Packages*
│   ├── Release
│   ├── Release.gpg
│   └── InRelease
├── KEY.gpg
├── stm32mp2-tsn.sources
└── BUILD-MANIFEST.txt
```

The same static tree is published to GitHub Pages at:

```text
https://chainsx.github.io/stm32mp2-tsn-dkms/debian/
```

## Install on STM32MP257

The target must run a Linux 6.6-based kernel with matching headers installed:

```bash
sudo apt install dkms build-essential linux-headers-$(uname -r)
```

Add the archive key and source:

```bash
BASE=https://chainsx.github.io/stm32mp2-tsn-dkms

curl -fsSL "$BASE/KEY.gpg" \
  | gpg --dearmor \
  | sudo tee /usr/share/keyrings/stm32mp257-tsn-archive-keyring.gpg >/dev/null

curl -fsSL "$BASE/stm32mp2-tsn.sources" \
  | sudo tee /etc/apt/sources.list.d/stm32mp2-tsn.sources >/dev/null

sudo apt update
sudo apt install stm32mp257-tsn-switch
```

The installed EDGE configuration assumes the OpenSTLinux systemd interface name
`end1`. Confirm the ETH1 interface with `ip -br link`; adjust
`/etc/modprobe.d/stm32mp257-tsn-edge.conf` before loading the stack when it is
not `end1`.

```bash
sudo dkms status
sudo modprobe stm32_deip
sudo modprobe edgx_pfm_lkm
lsmod | grep -E 'stm32_deip|edgx'
```

To install ACM only after validating the final device tree:

```bash
sudo apt install stm32mp257-tsn-acm
```

## Licensing

The kernel source recipes are GPL-2.0. The OpenSTLinux user-space recipes are
labelled `TTTECH-license`, and the DE-PTP recipe requires an explicit ST EULA
acceptance. User-space builds are therefore opt-in and Actions refuses them
without both relevant acknowledgements. See
[NOTICE-REDISTRIBUTION.md](NOTICE-REDISTRIBUTION.md).

## Repository checks

```bash
./scripts/test-template.sh
```

This performs shell syntax validation, checks the workflow has an arm64
user-space job and a commit-to-`main` publication step, then mock-builds all
DKMS/runtime package templates.
