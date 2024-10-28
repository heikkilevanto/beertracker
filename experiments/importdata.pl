#!/usr/bin/perl

# Script to import old beerdata text files into sqlite
# Created with a lot of help from ChatGTP, and lots of cursing at its stupidity

# TODO  (run out of ChatGpt tokens again)
#   - Forget all about the diagrams
#   - Any kind of line can have comments. Insert them so they refer to the proper GLASS record
#   - If a line has "people" field, insert it as a Person in the comments table
#   - Add effdate to the Glass record
#   - Add geo into names.Geocoordinates
#   - In Beer records, if the substyle is a two letter code, put it into Brew.country
#   - Refactor all the insert calls into a function called insert_record
#   - Comment.ReferTo should get the record type
#   - If there is no data to insert in the brew details, do not create a record.
#   - Do not insert anything but the style into wine_details. Put that into country.
#   - When checking a NAME, if we have geo coords, and the record does not, update the geocoordinates

# TODO Later, in a separate (manual?) step. Probably once I have imported the data
#   - Separate wine styles into country and region. Normalize country codes
#   - Get location details at least for the most common watering holes



use strict;
use warnings;
use DBI;



my $debug = 0;
my $username = "heikki";  # Default username


# Database setup
my $dbh = DBI->connect("dbi:SQLite:dbname=beertracker.db", "", "", { RaiseError => 1, AutoCommit => 1 })
    or die $DBI::errstr;

# Define the path to the data file
my $datafile = "../beerdata/heikki.data";

# Define data types
my %datalinetypes = (
    "Beer"       => ["stamp", "type", "wday", "effdate", "loc", "maker", "name", "vol", "style", "alc", "pr", "rate", "com", "geo", "subtype", "photo"],
    "Wine"       => ["stamp", "type", "wday", "effdate", "loc", "subtype", "maker", "name", "style", "vol", "alc", "pr", "rate", "com", "geo", "photo"],
    "Booze"      => ["stamp", "type", "wday", "effdate", "loc", "subtype", "maker", "name", "style", "vol", "alc", "pr", "rate", "com", "geo", "photo"],
    "Night"      => ["stamp", "type", "wday", "effdate", "loc", "subtype", "com", "people", "geo", "photo"],
    "Restaurant" => ["stamp", "type", "wday", "effdate", "loc", "subtype", "rate", "pr", "food", "people", "com", "geo", "photo"],
);


# Open the data file
open my $fh, '<', $datafile or die("Could not open $datafile for reading: $!");
my $nlines = 0;
# Process each line
while (<$fh>) {
    chomp;
    $nlines ++;
    print "$nlines: $_\n";
    next unless $_;         # Skip empty lines
    next if /^#/;           # Skip comment lines

    # Split line into fields
    my @datafields = split(/ *; */, $_);
    my $linetype = $datafields[1];  # Line type (e.g., Beer, Wine, etc.)
    next unless $linetype;

    # Get field names for this type
    my $fieldnamelist = $datalinetypes{$linetype};
    next unless $fieldnamelist;
    my @fnames = @{$fieldnamelist};

    # Create a hash to store the record's data
    my $rec = {};
    for my $i (0..$#fnames) {
        $rec->{$fnames[$i]} = $datafields[$i];
        my $v = $rec->{$fnames[$i]} || '(null)';
        print "$fnames[$i] : '$v' \n" if $debug;
    }

    # Common Fields: Initialize key variables from file data
    my $username = $rec->{username} || "heikki";
    my $timestamp = $rec->{stamp};
    my $location_id = get_or_insert_name($dbh, $rec->{loc});
    my $maker_id = $rec->{maker} ? get_or_insert_name($dbh, $rec->{maker}) : undef;
    my $brew_id = get_or_insert_brew($dbh, $rec->{name}, $maker_id, $rec->{style});

    # Insert a Glass record (for both beverage and event entries)
    my $glass_id = insert_glass(
        $dbh, $username, $timestamp, $location_id, $brew_id, $rec->{pr}, $rec->{vol}, $rec->{alc}
    );

    # Specific Fields: Insert details based on entry type
    if ($linetype eq 'Beer') {
        insert_beer_details($dbh, $brew_id, $rec->{style}, $rec->{subtype});
    } elsif ($linetype eq 'Wine') {
        insert_wine_details($dbh, $brew_id, $rec->{style});
    } elsif ($linetype eq 'Booze') {
        insert_booze_details($dbh, $brew_id, $rec->{geo}, $rec->{style});
    } elsif ($linetype eq 'Night' || $linetype eq 'Restaurant') {
        # No specific Brew details, just use Glass and Comment tables
        my $comment_text = $rec->{com} || "";
        my $refer_to = ($linetype eq 'Night') ? "Event" : "Location";
        insert_comment($dbh, $glass_id, $refer_to, $comment_text, undef, $rec->{rate});
    }

    # Debug print for each entry if $debug is set
    print "Processed $linetype entry with Glass ID: $glass_id\n" if $debug;

}

close($fh);

# Function to insert or retrieve a Name record
sub get_or_insert_name {
    my ($dbh, $name) = @_;
    return undef unless $name; # If name is empty, return undef

    # Check if the name already exists
    my $sth = $dbh->prepare("SELECT Id FROM NAMES WHERE Name = ?");
    $sth->execute($name);
    my ($id) = $sth->fetchrow_array;

    unless ($id) {
        # Insert new name if not found
        $sth = $dbh->prepare("INSERT INTO NAMES (Name) VALUES (?)");
        $sth->execute($name);
        $id = $dbh->last_insert_id(undef, undef, 'NAMES', 'Id');
    }

    print "Name ID: $id for '$name'\n" if $debug;
    return $id;
}

# Function to insert or retrieve a Brew record
sub get_or_insert_brew {
    my ($dbh, $name, $maker_id, $style) = @_;
    return undef unless $name; # If name is empty, return undef

    # Check if the brew already exists
    my $sth = $dbh->prepare("SELECT Id FROM BREWS WHERE Name = ? AND Producer IS ?");
    $sth->execute($name, $maker_id);
    my ($id) = $sth->fetchrow_array;

    unless ($id) {
        # Insert new brew if not found
        $sth = $dbh->prepare("INSERT INTO BREWS (Name, Producer, BrewStyle) VALUES (?, ?, ?)");
        $sth->execute($name, $maker_id, $style);
        $id = $dbh->last_insert_id(undef, undef, 'BREWS', 'Id');
    }

    print "Brew ID: $id for '$name' by Maker ID: " . ($maker_id // 'NULL') . "\n" if $debug;
    return $id;
}

# Function to insert a Glass record
sub insert_glass {
    my ($dbh, $username, $stamp, $location_id, $brew_id, $price, $volume, $alc) = @_;

    my $sth = $dbh->prepare(
        "INSERT INTO GLASSES (username, Timestamp, Location, Brew, Price, Volume, `Alc`)
         VALUES (?, ?, ?, ?, ?, ?, ?)"
    );
    $sth->execute($username, $stamp, $location_id, $brew_id, $price, $volume, $alc);
    my $id = $dbh->last_insert_id(undef, undef, 'GLASSES', 'Id');

    print "Inserted Glass with ID: $id\n" if $debug;
    return $id;
}

# Function to insert a Comment record
sub insert_comment {
    my ($dbh, $glass_id, $refer_to, $comment, $person_id, $rating) = @_;

    my $sth = $dbh->prepare(
        "INSERT INTO COMMENTS (Glass, ReferTo, Comment, Person, Rating)
         VALUES (?, ?, ?, ?, ?)"
    );
    $sth->execute($glass_id, $refer_to, $comment, $person_id, $rating);
    my $id = $dbh->last_insert_id(undef, undef, 'COMMENTS', 'Id');

    print "Inserted Comment with ID: $id\n" if $debug;
    return $id;
}

# Function to insert Beer-specific details
sub insert_beer_details {
    my ($dbh, $brew_id, $style, $flavor) = @_;

    my $sth = $dbh->prepare(
        "INSERT INTO BREWTYPE_BEER (Brew, Style, Flavors)
         VALUES (?, ?, ?)"
    );
    $sth->execute($brew_id, $style, $flavor);

    print "Inserted Beer details for Brew ID: $brew_id\n" if $debug;
}

# Function to insert Wine-specific details
sub insert_wine_details {
    my ($dbh, $brew_id, $region, $grape) = @_;

    my $sth = $dbh->prepare(
        "INSERT INTO BREWTYPE_WINE (Brew, Region)
         VALUES (?, ?)"
    );
    $sth->execute($brew_id, $region);

    print "Inserted Wine details for Brew ID: $brew_id\n" if $debug;
}

# Function to insert Booze-specific details
sub insert_booze_details {
    my ($dbh, $brew_id, $region, $flavor) = @_;

    my $sth = $dbh->prepare(
        "INSERT INTO BREWTYPE_BOOZE (Brew, Region, Flavor)
         VALUES (?, ?, ?)"
    );
    $sth->execute($brew_id, $region, $flavor);

    print "Inserted Booze details for Brew ID: $brew_id\n" if $debug;
}

