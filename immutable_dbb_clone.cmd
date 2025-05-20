#!/bin/bash

CMD=rclone                                                                                                      # Tested with rclone v1.68.1
FLAGS="--s3-chunk-size 16M --s3-upload-cutoff 0  --disable ServerSideAcrossConfigs  --stats 1s --progress"      # For production deployment you may want to remove "--stats 1s --progress"

SRC=COS_C2LAB                                                                                                   # rclone profile name, this profile must have at least read-only access to the
                                                                                                                # vault where Storage Protect writes DB backup
DST=COS_C2LAB_RETENTION                                                                                         # rclone profile name, this profile must have read/write access to the target
                                                                                                                # retention enabled vault
DBB_RETENTION_INTERVAL=4                                                                                        # Days to retain DBB clones bafore expiration. Note COS retention in managed separately
INCLUDE_DBV="--include *.DBV"                                                                                   # Storage Protect naming convention for DBB files/objects
SRC_BUCKET=tsminst1dbb                                                                                          # Bucket name in Storage Protect configuration where DBB is stored
DST_BUCKET=tsminst1dbbretday$(echo $(($(date +%s) / 86400))%$DBB_RETENTION_INTERVAL + 1| bc)                                            # Target retention enabled vault name, every day the name alternated day1 day2 day3 day4 day1 ...
# DST_BUCKET=tsminst1dbb1d                                              # Target retention enabled vault name, every day the name alternated day1 day2 day3 day4 day1 ...
INSTANCE_ID=dbbackup-tsminst1-c4fb71884961ee11955b82aaed4dffed                                                  # Name selected by your Storage Protect server instance, must match your actual identifier
DBB_DEVCLASS=DBBCOS                                                                                             # Storage Protect devclass name used for DB backup 'backup DB devclass=DBBCOS type=full'

DBV_COUNT=$($CMD ls $DST:$DST_BUCKET --include *DBV | wc -l)

if [[ $? -ne 0 ]]
        then echo Failed to run $CMD ls $DST:$DST_BUCKET
        exit -1
fi

if [[ $DBV_COUNT -gt 0 ]]
        then
                echo Deleting expired devconfig,volumehistory,enckey,DBV objects
                $CMD ls $DST:$DST_BUCKET --include volhistory | awk '{ print $2}'  | $CMD delete --files-from - $DST:$DST_BUCKET > /dev/null 2>&1
                if [[ $? -ne 0 ]]
                        then
                                echo Unable to delete $DST_BUCKET/$INSTANCE_ID/volhistory, InvalidRequestForLegalReasons: The object is protected
                                echo Exiting
                                exit 1
                        else
                                echo Deleting $DST:$DST_BUCKET/$INSTANCE_ID/volhistory: Deleted
                                for i in devconfig enckey *.DBV ; do
                                $CMD ls $DST:$DST_BUCKET --include $i | awk '{ print $2}'  | $CMD delete -v --files-from - $DST:$DST_BUCKET
                                done
                fi
fi



DBB_LATEST_SERIES=$($CMD cat $SRC:$SRC_BUCKET/$INSTANCE_ID/volhistory | egrep -A 1 -B 3 "Device Class Name:\s+$DBB_DEVCLASS" | grep "Backup Series:" | awk '{ print $3 }' | sort -u | tail -1)

echo DBB latest series: $DBB_LATEST_SERIES

# for i in $($CMD cat $SRC:$SRC_BUCKET/$INSTANCE_ID/volhistory | egrep -A4 -B1 "Backup Series:\s+$DBB_LATEST_SERIES" | egrep -A4 -B1 "Device Class Name:\s+$DBB_DEVCLASS" | grep "Volume Name: " | awk -F '"' '{ print $2}' ) ;
# do echo Cloning $i ; $CMD copy $SRC:$i $DST:/$DST_BUCKET/$INSTANCE_ID/volumes/DBV/ $FLAGS;
#  done
echo Cloning DBV objects to $DST_BUCKET/$INSTANCE_ID/
$CMD cat $SRC:$SRC_BUCKET/$INSTANCE_ID/volhistory | egrep -A4 -B1 "Backup Series:\s+$DBB_LATEST_SERIES" | egrep -B4 -A1 "Device Class Name:\s+$DBB_DEVCLASS" | grep "Volume Name: " | awk -F '"' '{ print $2}' | awk -F '/' '{ print $2"/"$3"/"$4"/"$5}' | $CMD copy $FLAGS --files-from -  COS_C2LAB:$SRC_BUCKET COS_C2LAB_RETENTION:$DST_BUCKET

echo Cloning volhistory
$CMD copy $SRC:$SRC_BUCKET/$INSTANCE_ID/volhistory $DST:/$DST_BUCKET/$INSTANCE_ID/volhistory.orig
echo Cloning devconfig
$CMD copy $SRC:$SRC_BUCKET/$INSTANCE_ID/devconfig  $DST:/$DST_BUCKET/$INSTANCE_ID/devconfig.orig
echo Cloning enckey
$CMD copy $SRC:$SRC_BUCKET/$INSTANCE_ID/enckey  $DST:/$DST_BUCKET/$INSTANCE_ID/

echo Modifying volhistory
$CMD cat  $DST:/$DST_BUCKET/$INSTANCE_ID/volhistory.orig/volhistory  | sed -e 's/\"'$SRC_BUCKET'/\"'$DST_BUCKET'/g' | $CMD rcat --quiet $DST:/$DST_BUCKET/$INSTANCE_ID/volhistory
echo Modifying devconfig
$CMD cat  $DST:/$DST_BUCKET/$INSTANCE_ID/devconfig.orig/devconfig    | sed -e 's/'$SRC_BUCKET'/'$DST_BUCKET'/g'    | $CMD rcat $DST:/$DST_BUCKET/$INSTANCE_ID/devconfig

# Known Limitations:
#
# Only uses a single COS Accesser (defined in rclone profile)
# Clones only one last Storage Protect full DB Backup Series
# Supports full Storage Protect DBB only, no snapshots or incremental backups
# No synchronization with the actual Storage Protect "backup db" process, requires manual synchronization
# Target vault retention should be set to $DBB_RETENTION_INTERVAL-1 days
