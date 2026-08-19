#!/bin/sh

set -eu

DB_PASSWORD=$(tr -d '\n\r\t ' < /run/secrets/mariadb-password | tr -d '\0')

cat >/run/pam-mysql.conf <<EOF
users.host              = mariadb
users.database          = ftp
users.db_user           = ftp_admin
users.db_passwd         = ${DB_PASSWORD}
users.table             = ftp_users
users.user_column       = username
users.password_column   = password_hash
users.password_crypt    = 1
users.where_clause      = enabled = 1
EOF

chmod 0600 /run/pam-mysql.conf

unset DB_PASSWORD

exec /usr/sbin/vsftpd /etc/vsftpd.conf
