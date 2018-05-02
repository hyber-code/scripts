#!/bin/bash

function restorebackup(){
    # determine the current profile
    cd ~/.thunderbird
    ls | grep "default$"
    # unpack the backup to /tmp/thunderbirdbackup
    mkdir -p /tmp/thunderbirdbackup
    #tar -zxf $1 --directory /tmp/thunderbirdbackup
    # mv the profile in place
    # mv the old profile
    # cleanup /tmp/thunderbirdbackup
    rm -fR /tmp/thunderbirdbackup
}


if [ -z $1 ]; then
   echo "Please specify the file to restore as parameter."
else
   if [ -f $1 ]; then
       echo "All existing thunderbird data will be moved ..."
       echo "Is $1 the backup you want to restore? (y/n)"
       read ANSWER
       if echo "$ANSWER" | grep -iq "^y" ; then
           # determine if thunderbird is open
           PID=$(pidof thunderbird)
           if [ $? == 0 ]; then
               # thunderbird is running
               # kill thunderbird
               kill -9 $PID
               # restore
               restorebackup $1
               # start thunderbird
               thunderbird &
               disown 
           else
               # thunderbird is not running
               restorebackup $1
           fi 
       else
           exit
       fi
   else
       echo "$1 is not a file that exists."
   fi
fi
