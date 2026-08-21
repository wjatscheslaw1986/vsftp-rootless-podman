#!/bin/bash

if [ "$(id -u)" = 0 ]; then
  echo "Please, don't run this script as root"
  exit 1
fi

SERVICE_NAME=${1}
IMAGE=${2}
POD=${3}
BASE_DIR="$HOME"/"$SERVICE_NAME"
FTP_STORAGE="$BASE_DIR"/ftp

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

SERVICE_PATH=$HOME/.config/systemd/user/podman-$SERVICE_NAME.service

echo "Variable values:"
echo "POD=$POD"
echo "IMAGE=$IMAGE"
echo "SERVICE_NAME=$SERVICE_NAME"
echo "FTP_STORAGE=$FTP_STORAGE"
echo "SERVICE_PATH=$SERVICE_PATH"

cat > "$SERVICE_PATH" << EOF
[Unit]
Description=Safe & Secure $SERVICE_NAME Service
After=network.target

[Service]
ExecStart=$HOME/.local/bin/"$SERVICE_NAME"_run.sh $SERVICE_NAME $IMAGE $POD $FTP_STORAGE $HOME/$SERVICE_NAME/log/vsftpd warn
#ExecStartPost=
ExecStop=/usr/bin/podman stop --ignore $SERVICE_NAME
ExecStopPost=/usr/bin/podman rm --force $SERVICE_NAME
Restart=always
TimeoutStartSec=20
TimeoutStopSec=5

[Install]
WantedBy=default.target
EOF

cp "$SERVICE_NAME"_run.sh $HOME/.local/bin/ && chmod 744 $HOME/.local/bin/"$SERVICE_NAME"_run.sh

systemctl --user daemon-reload
systemctl --user enable podman-$SERVICE_NAME.service
loginctl enable-linger $(whoami)
