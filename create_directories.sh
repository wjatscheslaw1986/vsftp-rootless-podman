#!/bin/bash

INSTANCE_NAME=${1:-vsftpd-1}
BASE_DIR="${HOME}/${INSTANCE_NAME}"

mkdir -p "${BASE_DIR}"/{ftp,mariadb/{libmysql,data},log/{vsftpd,mariadb}}


