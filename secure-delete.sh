#/bin/sh

sudo apt-get install -y secure-delete

# setup the alias so you can keep using rm
echo "alias rm='srm'" >> $HOME/.bash_aliases
