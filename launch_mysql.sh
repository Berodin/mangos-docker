#!/bin/bash
set -eo pipefail
shopt -s nullglob

LOG_FILE="/tmp/logfile.log"
echo "Starting script execution at $(date)" >> "$LOG_FILE"

# Environment variables with defaults
MYSQL_ROOT_PASSWORD=${MYSQL_ROOT_PASSWORD:-"mangos"}
MYSQL_ALLOW_EMPTY_PASSWORD=${MYSQL_ALLOW_EMPTY_PASSWORD:-""}
MYSQL_RANDOM_ROOT_PASSWORD=${MYSQL_RANDOM_ROOT_PASSWORD:-""}
MYSQL_INITDB_SKIP_TZINFO=${MYSQL_INITDB_SKIP_TZINFO:-""}
MYSQL_ONETIME_PASSWORD=${MYSQL_ONETIME_PASSWORD:-""}
MYSQL_USER=${MYSQL_USER:-"mangos"}
MYSQL_PASSWORD=${MYSQL_PASSWORD:-"mangos"}
MYSQL_DATABASE=${MYSQL_DATABASE:-"mangos"}
MANGOS_DATABASE_REALM_NAME=${MANGOS_DATABASE_REALM_NAME:-"Karazhan"}
MANGOS_SERVER_VERSION=${MANGOS_SERVER_VERSION:-2}
MANGOS_DB_RELEASE=${MANGOS_DB_RELEASE:-"Rel21"}
MYSQL_ROOT_HOST=${MYSQL_ROOT_HOST:-"%"}

echo "Checking for command options..." >> "$LOG_FILE"
# if command starts with an option, prepend mysqld
if [ "${1:0:1}" = '-' ]; then
	echo "got command options" >> "$LOG_FILE"
    set -- mysqld "$@"
fi

# skip setup if they want an option that stops mysqld
echo "check want help" >> "$LOG_FILE"
wantHelp=
for arg; do
	echo "arg: $arg" >> "$LOG_FILE"
    case "$arg" in
        -'?'|--help|--print-defaults|-V|--version)
            wantHelp=1
            break
            ;;
    esac
done

# Check config and fetch values
echo "_check_config" >> "$LOG_FILE"
_check_config() {
	toRun=( "$@" --verbose --help )
	if ! errors="$("${toRun[@]}" 2>&1 >/dev/null)"; then
		echo "errors: $errors in check_config" >> "$LOG_FILE"
		cat >&2 <<-EOM

			ERROR: mysqld failed while attempting to check config
			command was: "${toRun[*]}"

			$errors
		EOM
		exit 1
	fi
}

# Fetch value from server config
_get_config() {
    local conf="$1"; shift
    echo "get_config for $conf" >> "$LOG_FILE"
    local value=$("$@" --verbose --help --log-bin-index="$(mktemp -u)" 2>/dev/null | awk '$1 == "'"$conf"'" { print $2; exit }')
    echo "Config value for $conf: $value" >> "$LOG_FILE"
    echo $value
}

# allow the container to be started with `--user`
if [ "$1" = 'mysqld' -a -z "$wantHelp" -a "$(id -u)" = '0' ]; then
    _check_config "$@"
    DATADIR="$(_get_config 'datadir' "$@")"
	echo "DATADIR: $DATADIR" >> "$LOG_FILE"
    mkdir -p "$DATADIR"
    chown -R mysql:mysql "$DATADIR"
fi

echo "init DB" >> "$LOG_FILE"
if [ "$1" = 'mysqld' -a -z "$wantHelp" ]; then
    _check_config "$@"
    DATADIR="$(_get_config 'datadir' "$@")"

	echo "check config fine and dadir: $DATADIR" >> "$LOG_FILE"

	echo "datadir check: $DATADIR/mysql" >> "$LOG_FILE"
    if [ ! -d "$DATADIR/mysql" ]; then
		echo "variable check: MYSQL_ROOT_PASSWORD: $MYSQL_ROOT_PASSWORD MYSQL_ALLOW_EMPTY_PASSWORD: $MYSQL_ALLOW_EMPTY_PASSWORD MYSQL_RANDOM_ROOT_PASSWORD: $MYSQL_RANDOM_ROOT_PASSWORD" >> "$LOG_FILE"
        if [ -z "$MYSQL_ROOT_PASSWORD" -a -z "$MYSQL_ALLOW_EMPTY_PASSWORD" -a -z "$MYSQL_RANDOM_ROOT_PASSWORD" ]; then
            echo >&2 'error: database is uninitialized and password option is not specified '
            echo >&2 '  You need to specify one of MYSQL_ROOT_PASSWORD, MYSQL_ALLOW_EMPTY_PASSWORD and MYSQL_RANDOM_ROOT_PASSWORD'
            exit 1
        fi

        mkdir -p "$DATADIR"

        echo 'Initializing database'
        "$@" --initialize-insecure
        echo 'Database initialized'

        if command -v mysql_ssl_rsa_setup > /dev/null && [ ! -e "$DATADIR/server-key.pem" ]; then
            echo 'Initializing certificates'
			echo "Initializing certificates" >> "$LOG_FILE"
            mysql_ssl_rsa_setup --datadir="$DATADIR"
            echo 'Certificates initialized'
        fi

        SOCKET="$(_get_config 'socket' "$@")"
        echo "SOCKET value: $SOCKET" >> "$LOG_FILE"

        "$@" --skip-networking --socket="${SOCKET}" &
        pid="$!"

        mysql=( mysql --protocol=socket -uroot -hlocalhost --socket="${SOCKET}" )
		echo "mysql $mysql" >> "$LOG_FILE"

        for i in {30..0}; do
            if echo 'SELECT 1' | "${mysql[@]}" &>> "$LOG_FILE"; then
                echo "MySQL connection successful" >> "$LOG_FILE"
                break
            fi
            echo "MySQL init process in progress... Attempt $i" >> "$LOG_FILE"
            sleep 1
        done
        if [ "$i" = 0 ]; then
            echo >&2 'MySQL init process failed.'
            echo "MySQL init process failed after 30 attempts." >> "$LOG_FILE"
            exit 1
        fi

        if [ -z "$MYSQL_INITDB_SKIP_TZINFO" ]; then
			echo "MYSQL_INITDB_SKIP_TZINFO $MYSQL_INITDB_SKIP_TZINFO" >> "$LOG_FILE"
            mysql_tzinfo_to_sql /usr/share/zoneinfo | sed 's/Local time zone must be set--see zic manual page/FCTY/' | "${mysql[@]}" mysql
        fi

		echo "MYSQL_RANDOM_ROOT_PASSWORD $MYSQL_RANDOM_ROOT_PASSWORD" >> "$LOG_FILE"
        if [ ! -z "$MYSQL_RANDOM_ROOT_PASSWORD" ]; then
            MYSQL_ROOT_PASSWORD="$(pwgen -1 32)"
			echo "MYSQL_ROOT_PASSWORD $MYSQL_ROOT_PASSWORD" >> "$LOG_FILE"
            echo "GENERATED ROOT PASSWORD: $MYSQL_ROOT_PASSWORD"
        fi

		echo "MYSQL_ROOT_HOST $MYSQL_ROOT_HOST" >> "$LOG_FILE"
        rootCreate=
		if [ ! -z "$MYSQL_ROOT_HOST" -a "$MYSQL_ROOT_HOST" != 'localhost' ]; then
			echo "create root" >> "$LOG_FILE"
			# no, we don't care if read finds a terminating character in this heredoc
			# https://unix.stackexchange.com/questions/265149/why-is-set-o-errexit-breaking-this-read-heredoc-expression/265151#265151
			read -r -d '' rootCreate <<-EOSQL || true
				CREATE USER 'root'@'${MYSQL_ROOT_HOST}' IDENTIFIED BY '${MYSQL_ROOT_PASSWORD}' ;
				GRANT ALL ON *.* TO 'root'@'${MYSQL_ROOT_HOST}' WITH GRANT OPTION ;
			EOSQL
		fi

		echo "${mysql[@]}" >> "$LOG_FILE"
		"${mysql[@]}" <<-EOSQL
			SET @@SESSION.SQL_LOG_BIN=0;

			DELETE FROM mysql.user WHERE user NOT IN ('mysql.sys', 'mysqlxsys', 'root') OR host NOT IN ('localhost') ;
			SET PASSWORD FOR 'root'@'localhost'=PASSWORD('${MYSQL_ROOT_PASSWORD}') ;
			GRANT ALL ON *.* TO 'root'@'localhost' WITH GRANT OPTION ;
			${rootCreate}
			DROP DATABASE IF EXISTS test ;
			FLUSH PRIVILEGES ;
		EOSQL

		echo "MYSQL_ROOT_PASSWORD: $MYSQL_ROOT_PASSWORD" >> "$LOG_FILE"
        if [ ! -z "$MYSQL_ROOT_PASSWORD" ]; then
            mysql+=( -p"${MYSQL_ROOT_PASSWORD}" )
			echo "mysql in mysql_root_passwort: $mysql" >> "$LOG_FILE"
        fi

		echo "MYSQL_USER: $MYSQL_USER" >> "$LOG_FILE"
        if [ "$MYSQL_USER" -a "$MYSQL_PASSWORD" ]; then
			echo "create mysql user" >> "$LOG_FILE"
            echo "CREATE USER '$MYSQL_USER'@'%' IDENTIFIED BY '$MYSQL_PASSWORD' ;" | "${mysql[@]}"

			echo "MYSQL_DATABASE: $MYSQL_DATABASE" >> "$LOG_FILE"
            if [ "$MYSQL_DATABASE" ]; then
				echo "grant all on database" >> "$LOG_FILE"
                echo "GRANT ALL ON \`$MYSQL_DATABASE\`.* TO '$MYSQL_USER'@'%' ;" | "${mysql[@]}"
            fi

            echo 'FLUSH PRIVILEGES ;' | "${mysql[@]}"
        fi

        echo
		
		echo "MANGOS_SERVER_VERSION: $MANGOS_SERVER_VERSION" >> "$LOG_FILE"
        # WORLD DATABASE CREATION
        if [ -z "$MANGOS_SERVER_VERSION" ]; then
            echo >&2 '  You need to specify MANGOS_SERVER_VERSION in order to initialize the database'
            exit 1
        fi

		echo "MANGOS_DB_RELEASE: $MANGOS_DB_RELEASE" >> "$LOG_FILE"
        if [ -z "$MANGOS_DB_RELEASE" ]; then
            echo >&2 '  You need to specify MANGOS_DB_RELEASE in order to initialize the database'
            exit 1
        fi

		echo "MANGOS_SERVER_VERSION: $MANGOS_SERVER_VERSION" >> "$LOG_FILE"
		echo "MANGOS_WORLD_DB: $MANGOS_WORLD_DB" >> "$LOG_FILE"
		echo "MANGOS_CHARACTER_DB: $MANGOS_CHARACTER_DB" >> "$LOG_FILE"
        if [ "$MANGOS_SERVER_VERSION" -eq 4 ]; then
            MANGOS_WORLD_DB=mangos4
            MANGOS_CHARACTER_DB=character4
        elif [ "$MANGOS_SERVER_VERSION" -eq 3 ]; then
            MANGOS_WORLD_DB=mangos3
            MANGOS_CHARACTER_DB=character3
        elif [ "$MANGOS_SERVER_VERSION" -eq 2 ]; then
            MANGOS_WORLD_DB=mangos2
            MANGOS_CHARACTER_DB=character2
        elif [ "$MANGOS_SERVER_VERSION" -eq 1 ]; then
            MANGOS_WORLD_DB=mangos1
            MANGOS_CHARACTER_DB=character1
        else
            MANGOS_WORLD_DB=mangos0
            MANGOS_CHARACTER_DB=character0
        fi

        "${mysql[@]}" < /database/World/Setup/mangosdCreateDB.sql
        "${mysql[@]}" -D${MANGOS_WORLD_DB} < /database/World/Setup/mangosdLoadDB.sql
        for f in /database/World/Setup/FullDB/*; do
			echo "do FullDB stuff" >> "$LOG_FILE"
            echo "$0: running $f"; "${mysql[@]}" -D${MANGOS_WORLD_DB} < "$f";
        done
        echo "APPLYING UPDATES..."
        for f in /database/World/Updates/*/*.sql; do
			echo "do World/Updates stuff" >> "$LOG_FILE"
            echo "$0: running $f"; "${mysql[@]}" -D${MANGOS_WORLD_DB} < "$f";
        done
        echo "WORLD DATABASE CREATED."
        echo "CHARACTER DATABASE CREATION..."
        "${mysql[@]}" < /database/Character/Setup/characterCreateDB.sql
        "${mysql[@]}"  -D${MANGOS_CHARACTER_DB} < /database/Character/Setup/characterLoadDB.sql
        echo "APPLYING UPDATES..."
        for f in /database/Character/Updates/*/*.sql; do
			echo "do Character/Updates stuff" >> "$LOG_FILE"
            echo "$0: running $f"; "${mysql[@]}" -D${MANGOS_CHARACTER_DB} < "$f";
        done
        echo "CHARACTER DATABASE CREATED."
        echo "REALM DATABASE CREATION..."
	    "${mysql[@]}" <<-EOSQL
		    CREATE DATABASE realmd DEFAULT CHARACTER SET utf8 COLLATE utf8_general_ci;
		GRANT SELECT, INSERT, UPDATE, DELETE, CREATE, DROP, ALTER, LOCK TABLES ON \`realmd\`.* TO 'mangos'@'%';
		FLUSH PRIVILEGES;
	EOSQL
    "${mysql[@]}" -Drealmd < /database/Realm/Setup/realmdLoadDB.sql
    echo "APPLYING UPDATES..."
    for f in /database/Realm/Updates/*/*.sql; do
		echo "do Realm/Updates stuff" >> "$LOG_FILE"
        echo "$0: running $f"; "${mysql[@]}" -Drealmd < "$f";
    done
	"${mysql[@]}" -Drealmd <<-EOSQL
		INSERT INTO realmlist (name,realmbuilds) VALUES ('${MANGOS_DATABASE_REALM_NAME}','12340') ;
	EOSQL
        echo "REALM DATABASE CREATED."

        for f in /docker-entrypoint-initdb.d/*; do
			echo "f: $f" >> "$LOG_FILE"
            case "$f" in
                *.sh)     echo "$0: running $f"; . "$f" ;;
                *.sql)    echo "$0: running $f"; "${mysql[@]}" < "$f"; echo ;;
                *.sql.gz) echo "$0: running $f"; gunzip -c "$f" | "${mysql[@]}"; echo ;;
                *)        echo "$0: ignoring $f" ;;
            esac
            echo
        done

		if [ ! -z "$MYSQL_ONETIME_PASSWORD" ]; then
			echo "MYSQL_ONETIME_PASSWORD: $MYSQL_ONETIME_PASSWORD" >> "$LOG_FILE"
			"${mysql[@]}" <<-EOSQL
				ALTER USER 'root'@'%' PASSWORD EXPIRE;
			EOSQL
		fi
        if ! kill -s TERM "$pid" || ! wait "$pid"; then
            echo >&2 'MySQL init process failed.'
            exit 1
        fi

        echo
        echo 'MySQL init process done. Ready for start up.'
        echo
    fi
fi

exec "$@"