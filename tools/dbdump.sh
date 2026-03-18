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
DATESTAMP=$(date "+# Schema dumped at %F %H:%M with $BASE/scripts/dbdump.sh")

cat >../doc/db.schema <<EOF
# Beertracker database schema
$DATESTAMP
# Do not edit directly, unless you plan to run scripts/dbchange immediately
# The schema lives inside the sqlite database!
# Most changes must be done by adding a migration to migrate.pm, then they will be applied 
# automatically to both dev and production systems.
# A few difficult changes can be done manually here, but that requires running tools/dbchange
# in both dev and production, and needs to be coordinated with related code releases.

EOF

# Loop through the database dump and
# - skip all INSERT statements
# - Convert all UPPERCASE words to lowercase, but keep MixedCase and single 'A'
# - Add drop table statements before create tables and views
# - Add empty lines between statements

perl -ne '
    next if /INSERT INTO/i;
    s/\b([A-Z][A-Z_]+)\b/lc($1)/ge;
    if (/^\s*create\s+(table|view)\s+(?:if\s+not\s+exists\s+)?(\S+)/i) {
        my $kind = lc($1);
        my $name = $2;
        print "-- $kind $name\ndrop $kind if exists $name;\n"
    }
    print;
    print "\n" if /;\s*$/;
' db.dump >> ../doc/db.schema

cd ..
ls -l beerdata/*dump beerdata/beertracker.db* doc/db.schema
