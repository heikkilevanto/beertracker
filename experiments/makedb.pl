#!/usr/bin/perl

# Script to produce my beer database. Based on the design in #379. Made with
# the help of ChatGPT.

use strict;
use warnings;

use DBI;

# TODO - Change Brews to refer to a ProducerLocation, where I can have
# much more than the name of the producer. Keep the ProducerName in the
# Brew, for those that don't have anything more.

# Design considerations   TODO - Write more here
#
# Fields that are INTEGER are referring to other tables. If I want to save
# numbers, I use DECIMAL or such. This is a bit dirty, but makes it easier
# to generate forms with suitable magic for such fields.

# Connect to SQLite database (or create it if it doesn't exist)
my $databasefile = "beertracker.db";
die ("Database '$databasefile' not writable" ) unless ( -w $databasefile );

my $dbh = DBI->connect("dbi:SQLite:dbname=$databasefile", "", "", { RaiseError => 1, AutoCommit => 1 })
    or error($DBI::errstr);
$dbh->{sqlite_unicode} = 1;  # Yes, we use unicode in the database, and want unicode in the results!

# Drop existing tables if they exist to avoid conflicts
my @tables = qw(GLASSES COMMENTS PERSONS LOCATIONS BREWS WEEKDAYS);
for my $table (@tables) {
    $dbh->do("DROP TABLE IF EXISTS $table");
}
my @views = qw(BREWS_LIST LOCATIONS_LIST PERSONS_LIST GLASSREC COMPERS);
for my $v ( @views) {
  $dbh->do("DROP VIEW IF EXISTS $v");
}

# Create GLASSES table
# A glass of anything I can drink, or special "empty" glasses for
# restaurants etc. The main table. These are keyed by the username,
# so each user has his own history.
$dbh->do(q{
    CREATE TABLE GLASSES (
        Id INTEGER PRIMARY KEY AUTOINCREMENT,
        Username TEXT not null, /* every user has his own glasses - the rest are shared */
        Timestamp DATETIME not null,
        BrewType TEXT not null,  /* Wine, Beer, Restaurant */
        Location INTEGER,
        Brew INTEGER, /* Can be null for "empty glasses" which should not have alc nor vol */
        Price DECIMAL default 0,
        Volume DECIMAL default 0,
        Alc DECIMAL default 0.0,
        StDrinks DECIMAL default 0.0, /* pre-calculated Alc * Vol / OneDrink, zero for box wines etc */
        FOREIGN KEY (Location) REFERENCES LOCATIONS(Id),
        FOREIGN KEY (Brew) REFERENCES BREWS(Id)
    )
});
$dbh->do("CREATE INDEX idx_glasses_username ON GLASSES (Username COLLATE NOCASE)");  # Username, Id?
$dbh->do("CREATE INDEX idx_glasses_location ON GLASSES (Location)");
$dbh->do("CREATE INDEX idx_glasses_timestamp ON GLASSES (Timestamp)"); # Also effdate?


# Create BREWS table
# A Brew is a definition of a beer or other stuff, whereas a Glass is the
# event of one being drunk. These can be shared between users.
$dbh->do(q{
    CREATE TABLE BREWS (
        Id INTEGER PRIMARY KEY AUTOINCREMENT,
        Name TEXT,
        BrewType TEXT not null,  /* Wine, Beer, Restaurant */
        SubType TEXT,  /* Wines: Red, Booze: Rum, Restaurant: Pizza */
        BrewStyle TEXT, /* What ever style we get in, "IPA Hazy" */
        ProducerLocation INTEGER,  /* points to a LOCATION rec of the producer */
        Alc DECIMAL default 0.0,
        Country TEXT default '',
        Region TEXT default '',
        Flavor TEXT default '',  /* hops, grapes, fruits, cask */
        Year INTEGER default '',
        Details TEXT default '', /* Classification: Reserva, DOCG, 20y; Edition: Anniversary */
        FOREIGN KEY (ProducerLocation) REFERENCES LOCATIONS(Id)
    )
});
$dbh->do("CREATE INDEX idx_brews_name ON BREWS (Name COLLATE NOCASE)");
$dbh->do("CREATE INDEX idx_brews_producer_location ON BREWS(ProducerLocation)");

$dbh->do(q{
  CREATE VIEW BREWS_LIST AS select
    BREWS.Id,
    BREWS.Name,
  	PLOC.Name as Producer,
    BREWS.BrewType || ", " || BREWS.Subtype as Type,
    strftime ( '%Y-%m-%d %w', max(GLASSES.Timestamp), '-06:00' ) as Last,
    LOCATIONS.Name as Location,
    count(COMMENTS.Id) as Com,
    count(GLASSES.Id) as Count
  from BREWS
  left join LOCATIONS PLOC on PLOC.id = BREWS.ProducerLocation
  left join GLASSES on Glasses.Brew = BREWS.Id
  left join COMMENTS on COMMENTS.Glass = GLASSES.Id
  left join LOCATIONS on LOCATIONS.id = GLASSES.Location
  group by BREWS.id
});
# TODO The Last timestamp is right, but the location does not refer to that timestamp


# Create COMMENTS table
# Comments always refer to a glass, even if an "empty" one, since the glass has
# the username needed to keep users separate.
$dbh->do(q{
    CREATE TABLE COMMENTS (
        Id INTEGER PRIMARY KEY AUTOINCREMENT,
        Glass INTEGER not null,
        ReferTo TEXT DEFAULT "Beer",  /* What the comment is about */
        Comment TEXT default '',
        Rating INTEGER default '',
        Person INTEGER,
        Photo TEXT default '',
        FOREIGN KEY (Glass) REFERENCES GLASSES(Id),
        FOREIGN KEY (Person) REFERENCES PERSONS(Id)
    )
});
$dbh->do("CREATE INDEX idx_comments_person ON COMMENTS (Person)");
$dbh->do("CREATE INDEX idx_comments_glass ON COMMENTS (Glass)");


# Create PERSONS table
# All the people I want to remember.  These are personal to the username, but
# that comes from Glasses, via comments.
$dbh->do(q{
    CREATE TABLE PERSONS (
        Id INTEGER PRIMARY KEY AUTOINCREMENT,
        Name TEXT NOT NULL, /* The name I know the person by. Should be unique */
        FullName TEXT default '', /* Full name, if I know it */
        Description TEXT default '',  /* Small comment on the person to distinguish all Sørens */
        Contact TEXT default '', /* Email, phone, or such. If I need more, I can create a Location */
        Location INTEGER,  /* persons home, or possibly a bar or such connected with the person */
        RelatedPerson INTEGER default '',  /* Persons partner or such */
        FOREIGN KEY (RelatedPerson) REFERENCES PERSONS(Id),
        FOREIGN KEY (Location) REFERENCES LOCATIONS(Id)
    )
});
$dbh->do("CREATE INDEX idx_persons_name ON PERSONS (Name COLLATE NOCASE)");

$dbh->do(q{
  CREATE VIEW PERSONS_LIST AS select
    PERSONS.Id,
    PERSONS.Name,
    count(COMMENTS.Id) - 1 as Com,
    strftime ( '%Y-%m-%d %w', max(GLASSES.Timestamp), '-06:00' ) as Last,
    LOCATIONS.Name as Location
  from PERSONS
  left join COMMENTS on COMMENTS.Person = PERSONS.Id
  left join GLASSES on COMMENTS.Glass = GLASSES.Id
  left join LOCATIONS on LOCATIONS.id = GLASSES.Location
  group by Persons.id
});


# Create LOCATIONS table
# These are mostly bars and restaurants, but can also be homes of Persons, and
# other things that need an address, geo coordinates, and such.
$dbh->do(q{
    CREATE TABLE LOCATIONS (
        Id INTEGER PRIMARY KEY AUTOINCREMENT,
        Name TEXT NOT NULL,  /* The name I know it by. Used in pulldowns */
        OfficialName TEXT default '',  /* Official long name */
        Description TEXT default '',
        SubType TEXT default '', /* Restaurant/Bar type (Thai, Beer), etc */
        GeoCoordinates TEXT default '',
        Website TEXT default '',
        Contact TEXT default '', /* Phone, email, or such */
        Address TEXT default ''  /* Street, zip, city. Or just a description of where I found it */
    )
});
$dbh->do("CREATE INDEX idx_locations_name ON LOCATIONS (Name COLLATE NOCASE)");

# View for listing LOCATIONS
$dbh->do(q{
  CREATE VIEW LOCATIONS_LIST AS select
    LOCATIONS.Id,
    LOCATIONS.Name,
    strftime ( '%Y-%m-%d %w', max(GLASSES.Timestamp), '-06:00' ) as Last,
    LOCATIONS.SubType as Sub,
    LOCATIONS.Description as Desc
  from LOCATIONS
  left join GLASSES on GLASSES.Location = LOCATIONS.Id
  group by LOCATIONS.Id
});



# Create view GLASSREC  - a way to return records the way the old script likes them
# All fields must have a "as" clause, to make sure we get lowercase fieldnames
# TODO - Drop this when no longer needed
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
        coalesce(Brews.brewstyle,'') || ' ' ||
          coalesce(Brews.region,'')  || ' ' ||
          coalesce(Brews.country,'') || ' ' ||
          coalesce(Brews.details,'') || ' ' ||
          coalesce(Brews.year,'')
          as style,
        glasses.alc as alc,
        price as pr,
        locations.geocoordinates as geo
      from GLASSES , LOCATIONS
      left join BREWS  on glasses.Brew = Brews.id
      where glasses.Location = Locations.id
});

# Create vier COMPERS that combines comments and persons
# TODO - Drop this when we no longer need getrecord_com
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

