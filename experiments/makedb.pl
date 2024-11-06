#!/usr/bin/perl

# Script to produce my beer database. Based on the design in #379. Made with
# the help of ChatGPT. I have since made changes and added comments, so this
# should not be overwitten by a new chatGTP output.



use strict;
use warnings;

use DBI;

# Connect to SQLite database (or create it if it doesn't exist)
my $databasefile = "beertracker.db";
die ("Database '$databasefile' not writable" ) unless ( -w $databasefile );

my $dbh = DBI->connect("dbi:SQLite:dbname=$databasefile", "", "", { RaiseError => 1, AutoCommit => 1 })
    or error($DBI::errstr);
$dbh->{sqlite_unicode} = 1;  # Yes, we use unicode in the database, and want unicode in the results!

# Drop existing tables if they exist to avoid conflicts
my @tables = qw(GLASSES COMMENTS PERSONS LOCATIONS BREWS);
for my $table (@tables) {
    $dbh->do("DROP TABLE IF EXISTS $table");
}
my @views = qw(GLASSDET GLASSREC COMPERS);
for my $v ( @views) {
  $dbh->do("DROP VIEW IF EXISTS $v");
}

# Create GLASSES table
# A glass of anything I can drink, or special "empty" glasses for
# restaurants etc. The main table.
$dbh->do(q{
    CREATE TABLE GLASSES (
        Id INTEGER PRIMARY KEY AUTOINCREMENT,
        Username TEXT, /* every user has his own glasses - the rest are shared */
        Timestamp DATETIME,
        BrewType TEXT,  /* Wine, Beer, Restaurant */
        Location INTEGER,
        Brew INTEGER, /* Can be null for "empty glasses" which should not have alc nor vol */
        Price DECIMAL,
        Volume DECIMAL,
        Alc DECIMAL,
        FOREIGN KEY (Location) REFERENCES LOCATIONS(Id),
        FOREIGN KEY (Brew) REFERENCES BREWS(Id)
    )
});
$dbh->do("CREATE INDEX idx_glasses_username ON GLASSES (Username COLLATE NOCASE)");  # Username, Id?
$dbh->do("CREATE INDEX idx_glasses_location ON GLASSES (Location)");
$dbh->do("CREATE INDEX idx_glasses_timestamp ON GLASSES (Timestamp)"); # Also effdate?


# Create BREWS table
# A Brew is a definition of a beer or other stuff, whereas a Glass is the
# event of one being drunk.
$dbh->do(q{
    CREATE TABLE BREWS (
        Id INTEGER PRIMARY KEY AUTOINCREMENT,
        Name TEXT,   /* May be NULL for restaurants and such "empty-glass" things */
        BrewType TEXT,  /* Wine, Beer, Restaurant */
        SubType TEXT,  /* Wines: Red, Booze: Rum, Restaurant: Pizza */
        BrewStyle TEXT, /* What ever style we get in, "IPA Hazy" */
        ShortStyle TEXT, /* Short style like Red, IPA, Whisky */
        ShortName TEXT,
        Producer INTEGER,
        Alc DECIMAL,
        Country TEXT,
        Region TEXT,
        Flavor TEXT,  /* hops, grapes, fruits, cask */
        Year INTEGER,
        Details TEXT, /* Classification: Reserva, DOCG, 20y; Edition: Anniversary */
        StyleColor TEXT, /* For displaying in lists, graphs */
        ReplacedBy INTEGER,
        FOREIGN KEY (Producer) REFERENCES LOCATIONS(Id)
    )
});
$dbh->do("CREATE INDEX idx_brews_name ON BREWS (Name COLLATE NOCASE)");


# Create COMMENTS table
# Comments always refer to a glass, even if an "empty" one, since the glass has
# the username needed to keep users separate.
$dbh->do(q{
    CREATE TABLE COMMENTS (
        Id INTEGER PRIMARY KEY AUTOINCREMENT,
        Glass INTEGER,
        ReferTo TEXT DEFAULT "Beer",  /* What the comment is about */
        Comment TEXT,
        Rating INTEGER,
        Person INTEGER,
        Photo TEXT,
        FOREIGN KEY (Glass) REFERENCES GLASSES(Id),
        FOREIGN KEY (Person) REFERENCES PERSONS(Id)
    )
});
$dbh->do("CREATE INDEX idx_comments_person ON COMMENTS (Person)");
$dbh->do("CREATE INDEX idx_comments_glass ON COMMENTS (Glass)");


# Create PERSONS table
$dbh->do(q{
    CREATE TABLE PERSONS (
        Id INTEGER PRIMARY KEY AUTOINCREMENT,
        Name TEXT NOT NULL,
        ShortName TEXT,
        OfficialName TEXT,
        AddressId INTEGER,
        RelatedPerson INTEGER,
        FOREIGN KEY (RelatedPerson) REFERENCES PERSONS(Id),
        FOREIGN KEY (AddressId) REFERENCES LOCATIONS(Id)
    )
});
$dbh->do("CREATE INDEX idx_persons_name ON PERSONS (Name COLLATE NOCASE)");

# Create LOCATIONS table
$dbh->do(q{
    CREATE TABLE LOCATIONS (
        Id INTEGER PRIMARY KEY AUTOINCREMENT,
        Name TEXT NOT NULL,
        ShortName TEXT,
        OfficialName TEXT,
        GeoCoordinates TEXT,
        Website TEXT,
        Email TEXT
        StreetAddress TEXT,
        City TEXT,
        PostalCode TEXT,
        Country TEXT
    )
});
$dbh->do("CREATE INDEX idx_locations_name ON LOCATIONS (Name COLLATE NOCASE)");



# Create view GLASSDET
$dbh->do(q{
    CREATE VIEW GLASSDET AS
      select *, glasses.alc * glasses.volume as alcvol
      from GLASSES, BREWS, LOCATIONS
      where glasses.Brew = Brews.id and glasses.Location = Locations.id
});


# Create view GLASSREC  - a way to return records the way the old script likes them
# All fields must have a "as" clause, to make sure we get lowercase fieldnames
$dbh->do(q{
    CREATE VIEW GLASSREC AS
      select
        glasses.id as glassid,
        glasses.username as username,
        datetime(glasses.timestamp) as stamp,
        strftime ('%w', glasses.timestamp, '-06:00' ) as wdaynumber,  /* as number, monday=1 */
        strftime ('%Y-%m-%d', glasses.timestamp) as date,
        strftime ('%Y', glasses.timestamp) as year,
        strftime ('%H:%M:%S', glasses.timestamp) as time,
        glasses.brewtype as type,
        COALESCE(brews.subtype, brews.country) as subtype,
        strftime ('%Y-%m-%d', glasses.timestamp,'-06:00') as effdate,
        locations.name as loc,
        brews.producer as maker,
        brews.name as name,
        volume as vol,
        brewstyle as style,
        glasses.alc as alc,
        price as pr,
        locations.geocoordinates as geo
      from GLASSES , LOCATIONS
      left join BREWS  on glasses.Brew = Brews.id
      where glasses.Location = Locations.id
});

# Create vier COMPERS that combines comments and persons
$dbh->do(q{
    CREATE VIEW COMPERS AS
      select
        comments.glass as id,
        AVG(comments.Rating) AS rate,
        GROUP_CONCAT(comments.Comment, ' | ') AS com,
        COUNT(comments.Id) AS com_cnt,
        GROUP_CONCAT(comments.Photo, ' | ') AS photo,
        COUNT(comments.Id) AS com_cnt,
        GROUP_CONCAT(persons.name, ', ') AS people,
        COUNT(persons.Id) AS pers_cnt
      from COMMENTS
      LEFT JOIN PERSONS on PERSONS.id = COMMENTS.Person
      GROUP BY comments.glass
});


print "Database and tables created successfully.\n";

# Disconnect from the database
$dbh->disconnect;

