#! /usr/bin/bash

# A script to dump the beertracler database, and to split it into two
# files:
#  beerdata/db.dump - the full dump
#  beerdata/data.dump - dump of the data only
#  schema.sql - dump of the database schema

# Only the schema.sql should be maintained in git

# When the database changes, run this to get the dumps
# commit the schema in git


cd beerdata
#sqlite3 beertracker.db "PRAGMA wal_checkpoint(FULL);"
# Does not work, permission issues.
# Do a "get production data" via the web interface
sqlite3 beertracker.db ".dump" > db.dump
cat db.dump | grep    "INSERT INTO" > data.dump
cat db.dump | grep -v "INSERT INTO" > ../db.schema

cd ..
ls -l beerdata/*dump beerdata/beertracker.db* db.schema
