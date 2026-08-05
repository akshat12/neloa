#!/bin/sh
set -eu

IDENTITY_NAME=${NELOA_LOCAL_CODE_SIGN_IDENTITY:-Neloa Local Development}
LOGIN_KEYCHAIN=$(security default-keychain -d user | sed 's/^[[:space:]]*"//; s/"[[:space:]]*$//')

if security find-identity -v -p codesigning "$LOGIN_KEYCHAIN" 2>/dev/null | grep -Fq "\"$IDENTITY_NAME\""; then
    echo "$IDENTITY_NAME is already available."
    exit 0
fi

TEMP_DIRECTORY=$(mktemp -d "${TMPDIR:-/tmp}/neloa-signing.XXXXXX")
PRIVATE_KEY="$TEMP_DIRECTORY/neloa-local.key"
CERTIFICATE="$TEMP_DIRECTORY/neloa-local.crt"
IDENTITY_ARCHIVE="$TEMP_DIRECTORY/neloa-local.p12"
ARCHIVE_PASSWORD=$(openssl rand -hex 24)

cleanup() {
    find "$TEMP_DIRECTORY" -depth -delete 2>/dev/null || true
}
trap cleanup EXIT INT TERM

openssl req \
    -x509 \
    -newkey rsa:3072 \
    -sha256 \
    -days 3650 \
    -nodes \
    -keyout "$PRIVATE_KEY" \
    -out "$CERTIFICATE" \
    -subj "/CN=$IDENTITY_NAME/O=Neloa Local Development" \
    -addext "keyUsage=critical,digitalSignature" \
    -addext "extendedKeyUsage=codeSigning" \
    >/dev/null 2>&1

openssl pkcs12 \
    -export \
    -legacy \
    -inkey "$PRIVATE_KEY" \
    -in "$CERTIFICATE" \
    -out "$IDENTITY_ARCHIVE" \
    -passout "pass:$ARCHIVE_PASSWORD"

security import "$IDENTITY_ARCHIVE" \
    -k "$LOGIN_KEYCHAIN" \
    -P "$ARCHIVE_PASSWORD" \
    -T /usr/bin/codesign \
    >/dev/null

security add-trusted-cert \
    -d \
    -r trustRoot \
    -p codeSign \
    -k "$LOGIN_KEYCHAIN" \
    "$CERTIFICATE"

if ! security find-identity -v -p codesigning "$LOGIN_KEYCHAIN" 2>/dev/null | grep -Fq "\"$IDENTITY_NAME\""; then
    echo "The signing identity was imported but macOS does not consider it valid." >&2
    exit 1
fi

echo "$IDENTITY_NAME is ready."
