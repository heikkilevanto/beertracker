#! /usr/bin/bash

# A script to update the database structure
# Keeping the data

echo "Updating the database structure from db.schema"
cd beerdata || exit 1
#set -euo pipefail

sqlite3 beertracker.db ".dump" | grep "INSERT INTO" | grep -v "INSERT INTO sqlite_stat1" > data.dump

rm -f beertracker.*.bak
for F in beertracker.db*
do
  mv -f $F $F.bak
done


ls -l ../code/db.schema  data.dump

echo `date "+%F %X"` Importing schema
if ! sqlite3 beertracker.db < ../code/db.schema
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
UPDATE Glasses SET Brew = NULL WHERE Brew = '' or Brew = '0';
UPDATE Brews SET ProducerLocation = NULL WHERE ProducerLocation= '' or ProducerLocation = '0';

PRAGMA foreign_keys = ON;
PRAGMA foreign_key_check;
COMMIT;
PRAGMA OPTIMIZE;
EOF


# If the foreign_key_check outputs anything, we have a problem.
# That's why I add the UPDATEs above

chmod g+w beertracker.db
echo `date "+%F %X"` Done!

ls -l beertracker.db*
