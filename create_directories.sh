#!/bin/bash

INSTANCE_NAME=${1:-vsftpd-1}
MARIADB_OWNERSHIP=${2:-1000:1000}
VSFTPD_OWNERSHIP=${3:-1000:1000}
BASE_DIR="${HOME}/${INSTANCE_NAME}"

mkdir -p "${BASE_DIR}"/{ftp,mariadb/data}
#chown -R "${VSFTPD_OWNERSHIP}" "${BASE_DIR}/ftp"
#chown -R "${MARIADB_OWNERSHIP}" "${BASE_DIR}/mariadb"

echo "Directory structure created"
