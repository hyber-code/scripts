#!/bin/sh

# install haveged
sudo apt-get install -y haveged

# check the parameters of the config file
DESIRED='-w 1024'
PARAM=$(grep 'DAEMON_ARGS' /etc/default/haveged | cut -d '=' -f 2 | cut -c2-8)
echo 'Checking DAEMON_ARGS parameters in /etc/default/haveged ...'
if [ "$DESIRED" ==  "$PARAM" ] ; then
   echo 'Parameters OK'
else
   echo 'Parameters NOK, please check with your administrator.'
fi

# configure to start at boot
sudo update-rc.d haveged defaults

# Perform tests
echo 'Starting Tests, expect low number of failures but at least 998 success.'
cat /dev/random | rngtest -c 1000
echo ''
echo 'Checking entropy availability'
ENTROPY=$(cat /proc/sys/kernel/random/entropy_avail)
if [ $ENTROPY > 1000 ] ; then
   echo "$ENTROPY is high enough."
else
   echo "$ENTROPY is too low."
fi
