#!/bin/bash

CMD=rclone                                                                                                      # Tested with rclone v1.68.1
FLAGS="--s3-chunk-size 16M --s3-upload-cutoff 0  --disable ServerSideAcrossConfigs  --stats 1s --progress"      # For production deployment you may want to remove "--stats 1s --progress"
SRC=COS_C2LAB                                                                                                   # rclone profile name, this profile must have at least read-only access to the
                                                                                                                # vault where TSM writes DB backup
DST=COS_C2LAB_RETENTION                                                                                         # rclone profile name, this profile must have read/write access to the target
                                                                                                                # retention enabled vault
INCLUDE_DBV="--include *.DBV"                                                                                   # TSM naming convention for DBB files/objects
SRC_BUCKET=tsminst1dbb                                                                                          # Bucket name in TSM configuration where DBB is stored
DST_BUCKET=tsminst1dbbretday$(echo $(($(date +%s) / 86400))%4 + 1| bc)                                          # Target retention enabled vault name, every day the name alternated day1 day2 day3 day4 day1 ...
INSTANCE_ID=dbbackup-tsminst1-c4fb71884961ee11955b82aaed4dffed                                                  # Name selected by your TSM server instance, must match your actual identifier
DBB_DEVCLASS=DBBCOS                                                                                             # TSM devclass name used for DB backup 'backup DB devclass=DBBCOS type=full'


DBB_LATEST_SERIES=$($CMD cat $SRC:$SRC_BUCKET/$INSTANCE_ID/volhistory | egrep -A 1 -B 3 "Device Class Name:\s+$DBB_DEVCLASS" | grep "Backup Series:" | awk '{ print $3 }' | sort -u | tail -1)

echo DBB latest series: $DBB_LATEST_SERIES

for i in $(rclone cat $SRC:$SRC_BUCKET/$INSTANCE_ID/volhistory | egrep -A4 -B1 "Backup Series:\s+$DBB_LATEST_SERIES" | grep "Volume Name: " | awk -F '"' '{ print $2}' ) ;
do echo Cloning $i ; $CMD copy $SRC:$i $DST:/$DST_BUCKET/$INSTANCE_ID/volumes/DBV/ $FLAGS;
 done

echo Cloning volhistory
$CMD copy $SRC:$SRC_BUCKET/$INSTANCE_ID/volhistory $DST:/$DST_BUCKET/$INSTANCE_ID/volhistory.orig
echo Cloning devconfig
$CMD copy $SRC:$SRC_BUCKET/$INSTANCE_ID/devconfig  $DST:/$DST_BUCKET/$INSTANCE_ID/devconfig.orig
echo Cloning enckey
$CMD copy $SRC:$SRC_BUCKET/$INSTANCE_ID/enckey  $DST:/$DST_BUCKET/$INSTANCE_ID/

echo Modifying volhistory
$CMD cat  $DST:/$DST_BUCKET/$INSTANCE_ID/volhistory.orig/volhistory  | sed -e 's/\"'$SRC_BUCKET'/\"'$DST_BUCKET'/g' | $CMD rcat $DST:/$DST_BUCKET/$INSTANCE_ID/volhistory
echo Modifying devconfig
$CMD cat  $DST:/$DST_BUCKET/$INSTANCE_ID/devconfig.orig/devconfig    | sed -e 's/'$SRC_BUCKET'/'$DST_BUCKET'/g'    | $CMD rcat $DST:/$DST_BUCKET/$INSTANCE_ID/devconfig

# Known Limitations:
#
# Expiration and cleanup of expired version of TSM DB backups is not yet implemented
# Only uses a single COS Accesser (defined in rclone profile)
# Copies one DBV object at a time, may limit performance
# Clones only one last TSM DB Backup Series
# No synchronization with the actual TSM "backup db" process, requires manual synchronization
# Target vault retention should be set to 3 days (4 days rotation minus 1 day).
