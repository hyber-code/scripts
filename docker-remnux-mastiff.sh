#/bin/sh
sudo docker pull remnux/mastiff

# create the work directory if it doesn't exist
if [ ! -d $HOME/mastiff-workdir ]; then
    mkdir mastiff-workdir
    chmod a+xwr mastiff-workdir
fi
