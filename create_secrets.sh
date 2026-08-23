#!/usr/bin/env bash
set -euo pipefail

umask 077
mkdir -p secrets

if [[ -e secrets/mariadb-root-password &&
      -e secrets/mariadb-password &&
      -e secrets/ca-password ]]; then
    while true; do
        read -p "Secrets already exist; do you want to overwrite them? (N/y): " overwrite
        overwrite="${overwrite,,}"
        case "$overwrite" in
        ""|n|no)
            echo "Using existing secrets"
            exit 0
            ;;
        y|yes)
            echo "Rotating secrets"
            break
            ;;
        esac
    done
fi

find secrets/ -type f ! -name .gitkeep -delete

read -r -s -p "Enter MariaDB root password: " root_pass
echo
read -r -s -p "Enter MariaDB \"ftp\" database password: " db_pass
echo
read -r -s -p "Enter vsftpd Certificate Authority password (needed to create FTP-over-SSL infrastructure): " ca_pass
echo


# Length validation
if (( ${#root_pass} < 6 || ${#root_pass} > 128 )); then
      echo "Error: MariaDB root's password must be between 6 and 128 characters." >&2
        exit 1
fi

if (( ${#db_pass} < 6 || ${#db_pass} > 128 )); then
      echo "Error: MariaDB \"ftp\" database' password must be between 6 and 128 characters." >&2
        exit 1
fi

if (( ${#ca_pass} < 6 || ${#ca_pass} > 256 )); then
      echo "Error: CA password must be between 6 and 256 characters." >&2
        exit 1
fi

printf '%s' "$root_pass" > secrets/mariadb-root-password
printf '%s' "$db_pass"   > secrets/mariadb-password
printf '%s' "$ca_pass"   > secrets/ca-password


root_pass= db_pass= ca_pass=
unset root_pass db_pass ca_pass

echo "Secrets written to secrets/ (mode 600)."
