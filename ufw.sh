#/bin/sh

# configure the logging
sudo ufw logging medium
sudo ufw logging on

# allow ssh, or we will loose our connection
sudo ufw allow ssh

# turn the firewall on
status=$(sudo ufw status | cut -d ' ' -f 2)
if [ $status == 'inactive' ] ; then
  # activate the firewall
  sudo ufw enable <<< "y"
else
  # disactive the firewall
  sudo ufw disable
  # activate the firewall
  sudo ufw enable <<< "y"
fi
