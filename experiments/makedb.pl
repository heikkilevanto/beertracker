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
my @tables = qw(GLASSES COMMENTS PERSONS LOCATIONS ADDRESSES BREWS BREWTYPE_BEER BREWTYPE_WINE BREWTYPE_CIDER BREWTYPE_BOOZE);
for my $table (@tables) {
    $dbh->do("DROP TABLE IF EXISTS $table");
}

# Create GLASSES table
# A glass of anything I can drink, or special "empty" glasses for
# restaurants etc. The main table.
$dbh->do(q{
    CREATE TABLE GLASSES (
        Id INTEGER PRIMARY KEY AUTOINCREMENT,
        Username TEXT,
        Timestamp DATETIME,
        Effdate DATE,
        Location INTEGER,
        Brew INTEGER,
        Price DECIMAL,
        Volume DECIMAL, /* NULL indicates an "empty" glass */
        Alc DECIMAL,
        FOREIGN KEY (Location) REFERENCES LOCATIONS(Id),
        FOREIGN KEY (Brew) REFERENCES BREWS(Id)
    )
});

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

# Create ADDRESSES table
$dbh->do(q{
    CREATE TABLE ADDRESSES (
        Id INTEGER PRIMARY KEY AUTOINCREMENT,
        StreetAddress TEXT,
        City TEXT,
        Country TEXT,
        PostalCode TEXT,
        Website TEXT,
        Email TEXT
    )
});

# Create PERSONS table
$dbh->do(q{
    CREATE TABLE PERSONS (
        Id INTEGER PRIMARY KEY AUTOINCREMENT,
        Name TEXT NOT NULL,
        ShortName TEXT,
        OfficialName TEXT,
        AddressId INTEGER,
        RelatedPerson INTEGER,
        FOREIGN KEY (RelatedPerson) REFERENCES PERSONS(Id)
        FOREIGN KEY (AddressId) REFERENCES ADDRESSES(Id)
    )
});

# Create LOCATIONS table
$dbh->do(q{
    CREATE TABLE LOCATIONS (
        Id INTEGER PRIMARY KEY AUTOINCREMENT,
        Name TEXT NOT NULL,
        ShortName TEXT,
        OfficialName TEXT,
        AddressId INTEGER,
        GeoCoordinates TEXT,
        FOREIGN KEY (AddressId) REFERENCES ADDRESSES(Id)
    )
});


# Create BREWS table
# A Brew is a definition of a beer or other stuff, whereas a Glass is the
# event of one being drunk.
# Some of the brew details are in separate tables below. These are common to
# most of the brews.
$dbh->do(q{
    CREATE TABLE BREWS (
        Id INTEGER PRIMARY KEY AUTOINCREMENT,
        Name TEXT NOT NULL,
        ShortName TEXT,
        Producer INTEGER,
        BrewType TEXT,  /* Wine, Beer */
        BrewStyle TEXT, /* Red, IPA, Whisky */
        BrewStyleColor TEXT, /* For displaying in lists, graphs */
        /* BrewStyle and -Color are simplified from BREWTYPE_BEER.Style which */
        /* is the way the beer is "officially" defined */
        Alc DECIMAL,
        ReplacedBy INTEGER,
        FOREIGN KEY (Producer) REFERENCES LOCATIONS(Id)
    )
});

# Create BREWTYPE_BEER table
$dbh->do(q{
    CREATE TABLE BREWTYPE_BEER (
        Id INTEGER PRIMARY KEY AUTOINCREMENT,
        Brew INTEGER,
        Style TEXT, /* As defined by the brewery, if availabe */
        Flavors TEXT,  /* Hops, or fruits, or cask */
        Country TEXT DEFAULT "DK",  /* Often from the LOCATION record for the brewery */
        IBU INTEGER,
        Color TEXT,
        Year INTEGER,
        BatchNumber TEXT,
        FOREIGN KEY (Brew) REFERENCES BREWS(Id)
    )
});

# Create BREWTYPE_WINE table
$dbh->do(q{
    CREATE TABLE BREWTYPE_WINE (
        Id INTEGER PRIMARY KEY AUTOINCREMENT,
        Brew INTEGER,
        Country TEXT,
        Region TEXT,
        Flavor TEXT,  /* Grapes, fruits, cask */
        Year INTEGER,
        Classification TEXT, /* Reserva, DOCG, 20y */
        FOREIGN KEY (Brew) REFERENCES BREWS(Id)
    )
});

# Create BREWTYPE_CIDER table
$dbh->do(q{
    CREATE TABLE BREWTYPE_CIDER (
        Id INTEGER PRIMARY KEY AUTOINCREMENT,
        Brew INTEGER,
        Country TEXT,
        Region TEXT,
        Flavor TEXT,  /* Fruit, cask */
        FOREIGN KEY (Brew) REFERENCES BREWS(Id)
    )
});

# Create BREWTYPE_BOOZE table
$dbh->do(q{
    CREATE TABLE BREWTYPE_BOOZE (
        Id INTEGER PRIMARY KEY AUTOINCREMENT,
        Brew INTEGER,
        Style TEXT, /* Whisky, Rom, etc */
        Country TEXT,
        Region TEXT,
        Age INTEGER,
        Flavor TEXT, /* Fruit, cask */
        FOREIGN KEY (Brew) REFERENCES BREWS(Id)
    )
});

# Create indexes
# TODO - Create text indexes with COLLATE NOCASE
$dbh->do("CREATE INDEX idx_glasses_username ON GLASSES (Username COLLATE NOCASE)");  # Username, Id?
$dbh->do("CREATE INDEX idx_glasses_location ON GLASSES (Location COLLATE NOCASE)");
$dbh->do("CREATE INDEX idx_comments_person ON COMMENTS (Person COLLATE NOCASE)");
$dbh->do("CREATE INDEX idx_brewtype_beer_brew ON BREWTYPE_BEER (Brew)");
$dbh->do("CREATE INDEX idx_glasses_timestamp ON GLASSES (Timestamp)");
$dbh->do("CREATE INDEX idx_persons_name ON PERSONS (Name COLLATE NOCASE)");
$dbh->do("CREATE INDEX idx_locations_name ON LOCATIONS (Name COLLATE NOCASE)");
$dbh->do("CREATE INDEX idx_brews_name ON BREWS (Name COLLATE NOCASE)");

print "Database and tables created successfully.\n";

# Disconnect from the database
$dbh->disconnect;

