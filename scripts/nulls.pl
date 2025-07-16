#!/usr/bin/perl -w

# A script to go through the database and make all empty fields into NULLs
# So that sum() and avg() will work correctly
# It needs to drop and recreate all views and foreign keys, or sqlite gets
# confused...
# Also drops AUTOINCREMENT from the primary keys, that is not needed

use strict;
use warnings;
use Data::Dumper;
use DBI;


$| =  1; # Force perl to flush STDOUT after every write
# Database setup
my $databasefile = "../beerdata/beertracker.db";
die ("Database '$databasefile' not writable" ) unless ( -w $databasefile );

my $dbh = DBI->connect("dbi:SQLite:dbname=$databasefile", "", "", { RaiseError => 1, AutoCommit => 1 })
    or error($DBI::errstr);
$dbh->{sqlite_unicode} = 1;  # Yes, we use unicode in the database, and want unicode in the results!
$dbh->do('PRAGMA journal_mode = WAL'); # Avoid locking problems with SqLiteBrowser




# Save all views
my $views = $dbh->selectall_arrayref(
    "SELECT name, sql FROM sqlite_master WHERE type='view'",
    { Slice => {} }
);

# Drop all views
for my $view (@$views) {
    print "Dropping view: $view->{name}\n";
    $dbh->do("DROP VIEW IF EXISTS $view->{name}");
}

#  Disable FK checks
$dbh->do("PRAGMA foreign_keys = OFF");

#  Process each table
my $tables = $dbh->selectall_arrayref(
    "SELECT name FROM sqlite_master WHERE type='table' AND name NOT LIKE 'sqlite_%'",
    { Slice => {} }
);

for my $table (@$tables) {
    my $name = $table->{name};
    print "\nProcessing table: $name\n";

    # Get table structure
    my $cols = $dbh->selectall_arrayref("PRAGMA table_info($name)", { Slice => {} });

    my @col_defs;
    my @col_names;
    for my $col (@$cols) {
        push @col_names, $col->{name};

        my $def = $col->{name};
        $def .= " " . $col->{type} if $col->{type};
        $def .= " PRIMARY KEY" if $col->{pk};
        $def .= " NOT NULL" if $col->{notnull} && !$col->{pk};
        # Do not include DEFAULT
        push @col_defs, $def;
    }

    my $new_table = "${name}_new";
    my $create_sql = "CREATE TABLE $new_table (\n    " . join(",\n    ", @col_defs) . "\n)";
    $create_sql =~ s/\bAUTOINCREMENT\b//g;
    print "  Creating new table\n";
    $dbh->do($create_sql);

    # Copy data, converting '' to NULL
    my $col_list = join(", ", @col_names);
    #my $null_exprs = join(", ", map { "NULLIF($_, '')" } @col_names);
    my @null_exprs;
    for my $col (@$cols) {
      if ($col->{notnull} && !$col->{pk}) {
          push @null_exprs, $col->{name};  # Keep value
      } else {
          push @null_exprs, "NULLIF($col->{name}, '')";  # Convert '' to NULL
      }
    }
    my $null_exprs = join(", ", @null_exprs);

    my $copy_sql = "INSERT INTO $new_table ($col_list) SELECT $null_exprs FROM $name";
    $dbh->do($copy_sql);

    # Get indexes
    my $indexes = $dbh->selectall_arrayref(
        "SELECT name, sql FROM sqlite_master WHERE type='index' AND tbl_name = ? AND sql IS NOT NULL",
        { Slice => {} }, $name
    );

    # Drop original table and rename new one
    $dbh->do("DROP TABLE $name");
    $dbh->do("ALTER TABLE $new_table RENAME TO $name");

    # Recreate indexes
    for my $idx (@$indexes) {
        print "  Recreating index: $idx->{name}\n";
        $dbh->do($idx->{sql});
    }
}

#  Re-enable foreign keys
$dbh->do("PRAGMA foreign_keys = ON");

# Remove the sqllite_sequences, as we don't need them any more
$dbh->do("DELETE FROM sqlite_sequence");

#  Recreate views
for my $view (@$views) {
    print "Recreating view: $view->{name}\n";
    $dbh->do($view->{sql});
}

print "\nAll done.\n";
