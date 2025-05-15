# Known Limitations:
#
# Expiration and cleanup of expired version of TSM DB backups is not yet implemented
# Only uses a single COS Accesser (defined in rclone profile)
# Copies one DBV object at a time, may limit performance
# Clones only one last TSM DB Backup Series
# No synchronization with the actual TSM "backup db" process, requires manual synchronization
# Target vault retention should be set to 3 days (4 days rotation minus 1 day).
