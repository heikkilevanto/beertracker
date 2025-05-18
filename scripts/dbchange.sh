#! /usr/bin/bash

# A script to update the database structure
# Keeping the data

echo "Updating the database structure from db.schema"
cd beerdata

sqlite3 beertracker.db ".dump" | grep "INSERT INTO" > beerdata/data.dump

rm -f beertracker.*.bak
for F in beertracker.db*
do
  mv -f $F $F.bak
done


ls -l data.dump ../db.schema

echo `date "+%F %X"` Importing...
cat ../db.schema data.dump | sqlite3 beertracker.db
chmod g+w beertracker.db
echo `date "+%F %X"` Done!

ls -l beertracker.db*
