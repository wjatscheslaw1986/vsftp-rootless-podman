#!/usr/bin/env bash

set -Eeuo pipefail

# check a user isn't root
if [ "$(id -u)" = 0 ]; then
  echo "Please, don't run this script as root"
  exit 1
fi

SERVICE_NAME=${1:-mariadb}
IMAGE=${2:-localhost/mariadb}
POD=${3:-mariadb-pod}
DB_STORAGE="$HOME"/vsftpd/mariadb

echo "Variable values:"
echo "DB_STORAGE=$DB_STORAGE"
echo "POD=$POD"
echo "IMAGE=$IMAGE"
echo "SERVICE_NAME=$SERVICE_NAME"

podman image exists "$IMAGE" ||
    {
        echo "Image not found: $IMAGE" >&2
        exit 1
    }

# Replace the shell with Podman so signals propagate directly, using 'exec':
podman run \
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
       --secret source=mariadb-root-password,type=mount,uid=0,gid=0,mode=0400 \
       --secret source=mariadb-password,type=mount,uid=0,gid=0,mode=0400 \
       --name "$AUTH_DB_CONTAINER" \
       -v $DB_STORAGE:/var/lib/mysql:rw \
       --tmpfs /tmp:rw,noexec,nosuid,size=64m \
       --tmpfs /run:rw,noexec,nosuid,size=16m \
       --tmpfs /var/run,rw,noexec,nosuid,size=16m \
      "$IMAGE"

