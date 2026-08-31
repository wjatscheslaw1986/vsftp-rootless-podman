#!/usr/bin/env bash

shred secrets/mariadb-root-password
shred secrets/mariadb-password
shred secrets/ca-password
shred secrets/keys/vsftpd.key

rm -f secrets/mariadb-root-password
rm -f secrets/mariadb-password
rm -f secrets/ca-password
rm -f secrets/keys/vsftpd.key

echo "Passwords are wiped out"
