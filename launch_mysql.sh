#!/bin/bash
# This script initializes and configures a MySQL database for a MANGOS server, 
# including setting up users and applying database updates. Designed for Kubernetes with Persistent Volumes.

set -eo pipefail
shopt -s nullglob

LOG_FILE="/tmp/logfile.log"
log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $1" >> "$LOG_FILE"
}

log "Starting script execution."

# Default values for environment variables
MYSQL_ROOT_PASSWORD=${MYSQL_ROOT_PASSWORD:-"mangos"}
MYSQL_USER=${MYSQL_USER:-"mangos"}
MYSQL_PASSWORD=${MYSQL_PASSWORD:-"mangos"}
MYSQL_DATABASE=${MYSQL_DATABASE:-"mangos"}
MANGOS_DATABASE_REALM_NAME=${MANGOS_DATABASE_REALM_NAME:-"Karazhan"}
MANGOS_SERVER_VERSION=${MANGOS_SERVER_VERSION:-2}
MANGOS_DB_RELEASE=${MANGOS_DB_RELEASE:-"Rel22"}
MYSQL_ROOT_HOST=${MYSQL_ROOT_HOST:-"%"}
MYSQL_INFOSCHEMA_USER=mysql.infoschema
MYSQL_INFOSCHEMA_PASS="${MYSQL_INFOSCHEMA_PASS:-changeit}"
MANGOS_WORLD_DB=mangos${MANGOS_SERVER_VERSION}
MANGOS_CHARACTER_DB=character${MANGOS_SERVER_VERSION}

# Check and set permissions for log file
setup_log_file() {
    touch "$LOG_FILE"
    chown mysql:mysql "$LOG_FILE"
    chmod 660 "$LOG_FILE"
}

# Fetch configuration value
get_config() {
    local conf="$1"
    log "Fetching configuration for $conf"
    local value=$("mysqld" --verbose --help 2>/dev/null | grep "^$conf" | awk '{ print $2; exit }')
    log "Configuration value for $conf: $value"
    echo $value
}

# Set permissions for the data directory
set_datadir_permissions() {
    local DATADIR="$1"
    log "Setting permissions for the data directory."
    chown -R mysql:mysql "$DATADIR"
}

# Initialize MySQL Database
initialize_mysql() {
    log "Initializing MySQL Database."
    "$@" --initialize-insecure
    log "Database initialized."
}

# Start MySQL Server in background
start_mysql_server() {
    local SOCKET="$1"
    "$@" --skip-networking --socket="${SOCKET}" &
    pid="$!"
    log "MySQL server started in background with PID $pid"
}

# Wait for MySQL Server readiness
wait_for_mysql() {
    local mysql_command=( mysql --protocol=socket -uroot -hlocalhost --socket="$1" )
    for i in {30..0}; do
        if echo 'SELECT 1' | "${mysql_command[@]}" &> /dev/null; then
            break
        fi
        log "Waiting for MySQL server to be ready..."
        sleep 1
    done
    if [ "$i" = 0 ]; then
        log "MySQL init process failed."
        exit 1
    fi
    log "MySQL server is ready."
}


# Create users and set permissions
setup_users_and_permissions() {
    log "Setting up users and permissions."

    local mysql_command=( mysql --protocol=socket -uroot -hlocalhost --socket="$1" )

    # Root user setup
    log "Creating root user."
    "${mysql_command[@]}" <<-EOSQL
        SET @@SESSION.SQL_LOG_BIN=0;
        DELETE FROM mysql.user WHERE user NOT IN ('mysql.sys', 'mysqlxsys', 'root') OR host NOT IN ('localhost');
        ALTER USER 'root'@'localhost' IDENTIFIED BY '${MYSQL_ROOT_PASSWORD}';
        GRANT ALL ON *.* TO 'root'@'localhost' WITH GRANT OPTION;
        DROP DATABASE IF EXISTS test;
        FLUSH PRIVILEGES;
EOSQL

    # Application user setup
    log "Creating application user: $MYSQL_USER."
    "${mysql_command[@]}" <<-EOSQL
        CREATE USER '$MYSQL_USER'@'%' IDENTIFIED WITH 'caching_sha2_password' BY '$MYSQL_PASSWORD';
        GRANT ALL ON \`$MYSQL_DATABASE\`.* TO '$MYSQL_USER'@'%';
        FLUSH PRIVILEGES;
EOSQL

    # infoschema user setup
    log "Creating infoschema user: $MYSQL_INFOSCHEMA_USER."
    "${mysql_command[@]}" <<-EOSQL
        CREATE USER '$MYSQL_INFOSCHEMA_USER'@'localhost' IDENTIFIED WITH 'caching_sha2_password' BY '$MYSQL_INFOSCHEMA_PASS';
        GRANT SELECT ON mysql.* TO '$MYSQL_INFOSCHEMA_USER'@'localhost';
        FLUSH PRIVILEGES;
EOSQL
}

# Load database schemas and data
load_database_data() {
    log "Loading database data for server version: $MANGOS_SERVER_VERSION."
    local mysql_command=( mysql --protocol=socket -uroot -hlocalhost --socket="$1" -p"${MYSQL_ROOT_PASSWORD}" )

    # Load World, Character, and Realm databases
    log "Loading World, Character, and Realm databases."
    "${mysql_command[@]}" < /database/World/Setup/mangosdCreateDB.sql
    "${mysql_command[@]}" -D${MANGOS_WORLD_DB} < /database/World/Setup/mangosdLoadDB.sql
    "${mysql_command[@]}" < /database/Character/Setup/characterCreateDB.sql
    "${mysql_command[@]}"  -D${MANGOS_CHARACTER_DB} < /database/Character/Setup/characterLoadDB.sql
    "${mysql_command[@]}" <<-EOSQL
        CREATE DATABASE realmd DEFAULT CHARACTER SET utf8 COLLATE utf8_general_ci;
        GRANT SELECT, INSERT, UPDATE, DELETE, CREATE, DROP, ALTER, LOCK TABLES ON \`realmd\`.* TO 'mangos'@'%';
        FLUSH PRIVILEGES;
EOSQL
    "${mysql_command[@]}" -Drealmd < /database/Realm/Setup/realmdLoadDB.sql
}

# Apply database updates in sorted order
apply_database_updates() {
    log "Applying database updates."
    local mysql_command=( mysql --protocol=socket -uroot -hlocalhost --socket="$1" -p"${MYSQL_ROOT_PASSWORD}" )

    # Apply updates in /Realm_DB/Updates/Rel21/ first
    for f in $(find /Realm_DB/Updates/Rel21/ -name '*.sql' | sort); do
        log "Applying update: $f"
        "${mysql_command[@]}" -Drealmd < "$f"
    done

    # Apply updates in /database/Realm/Updates/Rel22/ next
    for f in $(find /database/Realm/Updates/Rel22/ -name '*.sql' | sort); do
        log "Applying update: $f"
        "${mysql_command[@]}" -Drealmd < "$f"
    done

    # Apply updates for World, Character, and other Realm updates
    for dir in /database/{World,Character}/Updates; do
        for f in $(find $dir -name '*.sql' | sort); do
            local database=$(basename $dir)  # Extracts 'World', 'Character' from the path
            log "Applying update in $database database: $f"
            "${mysql_command[@]}" -D${MANGOS_WORLD_DB} < "$f"
        done
    done

    log "Databases updated."
}

# Main execution logic
if [ "$1" = 'mysqld' ]; then
    DATADIR=$(get_config 'datadir' "$@")
    set_datadir_permissions "$DATADIR"

    SOCKET=$(get_config 'socket' "$@")
    log "Data directory: $DATADIR, Socket: $SOCKET"

    if [ "$(id -u)" = '0' ]; then
        set_datadir_permissions "$DATADIR"
        setup_log_file
        exec gosu mysql "$BASH_SOURCE" "$@"
    else
        log "Running mysqld as non-root user"
    fi

    if [ ! -d "$DATADIR/mysql" ]; then
        initialize_mysql "$@"
        start_mysql_server "$SOCKET" "$@"
        wait_for_mysql "$SOCKET"
        setup_users_and_permissions "$SOCKET"#
        load_database_data "$SOCKET"
    fi

    # Always apply database updates
    apply_database_updates "$SOCKET"
    log 'MySQL init process done. Ready for start up.'
fi

exec "$@"
