SHELL := /bin/bash

.DEFAULT_GOAL := build

AUTH_DB_IMAGE := mariadb
VSFTPD_IMAGE := vsftpd

INSTANCE_ID := 1
POD := $(VSFTPD_IMAGE)-$(INSTANCE_ID)
AUTH_DB_CONTAINER := $(AUTH_DB_IMAGE)-$(INSTANCE_ID)
VSFTPD_CONTAINER := $(VSFTPD_IMAGE)-$(INSTANCE_ID)

INSTANCE_DIRECTORY := $(HOME)/$(VSFTPD_CONTAINER)

DB_DIRECTORY := $(INSTANCE_DIRECTORY)/mariadb
VSFTPD_AUTH_DATA_DIR := $(DB_DIRECTORY)/data
FTP_DIRECTORY := $(INSTANCE_DIRECTORY)/ftp

DB_ROOT_PASSWORD_FILE := secrets/mariadb-root-password
DB_PASSWORD_FILE := secrets/mariadb-password
FTPS_PRIVATE_KEY_FILE := secrets/keys/vsftpd.key
CA_PRIVATE_KEY_PASSWORD_FILE := secrets/ca-password
SYSTEMD_MARIADB_FILE := mariadb_run.sh
SYSTEMD_VSFTPD_FILE := vsftpd_run.sh

# Rootless Podman user namespace mapping.
#
# This is deliberately kept as project configuration rather than being
# inferred from the image. The mapping must be valid for /etc/subuid
# and /etc/subgid of the user running Podman.
BLOCK_SIZE := 65536
SUBUID_BLOCK_INDEX := 2
INTERMEDIATE_UID_OFFSET := $(shell echo $$(( $(SUBUID_BLOCK_INDEX) * $(BLOCK_SIZE) + 1 )))
HOST_UID_OFFSET := $(shell echo $$(( $(INTERMEDIATE_UID_OFFSET) + 100000 - 1)))
DB_USER_UID := $(shell echo $$(( $(HOST_UID_OFFSET) + 100)))
DB_USER_GID := $(shell echo $$(( $(HOST_UID_OFFSET) + 101)))
FTP_USER_UID := $(shell echo $$(( $(HOST_UID_OFFSET) + 9898)))
FTP_USER_GID := $(shell echo $$(( $(HOST_UID_OFFSET) + 9898)))

.PHONY: all build images secrets pod run autoload stop down clean \
	create-secrets ssl-keys check-secrets check-pod \
	directories check-directories


all: build


build: images secrets pod directories


images:
	@echo "Building MariaDB image"
	podman build \
		--tag $(AUTH_DB_IMAGE) \
		--file Containerfile_MariaDB \
		.
	
	@echo "Building vsftpd image"
	podman build \
		--tag $(VSFTPD_IMAGE) \
		--file Containerfile_vsftpd \
		.

directories:
	@echo "Creating directories for mounting into the containers"
	./create_directories.sh $(VSFTPD_CONTAINER) $(DB_USER_UID):$(DB_USER_GID) $(FTP_USER_UID):$(FTP_USER_GID)

create-secrets:
	@echo "Creating secrets"
	./create_secrets.sh


ssl-keys: create-secrets
	@echo "Creating SSL certificates for FTPS"
	
	@test -f "$(CA_PRIVATE_KEY_PASSWORD_FILE)" || \
		{ echo "ERROR: missing $(CA_PRIVATE_KEY_PASSWORD_FILE)" >&2; exit 1; }
	
	./generate_certificates.sh


check-secrets:
	@test -f "$(DB_ROOT_PASSWORD_FILE)" || \
		{ echo "ERROR: missing $(DB_ROOT_PASSWORD_FILE)" >&2; exit 1; }
	
	@test -f "$(DB_PASSWORD_FILE)" || \
		{ echo "ERROR: missing $(DB_PASSWORD_FILE)" >&2; exit 1; }
	
	@test -f "$(FTPS_PRIVATE_KEY_FILE)" || \
		{ echo "ERROR: missing $(FTPS_PRIVATE_KEY_FILE)" >&2; exit 1; }
	
	@test "$$(stat -c '%a' "$(DB_ROOT_PASSWORD_FILE)")" = "600" || \
		{ echo "ERROR: $(DB_ROOT_PASSWORD_FILE) must have mode 0600" >&2; exit 1; }
	
	@test "$$(stat -c '%a' "$(DB_PASSWORD_FILE)")" = "600" || \
		{ echo "ERROR: $(DB_PASSWORD_FILE) must have mode 0600" >&2; exit 1; }
	
	@test "$$(stat -c '%a' "$(FTPS_PRIVATE_KEY_FILE)")" = "600" || \
		{ echo "ERROR: $(FTPS_PRIVATE_KEY_FILE) must have mode 0600" >&2; exit 1; }


check-directories:
	@if [[ ! -d "$(INSTANCE_DIRECTORY)" ]]; then \
		echo "ERROR: folder $(INSTANCE_DIRECTORY) is missing"; \
		exit 1; \
	fi
	
	@if [[ ! -d "$(DB_DIRECTORY)" ]]; then \
		echo "ERROR: folder $(DB_DIRECTORY) is missing"; \
		exit 1; \
	fi
	
	@if [[ ! -d "$(FTP_DIRECTORY)" ]]; then \
		echo "ERROR: folder $(FTP_DIRECTORY) is missing"; \
		exit 1; \
	fi
	
	@test "$$(stat -c '%a' "$(INSTANCE_DIRECTORY)")" = "755" || \
		{ echo "ERROR: folder $(INSTANCE_DIRECTORY) has wrong permissions: "$$(stat -c '%a' "$(INSTANCE_DIRECTORY)")", expected 755"; exit 1; }
	
	@test -O $(INSTANCE_DIRECTORY) && test -G $(INSTANCE_DIRECTORY) || \
		{ echo "ERROR: folder $(INSTANCE_DIRECTORY) must belong to the current user"; exit 1; }
	
	@test "$$(stat -c '%u:%g' "$(DB_DIRECTORY)")" = "$(DB_USER_UID):$(DB_USER_GID)" || \
		{ echo "ERROR: folder $(DB_DIRECTORY) has wrong owner: $$(stat -c '%u:%g' $(DB_DIRECTORY)), expected UID $(DB_USER_UID):$(DB_USER_GID)"; exit 1; }
	
	@test "$$(stat -c '%a' "$(DB_DIRECTORY)")" = "755" || \
		{ echo "ERROR: folder $(DB_DIRECTORY) has wrong permissions: $$(stat -c '%a' $(DB_DIRECTORY)), expected 755"; exit 1; }
	
	@test "$$(stat -c '%u:%g' "$(FTP_DIRECTORY)")" = "$(FTP_USER_UID):$(FTP_USER_GID)" || \
		{ echo "ERROR: folder $(FTP_DIRECTORY) has wrong owner: $$(stat -c '%u:%g' $(FTP_DIRECTORY)), expected UID $(FTP_USER_UID):$(FTP_USER_GID)"; exit 1; }
	
	@test "$$(stat -c '%a' "$(FTP_DIRECTORY)")" = "755" || \
		{ echo "ERROR: folder $(FTP_DIRECTORY) has wrong permissions: $$(stat -c '%a' $(FTP_DIRECTORY)), expected 755"; exit 1; }


secrets: check-secrets
	@echo "Creating/replacing Podman secrets"
	
	@podman secret rm mariadb-root-password 2>/dev/null || true
	@podman secret rm mariadb-password 2>/dev/null || true
	@podman secret rm vsftpd-ftps-key 2>/dev/null || true
	
	podman secret create \
		mariadb-root-password \
		./"$(DB_ROOT_PASSWORD_FILE)"
	podman secret create \
		mariadb-password \
		./"$(DB_PASSWORD_FILE)"
	podman secret create \
		vsftpd-ftps-key \
		./"$(FTPS_PRIVATE_KEY_FILE)"


check-pod:
	@podman pod exists "$(POD)" || { echo "ERROR: Pod $(POD) does not exist. Run 'make pod' first." >&2; exit 1; }


pod:
	@if podman pod exists "$(POD)"; then \
		echo "Pod $(POD) already exists"; \
	else \
		echo "Creating pod $(POD)"; \
		podman pod create \
			--name "$(POD)" \
			--uidmap=0:$(INTERMEDIATE_UID_OFFSET):$(BLOCK_SIZE) \
			--gidmap=0:$(INTERMEDIATE_UID_OFFSET):$(BLOCK_SIZE); \
	fi


run: check-directories check-pod check-secrets
	@echo "Running $(AUTH_DB_CONTAINER) container in pod $(POD)"
	
	podman run \
		--log-level=warn \
		--log-driver=journald \
		--rm \
		--read-only \
		--pod "$(POD)" \
		--security-opt=no-new-privileges \
		--cap-drop=ALL \
		--cap-add=CHOWN \
		--cap-add=FOWNER \
		--cap-add=DAC_OVERRIDE \
		--cap-add=SETUID \
		--cap-add=SETGID \
		--secret source=mariadb-root-password,type=mount,uid=0,gid=0,mode=0400,target=mariadb-root-password \
		--secret source=mariadb-password,type=mount,uid=0,gid=0,mode=0400,target=mariadb-password \
		--name "$(AUTH_DB_CONTAINER)" \
		-v $(DB_DIRECTORY):/var/lib/mysql:rw,U \
		--tmpfs /tmp:rw,noexec,nosuid,size=64m \
		--tmpfs /run:rw,noexec,nosuid,size=16m \
		--tmpfs /var/run,rw,noexec,nosuid,size=16m \
		localhost/"$(AUTH_DB_IMAGE)"
	
	@echo "Running $(VSFTPD_CONTAINER) container in pod $(POD)"
	
	podman run \
		--log-level=info \
		--log-driver=json-file \
		--rm \
		--read-only \
		--pod "$(POD)" \
		--security-opt=no-new-privileges \
		--cap-drop=ALL \
		--cap-add=SETUID \
		--cap-add=SETGID \
		--cap-add=NET_BIND_SERVICE \
		--secret source=vsftpd-ftps-key,type=mount,uid=9898,gid=9898,mode=0400,target=vsftpd-ftps-key \
		--secret source=mariadb-password,type=mount,uid=9898,gid=9898,mode=0400,target=mariadb-password \
		-p 2990:990/tcp \
		-p 21100-21110:21100-21110/tcp \
		--name "$(VSFTPD_CONTAINER)" \
		-v "$(FTP_DIRECTORY)":/srv/ftp:rw,U \
		-v ./cert/vsftpd.crt:/opt/vsftpd/vsftpd.crt:ro \
		-v ./config/ftp/vsftpd-pam.conf:/etc/pam.d/vsftpd:ro \
		-v ./config/ftp/vsftpd.conf:/etc/vsftpd.conf:ro \
		--tmpfs /tmp:rw,noexec,nosuid,size=64m \
		--tmpfs /run:rw,noexec,nosuid,size=16m \
		--tmpfs /var/run,rw,noexec,nosuid,size=16m \
		localhost/"$(VSFTPD_IMAGE)"


autoload:
	@echo "Installing user's systemd services for autoload"
	
	@test -f "$(SYSTEMD_MARIADB_FILE)" || \
		{ echo "ERROR: missing $(SYSTEMD_MARIADB_FILE)" >&2; exit 1; }
	
	@cp "$(SYSTEMD_MARIADB_FILE)" "$(AUTH_DB_CONTAINER)"_run.sh
	@./install_autoload_mariadb.sh "$(AUTH_DB_CONTAINER)" "$(AUTH_DB_IMAGE)" "$(POD)"
	
	@test -f "$(SYSTEMD_VSFTPD_FILE)" || \
		{ echo "ERROR: missing $(SYSTEMD_VSFTPD_FILE)" >&2; exit 1; }
	
	@cp "$(SYSTEMD_VSFTPD_FILE)" "$(VSFTPD_CONTAINER)"_run.sh
	@./install_autoload_vsftpd.sh "$(VSFTPD_CONTAINER)"


stop:
	@echo 'Stopping the pod "$(POD)"'
	-podman stop "$(POD)"


down:
	@echo 'Stop and remove the pod "$(POD)"'
	-podman pod stop "$(POD)"
	-podman pod rm "$(POD)"


clean: down
	@echo 'Removing images "$(AUTH_DB_IMAGE)" and "$(VSFTPD_IMAGE)"'
	-podman rmi "$(AUTH_DB_IMAGE)"
	-podman rmi "$(VSFTPD_IMAGE)"
