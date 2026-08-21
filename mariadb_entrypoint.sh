#!/bin/bash

set -Eeuo pipefail

DATADIR="${MARIADB_DATADIR:-/var/lib/mysql}"
LOGDIR="${MARIADB_LOGDIR:-/var/log/mariadb}"
SOCKET="${MARIADB_SOCKET:-/run/mysqld/mysqld.sock}"
PID="${MARIADB_PID:-/run/mysqld/mariadb.pid}"

MYSQL_USER="${MARIADB_USER:-ftp_auth}"
MYSQL_DATABASE="${MARIADB_DATABASE:-ftp}"
MYSQL_PASSWORD_FILE="${MARIADB_PASSWORD_FILE:-/run/secrets/mariadb-password}"
MARIADB_ROOT_PASSWORD_FILE="${MARIADB_ROOT_PASSWORD_FILE:-/run/secrets/mariadb-root-password}"

MYSQL_SYSTEM_USER="${MARIADB_SYSTEM_USER:-mysql}"
MYSQL_SYSTEM_GROUP="${MARIADB_SYSTEM_GROUP:-mysql}"

TEMP_PID=""

INIT_LOG="${LOGDIR}/mariadb-init.log"

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
    mkdir -p \
        "$DATADIR" \
        "$(dirname "$SOCKET")" \
        "$LOGDIR"

    chown "$MYSQL_SYSTEM_USER:$MYSQL_SYSTEM_GROUP" \
        "$DATADIR" \
        "$(dirname "$SOCKET")" \
        "$LOGDIR"

    chmod 0755 \
        "$DATADIR" \
        "$(dirname "$SOCKET")" \
        "$LOGDIR"
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
    rm -f "$SOCKET" "$PID"

    log "Starting temporary MariaDB server."

    mariadbd \
        --console \
        --datadir="$DATADIR" \
        --user="$MYSQL_SYSTEM_USER" \
        --socket="$SOCKET" \
        --skip-networking \
        --pid-file="$PID" \
        --log-error="$INIT_LOG" \
        &

    TEMP_PID=$!

    log "Temporary MariaDB PID: $TEMP_PID"
    log "Waiting for temporary MariaDB server to start."

    for second in $(seq 1 60); do
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
    local pid="$TEMP_PID"

    if [[ -z "$pid" ]]; then
        return 0
    fi

    log "Stopping temporary MariaDB server (PID $pid)."

    if kill -0 "$pid" 2>/dev/null; then
        mariadb-admin \
            --no-defaults \
            --protocol=socket \
            --socket="$SOCKET" \
            shutdown > /dev/null 2>&1 || true
    fi

     # First wait for normal termination.
    for _ in $(seq 1 100); do
        if ! kill -0 "$pid" 2>/dev/null; then
            break
        fi
        sleep 0.1
    done

    # If shutdown did not finish, terminate it explicitly.
    if kill -0 "$pid" 2>/dev/null; then
        log "Temporary MariaDB did not exit after shutdown; sending SIGTERM."
        kill -TERM "$pid" 2>/dev/null || true
    fi

    # Reap the process.
    wait "$pid" 2>/dev/null || true

    # Do not trust the socket disappearing alone; check both.
    for _ in $(seq 1 100); do
        if [[ ! -e "$SOCKET" && ! -e "$PID" ]]; then
            break
        fi
        sleep 0.1
    done

    if [[ -e "$SOCKET" || -e "$PID" ]]; then
        die "Temporary MariaDB did not release socket/PID files."
    fi

    TEMP_PID=""
    rm -f "$SOCKET"
    log "Temporary MariaDB server stopped completely."
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
    sql_file="/run/mysqld/mariadb-init.sql"

    cat >"$sql_file" <<EOF
ALTER USER 'root'@'localhost'
    IDENTIFIED BY ${root_password_sql};

CREATE DATABASE IF NOT EXISTS \`${MYSQL_DATABASE}\`
    CHARACTER SET utf8mb4
    COLLATE utf8mb4_unicode_ci
    COMMENT 'FTP server auth database';

USE \`${MYSQL_DATABASE}\`;

CREATE TABLE IF NOT EXISTS ftp_users (
    username       varchar(256) PRIMARY KEY,
    password_hash  varchar(512) NOT NULL,
    enabled        boolean NOT NULL DEFAULT true
);

CREATE USER IF NOT EXISTS '${MYSQL_USER}'@'%'
    IDENTIFIED BY ${mysql_password_sql};

GRANT SELECT
    ON \`${MYSQL_DATABASE}\`.ftp_users
    TO '${MYSQL_USER}'@'%';

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

    shred "$sql_file" && rm -f "$sql_file"

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
        --pid-file="$PID" \
        --log-error="$LOGDIR/mariadb.log"
}


cleanup() {
    stop_temporary_server
}


trap cleanup EXIT
trap 'exit 143' TERM
trap 'exit 130' INT

main "$@"
