#!/bin/bash
#
# A simple script to create a new user
# Needs to be run as root, so as not to expose it to the web interface.

echo -n "Username: "
read usr
echo -n "Password: "
read pwd
echo "Creating user $usr"

datafile="beerdata/$usr.data"
touch $datafile
chown www-data:heikki $datafile
chmod g+w $datafile

htpasswd -b  .htpasswd  $usr $pwd && echo "Created $usr all right"
