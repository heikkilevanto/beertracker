# DB migration system for beertracker
# Detects when the DB is older than the running code, shows a confirmation form
# (GET, o=migrate), and applies forward-only migrations (POST, o=migrate).

package migrate;
use strict;
use warnings;
use feature 'unicode_strings';
use utf8;
use File::Copy;
use POSIX qw(strftime);

#
# Adding a migration:
#   1. Write a sub mig_NNN_description below.
#   2. Register it in @MIGRATIONS (keep numeric order).
#   3. Bump $CODE_DB_VERSION to the highest migration id.
#
# Remember to add comments in create table/view statements about what is the
# purpose of the table/view, and to each column that is not immediately obvious.


################################################################################
# Migration registry
# Each entry: [ id (integer), description (string), \&sub ]
# The runner executes entries with id > globals.db_version, in list order.
################################################################################

our $CODE_DB_VERSION = 24;  # Bump this when you add migrations

# Note - the description should always start with the issue number, if known.
our @MIGRATIONS = (
  # Keep this here, it is needed when starting from an empty database
  [1, 'create globals table', \&mig_001_create_globals_table],

  # v3.4 released 18-May-2026.  Earlier migrations can be found in git
  [24, '688 brew subtype cleanup', \&mig_002_688_brew_subtype_cleanup],
);

################################################################################
# startup_check($c)
# Called from index.fcgi after db::open_db($c,'ro') and before htmlhead().
# - Missing globals table  → treat db_version as 0.
# - db_version > code      → fatal error.
# - db_version < code      → take backup, set $c->{op}='migrate', return.
# - db_version == code     → no-op.
################################################################################
sub startup_check {
  my $c = shift;

  my $db_version = _read_db_version($c);

  if ( $db_version > $CODE_DB_VERSION ) {
    util::error("DB version ($db_version) is newer than code version ($CODE_DB_VERSION). " .
                "Please update the code.");
  }

  if ( $db_version < $CODE_DB_VERSION ) {
    print { $c->{log} } "migrate: DB version $db_version < code version $CODE_DB_VERSION — migration needed\n";
    _backup_db($c);
    $c->{op} = 'migrate';
  }
  # If equal: no-op.
} # startup_check

################################################################################
# migrate_form($c)
# GET handler: show pending migrations and a POST button.
################################################################################
sub migrate_form {
  my $c = shift;

  my $db_version = _read_db_version($c);
  my @pending = grep { $_->[0] > $db_version } @MIGRATIONS;

  print qq{<div class='content'>
<h2>Database Migration Required</h2>
<p>DB version: <b>$db_version</b> &nbsp; Code version: <b>$CODE_DB_VERSION</b></p>
<p>The following migrations will be applied:</p>
<ul>
};
  foreach my $m (@pending) {
    print qq{<li><b>$m->[0]</b>: $m->[1]</li>\n};
  }
  print qq{</ul>
<form method="POST" action="$c->{url}?o=migrate" accept-charset="UTF-8">
  <input type='hidden' name='o' value='migrate'>
  <button type='submit'>Run migrations</button>
</form>
</div>
};
} # migrate_form

################################################################################
# run_migrations($c)
# POST handler (called inside the shared BEGIN TRANSACTION / COMMIT block).
# That also handles clearing the memory cache.
# Runs each pending migration in order; updates globals.db_version after each.
################################################################################
sub run_migrations {
  my $c = shift;

  $c->{migrating} = 1;

  my $db_version = _read_db_version($c);
  my @pending = grep { $_->[0] > $db_version } @MIGRATIONS;

  if ( !@pending ) {
    print { $c->{log} } "migrate: nothing to do (db_version=$db_version)\n";
  }

  foreach my $m (@pending) {
    my ($id, $desc, $sub) = @$m;
    print { $c->{log} } "migrate: running migration $id: $desc\n";
    $sub->($c);
    # Update db_version immediately after each migration so a partial run
    # can be resumed and we don't re-apply earlier migrations.
    db::execute($c,
      "INSERT OR REPLACE INTO globals(k,v) VALUES('db_version',?)", $id);
    print { $c->{log} } "migrate: migration $id done, db_version=$id\n";
  }
  # Make sure we have the current db_version
  # Needed when starting with an empty database, and no real migrations done.
  db::execute($c, "INSERT OR REPLACE INTO globals(k,v) VALUES('db_version', '$CODE_DB_VERSION')");

  $c->{migrating} = 0;
  # Success — the caller (index.fcgi) will COMMIT.
  # On any error DBI throws, the caller rolls back and db_version stays unchanged.
  $c->{redirect_url} = $c->{url};  # After migration, go to the default page.
} # run_migrations

################################################################################
# Private helpers
################################################################################

# Read globals.db_version; return 0 if the table does not exist yet.
sub _read_db_version {
  my $c = shift;
  # Check whether the globals table exists at all
  my ($exists) = $c->{dbh}->selectrow_array(
    "SELECT count(*) FROM sqlite_master WHERE type='table' AND name='globals'");
  return 0 unless $exists;
  my ($v) = $c->{dbh}->selectrow_array(
    "SELECT v FROM globals WHERE k='db_version'");
  return defined($v) ? int($v) : 0;
} # _read_db_version

# Take a timestamped file-copy backup; keep the last 3.
sub _backup_db {
  my $c = shift;
  my $dbfile = db::dbfile();
  my $backup = "$dbfile.bak";
  File::Copy::copy($dbfile, $backup)
    or print { $c->{log} } "migrate: WARNING: could not back up $dbfile to $backup: $!\n";
  print { $c->{log} } "migrate: backup created: $backup\n";
} # _backup_db

################################################################################
# Migration subs
################################################################################

sub mig_001_create_globals_table {
  my $c = shift;
  db::execute($c, "CREATE TABLE IF NOT EXISTS globals (k TEXT PRIMARY KEY, v TEXT)");
  db::execute($c, "INSERT OR REPLACE INTO globals(k,v) VALUES('db_version','0')");
} # mig_001_create_globals_table

################################################################################
# Migration 24: Brew subtype cleanup (issue #688)
# Normalize case, merge variant names into canonical subtypes
################################################################################
sub mig_002_688_brew_subtype_cleanup {
  my $c = shift;

  # Case normalization
  db::execute($c, "UPDATE brews SET SubType='IPA'     WHERE SubType IN ('ipa','Ipa')");
  db::execute($c, "UPDATE brews SET SubType='AIPA'    WHERE SubType='aipa'");
  db::execute($c, "UPDATE brews SET SubType='DIPA'    WHERE SubType='dipa'");
  db::execute($c, "UPDATE brews SET SubType='NEIPA'   WHERE SubType IN ('neipa','ne','Ne')");
  db::execute($c, "UPDATE brews SET SubType='NEPA'    WHERE SubType='nepa'");
  db::execute($c, "UPDATE brews SET SubType='SIPA'    WHERE SubType='sipa'");
  db::execute($c, "UPDATE brews SET SubType='APA'     WHERE SubType='apa'");
  db::execute($c, "UPDATE brews SET SubType='PA'      WHERE SubType='pa'");
  db::execute($c, "UPDATE brews SET SubType='Misc'    WHERE SubType='misc'");
  db::execute($c, "UPDATE brews SET SubType='Whisky'  WHERE SubType='whisky'");
  db::execute($c, "UPDATE brews SET SubType='Rum'     WHERE SubType='rom'");
  db::execute($c, "UPDATE brews SET SubType='Gin'     WHERE SubType='gin'");
  db::execute($c, "UPDATE brews SET SubType='Cocktail' WHERE SubType IN ('coctail','Coctail')");
  db::execute($c, "UPDATE brews SET SubType='Geuze'   WHERE SubType IN ('geuez','gueuze')");

  # Style merges
  db::execute($c, "UPDATE brews SET SubType='DIPA'    WHERE SubType IN ('DNE','Triple Neipa')");
  db::execute($c, "UPDATE brews SET SubType='Saison'  WHERE SubType='Sais'");
  db::execute($c, "UPDATE brews SET SubType='Sour'    WHERE SubType IN ('Geuze','Geuez','Gueuze','Oude','Sour - Fruited','Lambic Style - Fruit','Lambic Style - Unblended','Lambi')");
  db::execute($c, "UPDATE brews SET SubType='Stout'   WHERE SubType IN ('Imp Stout','Imperial Stout','Baltic Porter','Porter - Imperial / Double Baltic','Imp')");
  db::execute($c, "UPDATE brews SET SubType='Lager'   WHERE SubType IN ('Pils','Pilsener','Pilsner','Pilsner - Czech / Bohemian','Kellerbier / Zwickelbier','Kölsch','Lager - Mexican','Light')");
  db::execute($c, "UPDATE brews SET SubType='IPA'     WHERE SubType='IPA - International'");
  db::execute($c, "UPDATE brews SET SubType='AIPA'    WHERE SubType='American IPA'");
  db::execute($c, "UPDATE brews SET SubType='Brown'   WHERE SubType IN ('Brown Ale','Dark Ale')");
  db::execute($c, "UPDATE brews SET SubType='Belgian' WHERE SubType IN ('Belg','Bruin','Dubbel','Dubl','Tripel','Triple','Tripple','Quadrupel','Trappist','Blond')");
  db::execute($c, "UPDATE brews SET SubType='Vienna'  WHERE SubType='Vienn'");
  db::execute($c, "UPDATE brews SET SubType='Wheat'   WHERE SubType IN ('German Hefeweizen','Wheat Beer - Witbier')");
  db::execute($c, "UPDATE brews SET SubType='Cider'   WHERE SubType IN ('Cider - Other Fruit','Apple Natural','FR','GB')");
  db::execute($c, "UPDATE brews SET SubType='Ale'     WHERE SubType='Scotch ale'");
  db::execute($c, "UPDATE brews SET SubType='Ale'     WHERE SubType IN ('ESB','Cream','English','Irish')");
  db::execute($c, "UPDATE brews SET SubType='Dunkel'  WHERE SubType IN ('Dark','Juleb','Classic','Dunk')");
} # mig_002_688_brew_subtype_cleanup

################################################################################

# Tell the module loaded succesfully
1;
