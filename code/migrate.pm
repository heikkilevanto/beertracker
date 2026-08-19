# DB migration system for beertracker
# Detects when the DB is older than the running code, shows a confirmation form
# (GET, o=migrate), and applies forward-only migrations (POST, o=migrate).

package migrate;
use strict;
use warnings;
use feature 'unicode_strings';
use utf8;
use File::Copy;

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

our $CODE_DB_VERSION = 51;  # Bump this when you add migrations

# Note - the description should always start with the issue number, if known.
# Note - the function names must reflect the DB version number!

our @MIGRATIONS = (
  # Keep this here, it is needed when starting from an empty database
  [1, 'create globals table', \&mig_001_create_globals_table],
  # Add index to speed up the per-user brew list last-seen join
  [49, 'add idx_glasses_brew_user_ts index', \&mig_049_add_glasses_brew_user_ts_index],
  # Issue 744 - barcodes live on the glass; volume/price/alc per (Brew, Barcode)
  [50, 'add glasses.Barcode column and index', \&mig_050_add_glasses_barcode],
  # Issue 745 - lifecycle dates: when places opened/closed, brews released/discontinued,
  # plus an auto-collected FirstSeen date
  [51, 'add lifecycle dates to locations and brews', \&mig_051_add_lifecycle_dates],
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
  if (defined($v)) { return int($v); }
  return 0;
} # _read_db_version

# Back up the database
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


# Composite index to speed up the brew list query's glasses join per user:
#   left join glasses on glasses.Brew = brews.Id and glasses.Username = users.Username
sub mig_049_add_glasses_brew_user_ts_index {
  my $c = shift;
  db::execute($c, "CREATE INDEX IF NOT EXISTS idx_glasses_brew_user_ts ON glasses(Brew, Username, Timestamp)");
} # mig_049_add_glasses_brew_user_ts_index


# Issue 744 - barcode lives on the glass, not just on the brew.
# Each glass records the exact barcode scanned at that drinking event; the
# brew's single Barcode stays as a fallback/seed.
sub mig_050_add_glasses_barcode {
  my $c = shift;
  db::execute($c, "ALTER TABLE glasses ADD COLUMN Barcode text");
  db::execute($c, "CREATE INDEX IF NOT EXISTS idx_glasses_barcode ON glasses (Username, Barcode, Timestamp)");
} # mig_050_add_glasses_barcode


# Issue 745 - lifecycle dates for locations and brews.
# Dates may be partial (just a year, e.g. '2019'); they are stored as entered.
# FirstSeen is full YYYY-MM-DD, backfilled from existing data:
#   - brews: earliest date seen on tap
#   - locations: earliest glass (with the shared -06:00 day offset)
sub mig_051_add_lifecycle_dates {
  my $c = shift;
  db::execute($c, "ALTER TABLE locations ADD COLUMN Opened text");
  db::execute($c, "ALTER TABLE locations ADD COLUMN Closed text");
  db::execute($c, "ALTER TABLE locations ADD COLUMN FirstSeen text");
  db::execute($c, "ALTER TABLE brews ADD COLUMN Released text");
  db::execute($c, "ALTER TABLE brews ADD COLUMN Discontinued text");
  db::execute($c, "ALTER TABLE brews ADD COLUMN FirstSeen text");

  # Backfill FirstSeen for brews: the earliest of the first tap appearance and
  # the first glass, whichever came first (a brew can be drunk long before it
  # ever shows up on a tap)
  db::execute($c, "UPDATE brews SET FirstSeen = (
      SELECT MIN(first_seen) FROM (
        SELECT strftime('%Y-%m-%d', MIN(tap_beers.FirstSeen)) AS first_seen
          FROM tap_beers WHERE tap_beers.Brew = brews.Id
        UNION ALL
        SELECT strftime('%Y-%m-%d', MIN(glasses.Timestamp), '-06:00')
          FROM glasses WHERE glasses.Brew = brews.Id
      ))
    WHERE EXISTS (SELECT 1 FROM tap_beers WHERE tap_beers.Brew = brews.Id)
       OR EXISTS (SELECT 1 FROM glasses WHERE glasses.Brew = brews.Id)");

  # Backfill FirstSeen for locations that have glasses
  db::execute($c, "UPDATE locations SET FirstSeen = (
      SELECT strftime('%Y-%m-%d', MIN(glasses.Timestamp), '-06:00')
      FROM glasses WHERE glasses.Location = locations.Id)
    WHERE EXISTS (SELECT 1 FROM glasses WHERE glasses.Location = locations.Id)");

  # The brew_taps view references FirstSeen and Gone unqualified. Now that
  # locations also has a FirstSeen column (joined against by this view), the
  # unqualified FirstSeen became ambiguous and the view broke. Rebuild it with
  # qualified column references; same columns/order as before.
  db::execute($c, "DROP VIEW IF EXISTS brew_taps");
  db::execute($c, q{
    CREATE VIEW brew_taps AS
    SELECT
      tap_beers.*,
      locations.Name AS LocationName,
      round(julianday(coalesce(tap_beers.Gone, 'now')) - julianday(tap_beers.FirstSeen)) AS Days,
      strftime('%Y-%m-%d', tap_beers.FirstSeen) AS Since,
      strftime('%Y-%m-%d', tap_beers.Gone) AS GoneFormatted
    FROM tap_beers
    JOIN locations ON tap_beers.Location = locations.Id
  });
} # mig_051_add_lifecycle_dates


################################################################################

# Tell the module loaded succesfully
1;
