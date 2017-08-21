#!/bin/sh
GPGKEY="0x54DDD393"
VERSION="1.21"
BASEURL="https://launchpad.net/veracrypt/trunk"

# GPG import key
gpg --recv-keys $GPGKEY 

# download
mkdir -p /tmp/veracrypt
cd /tmp/veracrypt

wget -N "${BASEURL}/${VERSION}/+download/veracrypt-${VERSION}-setup.tar.bz2.sig"
wget -N "${BASEURL}/${VERSION}/+download/veracrypt-${VERSION}-setup.tar.bz2"

# check gpg
result= gpg --keyid-format 0xlong --verify "veracrypt-${VERSION}-setup.tar.bz2.sig" "veracrypt-${VERSION}-setup.tar.bz2"

# TODO: build the check if the result is good or bad

# unpack
tar xvjf "veracrypt-${VERSION}-setup.tar.bz2"
sudo ./"veracrypt-${VERSION}-setup-gui-x64"
