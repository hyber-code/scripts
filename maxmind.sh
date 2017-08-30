#!/bin/bash

# installing dependencies
sudo add-apt-repository -y ppa:maxmind/ppa
sudo apt-get update
sudo apt-get install -y libgeoip1
sudo apt-get install -y libgeoip-dev
sudo apt-get install -y geoip-bin

# installing python3 and pip3
sudo apt-get install -y python3
sudo apt-get install -y python3-setuptools
sudo apt-get install -y python3-pip

# defining aliases
echo "alias python='python3'" >> $HOME/.bash_aliases
echo "alias pip='pip3'" >> $HOME/.bash_aliases

# install GeoIP
sudo pip install GeoIP
