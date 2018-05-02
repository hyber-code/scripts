#!/bin/bash

# backup
function backup {
    TODAY=$(date +"%Y-%m-%d")
    tar -czf ~/Documents/thunderbird/thunderbird_$TODAY.tar.gz ~/.thunderbird/
}

# test if thunderbird is running first otherwise you need to kill it make backup and reopen it
PID=$(pidof thunderbird)
if [ $? == 0 ]; then
    # thunderbird is running
    # kill thunderbird
    kill -9 $PID
    # backup
    backup    
    # open thunderbird again
    thunderbird &
    disown
else
    # thunderbird is closed
    backup
fi
