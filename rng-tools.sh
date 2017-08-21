#!/bin/sh
# Daemon to use a Hardware TRNG. The rngd daemon acts as a bridge between a Hardware TRNG (true random number generator) 
# such as the ones in some Intel/AMD/VIA chipsets, and the kernel's PRNG (pseudo-random number generator). 
sudo apt-get install -y rng-tools
echo "HRNGDEVICE=/dev/urandom" | sudo tee --append /etc/default/rng-tools > /dev/null
sudo service rng-tools restart
