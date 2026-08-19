#!/bin/bash

set -Eeuo pipefail

DATADIR="${MARIADB_DATADIR:-/var/lib/mysql}"
SOCKET="${MARIADB_SOCKET:-/run/mysqld/mysqld.sock}"

MYSQL_USER="${MARIADB_USER:-ftp_auth}"
MYSQL_DATABASE="${MARIADB_DATABASE:-ftp}"
MYSQL_PASSWORD_FILE="${MARIADB_PASSWORD_FILE:-/run/secrets/mariadb-password}"
MARIADB_ROOT_PASSWORD_FILE="${MARIADB_ROOT_PASSWORD_FILE:-/run/secrets/mariadb-root-password}"

MYSQL_SYSTEM_USER="mysql"
MYSQL_SYSTEM_GROUP="mysql"

TEMP_PID=""


log() {
    printf '[mariadb-entrypoint] %s\n' "$*" >&2
}


die() {
    log "ERROR: $*"
    exit 1
}


require_file() {
    local file="$1"

    [[ -f "$file" ]] || die "Required file does not exist: $file"
    [[ -r "$file" ]] || die "Required file is not readable: $file"
}


read_secret() {
    local file="$1"

    require_file "$file"

    local value
    value="$(<"$file")"

    [[ -n "$value" ]] || die "Secret is empty: $file"

    printf '%s' "$value"
}


validate_identifier() {
    local name="$1"
    local description="$2"

    [[ "$name" =~ ^[a-zA-Z0-9_]+$ ]] || \
        die "Invalid ${description}: '$name'. Only ASCII letters, digits and underscore are allowed."
}


sql_escape_string() {
    local value="$1"

    # MariaDB normally treats backslash as an escape character.
    # Escape backslashes first, then single quotes.
    value="${value//\\/\\\\}"
    value="${value//\'/\'\'}"

    printf "'%s'" "$value"
}


setup_directories() {
    mkdir -p "$DATADIR"
    mkdir -p "$(dirname "$SOCKET")"

    chown "$MYSQL_SYSTEM_USER:$MYSQL_SYSTEM_GROUP" "$DATADIR"
    chown "$MYSQL_SYSTEM_USER:$MYSQL_SYSTEM_GROUP" "$(dirname "$SOCKET")"

    chmod 0750 "$DATADIR"
    chmod 0750 "$(dirname "$SOCKET")"
}


initialize_datadir() {
    if [[ -d "$DATADIR/mysql" ]]; then
        log "Existing MariaDB datadir detected."
        return
    fi

    log "MariaDB datadir is empty; initializing system tables."

    mariadb-install-db \
        --user="$MYSQL_SYSTEM_USER" \
        --datadir="$DATADIR" \
        --skip-test-db

    log "MariaDB system tables initialized."
}


start_temporary_server() {
    rm -f "$SOCKET"

    log "Starting temporary MariaDB server."

    mariadbd \
        --datadir="$DATADIR" \
        --user="$MYSQL_SYSTEM_USER" \
        --socket="$SOCKET" \
        --skip-networking \
        --pid-file=/run/mysqld/mariadb-init.pid \
        &

    TEMP_PID=$!

    log "Waiting for temporary MariaDB server."

    for _ in $(seq 1 60); do
        if mariadb-admin \
            --no-defaults \
            --protocol=socket \
            --socket="$SOCKET" \
            ping >/dev/null 2>&1
        then
            log "Temporary MariaDB server is ready."
            return
        fi

        if ! kill -0 "$TEMP_PID" 2>/dev/null; then
            die "Temporary MariaDB server exited before becoming ready."
        fi

        sleep 1
    done

    die "MariaDB did not become ready within 60 seconds."
}


stop_temporary_server() {
    if [[ -z "$TEMP_PID" ]]; then
        return
    fi

    if kill -0 "$TEMP_PID" 2>/dev/null; then
        log "Stopping temporary MariaDB server."

        mariadb-admin \
            --no-defaults \
            --protocol=socket \
            --socket="$SOCKET" \
            shutdown

        wait "$TEMP_PID" || true
    fi

    TEMP_PID=""
    rm -f "$SOCKET"
}


configure_database() {
    local root_password
    local mysql_password
    local root_password_sql
    local mysql_password_sql
    local sql_file

    root_password="$(read_secret "$MARIADB_ROOT_PASSWORD_FILE")"
    mysql_password="$(read_secret "$MYSQL_PASSWORD_FILE")"

    root_password_sql="$(sql_escape_string "$root_password")"
    mysql_password_sql="$(sql_escape_string "$mysql_password")"

    sql_file="/run/mysqld/mariadb-initialize.sql"

    cat >"$sql_file" <<EOF
ALTER USER 'root'@'localhost'
    IDENTIFIED BY ${root_password_sql};

CREATE DATABASE IF NOT EXISTS \`${MYSQL_DATABASE}\`
    CHARACTER SET utf8mb4
    COLLATE utf8mb4_unicode_ci;

CREATE USER IF NOT EXISTS '${MYSQL_USER}'@'%'
    IDENTIFIED BY ${mysql_password_sql};

ALTER USER '${MYSQL_USER}'@'%'
    IDENTIFIED BY ${mysql_password_sql};

GRANT ALL PRIVILEGES
    ON \`${MYSQL_DATABASE}\`.ftp_users
    TO '${MYSQL_USER}'@'127.0.0.1';

EOF

    chmod 0600 "$sql_file"

    unset root_password
    unset mysql_password
    unset root_password_sql
    unset mysql_password_sql

    log "Configuring MariaDB accounts and database."

    mariadb \
        --no-defaults \
        --protocol=socket \
        --socket="$SOCKET" \
        --batch \
        <"$sql_file"

    rm -f "$sql_file"

    log "MariaDB accounts and database configured."
}


mark_initialized() {
    local marker="$DATADIR/.mariadb-container-initialized"

    touch "$marker"

    chown "$MYSQL_SYSTEM_USER:$MYSQL_SYSTEM_GROUP" "$marker"
    chmod 0600 "$marker"
}


initialize_container() {
    if [[ -f "$DATADIR/.mariadb-container-initialized" ]]; then
        log "MariaDB container initialization already completed."
        return
    fi

    start_temporary_server

    configure_database

    stop_temporary_server

    mark_initialized

    log "MariaDB container initialization completed."
}


main() {
    [[ "$(id -u)" -eq 0 ]] || \
        die "The entrypoint must start as container root."

    validate_identifier "$MYSQL_USER" "MariaDB username"
    validate_identifier "$MYSQL_DATABASE" "MariaDB database name"

    require_file "$MARIADB_ROOT_PASSWORD_FILE"
    require_file "$MYSQL_PASSWORD_FILE"

    setup_directories
    initialize_datadir
    initialize_container

    log "Starting MariaDB."

    exec mariadbd \
        --datadir="$DATADIR" \
        --user="$MYSQL_SYSTEM_USER" \
        --bind-address=0.0.0.0 \
        --port=3306 \
        --pid-file=/run/mysqld/mariadb.pid
}


cleanup() {
    stop_temporary_server
}


trap cleanup EXIT
trap 'exit 143' TERM
trap 'exit 130' INT

main "$@"
