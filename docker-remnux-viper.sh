#!/bin/sh
sudo docker pull remnux/viper

# create the work directory if it doesn't exist
if [ ! -d $HOME/viper-workdir ]; then
    mkdir viper-workdir
    chmod a+xwr viper-workdir
fi

sudo docker run -d --rm -p 9090:9090 -v ~/viper-workdir:/home/nonroot/workdir remnux/viper
