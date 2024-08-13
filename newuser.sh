#!/bin/bash
#
# A simple script to create a new user
# Needs to be run as root, so as not to expose it to the web interface.

if [ "$EUID" -ne 0 ]
  then echo "Please run as root"
  exit
fi

echo -n "Username: "
read usr
echo -n "Password: "
read pwd
echo "Creating user $usr"

datafile="beerdata/$usr.data"
picdir="beerdata/$usr.photo"
mkdir -p $picdir
touch $datafile
chown www-data:heikki $datafile $picdir
chmod g+w $datafile $picdir

htpasswd -b  .htpasswd  $usr $pwd && echo "Created $usr all right"
