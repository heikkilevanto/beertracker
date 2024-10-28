#!/usr/bin/perl

# Script to import old beerdata text files into sqlite
# Created with a lot of help from ChatGTP, and lots of cursing at its stupidity

# TODO  (run out of ChatGpt tokens again)
#   - Forget all about the diagrams
#   - Any kind of line can have comments. Insert them so they refer to the proper GLASS record
#   - If a line has "people" field, insert it as a Person in the comments table
#   - Add effdate to the Glass record
#   - Add geo into names.Geocoordinates
#   - When checking a NAME, if we have geo coords, and the record does not, update the geocoordinates
#   - Get alc also into brew.alc
#   - BrewStyle should come from Style in the data
#   - If there is no data to insert in the brew details, do not create a record.
#   - Brewtype_wine should get something into Region. Check name, style, and maker in
#     that order, and take the first non-empty. If more than one set, put the rest into Region
#   - Refactor all the insert calls into a function called insert_record
# DONE so far. run out of tokens again

#   - The record type should go int Comment.ReferTo and Brews.BrewType
#   - Brewtype_wine should use Year instead of Vintage
#   - In Beer records, if the substyle is a two letter code, put it into country
#   - Do not insert brewtype records if we already have a matching one. Case-insensitive
#   - Normalize geo: remove enclosing "[]" and replace "/" with a space
#   - What would be the consequences of adding BEGIN TRANSACTION and COMMIT at insert_record

# TODO Problems I have seen
#   - Too many "Misc" brews
#   - Wine names and styles in older records
#   - No booze types

# TODO Later, in a separate (manual?) step. Probably once I have imported the data
#   - Separate wine styles into country and region. Normalize country codes
#   - Get location details at least for the most common watering holes




use strict;
use warnings;
use DBI;



my $debug = 1;  # Does not seem to slow down too much
my $username = "heikki";  # Default username


# Database setup
my $dbh = DBI->connect("dbi:SQLite:dbname=beertracker.db", "", "", { RaiseError => 1, AutoCommit => 1 })
    or die $DBI::errstr;

# Define the path to the data file
my $datafile = "../beerdata/heikki.data";

# Define data types
my %datalinetypes = (
    "Beer"       => ["stamp", "type", "wday", "effdate", "loc", "maker", "name",
                     "vol", "style", "alc", "pr", "rate", "com", "geo", "subtype", "photo"],
    "Wine"       => ["stamp", "type", "wday", "effdate", "loc", "subtype", "maker",
                     "name", "style", "vol", "alc", "pr", "rate", "com", "geo", "photo"],
    "Booze"      => ["stamp", "type", "wday", "effdate", "loc", "subtype", "maker",
                     "name", "style", "vol", "alc", "pr", "rate", "com", "geo", "photo"],
    "Night"      => ["stamp", "type", "wday", "effdate", "loc", "subtype", "com",
                     "people", "geo", "photo"],
    "Restaurant" => ["stamp", "type", "wday", "effdate", "loc", "subtype", "rate",
                     "pr", "food", "people", "com", "geo", "photo"],
);


# Open the data file
open F, '<', $datafile or die("Could not open $datafile for reading: $!");
my $nlines = 0;

# Main logic: Read each line, parse, and send data for insertion
while (<F>) {
    $nlines++;
    chomp;
    print "$nlines: $_ \n";
    next unless $_;                 # Skip empty lines
    next if /^.?.?.?#/;             # Skip comment lines (with BOM)

    # Parse the line and map fields to $rec hash
    my @datafields = split(/ *; */, $_);
    my $linetype = $datafields[1]; # Determine the type (Beer, Wine, Booze, etc.)
    my $rec = {};
    my $fieldnamelist = $datalinetypes{$linetype} || "";
    my @fnames = @{$fieldnamelist};

    for (my $i = 0; $fieldnamelist->[$i]; $i++) {
        $rec->{$fieldnamelist->[$i]} = $datafields[$i] || "";
    }

    # Pass the parsed record and line type to insert_data for processing
    insert_data($linetype, $rec);
}

close(F);

# Insert data into the database based on parsed fields and line type
sub insert_data {
    my ($type, $rec) = @_;

    # Determine the location and brew IDs, if provided
    my $location_id = $rec->{loc} ? get_or_insert_name($rec->{loc}, $rec->{geo}) : undef;
    my $brew_id     = $rec->{name} ? get_or_insert_brew($rec->{name}, $rec->{maker}, $rec->{style}, $rec->{alc}) : undef;

    # Insert a GLASS record with common fields
    my $glass_id = insert_glass({
        username    => $username,
        timestamp   => $rec->{stamp},
        location    => $location_id,
        brew        => $brew_id,
        price       => $rec->{pr},
        volume      => $rec->{vol},
        alc         => $rec->{alc},
        effdate     => $rec->{effdate},
    });

    # Insert a COMMENT record if there is a 'com' field
    if ($rec->{com}) {
        insert_comment({
            glass_id  => $glass_id,
            refer_to  => $type,              # Use record type as ReferTo
            comment   => $rec->{com},
            rating    => $rec->{rate},
            person    => $rec->{people} ? get_or_insert_name($rec->{people}) : undef,
            photo     => $rec->{photo},
        });
    }

    # Insert details into the relevant BREWTYPE table if applicable
    if ($type eq "Beer" && ($rec->{style} || $rec->{subtype} || $rec->{alc})) {
        insert_brewtype_beer({
            brew_id    => $brew_id,
            style      => $rec->{style},
            flavors    => $rec->{subtype},
            country    => $rec->{subtype} =~ /^[A-Z]{2}$/ ? $rec->{subtype} : undef,
            alc        => $rec->{alc},
        });
    }
    elsif ($type eq "Wine") {
        # Construct Region based on priority order: name, style, maker
        my @regions = grep { $_ } ($rec->{name}, $rec->{style}, $rec->{maker});
        my $region = shift @regions;
        insert_brewtype_wine({
            brew_id    => $brew_id,
            region     => $region,
            other_regions => join(", ", @regions) || undef,
            alc        => $rec->{alc},
        });
    }
    elsif ($type eq "Booze" && ($rec->{style} || $rec->{subtype} || $rec->{alc})) {
        insert_brewtype_booze({
            brew_id    => $brew_id,
            subtype    => $rec->{subtype},
            style      => $rec->{style},
            alc        => $rec->{alc},
        });
    }

    # Handle additional specific types (Night, Restaurant) as needed
    if ($type eq "Night" || $type eq "Restaurant") {
        # Additional logic for Night or Restaurant types if needed
    }
}



# Helper to get or insert a Name record (location or person)
sub get_or_insert_name {
    my ($name, $geo) = @_;
    my $id;

    # Check if the name exists in NAMES table
    my $sth = $dbh->prepare("SELECT Id, GeoCoordinates FROM NAMES WHERE Name = ?");
    $sth->execute($name);
    if (my $row = $sth->fetchrow_hashref) {
        $id = $row->{Id};

        # Update GeoCoordinates if geo is provided and empty in the existing record
        if ($geo && !$row->{GeoCoordinates}) {
            my $update_sth = $dbh->prepare("UPDATE NAMES SET GeoCoordinates = ? WHERE Id = ?");
            $update_sth->execute($geo, $id);
        }
    } else {
        # Insert new name record if it does not exist
        my $insert_sth = $dbh->prepare("INSERT INTO NAMES (Name, GeoCoordinates) VALUES (?, ?)");
        $insert_sth->execute($name, $geo);
        $id = $dbh->last_insert_id(undef, undef, "NAMES", undef);
    }
    return $id;
}

# Helper to get or insert a Brew record
sub get_or_insert_brew {
    my ($name, $maker, $style, $alc) = @_;
    my $id;

    # Check if the brew exists in BREWS table
    my $sth = $dbh->prepare("SELECT Id FROM BREWS WHERE Name = ?");
    $sth->execute($name);
    if ($id = $sth->fetchrow_array) {
        # Update optional fields if missing in existing record
        my $update_sth = $dbh->prepare("UPDATE BREWS SET Producer = COALESCE(?, Producer), BrewStyle = COALESCE(?, BrewStyle), Alc = COALESCE(?, Alc) WHERE Id = ?");
        $update_sth->execute($maker, $style, $alc, $id);
    } else {
        # Insert new brew record
        my $insert_sth = $dbh->prepare("INSERT INTO BREWS (Name, Producer, BrewStyle, Alc) VALUES (?, ?, ?, ?)");
        $insert_sth->execute($name, $maker, $style, $alc);
        $id = $dbh->last_insert_id(undef, undef, "BREWS", undef);
    }
    return $id;
}

# Helper to insert a Glass record
sub insert_glass {
    my ($data) = @_;
    my $sth = $dbh->prepare("INSERT INTO GLASSES (Username, Timestamp, Location, Brew, Price, Volume, Alc, Effdate) VALUES (?, ?, ?, ?, ?, ?, ?, ?)");
    $sth->execute($data->{username}, $data->{timestamp}, $data->{location}, $data->{brew}, $data->{price}, $data->{volume}, $data->{alc}, $data->{effdate});
    return $dbh->last_insert_id(undef, undef, "GLASSES", undef);
}

# Helper to insert a Comment record
sub insert_comment {
    my ($data) = @_;
    my $sth = $dbh->prepare("INSERT INTO COMMENTS (Glass, ReferTo, Comment, Rating, Person, Photo) VALUES (?, ?, ?, ?, ?, ?)");
    $sth->execute($data->{glass_id}, $data->{refer_to}, $data->{comment}, $data->{rating}, $data->{person}, $data->{photo});
    return $dbh->last_insert_id(undef, undef, "COMMENTS", undef);
}

# Helper to insert a BrewType record for Beer
sub insert_brewtype_beer {
    my ($data) = @_;
    return unless $data->{style} || $data->{flavors} || $data->{ibu} || $data->{color} || $data->{year} || $data->{batch_number};

    my $sth = $dbh->prepare("INSERT INTO BREWTYPE_BEER (Brew, Style, Flavors, IBU, Color, Year, BatchNumber) VALUES (?, ?, ?, ?, ?, ?, ?)");
    $sth->execute($data->{brew_id}, $data->{style}, $data->{flavors}, $data->{ibu}, $data->{color}, $data->{year}, $data->{batch_number});
}

# Helper to insert a BrewType record for Wine
sub insert_brewtype_wine {
    my ($data) = @_;
    return unless $data->{region} || $data->{flavor} || $data->{vintage} || $data->{classification};

    my $sth = $dbh->prepare("INSERT INTO BREWTYPE_WINE (Brew, Region, Flavor, Year, Classification) VALUES (?, ?, ?, ?, ?)");
    $sth->execute($data->{brew_id}, $data->{region}, $data->{flavor}, $data->{vintage}, $data->{classification});
}

# Helper to insert a BrewType record for Cider
sub insert_brewtype_cider {
    my ($data) = @_;
    return unless $data->{country} || $data->{region} || $data->{flavor};

    my $sth = $dbh->prepare("INSERT INTO BREWTYPE_CIDER (Brew, Country, Region, Flavor) VALUES (?, ?, ?, ?)");
    $sth->execute($data->{brew_id}, $data->{country}, $data->{region}, $data->{flavor});
}

# Helper to insert a BrewType record for Booze
sub insert_brewtype_booze {
    my ($data) = @_;
    return unless $data->{country} || $data->{region} || $data->{age} || $data->{flavor};

    my $sth = $dbh->prepare("INSERT INTO BREWTYPE_BOOZE (Brew, Country, Region, Age, Flavor) VALUES (?, ?, ?, ?, ?)");
    $sth->execute($data->{brew_id}, $data->{country}, $data->{region}, $data->{age}, $data->{flavor});
}

