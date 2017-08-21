#!/bin/sh

# installation
sudo apt-get install -y vim

# setup the alias so you can keep using vi
echo "alias vi='vim'" >> $HOME/.bash_aliases
