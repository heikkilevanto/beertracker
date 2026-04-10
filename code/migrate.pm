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

our $CODE_DB_VERSION = 17;  # Bump this when you add migrations

our @MIGRATIONS = (
  # v3.3 released here 21-Mar-2026.  Earlier migrations should be deleted soon
  [16, 'add Tags to persons and locations', \&mig_016_add_tags_to_persons_and_locations],
  [17, 'add ShortName to brews and locations', \&mig_017_add_shortname_to_brews_and_locations],
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
    return;
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
  my $ts = strftime("%Y%m%dT%H%M%S", localtime);
  my $backup = "$dbfile.bak.$ts";
  File::Copy::copy($dbfile, $backup)
    or print { $c->{log} } "migrate: WARNING: could not back up $dbfile to $backup: $!\n";
  print { $c->{log} } "migrate: backup created: $backup\n";
  _prune_backups($c, $dbfile);
} # _backup_db

# Keep at most 3 backups; delete the oldest ones.
sub _prune_backups {
  my $c = shift;
  my $dbfile = shift;
  my $pattern = "$dbfile.bak.";
  my @backups = sort glob("${pattern}*");
  while ( scalar(@backups) > 3 ) {
    my $old = shift @backups;
    unlink $old
      and print { $c->{log} } "migrate: removed old backup: $old\n";
  }
} # _prune_backups

################################################################################
# Migration subs
################################################################################

################################################################################
sub mig_016_add_tags_to_persons_and_locations {
  my $c = shift;

  db::execute($c, "ALTER TABLE persons ADD COLUMN Tags TEXT");
  db::execute($c, "ALTER TABLE locations ADD COLUMN Tags TEXT");

  db::execute($c, "DROP VIEW IF EXISTS persons_list");
  db::execute($c, q{
    CREATE VIEW persons_list AS
    SELECT
      persons.Id,
      persons.Name,
      'trmob' AS trmob,
      count(DISTINCT comments.Id) - 1 AS Com,
      strftime('%Y-%m-%d %w ', max(glasses.Timestamp), '-06:00') ||
        strftime('%H:%M', max(glasses.Timestamp)) AS Last,
      locations.Name AS Location,
      'tr' AS tr,
      'Clr' AS Clr,
      persons.description,
      (SELECT Filename FROM photos WHERE Person = persons.Id ORDER BY Ts DESC LIMIT 1) AS Photo,
      persons.Tags
    FROM persons
    LEFT JOIN comment_persons cp ON cp.Person = persons.Id
    LEFT JOIN comments ON comments.Id = cp.Comment
    LEFT JOIN glasses ON glasses.Id = comments.Glass
    LEFT JOIN locations ON locations.Id = glasses.Location
    GROUP BY persons.Id
  });

  db::execute($c, "DROP VIEW IF EXISTS locations_list");
  db::execute($c, q{
    CREATE VIEW locations_list AS
    SELECT
      locations.Id,
      locations.Name,
      locations.LocType || ', ' || locations.LocSubType AS Type,
      '' AS trmob,
      locations.lat || ' ' || locations.lon AS Geo,
      strftime('%Y-%m-%d %w ', max(glasses.Timestamp), '-06:00') ||
        strftime('%H:%M', max(glasses.Timestamp)) AS Last,
      r.rating_count || ';' || r.rating_average || ';' || r.comment_count AS Stats,
      (SELECT Filename FROM photos WHERE Location = locations.Id ORDER BY Ts DESC LIMIT 1) AS Photo,
      locations.Tags
    FROM locations
    LEFT JOIN glasses ON glasses.Location = locations.Id
    LEFT JOIN location_ratings r ON r.id = glasses.Id
    GROUP BY locations.Id
  });

} # mig_016_add_tags_to_persons_and_locations

################################################################################
sub mig_017_add_shortname_to_brews_and_locations {
  my $c = shift;

  db::execute($c, "ALTER TABLE brews ADD COLUMN ShortName TEXT");
  db::execute($c, "ALTER TABLE locations ADD COLUMN ShortName TEXT");

} # mig_017_add_shortname_to_brews_and_locations

1;
