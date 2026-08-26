#!/bin/bash

INSTANCE_NAME=${1:-vsftpd-1}
BASE_DIR="${HOME}/${INSTANCE_NAME}"
MARIADB_OWNERSHIP=${2:-1000:1000}
VSFTPD_OWNERSHIP=${3:-1000:1000}
VSFTPD_ROOT_OWNERSHIP=${4:-1000:1000}

mkdir -p "${BASE_DIR}"/{ftp,mariadb/data,log/{vsftpd,mariadb}}

if [ "$(id -u)" = 0 ]; then
    chown -R "${VSFTPD_OWNERSHIP}" "${BASE_DIR}/ftp"
    chown -R "${MARIADB_OWNERSHIP}" "${BASE_DIR}/mariadb"
    chown -R "${VSFTPD_ROOT_OWNERSHIP}" "${BASE_DIR}/log/vsftpd"
    chown -R "${MARIADB_OWNERSHIP}" "${BASE_DIR}/log/mariadb"
    echo "Directory structure created"
else
    echo "You need to execute 'chown -R "${VSFTPD_ROOT_OWNERSHIP}" "${BASE_DIR}/ftp"' with root privileges, presumably"
    echo "You need to execute 'chown -R "${VSFTPD_ROOT_OWNERSHIP}" "${BASE_DIR}/log/vsftpd"' with root privileges, presumably"
    echo "You need to execute 'chown -R "${MARIADB_OWNERSHIP}" "${BASE_DIR}/mariadb"' with root privileges, presumably"
    echo "You need to execute 'chown -R "${MARIADB_OWNERSHIP}" "${BASE_DIR}/log/mariadb"' with root privileges, presumably"
fi

echo "For each new FTP user, you must create their data folder structure under "${BASE_DIR}/ftp". For example, for user 'alice' you need to create "${BASE_DIR}/ftp/alice/data". The "${BASE_DIR}/ftp" and "${BASE_DIR}/ftp/alice" must both be owned by "${VSFTPD_ROOT_OWNERSHIP}". The "${BASE_DIR}/ftp/alice/data" folder must belong to "${VSFTPD_OWNERSHIP}". The "${BASE_DIR}/ftp/alice/data" and the "${BASE_DIR}/ftp" folders must have 0755 permissions. The "${BASE_DIR}/ftp/alice" folder must have 0555 permissions. Good luck with not messing this up."
