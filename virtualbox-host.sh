#/bin/sh

# installation virtualbox
sudo apt-get install virtualbox -y
sudo apt-get install virtualbox-qt -y

# determine the version of the extension pack
version=$(vboxmanage -v)
var1=$(echo $version | cut -d '_' -f 1)
var2=$(echo $version | cut -d 'r' -f 2)
file="Oracle_VM_VirtualBox_Extension_Pack-$var1-$var2.vbox-extpack"

# download the file and the hashes
baseurl="http://download.virtualbox.org/virtualbox"
echo "$baseurl/$var1/$file"

mkdir -p /tmp/virtualbox
cd /tmp/virtualbox
wget -N $baseurl/$var1/$file
wget -N https://www.virtualbox.org/download/hashes/$var1/SHA256SUMS

# check the hashes of the extension pack
vboxsha=$(grep -i "$var1.vbox-extpack" /tmp/virtualbox/SHA256SUMS | cut -d ' ' -f 1)
downloadsha=$(sha256sum /tmp/virtualbox/$file | cut -d ' ' -f 1)

if [ $vboxsha == $downloadsha ]; then
  # hashes match so we can install the extension pack
  echo "The sha256sum match, proceeding to install."
  sudo VBoxManage extpack uninstall "Oracle VM VirtualBox Extension Pack"
  sudo VBoxManage extpack install --replace /tmp/virtualbox/$file 
else
  echo "The shasum for extension pack download did not match."
fi

# installation of the guestadditions
# sudo apt-get install virtualbox-guest-additions-iso -y
