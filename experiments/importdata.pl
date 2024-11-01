#!/usr/bin/perl -w

# Script to import old beerdata text files into sqlite
# Created with a lot of help from ChatGTP, and lots of cursing at its stupidity
#
# At stage 2: Getting ChatGPT to propose changes, but editing them in manually.
# Do not reproduce the script with GPT any more!


# TODO
#  - Drop the BREWTYPE_X tables, collect the few relevant details directly into BREWS
#  - Separate wine styles into country and region. Normalize country codes. Check duplicates.
#  - Get location details at least for the most common watering holes



use strict;
use warnings;
use Data::Dumper;
use DBI;


my $username = "heikki";  # Default username
# Database setup
my $dbh = DBI->connect("dbi:SQLite:dbname=beertracker.db", "", "", { RaiseError => 1, AutoCommit => 1 })
    or die $DBI::errstr;

if ( $ARGV[0] ) {
  $dbh->trace(1);  # Log every SQL statement while debugging
}

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
    print STDERR "$nlines: $line \n" if ($nlines % 100 == 0);
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

    # TODO - Fix the wines
    # Old line
    # 2016-01-23 17:20:46; Wine; Sat; 2016-01-23; Home; red;    ; Santa Carolina;    ; 75; 14; 69; ; ; ; ;
    #  st                   ty    wd    eff       loc   sub mak    name          sty   vol  a   p
    # New line
    # 024-10-25 18:16:11; Wine; Fri; 2024-10-25; Home; White; Lenz Moser; Jubiläums Selection; Grüner Veltliner; 16; 12.5; ; ; ; 55.67; ;
    #  st                  ty    wd   eff         loc   sub    maker       name                  sty             v    a   p r c   geo  ph
    # Beer line
    # 2024-10-27 19:10:37; Beer; Sun; 2024-10-27; Ølbaren; Gamma; Orb; 25; IPA - New Zealand; 6.4; 48; ; ; ; DK; ;
    #  st                  ty    wd   eff         loc      maker  name  v   style             a    p  r c g sub ph
    #
    # So, in beer, we have a good style, and country code in sub
    # In new wine lines we have subtype and style right
    # In old wine lines we have subtype right, missing style
    # To make a beer line out of wine, swap sub and style

    # TODO Do this when calling get_or_insert_brew, redesign its parameters and get them from the right fields dep on type
    # TODO - But fix the wine data conversion first!




    # Pass the parsed record and line type to insert_data for processing
    insert_data($linetype, $rec);
}

close(F);

# Insert data into the database based on parsed fields and line type
sub insert_data {
    my ($type, $rec) = @_;


    # Begin transaction
    $dbh->do("BEGIN TRANSACTION");

    # Determine the location and brew IDs.
    my $location_id = get_or_insert_location($rec->{loc}, $rec->{geo});

    my $brew_id     = get_or_insert_brew($rec->{name}, $rec->{maker}, $rec->{style}, $rec->{alc}, $type);
    #                                 ($name, $maker, $style, $alc, $type)
    # type, style, country,


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
            photo     => $rec->{photo},
        });
    }
    # Insert a COMMENT record for every person mentioned
    if ($rec->{people}) {
        for my $pers ( split ( / *, */, $rec->{people} ) ) {
          insert_comment({
              glass_id  => $glass_id,
              refer_to  => $type,              # Use record type as ReferTo
              person    => get_or_insert_person($pers) ,
          });
        }
    }

    $dbh->do("COMMIT");
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
    my $id;

    $name = $type unless $name;  # for the "empty" glasses

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


