#! /usr/bin/bash

# A script to update the database structure
# Keeping the data

echo "Updating the database structure from db.schema"
cd beerdata
#set -euo pipefail

sqlite3 beertracker.db ".dump" | grep "INSERT INTO" > beerdata/data.dump

rm -f beertracker.*.bak
for F in beertracker.db*
do
  mv -f $F $F.bak
done


ls -l data.dump ../db.schema

echo `date "+%F %X"` Importing...
if ! sqlite3 beertracker.db < ../db.schema
then
  echo "Errors importing the schema"
  exit 1
fi

sqlite3 beertracker.db << EOF
PRAGMA synchronous = OFF;
PRAGMA journal_mode = MEMORY;
PRAGMA foreign_keys = OFF;
BEGIN TRANSACTION;
.read data.dump
COMMIT;
EOF

chmod g+w beertracker.db
echo `date "+%F %X"` Done!

ls -l beertracker.db*
