#!/usr/bin/perl

# Script to produce my beer database. Based on the design in #379. Made with
# the help of ChatGPT. I have since made changes and added comments, so this
# should not be overwitten by a new chatGTP output.



use strict;
use warnings;

use DBI;

# Connect to SQLite database (or create it if it doesn't exist)
my $dbh = DBI->connect("dbi:SQLite:dbname=beertracker.db", "", "", { RaiseError => 1 })
    or die $DBI::errstr;

# Drop existing tables if they exist to avoid conflicts
my @tables = qw(GLASSES COMMENTS PERSONS LOCATIONS BREWS);
for my $table (@tables) {
    $dbh->do("DROP TABLE IF EXISTS $table");
}
$dbh->do("DROP VIEW IF EXISTS GLASSDET");

# Create GLASSES table
# A glass of anything I can drink, or special "empty" glasses for
# restaurants etc. The main table.
$dbh->do(q{
    CREATE TABLE GLASSES (
        Id INTEGER PRIMARY KEY AUTOINCREMENT,
        Username TEXT,
        Timestamp DATETIME,
        Effdate DATE,
        RecordNumber INTEGER,  /* In the file we import from. Can be dropped once we to go production */
        Location INTEGER,
        Brew INTEGER,
        Price DECIMAL,
        Volume DECIMAL, /* NULL indicates an "empty" glass */
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
      select * from GLASSES, BREWS
      where glasses.Brew = Brews.id
});

print "Database and tables created successfully.\n";

# Disconnect from the database
$dbh->disconnect;

