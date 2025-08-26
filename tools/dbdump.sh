#! /usr/bin/bash

# A script to dump the beertracler database, and to split it into two
# files:
#  beerdata/db.dump - the full dump
#  beerdata/data.dump - dump of the data only
#  schema.sql - dump of the database schema

# Only the schema.sql should be maintained in git

# When the database changes, run this to get the dumps
# commit the schema in git

DIR=`pwd`
BASE=`basename "$DIR"`

cd beerdata
#sqlite3 beertracker.db "PRAGMA wal_checkpoint(FULL);"
# Does not work, permission issues.
# Do a "get production data" via the web interface
sqlite3 beertracker.db ".dump" > db.dump
cat db.dump | grep -i   "INSERT INTO" > data.dump

# Make the db.schema
# - skip all INSERT statements
# - Convert all UPPERCASE words to lowercase, but keep MixedCase and single 'A'
# - Add drop table statements before create tables and views
# - Add empty lines between statements
echo "# Beertracker database schema" >../db.schema
date "+# Schema dumped at %F %H:%M with $BASE/scripts/dbdump.sh" >> ../db.schema
echo "# Do not edit directly, unless you plan to run scripts/dbchange immediately" >>../db.schema
echo "# The schema lives inside the sqlite database!" >>../db.schema
echo "" >>../db.schema

perl -ne '
    next if /INSERT INTO/i;
    s/\b([A-Z][A-Z_]+)\b/lc($1)/ge;
    if (/^\s*create (table|view) (\S+)/i) {
        print "-- $1 $2\ndrop $1 if exists $2;\n"
    }
    print;
    print "\n" if /;\s*$/;
' db.dump >> ../code/db.schema

cd ..
ls -l beerdata/*dump beerdata/beertracker.db* code/db.schema
