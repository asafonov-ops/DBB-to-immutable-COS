# Known Limitations:
#
# Only uses a single COS Accesser (defined in rclone profile)
# Clones only one last TSM DB Backup Series
# No synchronization with the actual TSM "backup db" process, requires manual synchronization
# Target vault retention should be set to N-1 number of days (N days is desired retention duration for cloned DB copies).
