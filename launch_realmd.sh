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

# seed with defaults included in the container image, this is the
# case when /realmdconf is not specified
cp $CONFDIR/* /tmp

if [ -f /realmdconf/realmd.conf ]; then
	echo "/realmdconf/realmd.conf is being used"
	CONFIGS=/realmdconf
fi

# Use AWK to edit the configuration file

# If the line starts with "LoginDatabaseInfo", replace it
# Otherwise, leave the line unchanged
awk -v login_info="$LOGIN_DATABASE_INFO" '
    
    $1 == "LoginDatabaseInfo" && $2 == "=" {
        print "LoginDatabaseInfo = \"" login_info "\""
    } 
    
    { 
        print $0
    }' "$CONFIGS/realmd.conf" > /tmp/realmd.conf

# Move the edited configuration file back
mv /tmp/realmd.conf "$CONFIGS/realmd.conf"

${BINDIR}/realmd -c $CONFIGS/realmd.conf
