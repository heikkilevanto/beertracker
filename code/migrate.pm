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

our $CODE_DB_VERSION = 16;  # Bump this when you add migrations

our @MIGRATIONS = (
  [1, 'create globals table', \&mig_001_create_globals_table],
  [2, 'create photos table and backfill from comments.Photo', \&mig_002_photos_table],
  [3, 'add Photo column to locations_list view', \&mig_003_locations_list_photo],
  [4, 'add Photo column to persons_list and brews_list views', \&mig_004_persons_brews_list_photo],
  [5, 'add index on photos(Glass) for mainlist performance', \&mig_005_idx_photos_glass],
  [6, 'comments model phase 1 (types/location/visibility/multi-person)', \&mig_006_comments_model_phase1],
  [7, 'merge person-only comments for same glass into one', \&mig_007_merge_person_only_comments],
  [8, 'drop legacy comments.Person and comments.Photo columns', \&mig_008_drop_legacy_comment_columns],
  [9,  'fix comments_list Xusername for glass-less comments', \&mig_009_fix_comments_list_xusername],
  [10, 'add Brew column to comments, update comments_list view',  \&mig_010_comments_brew_column],
  [11, 'rebuild brew_ratings view to only count CommentType=brew ratings', \&mig_011_brew_ratings_type_filter],
  [12, 'brew_ratings per-user: add Username; rebuild brew list views with per-user stats', \&mig_012_brew_ratings_per_user],
  [13, 'brews_list per user via users x brews, so all brews are visible with user-only stats/count', \&mig_013_brews_list_user_crossjoin],
  [14, 'rebuild brews_dedup_list and producer_brews_list as per-(brew,user) rows', \&mig_014_other_brew_views_user_crossjoin],
  [15, 'add Photos column to comments_list view', \&mig_015_comments_list_photos],
  # v3.3 released here 21-Mar-2026.  Earlier migrations should be deleted soon
  [16, 'add Tags to persons and locations', \&mig_016_add_tags_to_persons_and_locations],
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

sub mig_001_create_globals_table {
  my $c = shift;
  db::execute($c, "CREATE TABLE IF NOT EXISTS globals (k TEXT PRIMARY KEY, v TEXT)");
  db::execute($c, "INSERT OR REPLACE INTO globals(k,v) VALUES('db_version','0')");
} # mig_001_create_globals_table

sub mig_002_photos_table {
  my $c = shift;
  db::execute($c, q{
    CREATE TABLE IF NOT EXISTS photos (
      Id INTEGER PRIMARY KEY,
      Filename TEXT NOT NULL,
      Caption TEXT,
      Glass INTEGER,
      Location INTEGER,
      Person INTEGER,
      Comment INTEGER,
      Brew INTEGER,
      Uploader INTEGER,
      Public INTEGER NOT NULL DEFAULT 0,
      Ts DATETIME DEFAULT CURRENT_TIMESTAMP
    )
  });
  db::execute($c, "CREATE INDEX IF NOT EXISTS idx_photos_comment  ON photos(Comment)");
  db::execute($c, "CREATE INDEX IF NOT EXISTS idx_photos_location ON photos(Location)");
  db::execute($c, "CREATE INDEX IF NOT EXISTS idx_photos_person   ON photos(Person)");
  db::execute($c, "CREATE INDEX IF NOT EXISTS idx_photos_brew     ON photos(Brew)");
  db::execute($c, "CREATE INDEX IF NOT EXISTS idx_photos_uploader ON photos(Uploader)");
  db::execute($c, "CREATE INDEX IF NOT EXISTS idx_photos_public   ON photos(Public)");

  # Ensure Heikki has a persons record (auto-assigned id).
  db::execute($c, q{
    INSERT OR IGNORE INTO persons (Name) VALUES ('Heikki')
  });

  # Backfill: migrate legacy comments.Photo filenames into the photos table.
  # Resolve Uploader by joining comments -> glasses (Username) -> persons (Name).
  db::execute($c, q{
    INSERT INTO photos (Filename, Comment, Uploader, Public, Ts)
      SELECT c.Photo, c.Id, p.Id, 0, g.Timestamp
        FROM comments c
        LEFT JOIN glasses g ON g.Id = c.Glass
        LEFT JOIN persons p ON lower(p.Name) = lower(g.Username)
       WHERE c.Photo IS NOT NULL AND c.Photo != ''
  });
  db::execute($c, "UPDATE comments SET Photo = NULL WHERE Photo IS NOT NULL");
} # mig_002_photos_table

################################################################################
sub mig_003_locations_list_photo {
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
      (SELECT Filename FROM photos WHERE Location = locations.Id ORDER BY Ts DESC LIMIT 1) AS Photo
    FROM locations
    LEFT JOIN glasses ON glasses.Location = locations.Id
    LEFT JOIN location_ratings r ON r.id = glasses.Id
    GROUP BY locations.Id
  });
} # mig_003_locations_list_photo

################################################################################
sub mig_004_persons_brews_list_photo {
  my $c = shift;

  db::execute($c, "DROP VIEW IF EXISTS persons_list");
  db::execute($c, q{
    CREATE VIEW persons_list AS
    SELECT
      persons.Id,
      persons.Name,
      'trmob' AS trmob,
      count(comments.Id) - 1 AS Com,
      strftime('%Y-%m-%d %w ', max(glasses.Timestamp), '-06:00') ||
        strftime('%H:%M', max(glasses.Timestamp)) AS Last,
      locations.Name AS Location,
      'tr' AS tr,
      'Clr' AS Clr,
      persons.description,
      (SELECT Filename FROM photos WHERE Person = persons.Id ORDER BY Ts DESC LIMIT 1) AS Photo
    FROM persons
    LEFT JOIN comments ON comments.Person = persons.Id
    LEFT JOIN glasses ON comments.Glass = glasses.Id
    LEFT JOIN locations ON locations.Id = glasses.Location
    GROUP BY persons.Id
  });

  db::execute($c, "DROP VIEW IF EXISTS brews_list");
  db::execute($c, q{
    CREATE VIEW brews_list AS
    SELECT
      brews.Id,
      brews.Name,
      ploc.Name AS Producer,
      brews.IsGeneric,
      'tr' AS tr,
      brews.Alc AS Alc,
      brews.BrewType || ', ' || brews.Subtype AS Type,
      r.rating_count || ';' || r.average_rating || ';' || r.comment_count AS Stats,
      count(glasses.Id) AS Count,
      'tr' AS tr,
      'Clr' AS Clr,
      strftime('%Y-%m-%d %w ', max(glasses.Timestamp), '-06:00') ||
        strftime('%H:%M', max(glasses.Timestamp)) AS Last,
      locations.Name AS Location,
      (SELECT Filename FROM photos WHERE Brew = brews.Id ORDER BY Ts DESC LIMIT 1) AS Photo
    FROM brews
    LEFT JOIN locations ploc ON ploc.Id = brews.ProducerLocation
    LEFT JOIN glasses ON glasses.Brew = brews.Id
    LEFT JOIN locations ON locations.Id = glasses.Location
    LEFT JOIN brew_ratings r ON r.Brew = brews.Id
    GROUP BY brews.Id
  });
} # mig_004_persons_brews_list_photo

################################################################################
sub mig_005_idx_photos_glass {
  my $c = shift;
  db::execute($c, "CREATE INDEX IF NOT EXISTS idx_photos_glass ON photos(Glass)");
} # mig_005_idx_photos_glass

################################################################################
sub mig_006_comments_model_phase1 {
  my $c = shift;

  # --- 1. New columns on comments ---
  db::execute($c, "ALTER TABLE comments ADD COLUMN CommentType TEXT");
  db::execute($c, "ALTER TABLE comments ADD COLUMN Ts DATETIME");
  db::execute($c, "ALTER TABLE comments ADD COLUMN Location INTEGER");
  db::execute($c, "ALTER TABLE comments ADD COLUMN Username TEXT");

  # --- 2. Many-to-many person join table ---
  db::execute($c, q{
    CREATE TABLE IF NOT EXISTS comment_persons (
      Comment INTEGER NOT NULL,
      Person  INTEGER NOT NULL,
      PRIMARY KEY (Comment, Person),
      FOREIGN KEY (Comment) REFERENCES comments(Id) ON DELETE CASCADE,
      FOREIGN KEY (Person)  REFERENCES persons(Id)
    )
  });

  # --- 3. Indexes ---
  db::execute($c, "CREATE INDEX IF NOT EXISTS idx_comments_type     ON comments(CommentType)");
  db::execute($c, "CREATE INDEX IF NOT EXISTS idx_comments_location ON comments(Location)");
  db::execute($c, "CREATE INDEX IF NOT EXISTS idx_comments_username ON comments(Username)");
  db::execute($c, "CREATE INDEX IF NOT EXISTS idx_comments_ts       ON comments(Ts)");
  db::execute($c, "CREATE INDEX IF NOT EXISTS idx_comment_persons_person  ON comment_persons(Person)");
  db::execute($c, "CREATE INDEX IF NOT EXISTS idx_comment_persons_comment ON comment_persons(Comment)");

  # --- 4. Backfill data ---

  # comment_persons from legacy single-person field
  db::execute($c, q{
    INSERT OR IGNORE INTO comment_persons (Comment, Person)
    SELECT Id, Person FROM comments WHERE Person IS NOT NULL
  });

  # Location: copy from the linked glass only when the glass is empty (no brew)
  db::execute($c, q{
    UPDATE comments
    SET Location = (
      SELECT g.Location FROM glasses g
      WHERE g.Id = comments.Glass AND g.Brew IS NULL
    )
    WHERE Location IS NULL
      AND Glass IS NOT NULL
      AND EXISTS (
        SELECT 1 FROM glasses g WHERE g.Id = comments.Glass AND g.Brew IS NULL
      )
  });

  # Username: take ownership from the glass owner
  db::execute($c, q{
    UPDATE comments
    SET Username = (SELECT g.Username FROM glasses g WHERE g.Id = comments.Glass)
    WHERE Username IS NULL
      AND Glass IS NOT NULL
      AND EXISTS (SELECT 1 FROM glasses g WHERE g.Id = comments.Glass)
  });

  # Ts: prefer glass timestamp, fall back to current time
  db::execute($c, q{
    UPDATE comments
    SET Ts = COALESCE(
      (SELECT g.Timestamp FROM glasses g WHERE g.Id = comments.Glass),
      CURRENT_TIMESTAMP
    )
    WHERE Ts IS NULL
  });

  # CommentType inference chain (in order — earlier rules take priority)
  db::execute($c, q{
    UPDATE comments SET CommentType = 'brew'
    WHERE CommentType IS NULL
      AND Glass IS NOT NULL
      AND EXISTS (SELECT 1 FROM glasses g WHERE g.Id = comments.Glass AND g.Brew IS NOT NULL)
  });

  db::execute($c, q{
    UPDATE comments SET CommentType = 'meal'
    WHERE CommentType IS NULL
      AND Glass IS NOT NULL
      AND EXISTS (
        SELECT 1 FROM glasses g
        WHERE g.Id = comments.Glass
          AND g.Brew IS NULL
          AND g.BrewType IN ('Restaurant', 'Meal')
      )
  });

  db::execute($c, q{
    UPDATE comments SET CommentType = 'night'
    WHERE CommentType IS NULL
      AND (
        (
          Glass IS NOT NULL
          AND EXISTS (
            SELECT 1 FROM glasses g
            WHERE g.Id = comments.Glass
              AND g.Brew IS NULL
              AND g.BrewType = 'Night'
          )
        ) OR (
          Location IS NOT NULL
          AND EXISTS (
            SELECT 1 FROM comment_persons cp WHERE cp.Comment = comments.Id
          )
        )
      )
  });

  db::execute($c, q{
    UPDATE comments SET CommentType = 'location'
    WHERE CommentType IS NULL
      AND Location IS NOT NULL
      AND NOT EXISTS (
        SELECT 1 FROM comment_persons cp WHERE cp.Comment = comments.Id
      )
  });

  db::execute($c, q{
    UPDATE comments SET CommentType = 'person'
    WHERE CommentType IS NULL
      AND Glass IS NULL
      AND EXISTS (
        SELECT 1 FROM comment_persons cp WHERE cp.Comment = comments.Id
      )
  });

  db::execute($c, q{
    UPDATE comments SET CommentType = 'glass' WHERE CommentType IS NULL
  });

  # --- 5. Rebuild views ---

  # compers is not used anywhere in code — drop it
  db::execute($c, "DROP VIEW IF EXISTS compers");

  # persons_list: switch from comments.Person join to comment_persons
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
      (SELECT Filename FROM photos WHERE Person = persons.Id ORDER BY Ts DESC LIMIT 1) AS Photo
    FROM persons
    LEFT JOIN comment_persons cp ON cp.Person = persons.Id
    LEFT JOIN comments ON comments.Id = cp.Comment
    LEFT JOIN glasses ON glasses.Id = comments.Glass
    LEFT JOIN locations ON locations.Id = glasses.Location
    GROUP BY persons.Id
  });

  # loc_ratings: add direct comments.Location path in addition to glass-routed path
  db::execute($c, "DROP VIEW IF EXISTS loc_ratings");
  db::execute($c, q{
    CREATE VIEW loc_ratings AS
    SELECT
      l.id,
      avg(CASE WHEN merged.Brew IS NOT NULL THEN merged.Rating END) AS brew_avg,
      count(CASE WHEN merged.Brew IS NOT NULL THEN merged.Rating END) AS brew_count,
      count(CASE WHEN merged.Brew IS NOT NULL THEN merged.Comment END) AS brew_comments,
      avg(CASE WHEN merged.Brew IS NULL THEN merged.Rating END) AS loc_avg,
      count(CASE WHEN merged.Brew IS NULL THEN merged.Rating END) AS loc_count,
      count(CASE WHEN merged.Brew IS NULL THEN merged.Comment END) AS loc_comments
    FROM locations l
    LEFT JOIN (
      SELECT g.Location AS loc_id, c.Rating, c.Comment, g.Brew
        FROM comments c JOIN glasses g ON g.Id = c.Glass
      UNION ALL
      SELECT c.Location AS loc_id, c.Rating, c.Comment, NULL AS Brew
        FROM comments c WHERE c.Location IS NOT NULL AND c.Glass IS NULL
    ) merged ON merged.loc_id = l.Id
    WHERE l.LocType <> 'Producer'
    GROUP BY l.Id
  });

  # location_ratings: same extension for direct location path
  db::execute($c, "DROP VIEW IF EXISTS location_ratings");
  db::execute($c, q{
    CREATE VIEW location_ratings AS
    SELECT
      l.id,
      count(merged.Rating)   AS rating_count,
      avg(merged.Rating)     AS rating_average,
      count(merged.Comment)  AS comment_count
    FROM locations l
    LEFT JOIN (
      SELECT g.Location AS loc_id, c.Rating, c.Comment
        FROM comments c JOIN glasses g ON g.Id = c.Glass
      UNION ALL
      SELECT c.Location AS loc_id, c.Rating, c.Comment
        FROM comments c WHERE c.Location IS NOT NULL AND c.Glass IS NULL
    ) merged ON merged.loc_id = l.Id
    WHERE l.LocType <> 'Producer'
    GROUP BY l.Id
  });

  # comments_list: add CommentType column, remove Photo (already NULL after mig_002),
  # use COALESCE(glass timestamp, comments.Ts) for sort/display
  db::execute($c, "DROP VIEW IF EXISTS comments_list");
  db::execute($c, q{
    CREATE VIEW comments_list AS
    SELECT
      comments.Id,
      strftime('%Y-%m-%d %w ', COALESCE(glasses.Timestamp, comments.Ts), '-06:00') ||
        strftime('%H:%M', COALESCE(glasses.Timestamp, comments.Ts)) AS Last,
      locations.Name AS LocName,
      'tr' AS tr,
      '' AS Clr,
      brews.Name AS BrewName,
      ploc.Name AS Prod,
      'tr' AS tr,
      comments.Rating AS Rate,
      persons.Name AS PersonName,
      comments.CommentType AS CommentType,
      comments.Comment AS Comment,
      'tr' AS tr,
      '' AS None,
      glasses.Username AS Xusername
    FROM comments
    LEFT JOIN glasses ON glasses.Id = comments.Glass
    LEFT JOIN brews ON brews.Id = glasses.Brew
    LEFT JOIN persons ON persons.Id = comments.Person
    LEFT JOIN locations ON locations.Id = glasses.Location
    LEFT JOIN locations ploc ON ploc.Id = brews.ProducerLocation
    ORDER BY Last DESC
  });

} # mig_006_comments_model_phase1

################################################################################
sub mig_007_merge_person_only_comments {
  my $c = shift;

  # For each glass that has any person-only comment (no text, no rating),
  # merge all its person-only comments into a single "keeper" comment:
  #   - If the glass also has a real comment (text or rating), keeper = MIN Id of real comments.
  #   - Otherwise, keeper = MIN Id of all comments for that glass.
  # All person links from surplus person-only comments are moved to the keeper,
  # then the surplus comments and their comment_persons rows are deleted.

  # Build a temp table of (Glass, keeper_id) — one row per affected glass.
  db::execute($c, q{
    CREATE TEMP TABLE _mig7_keepers AS
    SELECT gpo.Glass,
      COALESCE(
        MIN(CASE WHEN (c.Comment IS NOT NULL AND c.Comment != '')
                   OR (c.Rating  IS NOT NULL AND c.Rating  != 0)
             THEN c.Id END),
        MIN(c.Id)
      ) AS keeper_id
    FROM (
      SELECT DISTINCT Glass FROM comments
      WHERE Glass IS NOT NULL
        AND (Comment IS NULL OR Comment = '')
        AND (Rating  IS NULL OR Rating  = 0)
    ) gpo
    JOIN comments c ON c.Glass = gpo.Glass
    GROUP BY gpo.Glass
  });

  # Step 1: Copy person links from surplus person-only comments to the keeper.
  # OR IGNORE handles cases where the person is already linked to the keeper.
  db::execute($c, q{
    INSERT OR IGNORE INTO comment_persons (Comment, Person)
    SELECT k.keeper_id, cp.Person
    FROM _mig7_keepers k
    JOIN comments surplus ON surplus.Glass = k.Glass
    JOIN comment_persons cp ON cp.Comment = surplus.Id
    WHERE (surplus.Comment IS NULL OR surplus.Comment = '')
      AND (surplus.Rating  IS NULL OR surplus.Rating  = 0)
      AND surplus.Id != k.keeper_id
  });

  # Step 2: Delete comment_persons rows for surplus person-only comments.
  db::execute($c, q{
    DELETE FROM comment_persons
    WHERE Comment IN (
      SELECT surplus.Id
      FROM _mig7_keepers k
      JOIN comments surplus ON surplus.Glass = k.Glass
      WHERE (surplus.Comment IS NULL OR surplus.Comment = '')
        AND (surplus.Rating  IS NULL OR surplus.Rating  = 0)
        AND surplus.Id != k.keeper_id
    )
  });

  # Step 3: Delete the surplus person-only comments themselves.
  db::execute($c, q{
    DELETE FROM comments
    WHERE Id IN (
      SELECT surplus.Id
      FROM _mig7_keepers k
      JOIN comments surplus ON surplus.Glass = k.Glass
      WHERE (surplus.Comment IS NULL OR surplus.Comment = '')
        AND (surplus.Rating  IS NULL OR surplus.Rating  = 0)
        AND surplus.Id != k.keeper_id
    )
  });

  db::execute($c, "DROP TABLE IF EXISTS _mig7_keepers");

} # mig_007_merge_person_only_comments

################################################################################
sub mig_008_drop_legacy_comment_columns {
  my $c = shift;

  # Drop the legacy comments.Person (superseded by comment_persons join table)
  # and comments.Photo (superseded by the photos table; nulled out in mig_002).
  # SQLite 3.35+ supports ALTER TABLE DROP COLUMN, but only when no view or
  # index references the column, so drop those first.

  db::execute($c, "DROP INDEX IF EXISTS idx_comments_person");
  db::execute($c, "DROP VIEW IF EXISTS comments_list");
  db::execute($c, q{
    CREATE VIEW comments_list AS
    SELECT
      comments.Id,
      strftime('%Y-%m-%d %w ', COALESCE(glasses.Timestamp, comments.Ts), '-06:00') ||
        strftime('%H:%M', COALESCE(glasses.Timestamp, comments.Ts)) AS Last,
      locations.Name AS LocName,
      'tr' AS tr,
      '' AS Clr,
      brews.Name AS BrewName,
      ploc.Name AS Prod,
      'tr' AS tr,
      comments.Rating AS Rate,
      group_concat(persons.Name, ', ') AS PersonName,
      comments.CommentType AS CommentType,
      comments.Comment AS Comment,
      'tr' AS tr,
      '' AS None,
      glasses.Username AS Xusername
    FROM comments
    LEFT JOIN glasses ON glasses.Id = comments.Glass
    LEFT JOIN brews ON brews.Id = glasses.Brew
    LEFT JOIN comment_persons cp ON cp.Comment = comments.Id
    LEFT JOIN persons ON persons.Id = cp.Person
    LEFT JOIN locations ON locations.Id = glasses.Location
    LEFT JOIN locations ploc ON ploc.Id = brews.ProducerLocation
    GROUP BY comments.Id
    ORDER BY Last DESC
  });

  db::execute($c, "ALTER TABLE comments DROP COLUMN Person");
  db::execute($c, "ALTER TABLE comments DROP COLUMN Photo");

} # mig_008_drop_legacy_comment_columns

sub mig_009_fix_comments_list_xusername {
  my $c = shift;

  # comments_list used glasses.Username as Xusername, which is NULL for
  # glass-less comments, making them invisible on the comments list page.
  # Fix: use COALESCE(glasses.Username, comments.Username).

  db::execute($c, "DROP VIEW IF EXISTS comments_list");
  db::execute($c, q{
    CREATE VIEW comments_list AS
    SELECT
      comments.Id,
      strftime('%Y-%m-%d %w ', COALESCE(glasses.Timestamp, comments.Ts), '-06:00') ||
        strftime('%H:%M', COALESCE(glasses.Timestamp, comments.Ts)) AS Last,
      locations.Name AS LocName,
      'tr' AS tr,
      '' AS Clr,
      brews.Name AS BrewName,
      ploc.Name AS Prod,
      'tr' AS tr,
      comments.Rating AS Rate,
      group_concat(persons.Name, ', ') AS PersonName,
      comments.CommentType AS CommentType,
      comments.Comment AS Comment,
      'tr' AS tr,
      '' AS None,
      COALESCE(glasses.Username, comments.Username) AS Xusername
    FROM comments
    LEFT JOIN glasses ON glasses.Id = comments.Glass
    LEFT JOIN brews ON brews.Id = glasses.Brew
    LEFT JOIN comment_persons cp ON cp.Comment = comments.Id
    LEFT JOIN persons ON persons.Id = cp.Person
    LEFT JOIN locations ON locations.Id = glasses.Location
    LEFT JOIN locations ploc ON ploc.Id = brews.ProducerLocation
    GROUP BY comments.Id
    ORDER BY Last DESC
  });

} # mig_009_fix_comments_list_xusername

sub mig_010_comments_brew_column {
  my $c = shift;

  # Add a Brew FK to comments so glass-less comments can reference a specific brew.
  db::execute($c, "ALTER TABLE comments ADD COLUMN Brew INTEGER REFERENCES brews(Id)");
  db::execute($c, "CREATE INDEX idx_comments_brew ON comments(Brew)");

  # Recreate comments_list so BrewName, LocName, Prod and Xusername all
  # fall back to the comment's own Brew/Location when there is no glass.
  db::execute($c, "DROP VIEW IF EXISTS comments_list");
  db::execute($c, q{
    CREATE VIEW comments_list AS
    SELECT
      comments.Id,
      strftime('%Y-%m-%d %w ', COALESCE(glasses.Timestamp, comments.Ts), '-06:00') ||
        strftime('%H:%M', COALESCE(glasses.Timestamp, comments.Ts)) AS Last,
      COALESCE(loc_comment.Name, loc_glass.Name) AS LocName,
      'tr' AS tr,
      '' AS Clr,
      COALESCE(brew_comment.Name, brew_glass.Name) AS BrewName,
      COALESCE(ploc_comment.Name, ploc_glass.Name) AS Prod,
      'tr' AS tr,
      comments.Rating AS Rate,
      group_concat(persons.Name, ', ') AS PersonName,
      comments.CommentType AS CommentType,
      comments.Comment AS Comment,
      'tr' AS tr,
      '' AS None,
      COALESCE(glasses.Username, comments.Username) AS Xusername
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
    ORDER BY Last DESC
  });

} # mig_010_comments_brew_column

################################################################################
sub mig_011_brew_ratings_type_filter {
  my $c = shift;
  db::execute($c, "DROP VIEW IF EXISTS brew_ratings");
  db::execute($c, q{
    CREATE VIEW brew_ratings AS
    SELECT
        g.brew,
        count(g.brew) AS glass_count,
        count(CASE WHEN c.rating IS NOT NULL AND c.rating != '' THEN 1 END) AS rating_count,
        avg(CASE WHEN c.rating IS NOT NULL AND c.rating != '' THEN c.rating END) AS average_rating,
        count(CASE WHEN c.comment IS NOT NULL AND c.comment != '' THEN 1 END) AS comment_count
    FROM glasses g
    LEFT JOIN comments c ON c.glass = g.id AND c.CommentType = 'brew'
    WHERE g.brew IS NOT NULL
    GROUP BY g.brew
  });
} # mig_011_brew_ratings_type_filter

################################################################################
sub mig_012_brew_ratings_per_user {
  my $c = shift;

  # Add Username to brew_ratings so each user has their own row per brew
  db::execute($c, "DROP VIEW IF EXISTS brew_ratings");
  db::execute($c, q{
    CREATE VIEW brew_ratings AS
    SELECT
        g.Username,
        g.brew,
        count(g.brew) AS glass_count,
        count(CASE WHEN c.rating IS NOT NULL AND c.rating != '' THEN 1 END) AS rating_count,
        avg(CASE WHEN c.rating IS NOT NULL AND c.rating != '' THEN c.rating END) AS average_rating,
        count(CASE WHEN c.comment IS NOT NULL AND c.comment != '' THEN 1 END) AS comment_count
    FROM glasses g
    LEFT JOIN comments c ON c.glass = g.id AND c.CommentType = 'brew'
    WHERE g.brew IS NOT NULL
    GROUP BY g.Username, g.brew
  });

  # Rebuild brews_list with xUsername column and per-user brew_ratings join.
  # Grouping by (brews.Id, glasses.Username) gives one row per (brew, user);
  # the xUsername filter in listrecords callers restricts to current user only
  # while brews with NULL username (never tasted by anyone) still appear.
  db::execute($c, "DROP VIEW IF EXISTS brews_list");
  db::execute($c, q{
    CREATE VIEW brews_list AS
    SELECT
      brews.Id,
      brews.Name,
      ploc.Name AS Producer,
      brews.IsGeneric,
      'tr' AS tr,
      brews.Alc AS Alc,
      brews.BrewType || ', ' || brews.Subtype AS Type,
      r.rating_count || ';' || r.average_rating || ';' || r.comment_count AS Stats,
      count(glasses.Id) AS Count,
      'tr' AS tr,
      'Clr' AS Clr,
      strftime('%Y-%m-%d %w ', max(glasses.Timestamp), '-06:00') ||
        strftime('%H:%M', max(glasses.Timestamp)) AS Last,
      locations.Name AS Location,
      (SELECT Filename FROM photos WHERE Brew = brews.Id ORDER BY Ts DESC LIMIT 1) AS Photo,
      glasses.Username AS xUsername
    FROM brews
    LEFT JOIN locations ploc ON ploc.Id = brews.ProducerLocation
    LEFT JOIN glasses ON glasses.Brew = brews.Id
    LEFT JOIN locations ON locations.Id = glasses.Location
    LEFT JOIN brew_ratings r ON r.Brew = brews.Id AND r.Username = glasses.Username
    GROUP BY brews.Id, glasses.Username
  });

  db::execute($c, "DROP VIEW IF EXISTS brews_dedup_list");
  db::execute($c, q{
    CREATE VIEW brews_dedup_list AS
    SELECT
        brews.Id,
        'Chk' AS Chk,
        brews.Name,
        '?' AS Sim,
        ploc.Name AS Producer,
        brews.Alc AS Alc,
        brews.BrewType || ', ' || brews.Subtype AS Type,
        strftime('%Y-%m-%d %w ', max(glasses.Timestamp), '-06:00') ||
          strftime('%H:%M', max(glasses.Timestamp)) AS Last,
        locations.Name AS Location,
        r.rating_count || ';' || r.average_rating || ';' || r.comment_count AS Stats,
        count(glasses.Id) AS Count,
        glasses.Username AS xUsername
    FROM brews
    LEFT JOIN locations ploc ON ploc.id = brews.ProducerLocation
    LEFT JOIN glasses ON glasses.Brew = brews.Id
    LEFT JOIN locations ON locations.id = glasses.Location
    LEFT JOIN brew_ratings r ON r.Brew = brews.Id AND r.Username = glasses.Username
    GROUP BY brews.id, glasses.Username
  });

  db::execute($c, "DROP VIEW IF EXISTS producer_brews_list");
  db::execute($c, q{
    CREATE VIEW producer_brews_list AS
    SELECT
        brews.Id AS xId,
        brews.Name,
        ploc.Name AS xProducer,
        brews.Alc AS Alc,
        brews.Subtype AS Sub,
        r.rating_count || ';' || r.average_rating || ';' || r.comment_count AS Stats,
        strftime('%Y-%m-%d', max(glasses.Timestamp), '-06:00') AS Last,
        glasses.Username AS xUsername
    FROM brews
    LEFT JOIN locations ploc ON ploc.id = brews.ProducerLocation
    LEFT JOIN glasses ON glasses.Brew = brews.Id
    LEFT JOIN brew_ratings r ON r.Brew = brews.Id AND r.Username = glasses.Username
    GROUP BY brews.id, glasses.Username
  });

} # mig_012_brew_ratings_per_user

################################################################################
sub mig_013_brews_list_user_crossjoin {
  my $c = shift;

  # Build brews_list as one row per (brew, user). This guarantees each user
  # sees all brews (including those only tasted by others) while keeping
  # Stats/Count scoped to that specific user.
  db::execute($c, "DROP VIEW IF EXISTS brews_list");
  db::execute($c, q{
    CREATE VIEW brews_list AS
    WITH users AS (
      SELECT DISTINCT Username FROM glasses
    )
    SELECT
      brews.Id,
      brews.Name,
      ploc.Name AS Producer,
      brews.IsGeneric,
      'tr' AS tr,
      brews.Alc AS Alc,
      brews.BrewType || ', ' || brews.Subtype AS Type,
      r.rating_count || ';' || r.average_rating || ';' || r.comment_count AS Stats,
      count(glasses.Id) AS Count,
      'tr' AS tr,
      'Clr' AS Clr,
      strftime('%Y-%m-%d %w ', max(glasses.Timestamp), '-06:00') ||
        strftime('%H:%M', max(glasses.Timestamp)) AS Last,
      locations.Name AS Location,
      (SELECT Filename FROM photos WHERE Brew = brews.Id ORDER BY Ts DESC LIMIT 1) AS Photo,
      users.Username AS xUsername
    FROM brews
    CROSS JOIN users
    LEFT JOIN locations ploc ON ploc.Id = brews.ProducerLocation
    LEFT JOIN glasses ON glasses.Brew = brews.Id AND glasses.Username = users.Username
    LEFT JOIN locations ON locations.Id = glasses.Location
    LEFT JOIN brew_ratings r ON r.Brew = brews.Id AND r.Username = users.Username
    GROUP BY brews.Id, users.Username
  });
} # mig_013_brews_list_user_crossjoin

################################################################################
sub mig_014_other_brew_views_user_crossjoin {
  my $c = shift;

  db::execute($c, "DROP VIEW IF EXISTS brews_dedup_list");
  db::execute($c, q{
    CREATE VIEW brews_dedup_list AS
    WITH users AS (
      SELECT DISTINCT Username FROM glasses
    )
    SELECT
        brews.Id,
        'Chk' AS Chk,
        brews.Name,
        '?' AS Sim,
        ploc.Name AS Producer,
        brews.Alc AS Alc,
        brews.BrewType || ', ' || brews.Subtype AS Type,
        strftime('%Y-%m-%d %w ', max(glasses.Timestamp), '-06:00') ||
          strftime('%H:%M', max(glasses.Timestamp)) AS Last,
        locations.Name AS Location,
        r.rating_count || ';' || r.average_rating || ';' || r.comment_count AS Stats,
        count(glasses.Id) AS Count,
        users.Username AS xUsername
    FROM brews
    CROSS JOIN users
    LEFT JOIN locations ploc ON ploc.id = brews.ProducerLocation
    LEFT JOIN glasses ON glasses.Brew = brews.Id AND glasses.Username = users.Username
    LEFT JOIN locations ON locations.id = glasses.Location
    LEFT JOIN brew_ratings r ON r.Brew = brews.Id AND r.Username = users.Username
    GROUP BY brews.id, users.Username
  });

  db::execute($c, "DROP VIEW IF EXISTS producer_brews_list");
  db::execute($c, q{
    CREATE VIEW producer_brews_list AS
    WITH users AS (
      SELECT DISTINCT Username FROM glasses
    )
    SELECT
        brews.Id AS xId,
        brews.Name,
        ploc.Name AS xProducer,
        brews.Alc AS Alc,
        brews.Subtype AS Sub,
        r.rating_count || ';' || r.average_rating || ';' || r.comment_count AS Stats,
        strftime('%Y-%m-%d', max(glasses.Timestamp), '-06:00') AS Last,
        users.Username AS xUsername
    FROM brews
    CROSS JOIN users
    LEFT JOIN locations ploc ON ploc.id = brews.ProducerLocation
    LEFT JOIN glasses ON glasses.Brew = brews.Id AND glasses.Username = users.Username
    LEFT JOIN brew_ratings r ON r.Brew = brews.Id AND r.Username = users.Username
    GROUP BY brews.id, users.Username
  });
} # mig_014_other_brew_views_user_crossjoin

################################################################################
sub mig_015_comments_list_photos {
  my $c = shift;
  db::execute($c, "DROP VIEW IF EXISTS comments_list");
  db::execute($c, q{
    CREATE VIEW comments_list AS
    SELECT
      comments.Id,
      strftime('%Y-%m-%d %w ', COALESCE(glasses.Timestamp, comments.Ts), '-06:00') ||
        strftime('%H:%M', COALESCE(glasses.Timestamp, comments.Ts)) AS Last,
      COALESCE(loc_comment.Name, loc_glass.Name) AS LocName,
      'tr' AS tr,
      '' AS Clr,
      COALESCE(brew_comment.Name, brew_glass.Name) AS BrewName,
      COALESCE(ploc_comment.Name, ploc_glass.Name) AS Prod,
      'tr' AS tr,
      comments.Rating AS Rate,
      group_concat(persons.Name, ', ') AS PersonName,
      comments.CommentType AS CommentType,
      comments.Comment AS Comment,
      'tr' AS tr,
      (SELECT group_concat(Filename, '|') FROM photos WHERE Comment = comments.Id) AS Photos,
      '' AS None,
      COALESCE(glasses.Username, comments.Username) AS Xusername
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
    ORDER BY Last DESC
  });
} # mig_015_comments_list_photos

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

1;
