#!/usr/bin/env bash

set -Eeuo pipefail

# check a user isn't root
if [ "$(id -u)" = 0 ]; then
  echo "Please, don't run this script as root"
  exit 1
fi

SERVICE_NAME=${1:-vsftpd}
IMAGE=${2:-localhost/vsftpd}
POD=${3:-vsftpd-pod}
BASE_DIR="$HOME"/vsftpd
FTP_STORAGE_PATH=${4:-"$BASE_DIR"/ftp}

echo "Variable values:"
echo "BASE_DIR=$BASE_DIR"
echo "FTP_STORAGE_PATH=$FTP_STORAGE_PATH"
echo "POD=$POD"
echo "IMAGE=$IMAGE"
echo "SERVICE_NAME=$SERVICE_NAME"

podman image exists "$IMAGE" ||
    {
        echo "Image not found: $IMAGE" >&2
        exit 1
    }

# Replace the shell with Podman so signals propagate directly, using 'exec':
exec podman run \
    --rm \
    --log-level=info \
    --log-driver=json-file \
    --read-only \
    --pod "${POD}" \
    --security-opt=no-new-privileges \
    --cap-drop=ALL \
    --cap-add=SETUID \
    --cap-add=SETGID \
    --cap-add=NET_BIND_SERVICE \
    --secret source=vsftpd-ftps-key,target=vsftpd.key,type=mount,uid=9898,gid=9898,mode=0400 \
    -p 3221:21/tcp \
    -p 3220:20/tcp \
    -p 21100-21110:21100-21110/tcp \
    --name "${SERVICE_NAME}" \
    -v "${FTP_STORAGE_PATH}":/srv/ftp:rw \
    -v ./cert/vsftpd.crt:/opt/vsftpd/vsftpd.crt:ro \
    -v ./config/ftp/vsftpd-pam.conf:/etc/pam-mysql.conf:ro \
    -v ./config/ftp/vsftpd.conf:/etc/vsftpd.conf:ro \
    --tmpfs /tmp:rw,noexec,nosuid,size=64m \
    --tmpfs /run:rw,noexec,nosuid,size=16m \
    --tmpfs /var/run,rw,noexec,nosuid,size=16m \
    "$IMAGE"

