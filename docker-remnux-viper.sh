#!/bin/sh
sudo docker pull remnux/viper
cd $HOME
mkdir viper-workdir
chmod a+xwr viper-workdir
sudo docker run -d --rm -p 9090:9090 -v ~/viper-workdir:/home/nonroot/workdir remnux/viper
