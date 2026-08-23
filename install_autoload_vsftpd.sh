#!/bin/bash

if [ "$(id -u)" = 0 ]; then
  echo "Please, don't run this script as root"
  exit 1
fi

SERVICE_NAME=${1}
IMAGE=${2}
POD=${3}
DB_SERVICE_NAME=${4}
BASE_DIR="$HOME"/"$SERVICE_NAME"
FTP_STORAGE="$BASE_DIR"/ftp

if [ -z "${SERVICE_NAME}" ]; then
    echo "Install autoload: ftp service name isn't set, but required."
    exit 1
fi

if [ -z "${DB_SERVICE_NAME}" ]; then
    echo "Install autoload: auth service name isn't set, but required."
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

SERVICE_PATH=$HOME/.config/systemd/user/podman-$SERVICE_NAME.service

echo "Variable values:"
echo "POD=$POD"
echo "IMAGE=$IMAGE"
echo "SERVICE_NAME=$SERVICE_NAME"
echo "FTP_STORAGE=$FTP_STORAGE"
echo "SERVICE_PATH=$SERVICE_PATH"

mkdir -p "$HOME/.config/systemd/user" "$HOME/.local/bin"

cat > "$SERVICE_PATH" << EOF
[Unit]
Description=Safe & Secure $SERVICE_NAME Service
Requires=podman-$DB_SERVICE_NAME.service
After=podman-$DB_SERVICE_NAME.service network-online.target
Wants=network-online.target
PartOf=podman-$DB_SERVICE_NAME.service

[Service]
ExecStart=$HOME/.local/bin/"$SERVICE_NAME"_run.sh $SERVICE_NAME $IMAGE $POD $FTP_STORAGE $HOME/$SERVICE_NAME/log/vsftpd warn
#ExecStartPost=
ExecStop=/usr/bin/podman stop --ignore $SERVICE_NAME
ExecStopPost=/usr/bin/podman rm --force --ignore $SERVICE_NAME
Restart=always
RestartSec=5
TimeoutStartSec=60
TimeoutStopSec=30

[Install]
WantedBy=default.target
EOF

cp "$SERVICE_NAME"_run.sh $HOME/.local/bin/ && chmod 744 $HOME/.local/bin/"$SERVICE_NAME"_run.sh

systemctl --user daemon-reload
systemctl --user enable podman-$SERVICE_NAME.service
loginctl enable-linger $(whoami)
