#!/usr/bin/env bash
set -Eeuo pipefail
name='STM32MP257 TSN APT Archive'
email='noreply@example.invalid'
out=.secrets
while [[ $# -gt 0 ]]; do
  case "$1" in
    --name) name=$2; shift 2;;
    --email) email=$2; shift 2;;
    --out) out=$2; shift 2;;
    *) echo "unknown argument: $1" >&2; exit 64;;
  esac
done
mkdir -p "$out"
export GNUPGHOME="$(mktemp -d)"; trap 'rm -rf "$GNUPGHOME"' EXIT
chmod 700 "$GNUPGHOME"
gpg --batch --passphrase '' --quick-generate-key "$name <$email>" ed25519 sign 3y
fingerprint="$(gpg --batch --with-colons --list-secret-keys | awk -F: '$1=="fpr"{print $10; exit}')"
gpg --batch --armor --export-secret-keys "$fingerprint" > "$out/private-key.asc"
gpg --batch --armor --export "$fingerprint" > "$out/public-key.asc"
printf '%s\n' "$fingerprint" > "$out/fingerprint.txt"
chmod 600 "$out/private-key.asc"
printf 'Created %s\n' "$out/private-key.asc"
