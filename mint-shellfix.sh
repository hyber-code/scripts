#!/bin/bash
echo "The default shell on mint Linux is dash, this script changes /bin/sh"
echo "from /bin/dash to /bin/bash."

# make a backup
sudo mv /bin/sh /bin/sh.bak

# make the new soft link
sudo ln -s /bin/bash /bin/sh
