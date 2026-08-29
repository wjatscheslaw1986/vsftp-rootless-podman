#!/bin/bash

if [ "$(id -u)" = 0 ]; then
  echo "Please, don't run this script as root"
  exit 1
fi

SERVICE_NAME=${1}
IMAGE=${2}
POD=${3}
DB_STORAGE_PATH=${4}
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

if [ -z "${DB_STORAGE_PATH}" ]; then
    echo "Install autoload: data dir isn't set, but required."
    exit 1
fi

if [ -z "${LOGS_DIR}" ]; then
	echo "Install autoload: logs dir isn't set, but required."
	exit 1
fi

if [ ! -f mariadb_run.sh ]; then
	echo "Please run this script from inside of the git repository folder. The file mariadb_run.sh hasn't been found. Aborting"
	exit 1
fi


SERVICE_PATH=$HOME/.config/systemd/user/podman-$SERVICE_NAME.service

mkdir -p "$HOME/.config/systemd/user" "$HOME/.local/bin"

cat > "$SERVICE_PATH" << EOF
[Unit]
Description=Safe & Secure $SERVICE_NAME Service
After=network.target

[Service]
ExecStart=$HOME/.local/bin/${SERVICE_NAME}_run.sh $SERVICE_NAME $IMAGE $POD $DB_STORAGE_PATH $LOGS_DIR
#ExecStartPost=
ExecStop=/usr/bin/podman stop --ignore $SERVICE_NAME
ExecStopPost=/usr/bin/podman rm --force --ignore $SERVICE_NAME
Restart=always
TimeoutStartSec=180
TimeoutStopSec=30
RestartSec=5

[Install]
WantedBy=default.target
EOF

cp mariadb_run.sh $HOME/.local/bin/"$SERVICE_NAME"_run.sh && chmod 744 $HOME/.local/bin/"$SERVICE_NAME"_run.sh

systemctl --user daemon-reload
systemctl --user enable podman-$SERVICE_NAME.service
#loginctl enable-linger $(whoami)
