#!/usr/bin/env bash

set -euo pipefail

# check a user isn't root
if [ "$(id -u)" = 0 ]; then
  echo "Please, don't run this script as root"
  exit 1
fi

SERVICE_NAME=${1}
IMAGE=${2}
POD=${3}
DB_STORAGE=${4}
LOGS_DIR=${5}

if [ -z "${SERVICE_NAME}" ]; then
    echo "Install autoload: service name isn't set, but required."
    exit 1
fi

if [ -z "${IMAGE}" ]; then
    echo "Install autoload: image name isn't set, but required."
    exit 1
fi

if [ -z "${POD}" ]; then
    echo "Install autoload: pod name isn't set, but required."
    exit 1
fi

if [ -z "${DB_STORAGE}" ]; then
    echo "Install autoload: data dir for writable mount isn't set, but required."
    exit 1
fi

if [ -z "${LOGS_DIR}" ]; then
    echo "Install autoload: logs dir for writable mount isn't set, but required."
    exit 1
fi

echo "Variable values:"
echo "DB_STORAGE=$DB_STORAGE"
echo "POD=$POD"
echo "IMAGE=$IMAGE"
echo "SERVICE_NAME=$SERVICE_NAME"
echo "LOGS_DIR=$LOGS_DIR"

podman image exists "$IMAGE" ||
    {
        echo "Image not found: $IMAGE" >&2
        exit 1
    }

# Replace the shell with Podman so signals propagate directly, using 'exec':
exec podman run \
       --log-level=warn \
       --log-driver=journald \
       --rm \
       --read-only \
       --pod "$POD" \
       --security-opt=no-new-privileges \
       --cap-drop=ALL \
       --cap-add=CHOWN \
       --cap-add=FOWNER \
       --cap-add=DAC_OVERRIDE \
       --cap-add=SETUID \
       --cap-add=SETGID \
       --secret source=mariadb-root-password,type=mount,uid=0,gid=0,mode=0400,target=mariadb-root-password \
       --secret source=mariadb-password,type=mount,uid=0,gid=0,mode=0400,target=mariadb-password \
       --name "$SERVICE_NAME" \
       -v "$LOGS_DIR":/var/log/mariadb:rw \
       -v "$DB_STORAGE":/var/lib/mysql:rw \
       --tmpfs /tmp:rw,noexec,nosuid,size=64m \
       --tmpfs /run:rw,noexec,nosuid,size=16m \
       --tmpfs /var/run,rw,noexec,nosuid,size=16m \
      "$IMAGE"

