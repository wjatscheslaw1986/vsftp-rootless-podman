#!/usr/bin/env bash

set -Eeuo pipefail

# check a user isn't root
if [ "$(id -u)" = 0 ]; then
  echo "Please, don't run this script as root"
  exit 1
fi

SERVICE_NAME=${1:-}

if [[ -z "$SERVICE_NAME" ]]; then
  echo "Service name is required." >&2
  exit 1
fi

IMAGE=${2:-localhost/vsftpd}
POD=${3:-${SERVICE_NAME}}
BASE_DIR="$HOME"/"${SERVICE_NAME}"
FTP_STORAGE_PATH=${4:-"$BASE_DIR"/ftp}
LOGS_DIR=${5:-"$BASE_DIR"/log/vsftpd}
LOG_LEVEL=${6:-warn}

echo "Variable values:"
echo "BASE_DIR=$BASE_DIR"
echo "FTP_STORAGE_PATH=$FTP_STORAGE_PATH"
echo "POD=$POD"
echo "IMAGE=$IMAGE"
echo "SERVICE_NAME=$SERVICE_NAME"
echo "LOGS_DIR=$LOGS_DIR"
echo "LOG_LEVEL=$LOG_LEVEL"

podman image exists "$IMAGE" ||
    {
        echo "Image not found: $IMAGE" >&2
        exit 1
    }

# Replace the shell with Podman so signals propagate directly, using 'exec':
exec podman run \
    --rm \
    --log-level="${LOG_LEVEL}" \
    --log-driver=json-file \
    --read-only \
    --pod "${POD}" \
    --security-opt=no-new-privileges \
    --cap-drop=ALL \
    --cap-add=SETUID \
    --cap-add=SETGID \
    --cap-add=NET_BIND_SERVICE \
    --cap-add=SYS_CHROOT \
    --secret source=vsftpd-ftps-key,type=mount,uid=0,gid=0,mode=0400,target=vsftpd.key \
    --secret source=mariadb-password,type=mount,uid=0,gid=0,mode=0400,target=mariadb-password \
    --name "${SERVICE_NAME}" \
    -v "${FTP_STORAGE_PATH}":/srv/ftp:rw \
    -v "${LOGS_DIR}":/var/log/vsftpd:rw \
    --tmpfs /tmp:rw,noexec,nosuid,nodev,size=64m \
    --tmpfs /run:rw,noexec,nosuid,nodev,size=16m \
    --tmpfs /var/run/vsftpd:rw,noexec,nosuid,nodev,size=16m \
    --tmpfs /var/run/vsftpd/empty:ro,size=1m \
    "$IMAGE"

