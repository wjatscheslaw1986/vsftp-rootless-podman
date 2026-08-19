#!/bin/bash

FTP_USER_NAME_FILE=./secrets/ftp_user_name.txt
FTP_USER_PASSWORD_FILE=./secrets/ftp_user_password.txt
FTP_USER_NAME=$(tr -d '\n\r\t ' < "$FTP_USER_NAME_FILE" | tr -d '\0')
FTP_USER_PASSWORD=$(tr -d '\n\r\t ' < "$FTP_USER_PASSWORD_FILE" | tr -d '\0')

if [[ -z "$FTP_USER_PASSWORD" ]]; then
    echo "FTP user password is empty" >&2
    exit 1
fi

FTP_USER_PASSWORD_HASH=$(openssl passwd -6 "${FTP_USER_PASSWORD}")
unset FTP_USER_PASSWORD

cat > ./docker_files/init.sql << EOF
INSERT INTO ftp_users (
    username,
    password_hash,
    enabled
)
VALUES (
    "${FTP_USER_NAME}",
    "${FTP_USER_PASSWORD_HASH}",
    TRUE
);
