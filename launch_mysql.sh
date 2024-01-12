#!/bin/bash
# Initializes and configures a MySQL database for a MANGOS server.
# This includes setting up users and applying database updates.
# Designed for Kubernetes with Persistent Volumes.

set -eo pipefail
shopt -s nullglob

LOG_FILE="/tmp/logfile.log"
log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $1" >> "$LOG_FILE"
}

log "Starting script execution."

# Default values for environment variables
MYSQL_PRIVILEGED_USER="mysql"
MYSQL_PRIVILEGED_USER_PASSWORD=${MYSQL_PRIVILEGED_USER_PASSWORD:-"changeit"}
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
MANGOS_WORLD_DB=mangos${MANGOS_SERVER_VERSION:-2}
MANGOS_CHARACTER_DB=character${MANGOS_SERVER_VERSION:-2}

# Check and set permissions for log file
setup_log_file() {
    chmod 777 /tmp
    touch "$LOG_FILE"
    chown mysql:mysql "$LOG_FILE"
    chmod 660 "$LOG_FILE"
}

# Fetch configuration value
get_config() {
    local conf="$1"
    local value=$("mysqld" --verbose --help 2>/dev/null | grep "^$conf" | awk '{ print $2; exit }')
    if [ -z "$value" ]; then
        log "Error: Unable to fetch configuration for $conf"
        exit 1
    fi
    echo $value
}

# Set permissions for the data directory
set_datadir_permissions() {
    local DATADIR="$1"
    log "Setting permissions for the data directory."
    chown -R mysql:mysql "$DATADIR"
}

# Initialize MariaDB Database
initialize_db() {
    if [ ! -d "$DATADIR/mysql" ]; then
        mariadb-install-db --user=mysql
        log "MariaDB system tables initialized."
    else
        log "MariaDB system tables already exist."
    fi
}

start_mysql_server() {
    local socket="$1"
    mysqld --socket="$socket" > /tmp/mysqld.log 2>&1 &
    pid=$!
    log "MariaDB server started with PID $pid"
	
	sleep 10
	
	if [ ! -d "$DATADIR/mysql" ]; then
		local mysql_command=( mysql --protocol=socket -u"$MYSQL_PRIVILEGED_USER" -hlocalhost --socket="$socket" )
	else
		local mysql_command=( mysql --protocol=socket -u"$MYSQL_PRIVILEGED_USER" -p"$MYSQL_PRIVILEGED_USER_PASSWORD" -hlocalhost --socket="$socket" )
	fi
	
    for i in {30..0}; do
        if echo 'SELECT 1' | "${mysql_command[@]}" &> /dev/null; then
            log "MariaDB server is ready."
            return
        fi
        sleep 1
    done
    log "Error: MariaDB server failed to start"
    exit 1
}

# Create users and set permissions
setup_users_and_permissions() {
    log "Setting up users and permissions."
	
	mysql_command=( mysql --protocol=socket -u${MYSQL_PRIVILEGED_USER} -hlocalhost --socket="$1")
    #set password for db user mysql
    "${mysql_command[@]}" <<-EOSQL
        ALTER USER 'mysql'@'localhost' IDENTIFIED BY '${MYSQL_PRIVILEGED_USER_PASSWORD}';
        FLUSH PRIVILEGES;
EOSQL
	
    local mysql_command=( mysql --protocol=socket -u${MYSQL_PRIVILEGED_USER} -p${MYSQL_PRIVILEGED_USER_PASSWORD} -hlocalhost --socket="$1" )

    # Root user setup
    log "Creating root user." 
    "${mysql_command[@]}" <<-EOSQL 2>&1 | tee -a "$LOG_FILE"
        ALTER USER 'root'@'localhost' IDENTIFIED BY '${MYSQL_ROOT_PASSWORD}';
        GRANT ALL ON *.* TO 'root'@'localhost' WITH GRANT OPTION;
        DROP DATABASE IF EXISTS test;
        FLUSH PRIVILEGES;
EOSQL

    # Application user setup
    log "Creating application user: $MYSQL_USER." 
    "${mysql_command[@]}" <<-EOSQL 2>&1 | tee -a "$LOG_FILE"
        CREATE USER '$MYSQL_USER'@'%' IDENTIFIED BY '$MYSQL_PASSWORD';
        GRANT ALL ON \`$MYSQL_DATABASE\`.* TO '$MYSQL_USER'@'%';
        FLUSH PRIVILEGES;
EOSQL

    # infoschema user setup
    log "Creating infoschema user: $MYSQL_INFOSCHEMA_USER."
    "${mysql_command[@]}" <<-EOSQL 2>&1 | tee -a "$LOG_FILE"
        CREATE USER '$MYSQL_INFOSCHEMA_USER'@'localhost' IDENTIFIED BY '$MYSQL_INFOSCHEMA_PASS';
        GRANT SELECT ON mysql.* TO '$MYSQL_INFOSCHEMA_USER'@'localhost';
        FLUSH PRIVILEGES;
EOSQL
}

# Function to load data into a specific database
load_data_into_database() {
    local database_directory="$1"
    local database_name="$2"
    local database_script_name="$3"
    local socket="$4"
    local mysql_command=( mysql --protocol=socket -u"$MYSQL_PRIVILEGED_USER" -p"$MYSQL_PRIVILEGED_USER_PASSWORD" -hlocalhost --socket="$socket" )

    if [ -d "$database_directory" ]; then
        log "Loading data into $database_name database."

        # Load database creation script if exists
        local db_create_script="$database_directory/${database_script_name}CreateDB.sql"
        log "Creation Script: $db_create_script"
        if [ -f "$db_create_script" ]; then
            log "Creation Script: $db_create_script found and will be executed"
            "${mysql_command[@]}" < "$db_create_script"
        fi

        # Load database initial data script if exists
        local db_load_script="$database_directory/${database_script_name}LoadDB.sql"
        log "Loader Script: $db_load_script"
        if [ -f "$db_load_script" ]; then
            "${mysql_command[@]}" -D"$database_name" < "$db_load_script"
        fi

        # Load additional data from specific directory
        local additional_data_dir="$database_directory/FullDB"
        if [ -d "$additional_data_dir" ]; then
            for f in $(find "$additional_data_dir" -name '*.sql' | sort); do
                log "Applying data file: $f"
                "${mysql_command[@]}" -D"$database_name" < "$f"
            done
        fi
    else
        log "Warning: Directory $database_directory does not exist. Skipping data load for $database_name."
    fi
}

# Load database schemas and data
load_database_data() {
    local socket="$1"
    load_data_into_database "/database/World/Setup" "mangos${MANGOS_SERVER_VERSION}" "mangosd" "$socket"
    load_data_into_database "/database/Character/Setup" "character${MANGOS_SERVER_VERSION}" "character" "$socket"

    # Handle realmd separately due to its unique structure
    local mysql_command=( mysql --protocol=socket -u"$MYSQL_PRIVILEGED_USER" -p"$MYSQL_PRIVILEGED_USER_PASSWORD" -hlocalhost --socket="$socket" )
    "${mysql_command[@]}" <<-EOSQL
        CREATE DATABASE IF NOT EXISTS realmd DEFAULT CHARACTER SET utf8 COLLATE utf8_general_ci;
        GRANT SELECT, INSERT, UPDATE, DELETE, CREATE, DROP, ALTER, LOCK TABLES ON \`realmd\`.* TO 'mangos'@'%';
        FLUSH PRIVILEGES;
EOSQL
    log "Loading data into realmd database."
    "${mysql_command[@]}" -Drealmd < "/database/Realm/Setup/realmdLoadDB.sql"
}
# Apply database updates in sorted order
apply_updates() {
    local socket="$1"
    local mysql_command=( mysql --protocol=socket -u"$MYSQL_PRIVILEGED_USER" -p"$MYSQL_PRIVILEGED_USER_PASSWORD" -hlocalhost --socket="$socket" )

    # Function to apply updates from a directory
    apply_updates_from_directory() {
        local directory="$1"
        local database="$2"
        for f in $(find "$directory" -name '*.sql' | sort); do
            log "Applying update: $f"
            "${mysql_command[@]}" -D"$database" < "$f"
        done
    }

    apply_updates_from_directory "/Realm_DB/Updates/Rel21" "realmd"
    apply_updates_from_directory "/database/Realm/Updates/Rel22" "realmd"
    apply_updates_from_directory "/database/Character/Updates" "$MANGOS_CHARACTER_DB"
    apply_updates_from_directory "/database/World/Updates" "$MANGOS_WORLD_DB"
    log "All database updates applied."
}

add_reamlist() {
    log "Add realmlist ${MANGOS_DATABASE_REALM_NAME} to realmd"
	local mysql_command=( mysql --protocol=socket -u${MYSQL_PRIVILEGED_USER} -p${MYSQL_PRIVILEGED_USER_PASSWORD} -hlocalhost --socket="$1" )
    "${mysql_command[@]}" -Drealmd <<-EOSQL
		INSERT INTO realmlist (name,realmbuilds) VALUES ('${MANGOS_DATABASE_REALM_NAME}','12340') ;
EOSQL

}

main() {
    DATADIR=$(get_config 'datadir')
    SOCKET=$(get_config 'socket')
    log "Data directory: $DATADIR, Socket: $SOCKET"

    # script needs to run with user mysql except for chown on datadir, so after that we switch the user with gosu and restart the script
    if [ "$(id -u)" = '0' ]; then
        setup_log_file
        chown -R mysql:mysql "$DATADIR"
        log "Executing script with gosu as mysql user"
        exec gosu mysql "$0" "$@"
    fi

    # check whether DB init is needed
    if [ ! -d "$DATADIR/mysql" ]; then
        initialize_db
		# Start MariaDB
		start_mysql_server "$SOCKET"
        setup_users_and_permissions "$SOCKET"
        load_database_data "$SOCKET"
        add_reamlist "$SOCKET"
	else
		# No initialization needed, just start the DB and apply updates
		log "DB is already initialized, just applying updates if applicable."
		start_mysql_server "$SOCKET"
    fi

    # Always try to apply updates (if new image with new content was pulled)
    apply_updates "$SOCKET"

    log 'MySQL process complete. Ready for start up.'
    wait $pid
}

main "$@"
