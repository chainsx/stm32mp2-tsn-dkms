#!/usr/bin/env bash
set -Eeuo pipefail
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
. "$SCRIPT_DIR/lib.sh"
repo_dir= key_id= public_key= origin='STM32MP257 TSN APT Archive' label='STM32MP257 TSN APT Archive'
while [[ $# -gt 0 ]]; do
  case "$1" in
    --repo) repo_dir=$2; shift 2;;
    --key-id) key_id=$2; shift 2;;
    --public-key) public_key=$2; shift 2;;
    --origin) origin=$2; shift 2;;
    --label) label=$2; shift 2;;
    -h|--help) exit 0;;
    *) die "unknown argument: $1";;
  esac
done
[[ -n "$repo_dir" && -n "$key_id" && -n "$public_key" ]] || die '--repo --key-id --public-key are required'
need apt-ftparchive; need gpg
compgen -G "$repo_dir/*.deb" >/dev/null || die "no debian packages in $repo_dir"
mkdir -p "$(dirname "$public_key")"
pushd "$repo_dir" >/dev/null
apt-ftparchive packages . > Packages
gzip -9fk Packages
xz -9efk Packages
apt-ftparchive \
  -o "APT::FTPArchive::Release::Origin=$origin" \
  -o "APT::FTPArchive::Release::Label=$label" \
  -o 'APT::FTPArchive::Release::Suite=./' \
  -o 'APT::FTPArchive::Release::Codename=./' \
  -o 'APT::FTPArchive::Release::Architectures=arm64 all' \
  -o 'APT::FTPArchive::Release::Components=main' \
  release . > Release
args=(--batch --yes --local-user "$key_id")
if [[ -n "${APT_GPG_PASSPHRASE:-}" ]]; then args+=(--pinentry-mode loopback --passphrase "$APT_GPG_PASSPHRASE"); fi
gpg "${args[@]}" --armor --detach-sign --output Release.gpg Release
gpg "${args[@]}" --clearsign --output InRelease Release
popd >/dev/null
gpg --batch --yes --armor --export "$key_id" > "$public_key"
