#!/usr/bin/env bash

CA_PASSWORD_FILE="secrets/ca-password"

set -Eeuo pipefail

mkdir -p cert secrets/keys && chmod 700 cert secrets/keys

if [[ ! -f "$CA_PASSWORD_FILE" ]]; then
    echo "CA password file not found" >&2
    exit 1
fi

rm -f secrets/keys/ca.key cert/ca.crt secrets/keys/vsftpd.key cert/vsftpd.csr cert/vsftpd.crt

echo
echo "Generating keys and certificates..."
openssl genrsa -aes256 -out secrets/keys/ca.key -passout "file:${CA_PASSWORD_FILE}" 4096
chmod 600 secrets/keys/ca.key
openssl req -config config/ssl/ca.conf -x509 -new -key secrets/keys/ca.key -days 3650 -out cert/ca.crt -passin "file:${CA_PASSWORD_FILE}"

openssl genrsa -traditional -out secrets/keys/vsftpd.key 4096
chmod 600 secrets/keys/vsftpd.key
openssl req -new -config config/ssl/vsftpd-cert.conf -key secrets/keys/vsftpd.key -out cert/vsftpd.csr
openssl x509 -req -CA cert/ca.crt -CAkey secrets/keys/ca.key -in cert/vsftpd.csr -out cert/vsftpd.crt -passin "file:${CA_PASSWORD_FILE}" -days 3649 -sha256 -extfile config/ssl/vsftpd-cert.conf -extensions v3_server

shred secrets/keys/ca.key && rm secrets/keys/ca.key

find ./cert -type f -name '*.csr' -delete
find ./cert -type f -exec chmod 644 {} +

echo
echo "SSL files generated:"
echo "CA certificate for the client: cert/ca.crt"
echo "FTPS certificate for the server: cert/vsftpd.crt"
echo "FTPS private key for the server: secrets/keys/vsftpd.key"

