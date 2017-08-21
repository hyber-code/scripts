#!/bin/bash
cd $HOME
mkdir fir
cd fir
wget -N "https://raw.githubusercontent.com/certsocietegenerale/FIR/master/docker/Dockerfile"
sudo docker build -t certsocietegenerale/fir .
sudo docker run -d --rm -p 8000:8000 certsocietegenerale/fir
