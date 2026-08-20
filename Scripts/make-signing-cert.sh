#!/usr/bin/env bash
# One-time: create a stable self-signed code-signing identity in the login keychain.
#
# Why: ad-hoc signatures (codesign -s -) give the app a new code identity on
# every rebuild. A stable identity keeps one signature across builds, so
# `codesign --verify` means something and the build stops warning.
#
# It does NOT stop the Keychain re-prompting for the stored OAuth refresh
# tokens: the legacy keychain ACL pins the exact code, and this certificate's
# Designated Requirement does not override it. Every rebuild prompts, stable
# identity or not. AGENTS.md records the measurement - do not try to fix it.
#
# The key and certificate are imported as separate PEM files rather than bundled
# into a PKCS#12. OpenSSL 3 writes PKCS#12 with an AES-256 cipher and a SHA-256
# MAC, which Apple's importer cannot verify - it reports "MAC verification failed
# (wrong password?)". PEM sidesteps the format negotiation completely and needs
# no password.
#
# This script is interactive: macOS prompts to authorise the trust change.
set -euo pipefail

NAME="${1:-YouHaveAMeeting Dev}"
KEYCHAIN="${2:-$HOME/Library/Keychains/login.keychain-db}"

if security find-identity -p codesigning | grep -qF "$NAME"; then
  if security find-identity -v -p codesigning | grep -qF "$NAME"; then
    echo "identity '$NAME' already exists - nothing to do"
    exit 0
  fi
  echo "identity '$NAME' exists but is not trusted, so codesign cannot use it." >&2
  echo "Delete it in Keychain Access (login keychain, My Certificates) and re-run." >&2
  exit 1
fi

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

openssl req -x509 -newkey rsa:2048 -nodes -days 3650 \
  -keyout "$WORK/key.pem" -out "$WORK/cert.pem" \
  -subj "/CN=$NAME" \
  -addext "basicConstraints=critical,CA:false" \
  -addext "keyUsage=critical,digitalSignature" \
  -addext "extendedKeyUsage=critical,codeSigning" 2> /dev/null

# Let security detect the formats. Passing -f openssl rejects the PKCS#8 key
# OpenSSL 3 writes, and -f pkcs8 is not a format it accepts either.
# -A and -T /usr/bin/codesign let codesign use the key without prompting.
security import "$WORK/key.pem" -k "$KEYCHAIN" -A -T /usr/bin/codesign
security import "$WORK/cert.pem" -k "$KEYCHAIN" -A -T /usr/bin/codesign

# codesign refuses a certificate it cannot build a chain to, so the self-signed
# root has to be trusted - for code signing only, not for TLS.
security add-trusted-cert -r trustRoot -p codeSign -k "$KEYCHAIN" "$WORK/cert.pem"

echo "created code-signing identity '$NAME'"
security find-identity -v -p codesigning | grep -F "$NAME"
