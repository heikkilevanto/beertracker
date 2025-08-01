#! /usr/bin/bash

# A script to update the database structure
# Keeping the data

echo "Updating the database structure from db.schema"
cd beerdata || exit 1
#set -euo pipefail

sqlite3 beertracker.db ".dump" | grep "INSERT INTO" > data.dump

rm -f beertracker.*.bak
for F in beertracker.db*
do
  mv -f $F $F.bak
done


ls -l ../db.schema  data.dump

echo `date "+%F %X"` Importing schema
if ! sqlite3 beertracker.db < ../db.schema
then
  echo "Errors importing the schema"
  exit 1
fi

echo `date "+%F %X"` Importing data
sqlite3 beertracker.db << EOF
PRAGMA synchronous = OFF;
PRAGMA journal_mode = MEMORY;
PRAGMA foreign_keys = OFF;
BEGIN TRANSACTION;
.read data.dump
UPDATE COMMENTS SET Rating = NULL where Rating = 0 or Rating = '';
COMMIT;
PRAGMA OPTIMIZE;
EOF

# The rating trick can be removed in near future, when we no longer need it

chmod g+w beertracker.db
echo `date "+%F %X"` Done!

ls -l beertracker.db*
