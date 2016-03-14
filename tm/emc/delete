#!/bin/bash

# -------------------------------------------------------------------------- #
# Copyright 2002-2015, OpenNebula Project, OpenNebula Systems                #
#                                                                            #
# Licensed under the Apache License, Version 2.0 (the "License"); you may    #
# not use this file except in compliance with the License. You may obtain    #
# a copy of the License at                                                   #
#                                                                            #
# http://www.apache.org/licenses/LICENSE-2.0                                 #
#                                                                            #
# Unless required by applicable law or agreed to in writing, software        #
# distributed under the License is distributed on an "AS IS" BASIS,          #
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.   #
# See the License for the specific language governing permissions and        #
# limitations under the License.                                             #
#--------------------------------------------------------------------------- #

# clone fe:SOURCE host:remote_system_ds/disk.i vmid dsid
#   - fe is the front-end hostname
#   - SOURCE is the path of the disk image in the form DS_BASE_PATH/disk
#   - host is the target host to deploy the VM
#   - remote_system_ds is the path for the system datastore in the host
#   - vmid is the id of the VM
#   - dsid is the target datastore (0 is the system datastore)

SRC=$1
DST=$2

VMID=$3
DSID=$4

if [ -z "${ONE_LOCATION}" ]; then
    TMCOMMON=/var/lib/one/remotes/tm/tm_common.sh
else
    TMCOMMON=$ONE_LOCATION/var/remotes/tm/tm_common.sh
fi

. $TMCOMMON

DRIVER_PATH=$(dirname $0)

# Libraries location
if [ -z "${ONE_LOCATION}" ]; then
    LIB_LOCATION=/usr/lib/one
else
    LIB_LOCATION=$ONE_LOCATION/lib
fi


#-------------------------------------------------------------------------------
# Set dst path and dir
#-------------------------------------------------------------------------------

SRC_PATH=`arg_path $SRC`
DST_PATH=`arg_path $DST`

DST_HOST=`arg_host $DST`
DST_DIR=`dirname $DST_PATH`


ssh_make_path $DST_HOST $DST_DIR

#-------------------------------------------------------------------------------
# Get Datastore information for communication with EMC controller
#-------------------------------------------------------------------------------

DISK_ID=$(basename ${DST_PATH} | cut -d. -f2)

XPATH="${DRIVER_PATH}/../../datastore/xpath.rb --stdin"

unset i j XPATH_ELEMENTS

while IFS= read -r -d '' element; do
    XPATH_ELEMENTS[i++]="$element"
done < <(onedatastore show -x $DSID| $XPATH \
                    /DATASTORE/TEMPLATE/CLI_HOSTNAME \
                    /DATASTORE/TEMPLATE/CLI_USER \
                    /DATASTORE/TEMPLATE/CLI_PASSWORD)

CLI_HOSTNAME="${XPATH_ELEMENTS[j++]}"
CLI_USER="${XPATH_ELEMENTS[j++]}"
CLI_PASSWORD="${XPATH_ELEMENTS[j++]}"

echo $CLI_HOSTNAME $CLI_USER $CLI_PASSWORD

. $DRIVER_PATH/../../datastore/emc/func.sh


# 1. Check if SG exists
# 1.1. Create SG
# 1.2. Check if host exits
# 1.2.1. Assign host to SG

# 2. Assign LUN to SG
# 3. Refresh SCSI
# 4. Update multipath device
# 5. Make link to system DS at remote host

