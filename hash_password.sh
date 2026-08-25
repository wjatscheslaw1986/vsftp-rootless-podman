#!/bin/bash

read -r -s -p "Enter FTP user password: " ftp_user_pass

# Length validation
if (( ${#ftp_user_pass} < 6 || ${#ftp_user_pass} > 128 )); then
      echo "Error: FTP user password must be between 6 and 128 characters." >&2
        exit 1
fi

echo ""
echo "The sha512 hash: "
echo $(openssl passwd -6 -salt "$(head -c 16 /dev/urandom | xxd -p)" ${ftp_user_pass})

ftp_user_pass=
unset ftp_user_pass
