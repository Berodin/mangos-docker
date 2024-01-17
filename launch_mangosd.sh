#!/bin/bash

# Copyright 2017 Stephen SORRIAUX
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
# http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

BINDIR=/etc/mangos/bin
CONFDIR=/etc/mangos/conf
CONFIGS=/tmp
LOGIN_DATABASE_INFO="${CHART_FULLNAME}-mysql-service;3306;${MYSQL_USER};${MYSQL_PASSWORD};realmd"
WORLD_DATABASE_INFO="${CHART_FULLNAME}-mysql-service;3306;${MYSQL_USER};${MYSQL_PASSWORD};mangos${DATABASE_SUFFIX}"
CHARACTER_DATABASE_INFO="${CHART_FULLNAME}-mysql-service;3306;${MYSQL_USER};${MYSQL_PASSWORD};character${DATABASE_SUFFIX}"
# seed with defaults included in the container image, this is the
# case when /mangosconf is not specified

# move serverfiles from temporary path /var/etc/mangos to PV mounted NFS path /etc/mangos
cp -rp /var/etc/mangos/* /etc/mangos/ 

# Prüfe und verwende benutzerdefinierte Konfigurationen
if [ -f /mangosconf/mangosd.conf ]; then
    echo "/mangosconf/mangosd.conf is being used"
    CONFIGS=/mangosconf
else
    if [ ! -f $CONFIGS/mangosd.conf ]; then
        cp -p $CONFDIR/mangosd.conf $CONFIGS/mangosd.conf
    fi
fi

if [ -f /mangosconf/ahbot.conf ]; then
    echo "/mangosdconf/ahbot.conf is being used"
    AHCONFIG="-a /mangosconf/ahbot.conf"
else
    if [ ! -f $CONFIGS/ahbot.conf ]; then
        cp -p $CONFDIR/ahbot.conf.dist $CONFIGS/ahbot.conf
    fi
    AHCONFIG="-a $CONFIGS/ahbot.conf"
fi

# populate template with env vars
sed -i 's,LoginDatabaseInfo.*=.*,LoginDatabaseInfo = '"$(echo $LOGIN_DATABASE_INFO | sed 's/[;&]/\\&/g')"',g' $CONFIGS/mangosd.conf
sed -i 's,WorldDatabaseInfo.*=.*,WorldDatabaseInfo = '"$(echo $WORLD_DATABASE_INFO | sed 's/[;&]/\\&/g')"',g' $CONFIGS/mangosd.conf
sed -i 's,CharacterDatabaseInfo.*=.*,CharacterDatabaseInfo = '"$(echo $CHARACTER_DATABASE_INFO | sed 's/[;&]/\\&/g')"',g' $CONFIGS/mangosd.conf
sed -i 's,'/server/install/etc/','/etc/mangos/',' $CONFIGS/mangosd.conf

exec ${BINDIR}/mangosd -c $CONFIGS/mangosd.conf ${AHCONFIG}