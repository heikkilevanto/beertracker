#!/usr/bin/perl -w

# Script to import old beerdata text files into sqlite
# Created with a lot of help from ChatGTP, and lots of cursing at its stupidity
#
# At stage 2: Getting ChatGPT to propose changes, but editing them in manually.
# Do not reproduce the script with GPT any more!


# TODO
#  - Drop NAMES. Make PERSONS and LOCATIONS, both pointing to ADDRESSES which
#    contain street and net addresses.
#  - Separate wine styles into country and region. Normalize country codes. Check duplicates.
#  - Get location details at least for the most common watering holes




use strict;
use warnings;
use DBI;


my $username = "heikki";  # Default username

# Database setup
my $dbh = DBI->connect("dbi:SQLite:dbname=beertracker.db", "", "", { RaiseError => 1, AutoCommit => 1 })
    or die $DBI::errstr;

#$dbh->trace(1);  # Log every SQL statement while debugging

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
    my $line = $_;
    print "$nlines: $line \n";
    next unless $line;          # Skip empty lines
    next if /^.?.?.?#/;             # Skip comment lines (with BOM)

    # Parse the line and map fields to $rec hash
    my @datafields = split(/ *; */, $line);
    my $linetype = $datafields[1]; # Determine the type (Beer, Wine, Booze, etc.)
    my $rec = {};
    my $fieldnamelist = $datalinetypes{$linetype} || "";
    my @fnames = @{$fieldnamelist};

    for (my $i = 0; $fieldnamelist->[$i]; $i++) {
        $rec->{$fieldnamelist->[$i]} = $datafields[$i] || "";
    }

    # Normalize old style geo
    $rec->{geo} =~ s/\[([0-9.]+)\/([0-9.]+)]/$1 $2/;

    if ( $line =~ /\Wcider\W/i ) {
      $linetype = "Cider" ;
      $rec->{style} =~ s/cider\W*//i; # don't repeat that in the style

    }


    # Pass the parsed record and line type to insert_data for processing
    insert_data($linetype, $rec);
}

close(F);

# Insert data into the database based on parsed fields and line type
sub insert_data {
    my ($type, $rec) = @_;


    # Begin transaction
    $dbh->do("BEGIN TRANSACTION");

    # Determine the location and brew IDs. Can be undef
    my $location_id = get_or_insert_location($rec->{loc}, undef, $rec->{geo});  # we don't know the addresses here
    my $brew_id     = get_or_insert_brew($rec->{name}, $rec->{maker}, $rec->{style}, $rec->{alc}, $type);

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
            person    => get_or_insert_person($rec->{people}) ,
            photo     => $rec->{photo},
        });
    }

    # Insert details into the relevant BREWTYPE table if applicable
    if ($type eq "Beer") {
        insert_brewtype_beer({
            brew_id    => $brew_id,
            style      => $rec->{style},
            flavors    => $rec->{subtype},
            country    => $rec->{subtype} =~ /^[A-Z]{2}$/ ? $rec->{subtype} : undef,
            alc        => $rec->{alc},
        });
    }
    elsif ($type eq "Cider") {
        insert_brewtype_cider({
            brew_id    => $brew_id,
            style      => $rec->{style},
            flavors    => $rec->{subtype},
            country    => $rec->{subtype} =~ /^[A-Z]{2}$/ ? $rec->{subtype} : undef,
            alc        => $rec->{alc},
        });
    }
    elsif ($type eq "Wine") {
        # Construct Region based on priority order: name, style, maker
        my @regions = grep { $_ } ($rec->{style}, $rec->{maker});
        my $region = shift @regions;
        insert_brewtype_wine({
            brew_id    => $brew_id,
            region     => $region,
            flavor     => join(", ", @regions) || undef,
            alc        => $rec->{alc},
        });
    }
    elsif ($type eq "Booze") {
        insert_brewtype_booze({
            brew_id    => $brew_id,
            style      => $rec->{subtype},
            region     => $rec->{style},
            alc        => $rec->{alc},
        });
    }
    # Handle additional specific types (Night, Restaurant) as needed
    # They get comments already, and don't seem to need Brewtype_x records for now
    elsif ($type eq "Restaurant" || $type eq "Night") {
    }
    else {
      die "Bad record type '$type' ";
    }


    $dbh->do("COMMIT");
}

# Helper to get or insert an address
sub get_or_insert_address {
    my ($address) = @_;
    my $address_id;

    # Don't insert empty addresses
    return undef unless $address;

    # Check if the address already exists
    my $sth_check = $dbh->prepare("SELECT Id FROM ADDRESSES WHERE StreetAddress = ?");
    $sth_check->execute($address);

    if ($address_id = $sth_check->fetchrow_array) {
        return $address_id;
    } else {
        # Insert new address if it doesn't exist
        my $sth_insert = $dbh->prepare("INSERT INTO ADDRESSES (StreetAddress) VALUES (?)");
        $sth_insert->execute($address);
        return $dbh->last_insert_id(undef, undef, "ADDRESSES", undef);
    }
}


# Helper to get or insert a Location record
sub get_or_insert_location {
    my ($location_name, $geo) = @_;

    return undef unless $location_name;

    # Check if the location already exists
    my $sth_check = $dbh->prepare("SELECT Id FROM LOCATIONS WHERE Name = ?");
    $sth_check->execute($location_name);

    if (my $location_id = $sth_check->fetchrow_array) {
        return $location_id;
    } else {
        # Insert new location record if it does not exist
        my $sth_insert = $dbh->prepare("INSERT INTO LOCATIONS (Name, GeoCoordinates) VALUES (?, ?)");
        $sth_insert->execute($location_name, $geo);
        return $dbh->last_insert_id(undef, undef, "LOCATIONS", undef);
    }
}

# Helper to get or insert a Person record
sub get_or_insert_person {
    my ($person_name) = @_;

    # Don't insert persons without names
    return undef unless $person_name;

    # Check if the person already exists
    my $sth_check = $dbh->prepare("SELECT Id FROM PERSONS WHERE Name = ?");
    $sth_check->execute($person_name);

    if (my $person_id = $sth_check->fetchrow_array) {
        return $person_id;
    } else {
        # Insert new person record if it does not exist
        my $sth_insert = $dbh->prepare("INSERT INTO PERSONS (Name) VALUES (?)");
        $sth_insert->execute($person_name);
        return $dbh->last_insert_id(undef, undef, "PERSONS", undef);
    }
}



# Helper to get or insert a Brew record
sub get_or_insert_brew {
    my ($name, $maker, $style, $alc, $type) = @_;
    return unless $name;
    my $id;

    # Check if the brew exists in the BREWS table
    my $sth = $dbh->prepare("SELECT Id FROM BREWS WHERE Name = ?");
    $sth->execute($name);
    if ($id = $sth->fetchrow_array) {
        # Update optional fields if missing in existing record
        my $update_sth = $dbh->prepare("UPDATE BREWS SET Producer = COALESCE(?, Producer), BrewStyle = COALESCE(?, BrewStyle), Alc = COALESCE(?, Alc), BrewType = COALESCE(?, BrewType) WHERE Id = ?");
        $update_sth->execute($maker, $style, $alc, $type, $id);
    } else {
        # Insert new brew record, including BrewType
        my $insert_sth = $dbh->prepare("INSERT INTO BREWS (Name, Producer, BrewStyle, Alc, BrewType) VALUES (?, ?, ?, ?, ?)");
        $insert_sth->execute($name, $maker, $style, $alc, $type);
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

    # Check if the 'substyle' is a two-letter country code
    my $country = ($data->{flavors} && $data->{flavors} =~ /^[A-Z]{2}$/) ? $data->{flavors} : undef;
    my $flavors = $country ? undef : $data->{flavors}; # Use substyle as flavor only if not a country code

    return unless $data->{style} || $flavors || $country;

    # Check if an identical record already exists
    my $sth_check = $dbh->prepare("SELECT 1 FROM BREWTYPE_BEER WHERE Brew = ? AND Style = ? AND Flavors = ? AND Country = ? ");
    $sth_check->execute($data->{brew_id}, $data->{style}, $flavors, $country);

    # If no record is found, proceed with the insertion
    unless ($sth_check->fetchrow_array) {
      my $sth_insert = $dbh->prepare("INSERT INTO BREWTYPE_BEER (Brew, Style, Flavors, Country) VALUES (?, ?, ?, ?)");
      $sth_insert->execute($data->{brew_id}, $data->{style}, $flavors, $country);
    }

}

# Helper to insert a BrewType record for Wine
sub insert_brewtype_wine {
    my ($data) = @_;
    return unless $data->{region} || $data->{flavor} || $data->{year} || $data->{classification};

    # Check if an identical record already exists
    my $sth_check = $dbh->prepare("SELECT 1 FROM BREWTYPE_WINE WHERE Brew = ? AND Region = ? AND Flavor = ? ");
    $sth_check->execute($data->{brew_id}, $data->{region}, $data->{flavor});

    # If no record is found, proceed with the insertion
    unless ($sth_check->fetchrow_array) {
        my $sth_insert = $dbh->prepare("INSERT INTO BREWTYPE_WINE (Brew, Region, Flavor) VALUES (?, ?, ? )");
        $sth_insert->execute($data->{brew_id}, $data->{region}, $data->{flavor});
    }
}

# Helper to insert a BrewType record for Cider
sub insert_brewtype_cider {
    my ($data) = @_;
    return unless $data->{country} || $data->{region} || $data->{flavor};
    # TODO - Check for dups
    my $sth = $dbh->prepare("INSERT INTO BREWTYPE_CIDER (Brew, Country, Region, Flavor) VALUES (?, ?, ?, ?)");
    $sth->execute($data->{brew_id}, $data->{country}, $data->{region}, $data->{flavor});
}

# Helper to insert a BrewType record for Booze
sub insert_brewtype_booze {
    my ($data) = @_;
    return unless $data->{style} || $data->{region} || $data->{age} || $data->{flavor};
    # TODO - Check for dups

    my $sth = $dbh->prepare("INSERT INTO BREWTYPE_BOOZE (Brew, Style, Country, Region, Age, Flavor) VALUES (?, ?, ?, ?, ?, ?)");
    $sth->execute($data->{brew_id}, $data->{style}, $data->{country}, $data->{region}, $data->{age}, $data->{flavor});
}

