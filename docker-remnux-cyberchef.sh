#!/bin/sh
# pull the remnux/cyberchef
sudo docker pull remnux/cyberchef
# start the cyberchef listening on port 8080
sudo docker run -d --rm -p 8080:80 remnux/cyberchef
