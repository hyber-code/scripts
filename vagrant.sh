#!/bin/sh
GPGKEY="51852D87348FFC4C"
VERSION="1.9.7"
URLBASE="https://releases.hashicorp.com/vagrant"

# GPG import key
gpg --recv-keys $GPGKEY

# download
mkdir -p /tmp/vagrant
cd /tmp/vagrant
wget -N "${URLBASE}/${VERSION}/vagrant_${VERSION}_SHA256SUMS"
wget -N "${URLBASE}/${VERSION}/vagrant_${VERSION}_SHA256SUMS.sig"
wget -N "${URLBASE}/${VERSION}/vagrant_${VERSION}_i686.deb"

# check gpg
result= gpg --keyid-format 0xlong --verify "vagrant_${VERSION}_SHA256SUMS.sig" "vagrant_${VERSION}_SHA256SUMS"

# TODO: build the check if the result is good or bad


# check sha256sum
sha256sum /tmp/vagrant/"vagrant_${VERSION}_i686.deb"
grep "i686.deb" /tmp/vagrant/"vagrant_${VERSION}_SHA256SUMS"

# TODO: build the check if the sha256sum matches or not

sudo dpkg -i /tmp/vagrant/"vagrant_${VERSION}_i686.deb"

# install vagrant SCP plugin
vagrant plugin install vagrant-scp
