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

our $CODE_DB_VERSION = 35;  # Bump this when you add migrations

# Note - the description should always start with the issue number, if known.
# Note - the function names must reflect the DB version number!

our @MIGRATIONS = (
  # Keep this here, it is needed when starting from an empty database
  [1, 'create globals table', \&mig_001_create_globals_table],

  # v3.4 released 18-May-2026.  Earlier migrations can be found in git
  [24, '688 brew subtype cleanup', \&mig_024_688_brew_subtype_cleanup],

  # Unreleased (dev only)
  [25, '714 fix locations_list view join', \&mig_025_714_fix_locations_list],
  [26, '715 locations_list null-safe Type column', \&mig_026_715_locations_list_null_safe],
  [27, '695 create photos_list view', \&mig_027_photos_list_view],
  [28, '699 photos_list use _cont for Person fields', \&mig_028_photos_list_cont],
  [29, '700 simplify photos_list view', \&mig_029_photos_list_simplify],

  # Unreleased (dev only)
  [30, '703 locations_list use suffixes', \&mig_030_locations_list_suffixes],

  # Unreleased (dev only)
  [31, 'persons_list use suffixes', \&mig_031_persons_list_suffixes],
  [32, 'brews_list use suffixes', \&mig_032_brews_list_suffixes],
  [33, 'comments_list use suffixes', \&mig_033_comments_list_suffixes],
  [34, 'brews_list Id links to Brew', \&mig_034_brews_list_id_link],
  [35, '705 locations_list use IdClr and auto-width', \&mig_035_locations_list_idclr],
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
sub mig_024_688_brew_subtype_cleanup {
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
} # mig_024_688_brew_subtype_cleanup

################################################################################
# Migration 25: Fix locations_list view join (issue #714)
# The old view had  "left join location_ratings r on r.id = glasses.Id"
# which compared a location id to a glass id, so ratings never matched.
################################################################################
sub mig_025_714_fix_locations_list {
  my $c = shift;

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
      locations.Tags,
      locations.Country,
      locations.Region
    FROM locations
    LEFT JOIN glasses ON glasses.Location = locations.Id
    LEFT JOIN location_ratings r ON r.id = locations.Id
    GROUP BY locations.Id
  });
} # mig_025_714_fix_locations_list

################################################################################
# Migration 26: Make locations_list Type column NULL-safe (issue #715)
# SQLite || returns NULL if any operand is NULL, so a location with LocType='Bar'
# and NULL LocSubType showed as NULL instead of "Bar, NULL".
################################################################################
sub mig_026_715_locations_list_null_safe {
  my $c = shift;

  db::execute($c, "DROP VIEW IF EXISTS locations_list");
  db::execute($c, q{
    CREATE VIEW locations_list AS
    SELECT
      locations.Id,
      locations.Name,
      COALESCE(locations.LocType, 'NULL') || ', ' || COALESCE(locations.LocSubType, 'NULL') AS Type,
      '' AS trmob,
      locations.lat || ' ' || locations.lon AS Geo,
      strftime('%Y-%m-%d %w ', max(glasses.Timestamp), '-06:00') ||
        strftime('%H:%M', max(glasses.Timestamp)) AS Last,
      r.rating_count || ';' || r.rating_average || ';' || r.comment_count AS Stats,
      (SELECT Filename FROM photos WHERE Location = locations.Id ORDER BY Ts DESC LIMIT 1) AS Photo,
      locations.Tags,
      locations.Country,
      locations.Region
    FROM locations
    LEFT JOIN glasses ON glasses.Location = locations.Id
    LEFT JOIN location_ratings r ON r.id = locations.Id
    GROUP BY locations.Id
  });
} # mig_026_715_locations_list_null_safe

################################################################################
# Migration 27: Create photos_list view (issue #695)
# 2-column layout: Photo on left, text fields stacked on right.
# Id + Clr pseudo-field on the first line. _R8 suffix for rowspan=8.
# x-prefixed columns are hidden fields used for WHERE filtering.
################################################################################
sub mig_027_photos_list_view {
  my $c = shift;

  db::execute($c, "DROP VIEW IF EXISTS photos_list");
  db::execute($c, q{
    CREATE VIEW photos_list AS
    SELECT
      p.Filename AS Photo_R8,
      p.Id AS IdClr,
      '' AS TR1,
      p.Caption AS Caption_A,
      '' AS TR2,
      CASE WHEN p.Person IS NOT NULL THEN 'P[' || p.Person || ']: ' || char(0xAB) || p2.Name || char(0xBB) END AS Person_A,
      '' AS TR3,
      CASE WHEN p.Brew IS NOT NULL THEN
        'B[' || p.Brew || ']: ' ||
        CASE WHEN pl_b.Name IS NOT NULL THEN char(0xAB) || pl_b.Name || char(0xBB) || ': ' ELSE '' END ||
        char(0xAB) || b.Name || char(0xBB) ||
        CASE WHEN b.Details IS NOT NULL THEN ' - ' || char(0xAB) || b.Details || char(0xBB) ELSE '' END
      END AS Brew_A,
      '' AS TR4,
      CASE WHEN p.Location IS NOT NULL THEN 'L[' || p.Location || ']: ' || char(0xAB) || l.Name || char(0xBB) END AS Location_A,
      '' AS TR5,
      CASE WHEN p.Glass IS NOT NULL THEN
        'G[' || p.Glass || ']: ' || TRIM(
          CASE WHEN pl_g.Name IS NOT NULL THEN char(0xAB) || pl_g.Name || char(0xBB) || ':' ELSE '' END ||
          CASE WHEN b_g.Name IS NOT NULL THEN ' ' || char(0xAB) || b_g.Name || char(0xBB) ELSE '' END ||
          CASE WHEN b_g.Details IS NOT NULL THEN ' (' || char(0xAB) || b_g.Details || char(0xBB) || ')' ELSE '' END ||
          CASE WHEN b_g.Name IS NULL AND g_g.BrewType IS NOT NULL
               THEN ' [' || char(0xAB) || g_g.BrewType || char(0xBB) || ']' ELSE '' END ||
          CASE WHEN l_g.Name IS NOT NULL THEN ' @ ' || char(0xAB) || l_g.Name || char(0xBB) ELSE '' END
        )
      END AS Glass_A,
      '' AS TR6,
      CASE WHEN p.Comment IS NOT NULL THEN
        'C[' || p.Comment || ']: ' || TRIM(
          CASE WHEN c.Rating IS NOT NULL THEN '(' || char(0xAB) || c.Rating || char(0xBB) || ') ' ELSE '' END ||
          COALESCE(c.Comment, '') ||
          (SELECT ' — ' || group_concat(char(0xAB) || p3.Name || char(0xBB), ', ')
           FROM comment_persons cp2
           JOIN persons p3 ON p3.Id = cp2.Person
           WHERE cp2.Comment = c.Id)
        )
      END AS Comment_A,
      '' AS TR7,
      SUBSTR(p.Ts, 1, 16) AS Ts_A,
      p.Glass AS xGlass,
      p.Comment AS xComment,
      p.Location AS xLocation,
      p.Person AS xPerson,
      p.Brew AS xBrew,
      p.Uploader AS xUploader,
      p.Public AS xPublic
    FROM photos p
    LEFT JOIN persons p2     ON p2.Id = p.Person
    LEFT JOIN brews b        ON b.Id = p.Brew
    LEFT JOIN locations pl_b ON pl_b.Id = b.ProducerLocation
    LEFT JOIN locations l    ON l.Id = p.Location
    LEFT JOIN glasses g_g    ON g_g.Id = p.Glass
    LEFT JOIN brews b_g      ON b_g.Id = g_g.Brew
    LEFT JOIN locations l_g  ON l_g.Id = g_g.Location
    LEFT JOIN locations pl_g ON pl_g.Id = b_g.ProducerLocation
    LEFT JOIN comments c     ON c.Id = p.Comment
  });
} # mig_027_photos_list_view

################################################################################
# Migration 28: photos_list uses _cont for Person fields (issue #699)
# Split Person_A into PersonPref + PersonName with _cont so the two
# columns render as one cell (same visual layout) but can have separate
# suffixes applied (e.g. _id:person on the ID column later).
################################################################################
sub mig_028_photos_list_cont {
  my $c = shift;

  db::execute($c, "DROP VIEW IF EXISTS photos_list");
  db::execute($c, q{
    CREATE VIEW photos_list AS
    SELECT
      p.Filename AS Photo_R8,
      p.Id AS IdClr,
      '' AS TR1,
      p.Caption AS Caption_A,
      '' AS TR2,
      p.Person AS "PersonId_A_cont_link:Person",
      p2.Name AS "PersonName_A_filter",
      '' AS TR3,
      p.Brew AS "BrewId_A_cont_link:Brew",
      CASE WHEN pl_b.Name IS NOT NULL THEN pl_b.Name || ': ' ELSE '' END ||
        b.Name ||
        CASE WHEN b.Details IS NOT NULL THEN ' - ' || b.Details ELSE '' END
      AS "BrewText_A_filter",
      '' AS TR4,
      p.Location AS "LocationId_A_cont_link:Location",
      l.Name AS "LocationName_A_filter",
      '' AS TR5,
      p.Glass AS "GlassId_A_cont_link:Glass",
      NULLIF(TRIM(
        CASE WHEN pl_g.Name IS NOT NULL THEN pl_g.Name || ':' ELSE '' END ||
        CASE WHEN b_g.Name IS NOT NULL THEN ' ' || b_g.Name ELSE '' END ||
        CASE WHEN b_g.Details IS NOT NULL THEN ' (' || b_g.Details || ')' ELSE '' END ||
        CASE WHEN b_g.Name IS NULL AND g_g.BrewType IS NOT NULL
             THEN ' [' || g_g.BrewType || ']' ELSE '' END ||
        CASE WHEN l_g.Name IS NOT NULL THEN ' @ ' || l_g.Name ELSE '' END
      ), '') AS "GlassText_A_filter",
      '' AS TR6,
      p.Comment AS "CommentId_A_cont_link:Comment",
      NULLIF(TRIM(
        CASE WHEN c.Rating IS NOT NULL THEN '(' || char(0xAB) || c.Rating || char(0xBB) || ') ' ELSE '' END ||
        COALESCE(c.Comment, '') ||
        (SELECT ' — ' || group_concat(char(0xAB) || p3.Name || char(0xBB), ', ')
         FROM comment_persons cp2
         JOIN persons p3 ON p3.Id = cp2.Person
         WHERE cp2.Comment = c.Id)
      ), '') AS "CommentText_A",
      '' AS TR7,
      SUBSTR(p.Ts, 1, 16) AS Ts_A,
      p.Glass AS xGlass,
      p.Comment AS xComment,
      p.Location AS xLocation,
      p.Person AS xPerson,
      p.Brew AS xBrew,
      p.Uploader AS xUploader,
      p.Public AS xPublic
    FROM photos p
    LEFT JOIN persons p2     ON p2.Id = p.Person
    LEFT JOIN brews b        ON b.Id = p.Brew
    LEFT JOIN locations pl_b ON pl_b.Id = b.ProducerLocation
    LEFT JOIN locations l    ON l.Id = p.Location
    LEFT JOIN glasses g_g    ON g_g.Id = p.Glass
    LEFT JOIN brews b_g      ON b_g.Id = g_g.Brew
    LEFT JOIN locations l_g  ON l_g.Id = g_g.Location
    LEFT JOIN locations pl_g ON pl_g.Id = b_g.ProducerLocation
    LEFT JOIN comments c     ON c.Id = p.Comment
  });
} # mig_028_photos_list_cont

################################################################################
# Migration 29: Simplify photos_list view (issue #700)
# - Move Ts to row 1 after IdClr
# - Use _contline on first data field of each row (instead of separate _cont/empty columns)
# - Split combined columns (BrewText, GlassText, CommentText) into atomic fields
# - Remove SQL string concatenation — use _link:Entity suffix for links
# - Use _as:LocName for location names (-> @Name)
# - Keep comment persons as separate column
# - Rely on word-click from listrecords for plain-text fields
################################################################################
sub mig_029_photos_list_simplify {
  my $c = shift;

  db::execute($c, "DROP VIEW IF EXISTS photos_list");
  db::execute($c, q{
    CREATE VIEW photos_list AS
    SELECT
      p.Filename AS Photo_R8,
      p.Id AS "IdClr_A_contline",
      SUBSTR(p.Ts, 1, 16) AS Ts_A,

      '' AS TR1,
      p.Caption AS Caption_A,

      '' AS TR2,
      p.Person AS "PersonId_A_contline_link:Person",
      p2.Name AS "PersonName_A_filter",

      '' AS TR3,
      p.Brew AS "BrewId_A_contline_link:Brew",
      pl_b.Name AS "BrewProducer_A_filter",
      b.Name AS "BrewName_A_filter",
      b.Details AS "BrewDetails_A_filter",

      '' AS TR4,
      p.Location AS "LocationId_A_contline_link:Location",
      l.Name AS "LocationName_A_filter_as:LocName",

      '' AS TR5,
      p.Glass AS "GlassId_A_contline_link:Glass",
      pl_g.Name AS "GlassProducer_A_filter",
      b_g.Name AS "GlassBrewName_A_filter",
      b_g.Details AS "GlassDetails_A_filter",
      g_g.BrewType AS "GlassBrewType_A_filter",
      l_g.Name AS "GlassLocName_A_filter_as:LocName",

      '' AS TR6,
      p.Comment AS "CommentId_A_contline_link:Comment",
      c.Rating AS "CommentRating_A_filter",
      c.Comment AS "CommentText_A",
      (SELECT group_concat(p3.Name, ', ')
       FROM comment_persons cp2
       JOIN persons p3 ON p3.Id = cp2.Person
       WHERE cp2.Comment = c.Id) AS "CommentPersons_A_filter",

      '' AS TR7,
      p.Glass AS xGlass,
      p.Comment AS xComment,
      p.Location AS xLocation,
      p.Person AS xPerson,
      p.Brew AS xBrew,
      p.Uploader AS xUploader,
      p.Public AS xPublic

    FROM photos p
    LEFT JOIN persons p2     ON p2.Id = p.Person
    LEFT JOIN brews b        ON b.Id = p.Brew
    LEFT JOIN locations pl_b ON pl_b.Id = b.ProducerLocation
    LEFT JOIN locations l    ON l.Id = p.Location
    LEFT JOIN glasses g_g    ON g_g.Id = p.Glass
    LEFT JOIN brews b_g      ON b_g.Id = g_g.Brew
    LEFT JOIN locations l_g  ON l_g.Id = g_g.Location
    LEFT JOIN locations pl_g ON pl_g.Id = b_g.ProducerLocation
    LEFT JOIN comments c     ON c.Id = p.Comment
  });
} # mig_029_photos_list_simplify

################################################################################
# Migration 30: locations_list uses suffixes (issue #703)
# Two-line layout with photo spanning both rows, combined LocType+LocSubType,
# country/region helper via CountryRegion field.
################################################################################
sub mig_030_locations_list_suffixes {
  my $c = shift;

  db::execute($c, "DROP VIEW IF EXISTS locations_list");
  db::execute($c, q{
    CREATE VIEW locations_list AS
    SELECT
      locations.Id AS "Id_link:Location",
      '' AS "Clr_cont",
      locations.Name AS "Name_A_as:LocName_cont",
      CASE
        WHEN locations.LocType IS NOT NULL AND locations.LocType != '' AND
             locations.LocSubType IS NOT NULL AND locations.LocSubType != ''
        THEN '[' || locations.LocType || ', ' || locations.LocSubType || ']'
        WHEN locations.LocType IS NOT NULL AND locations.LocType != ''
        THEN '[' || locations.LocType || ']'
        WHEN locations.LocSubType IS NOT NULL AND locations.LocSubType != ''
        THEN '[' || locations.LocSubType || ']'
        ELSE ''
      END AS "LocType_A_cont",
      r.rating_count || ';' || r.rating_average || ';' || r.comment_count AS "Ratings_as:Stats",
      (SELECT Filename FROM photos WHERE Location = locations.Id ORDER BY Ts DESC LIMIT 1) AS "Photo_R2_noheader_nofilter",
      '' AS TR1,
      locations.lat || ' ' || locations.lon AS "Geo",
      COALESCE(locations.Country,'') || ';' || COALESCE(locations.Region,'') AS "CountryRegion_A_contline",
      strftime('%Y-%m-%d %w ', max(glasses.Timestamp), '-06:00') ||
        strftime('%H:%M', max(glasses.Timestamp)) AS "Last_cont",
      locations.Tags AS xTags
    FROM locations
    LEFT JOIN glasses ON glasses.Location = locations.Id
    LEFT JOIN location_ratings r ON r.id = locations.Id
    GROUP BY locations.Id
  });
} # mig_030_locations_list_suffixes

################################################################################
# Migration 31: persons_list 3-line layout with suffixes
# 3-line format: Id + Name_C2 + Photo_R3 | Com + Description + Last | Clr + Tags + Location
################################################################################
sub mig_031_persons_list_suffixes {
  my $c = shift;

  db::execute($c, "DROP VIEW IF EXISTS persons_list");
  db::execute($c, q{
    CREATE VIEW persons_list AS
    SELECT
      persons.Id AS "Id_link:Person",
      persons.Name AS "Name_A_as:Person_C2",
      (SELECT Filename FROM photos WHERE Person = persons.Id ORDER BY Ts DESC LIMIT 1) AS "Photo_R3_noheader_nofilter",
      '' AS TR1,
      count(distinct comments.Id) - 1 AS Com,
      persons.description AS "Description_A",
      strftime('%Y-%m-%d %w ', max(coalesce(glasses.Timestamp, comments.Ts)), '-06:00') ||
        strftime('%H:%M', max(coalesce(glasses.Timestamp, comments.Ts))) AS "Last_A",
      '' AS TR2,
      'Clr' AS Clr,
      persons.Tags AS "Tags_A",
      locations.Name AS "Location_A"
    FROM persons
    LEFT JOIN comment_persons cp ON cp.Person = persons.Id
    LEFT JOIN comments ON comments.Id = cp.Comment
    LEFT JOIN glasses ON glasses.Id = comments.Glass
    LEFT JOIN locations ON locations.Id = glasses.Location
    GROUP BY persons.Id
  });
} # mig_031_persons_list_suffixes

################################################################################
# Migration 32: brews_list use suffixes
# 4-column table with IdClr, Name, Type, Photo on row 1;
# Alc, Producer, Stats(colspan 2) on row 2;
# Count, Last, Location, xUsername on row 3.
################################################################################
sub mig_032_brews_list_suffixes {
  my $c = shift;

  db::execute($c, "DROP VIEW IF EXISTS brews_list");
  db::execute($c, q{
    CREATE VIEW brews_list AS
    with users as (
      select distinct Username from glasses
    )
    select
      brews.Id AS "Id_A",
      brews.Name AS "Name_A_cont",
      brews.BrewType || ', ' || brews.SubType AS "Type_A",
      (SELECT Filename FROM photos WHERE Brew = brews.Id ORDER BY Ts DESC LIMIT 1)
        AS "Photo_R3_noheader_nofilter",
      '' AS TR1,
      brews.Alc AS "Alc",
      ploc.Name AS "Producer_A_cont",
      r.rating_count || ';' || r.average_rating || ';' || r.comment_count AS "Stats_as:Stats",
      '' AS TR2,
      count(glasses.Id) AS "Count",
      strftime('%Y-%m-%d %w ', max(glasses.Timestamp), '-06:00') ||
        strftime('%H:%M', max(glasses.Timestamp)) AS "Last_cont",
      locations.Name AS "Location_A_as:LocName",
      users.Username AS xUsername
    from brews
    cross join users
    left join locations ploc on ploc.Id = brews.ProducerLocation
    left join glasses on glasses.Brew = brews.Id and glasses.Username = users.Username
    left join locations on locations.Id = glasses.Location
    left join brew_ratings r on r.Brew = brews.Id and r.Username = users.Username
    group by brews.Id, users.Username
  });
} # mig_032_brews_list_suffixes

################################################################################
# Migration 33: comments_list use suffixes (issue #???)
# 4-row, 3-column + photo layout:
#   Row1 = [Id_link:Comment + CommentType] [Last     ] [Photo_R4]
#   Row2 = [BrewId_link:Brew + Prod + BrewName] [LocName] |
#   Row3 = [Rate] [Comment                               ] |
#   Row4 = [Clr ] [PersonName                            ] |
# Photo on far right, rowspan 4. Prod rendered in italic, BrewName in bold
# (handled by listrecords.pm). Uses _link, _A, _cont, _noheader.
################################################################################
sub mig_033_comments_list_suffixes {
  my $c = shift;

  db::execute($c, "DROP VIEW IF EXISTS comments_list");
  db::execute($c, q{
    CREATE VIEW comments_list AS
    SELECT
      comments.Id AS "Id_A_link:Comment",
      comments.CommentType AS "CommentType_A_cont",
      strftime('%Y-%m-%d %w ', COALESCE(glasses.Timestamp, comments.Ts), '-06:00') ||
        strftime('%H:%M', COALESCE(glasses.Timestamp, comments.Ts)) AS "Last_A",
      (SELECT Filename FROM photos WHERE Comment = comments.Id ORDER BY Ts DESC LIMIT 1)
        AS "Photo_R4_noheader_nofilter",

      '' AS TR1,
      comments.Brew AS "BrewId_A_link:Brew",
      COALESCE(ploc_comment.Name, ploc_glass.Name) AS "Prod_A_cont",
      COALESCE(brew_comment.Name, brew_glass.Name) AS "BrewName_A_cont",
      COALESCE(loc_comment.Name, loc_glass.Name) AS "LocName_A",

      '' AS TR2,
      comments.Rating AS "Rate_A",
      comments.Comment AS "Comment_A",

      '' AS TR3,
      'Clr' AS Clr,
      group_concat(persons.Name, ', ') AS "PersonName_A",

      COALESCE(glasses.Username, comments.Username) AS xUsername

    FROM comments
    LEFT JOIN glasses       ON glasses.Id       = comments.Glass
    LEFT JOIN brews brew_glass   ON brew_glass.Id   = glasses.Brew
    LEFT JOIN brews brew_comment ON brew_comment.Id = comments.Brew
    LEFT JOIN comment_persons cp ON cp.Comment = comments.Id
    LEFT JOIN persons            ON persons.Id  = cp.Person
    LEFT JOIN locations loc_glass   ON loc_glass.Id   = glasses.Location
    LEFT JOIN locations loc_comment ON loc_comment.Id = comments.Location
    LEFT JOIN locations ploc_glass   ON ploc_glass.Id   = brew_glass.ProducerLocation
    LEFT JOIN locations ploc_comment ON ploc_comment.Id = brew_comment.ProducerLocation
    GROUP BY comments.Id
  });
} # mig_033_comments_list_suffixes

################################################################################
# Migration 34: brews_list Id links to Brew
# Change Id_A to Id_A_link:Brew so the Id cell is a clickable link
# to the Brew edit page.
################################################################################
sub mig_034_brews_list_id_link {
  my $c = shift;

  db::execute($c, "DROP VIEW IF EXISTS brews_list");
  db::execute($c, q{
    CREATE VIEW brews_list AS
    with users as (
      select distinct Username from glasses
    )
    select
      brews.Id AS "IdClr_A",
      brews.Name AS "Name_A_cont",
      brews.BrewType || ', ' || brews.SubType AS "Type_A",
      (SELECT Filename FROM photos WHERE Brew = brews.Id ORDER BY Ts DESC LIMIT 1)
        AS "Photo_R3_noheader_nofilter",
      '' AS TR1,
      brews.Alc AS "Alc",
      ploc.Name AS "Producer_A_cont",
      r.rating_count || ';' || r.average_rating || ';' || r.comment_count AS "Stats_as:Stats",
      '' AS TR2,
      count(glasses.Id) AS "Count",
      strftime('%Y-%m-%d %w ', max(glasses.Timestamp), '-06:00') ||
        strftime('%H:%M', max(glasses.Timestamp)) AS "Last_cont",
      locations.Name AS "Location_A_as:LocName",
      users.Username AS xUsername
    from brews
    cross join users
    left join locations ploc on ploc.Id = brews.ProducerLocation
    left join glasses on glasses.Brew = brews.Id and glasses.Username = users.Username
    left join locations on locations.Id = glasses.Location
    left join brew_ratings r on r.Brew = brews.Id and r.Username = users.Username
    group by brews.Id, users.Username
  });
} # mig_034_brews_list_id_link

################################################################################
# Migration 35: locations_list use IdClr and auto-width (issue #705)
# Replace Id_link + Clr_cont with IdClr in column 1, keep Name+Type auto-width.
################################################################################
sub mig_035_locations_list_idclr {
  my $c = shift;

  db::execute($c, "DROP VIEW IF EXISTS locations_list");
  db::execute($c, q{
    CREATE VIEW locations_list AS
    SELECT
      locations.Id AS "IdClr",
      locations.Name AS "Name_A_as:LocName_cont",
      CASE
        WHEN locations.LocType IS NOT NULL AND locations.LocType != '' AND
             locations.LocSubType IS NOT NULL AND locations.LocSubType != ''
        THEN '[' || locations.LocType || ', ' || locations.LocSubType || ']'
        WHEN locations.LocType IS NOT NULL AND locations.LocType != ''
        THEN '[' || locations.LocType || ']'
        WHEN locations.LocSubType IS NOT NULL AND locations.LocSubType != ''
        THEN '[' || locations.LocSubType || ']'
        ELSE ''
      END AS "LocType_A_cont",
      r.rating_count || ';' || r.rating_average || ';' || r.comment_count AS "Ratings_as:Stats",
      (SELECT Filename FROM photos WHERE Location = locations.Id ORDER BY Ts DESC LIMIT 1) AS "Photo_R2_noheader_nofilter",
      '' AS TR1,
      locations.lat || ' ' || locations.lon AS "Geo",
      COALESCE(locations.Country,'') || ';' || COALESCE(locations.Region,'') AS "CountryRegion_A_contline",
      strftime('%Y-%m-%d %w ', max(glasses.Timestamp), '-06:00') ||
        strftime('%H:%M', max(glasses.Timestamp)) AS "Last_cont",
      locations.Tags AS xTags
    FROM locations
    LEFT JOIN glasses ON glasses.Location = locations.Id
    LEFT JOIN location_ratings r ON r.id = locations.Id
    GROUP BY locations.Id
  });
} # mig_035_locations_list_idclr

################################################################################

# Tell the module loaded succesfully
1;
