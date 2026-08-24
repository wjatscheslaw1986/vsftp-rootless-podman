#!/bin/bash

INSTANCE_NAME=${1:-vsftpd-1}
BASE_DIR="${HOME}/${INSTANCE_NAME}"
MARIADB_OWNERSHIP=${2:-1000:1000}
VSFTPD_OWNERSHIP=${3:-1000:1000}

mkdir -p "${BASE_DIR}"/{ftp,mariadb/data,log/{vsftpd,mariadb}}

if [ "$(id -u)" = 0 ]; then
    chown -R "${VSFTPD_OWNERSHIP}" "${BASE_DIR}/ftp"
    chown -R "${MARIADB_OWNERSHIP}" "${BASE_DIR}/mariadb"
    chown -R "${VSFTPD_OWNERSHIP}" "${BASE_DIR}/log/vsftpd"
    chown -R "${MARIADB_OWNERSHIP}" "${BASE_DIR}/log/mariadb"
    echo "Directory structure created"
else
    echo "You need to execute 'chown -R "${VSFTPD_OWNERSHIP}" "${BASE_DIR}/ftp"' with root privileges, presumably"
    echo "You need to execute 'chown -R "${VSFTPD_OWNERSHIP}" "${BASE_DIR}/log/vsftpd"' with root privileges, presumably"
    echo "You need to execute 'chown -R "${MARIADB_OWNERSHIP}" "${BASE_DIR}/mariadb"' with root privileges, presumably"
    echo "You need to execute 'chown -R "${MARIADB_OWNERSHIP}" "${BASE_DIR}/log/mariadb"' with root privileges, presumably"
fi

