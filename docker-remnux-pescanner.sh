#!/bin/sh
sudo docker pull remnux/pescanner

# create the work directory if it doesn't exist
if [ ! -d $HOME/pescanner-workdir ]; then
    mkdir pescanner-workdir
    chmod a+xwr pescanner-workdir
fi
