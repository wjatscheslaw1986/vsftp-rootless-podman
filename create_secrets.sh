#!/usr/bin/env bash
set -euo pipefail

umask 077
mkdir -p secrets
find secrets/ -type f -exec rm {} +

read -r -s -p "Enter MariaDB root password: " root_pass
echo
read -r -s -p "Enter MariaDB \"ftp\" database password: " db_pass
echo
read -r -s -p "Enter vsftpd Certificate Authority password (needed to create FTP-over-SSL infrastructure): " ca_pass
echo


# Length validation
if [[ -z ${#root_pass} || ${#root_pass} -lt 6 || ${#root_pass} -gt 128 ]]; then
  echo "Error: MariaDB root's password must be between 6 and 128 characters." >&2
  exit 1
fi

if [[ -z ${#db_pass} || ${#db_pass} -lt 6 || ${#db_pass} -gt 128 ]]; then
  echo "Error: MariaDB \"ftp\" database' password must be between 6 and 128 characters." >&2
  exit 1
fi

if [[ -z ${#ca_pass} || ${#ca_pass} -lt 6 || ${#ca_pass} -gt 256 ]]; then
  echo "Error: CA password must be between 6 and 256 characters." >&2
  exit 1
fi


printf '%s' "$root_pass" > secrets/mariadb-root-password
printf '%s' "$db_pass"   > secrets/mariadb-password
printf '%s' "$ca_pass"   > secrets/ca-password


root_pass= db_pass= ca_pass=
unset root_pass db_pass ca_pass

echo "Secrets written to secrets/ (mode 600)."
