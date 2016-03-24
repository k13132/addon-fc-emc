#!/bin/bash

. /var/lib/one/remotes/scripts_common.sh
NAVISECCLI="/opt/Navisphere/bin/naviseccli -User $CLI_USER -Password $CLI_PASSWORD -Address $CLI_HOSTNAME -Scope 0 "
LOCK=/var/tmp/one/datastore/emc/lock
SLEEP=3
TIMEOUT=90

#------------------------------------------------------------------------------
#  Creates uniform Storage Group name based on host name
#    @param $1 - DNS hostname of node
#    @return None
#	Bet sets up variable SG
#------------------------------------------------------------------------------
function make_SG_name {
  # Function for making unified Storage Group name based on host name
  SG="ONE_${1}"
}


#------------------------------------------------------------------------------
#  Assign specified host by selected LUN
#    @param $1 - LUN id bysed on numbering in Navishere convences
#    @param $2 - DNS hostname of node 
#    @return None
#------------------------------------------------------------------------------
function assign_image_to_host {
  # Assign specified host by selected LUN

  # 0. Storage group name
  make_SG_name $2
 
  # 1. Check if SG exists
  CMD="$NAVISECCLI storagegroup -list | awk -F: 'BEGIN{n=0}/Storage Group Name:/{gsub(\" \",\"\",\$2); if(\$2 == \"$SG\"){ n+=1; exit} }END{print n;}'";
  SG_EXISTS=`echo $CMD | sh`
  if [ $SG_EXISTS == '0' ]; then
     # Create storage group
     CMD="$NAVISECCLI storagegroup -create -gname $SG";
     echo $CMD | sh
  fi
  
  # 2. Check if host is registered with EMC controller
  REGISTEREDUID=`mktemp`
  $NAVISECCLI port -list -hba | awk '{if( $1 == "HBA" && $2 == "UID:" ){HBAUID=$3}if( $1 == "Server" && $2 == "Name:" ){SERVERIP=$3}if( $1 == "Server" && $2 == "IP" ){IP=$4}if( $1 == "SP" && $2 == "Port" ){print HBAUID" "SERVERIP" "IP" "$4}}' > $REGISTEREDUID

  for h in `ls /sys/class/fc_host`; do
    HBA_node=$(cat /sys/class/fc_host/$h/node_name | sed 's/.\{2\}/&:/g' | awk '{print substr($0,4,length($0)-4)}')
    HBA_port=$(cat /sys/class/fc_host/$h/port_name | sed 's/.\{2\}/&:/g' | awk '{print substr($0,4,length($0)-4)}')
    HBA="$HBA_node:$HBA_port"


    if [ $(grep -i ${HBA^^} $REGISTEREDUID | awk '/UNKNOWN/{print $0}' | wc -l) -ge 1 ]; then
#       echo "Register HBA" $HBA $2
       HBA_IP=$(getent hosts kvasi.k13132.local | awk '{print $1}')
       SPPORT=$(grep -i ${HBA^^} $REGISTEREDUID | awk '/UNKNOWN/{print $4}' | head -n1)

       $NAVISECCLI storagegroup -setpath -o -hbauid $HBA -sp a -spport $SPPORT -ip $HBA_IP -failovermode 4 -arraycommpath 1 -host $2
       $NAVISECCLI storagegroup -setpath -o -hbauid $HBA -sp b -spport $SPPORT -ip $HBA_IP -failovermode 4 -arraycommpath 1 -host $2
    fi;
  done
  rm $REGISTEREDUID 

  # 3. Check if host is assigned to SG
  T=$($NAVISECCLI storagegroup -list -gname $SG)
  N=0
  for h in `ls /sys/class/fc_host`; do
    HBA_node=$(cat /sys/class/fc_host/$h/node_name | sed 's/.\{2\}/&:/g' | awk '{print substr($0,4,length($0)-4)}')
    HBA_port=$(cat /sys/class/fc_host/$h/port_name | sed 's/.\{2\}/&:/g' | awk '{print substr($0,4,length($0)-4)}')
    HBA="$HBA_node:$HBA_port"

    # Count the number of of HBA connected to SG which are same as HBA of local device
    i=$(echo $T | grep -i $HBA | wc -l)
    N=$((N+i))
  done;

  if [ $N -eq 0 ]; then
    $NAVISECCLI storagegroup -connecthost -host $2 -gname $SG -o
  fi;

  # 3. Assign LUN to SG
  CMD="$NAVISECCLI storagegroup -addhlu -gname $SG -hlu $1 -alu $1" 
  log "Attaching LUN to SG: $CMD" 
  echo $CMD | sh > /dev/null
}


#------------------------------------------------------------------------------
#  Function for un-connecting selected LUN from specified host
#    @param $1 - LUN id bysed on numbering in Navishere convences
#    @param $2 - DNS hostname of node
#    @return None
#------------------------------------------------------------------------------
function unassign_image_from_host { 
 
  # 0. Make storage group name based on hostname
  make_SG_name $2
 
  # 1. Check if assigned
  CMD="$NAVISECCLI storagegroup -list -gname $SG | awk 'BEGIN{s=0}{ if(\$1 == '$1'){s+=1;}} END{ print s }'"
  E=`echo $CMD | sh`;

  if [ $E -eq '0' ]; then
    exit 0
  fi

  # 2. Unassign
  CMD="$NAVISECCLI storagegroup -removehlu -gname $SG -hlu $1 -o"
  exec_and_log "$CMD" "Unable to unassign LUN $1 from $SG"
}


#------------------------------------------------------------------------------
#  Function for creating block device based on LUN id which is already assigned 
#  to host
#    @param $1 - LUN id bysed on numbering in Navishere convences
#    @param $2 - Destination path where to symlink device
#    @return None
#------------------------------------------------------------------------------
function create_block_device {

  # Scan FC transponders
  GMPATHDEV=""
  for d in `ls /sys/class/fc_transport/`; do
    # Convert X:X:X into X X X 
    ids=`echo ${d#target*} | sed -e "s/:/ /g"`
    
    # Request block device from scsi subystem
    CMD="echo \"scsi add-single-device $ids $1\" > /proc/scsi/scsi"
    sudo bash -c "$CMD"

    # Scan and create multipath device
    sleep 1
    DEV=$(lsscsi `echo "$ids $1" | sed -e 's/ /:/g'` | awk '{print $6}')
    SCSIID=$(sudo /lib/udev/scsi_id  --whitelisted --device=$DEV)

    # Find multipath device
    if [ ! -z $SCSIID ]; then
      sudo multipath -v0 $SCSIID
      MPATHDEV=$(sudo multipath -l  | grep $SCSIID | awk '{print $1}')
      if [ -z $GMPATHDEV ] && [ ! -z $MPATHDEV ]; then
          GMPATHDEV=$MPATHDEV
      fi;
    fi;
  done;
  
  # Permissions for mpath device
  DEV="/dev/mapper/$GMPATHDEV"
  DM=$(readlink -f $DEV)
  sudo chown oneadmin:oneadmin $DM $DEV

  # Return multipath identifier
  echo $DEV

  # Make symlink if $2 is defined
  if [ $# -ge 2 ]; then
    ln -sf $DEV $2
  fi;
}


#------------------------------------------------------------------------------
#  Function for droping block device based on LUN id which is already assigned
#  to host
#    @param $1 - LUN id bysed on numbering in Navishere convences
#    @return None
#------------------------------------------------------------------------------
function drop_block_device {

  # Scan FC transponders
  GMPATHDEV=""
  MPATHFLUSHED=0
  for d in `ls /sys/class/fc_transport/`; do
    # Convert X:X:X into X X X
    ids=`echo ${d#target*} | sed -e "s/:/ /g"`

    if [ $MPATHFLUSHED -eq 0 ]; then
      DEV=$(lsscsi `echo "$ids $1" | sed -e 's/ /:/g'` | awk '{print $6}')
      SCSIID=$(sudo /lib/udev/scsi_id  --whitelisted --device=$DEV)
      log "Devices: $DEV $SCSIID"
      if [ ! -z $SCSIID ]; then
        MPATHDEV=$(sudo multipath -l  | grep $SCSIID | awk '{print $1}')
	log "finding device $DEV $SCSIID $MPATHDEV $GMPATHDEV"
        if [ -z $GMPATHDEV ] && [ ! -z $MPATHDEV ]; then
            GMPATHDEV=$MPATHDEV
        fi;
      fi;
      
      # Flush multipath device 
      log "Multipath flush: $MPATHDEV"
      sudo multipath -f $MPATHDEV -v0 
      MPATHFLUSHED=1
    fi;

    # Drop block device from scsi subystem
    CMD="echo \"scsi remove-single-device $ids $1\" > /proc/scsi/scsi"
    sudo bash -c "$CMD" > /dev/null

  done;
}


#------------------------------------------------------------------------------
#  Function creating an exclusive are 
#    @return None
#------------------------------------------------------------------------------
function semaphor_on {
	w=0
	while [ -e $LOCK ]; do
	 sleep $SLEEP;
	 log "Waiting $w/${TIMEOUT}s till $LOCK is released";
	 w=$((w+$SLEEP));
	 if [ $w -gt $TIMEOUT ]; then
	    exit 1;
	 fi;
	done
	touch $LOCK
}


#------------------------------------------------------------------------------
#  Function creating an exclusive are
#    @return None
#------------------------------------------------------------------------------
function semaphor_off {
	w=0
	while true; do
	  $NAVISECCLI getlun $LUN_ID | grep "Invalid LUN number"
	  if [ $? -eq 1  ]; then
	    break;
	  fi;
	  log "Waiting $w/${TIMEOUT}s till $1 is created";
	  w=$((w+$SLEEP));
	  if [ $w -gt $TIMEOUT ]; then
	    exit 1;
	  fi;
	  sleep $SLEEP;
	done;
	rm $LOCK
}

#assign_image_to_host 4 `hostname`
#create_block_device 4

#drop_block_device 4
