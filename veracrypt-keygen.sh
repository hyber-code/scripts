#!/bin/sh
echo "Generating key at $1"
veracrypt --text --create-keyfile --random-source=/dev/random $1
