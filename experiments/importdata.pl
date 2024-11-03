#!/usr/bin/perl -w

# Script to import old beerdata text files into sqlite
# Created with a lot of help from ChatGTP, and lots of cursing at its stupidity
#
# At stage 2: Getting ChatGPT to propose changes, but editing them in manually.
# Do not reproduce the script with GPT any more!


# TODO
#  - Separate wine styles into country and region. Normalize country codes. Check duplicates.
#  - Short styles (subtype?) for beers
#  - Get location details at least for the most common watering holes
#  - Clean up the code. Similar parameter passing for all the insert_ functions



use strict;
use warnings;
use Data::Dumper;
use DBI;


my $username = $ARGV[0] || "heikki";

# Database setup
my $dbh = DBI->connect("dbi:SQLite:dbname=beertracker.db", "", "", { RaiseError => 1, AutoCommit => 1 })
    or die $DBI::errstr;

# $dbh->trace(1);  # Log every SQL statement while debugging

# Define the path to the data file
my $datafile = "../beerdata/$username.data";
my $oldfile = "./$username.data.OLD";


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



# Read the old type lines from the old file, in order to fix wine styles
my %winestyles;  # indexed by timestamp
sub readwines {
  if ( -r $oldfile ) {
    print "Reading old wine styles from $oldfile \n";
    open F, '<', $oldfile or die("Could not open $oldfile for reading: $!");
    while ( <F> ) {
      chomp();
      my $line = $_ ;
      next unless $line;          # Skip empty lines
      next if /^.?.?.?#/;             # Skip comment lines (with BOM)
      #print "$line \n";
      my @datafields = split(/ *; */, $line);
      my $stamp = $datafields[0];
      my $linetype = $datafields[1];
      my $winestyle = $datafields[7];
      if ( $linetype =~ /Mon|Tue|Wed|Thu|Fri|Sat|Sun/ &&   # Old style line
          $line =~ /wine/i  && # about wine
          $winestyle ) {
        $winestyles{$stamp} = $winestyle;
        #print "$line \n";
        #print "   got '$winestyle' \n";
      }
    }
    print "got " . scalar(keys(%winestyles)) . " wine styles \n";
  }
}

sub readfile {
  # Open the data file
  open F, '<', $datafile or die("Could not open $datafile for reading: $!");

  my $nlines = 0;
  my $nrecords = 0;
  my $nfixes = 0;
  # Main logic: Read each line, parse, and send data for insertion
  while (<F>) {
      $nlines++;
      chomp;
      my $line = $_;
      next unless $line;          # Skip empty lines
      next if /^.?.?.?#/;             # Skip comment lines (with BOM)
      print sprintf("%6d %6d: ", $nlines,$nrecords), "$line \n" if ($nrecords % 1000 == 0);

      # Parse the line and map fields to $rec hash
      my @datafields = split(/ *; */, $line);
      my $linetype = $datafields[1]; # Determine the type (Beer, Wine, Booze, etc.)
      my $rec = {};

      my $fieldnamelist = $datalinetypes{$linetype} || "";
      die ("Bad line (old format?) \n$line\n ") unless $fieldnamelist;
      my @fnames = @{$fieldnamelist};

      for (my $i = 0; $fieldnamelist->[$i]; $i++) {
          $rec->{$fieldnamelist->[$i]} = $datafields[$i] || undef;
      }

      # Check timestamp, confuses SqLite if impossible
      my ($yy,$mm,$dd, $ho,$mi,$se) = $rec->{stamp}=~/^(\d+)-(\d\d)-(\d\d) (\d\d+):(\d\d):(\d\d)$/;
      if ( !$yy || !$se ||  # didn't match
           length($yy) != 4 || $yy<2016 || $yy>2025 ||
           length($mm) != 2 || $mm<01 || $mm>12 ||
           length($dd) != 2 || $dd<01 || $dd>31 ||
           length($ho) != 2 || $ho<00 || $ho>23 ||
           length($mi) != 2 || $mi<00 || $mi>59 ||
           length($se) != 2 || $se<00 || $se>59 ) {
        print "Bad time stamp '$rec->{stamp}' in line $nlines record $nrecords\n";
        print "  '$yy' '$mm' '$dd'  '$ho' '$mi' '$se' \n";
        print "  $line\n";
        next;
      }
      $rec->{recordnumber} = ++$nrecords ;  # Remember for cross checking the code

      # Normalize old style geo
      $rec->{geo} =~ s/\[([0-9.]+)\/([0-9.]+)]/$1 $2/ if ($rec->{geo});
      $rec->{stamp} =~s/ ([0-9]:)/ 0$1/;  # Make sure we have leading zero in time
      if ( $line =~ /\Wcider\W/i ) {
        $linetype = "Cider" ;
        $rec->{style} =~ s/cider\W*//i; # don't repeat that in the style
      }

      my $fixstyle = $winestyles{ $rec->{stamp} };
      if ( $fixstyle && ! $rec->{style} ) {
        $rec->{style} = $fixstyle;
        $nfixes++;
      }

      if ( $linetype eq "Beer" ) { # We used to have country in the subtype
        $rec->{country} = $rec->{subtype};
        $rec->{subtype} = undef;
      }

      # Complain of really bad records
      die ("Record without stamp at line $nlines\n$line\n") unless $rec->{stamp};

      # Pass the parsed record and line type to insert_data for processing
      insert_data($linetype, $rec);
  }

  close(F);

  print "\n";
  printf ("%5d lines read\n", $nlines);
  printf ("%5d records\n", $nrecords);
  printf ("%5d wine fixes\n", $nfixes);
}

# Insert data into the database based on parsed fields and line type
sub insert_data {
    my ($type, $rec) = @_;


    # Begin transaction
    $dbh->do("BEGIN TRANSACTION");

    # Determine the location and brew IDs.
    my $location_id = get_or_insert_location($rec->{loc}, $rec->{geo});

    my $brew_id = get_or_insert_brew($type, $rec->{subtype}, $rec->{name},
       $rec->{maker}, $rec->{style}, $rec->{alc}, $rec->{country});


    # Insert a GLASS record with common fields
    my $glass_id = insert_glass({
        username     => $username,
        timestamp    => $rec->{stamp},
        recordnumber => $rec->{recordnumber},
        type         => $type,
        location     => $location_id,
        brew         => $brew_id,
        price        => $rec->{pr},
        volume       => $rec->{vol},
        alc          => $rec->{alc},
    });

    # Insert a COMMENT record if there is a 'com' field
    if ($rec->{com}||$rec->{photo}) {
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
my $insert_loc = $dbh->prepare("INSERT INTO LOCATIONS (Name, GeoCoordinates) VALUES (?, ?)");
sub get_or_insert_location {
    my ($location_name, $geo) = @_;

    return undef unless $location_name;

    # Check if the location already exists
    my $sth_check = $dbh->prepare("SELECT Id, GeoCoordinates FROM LOCATIONS WHERE Name = ?");
    $sth_check->execute($location_name);

    if (my ($location_id, $old_geo) = $sth_check->fetchrow_array) {
        if (!$old_geo && $geo) {
          my $usth = $dbh->prepare("UPDATE LOCATIONS ".
            "set GeoCoordinates = ? " .
            "where id = ? ");
          $usth->execute($geo, $location_id);
        }
        return $location_id;
    } else {  # Insert new location record if it does not exist
        $insert_loc->execute($location_name, $geo);
        return $dbh->last_insert_id(undef, undef, "LOCATIONS", undef);
    }
}

# Helper to get or insert a Person record
my $insert_person = $dbh->prepare("INSERT INTO PERSONS (Name) VALUES (?)");
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
        $insert_person->execute($person_name);
        return $dbh->last_insert_id(undef, undef, "PERSONS", undef);
    }
}



# Helper to get or insert a Brew record
my $insert_brew = $dbh->prepare("INSERT INTO BREWS (Brewtype, SubType, Name, Producer, BrewStyle, Alc, Country) VALUES (?, ?, ?, ?, ?, ?, ?)");
sub get_or_insert_brew {
    my ($type, $subtype, $name, $maker, $style, $alc, $country) = @_;
    my $id;
    my($prod, $sty, $al);
    # Check if the brew exists in the BREWS table
    my $sth = $dbh->prepare("SELECT Id, Producer, Brewstyle, Alc FROM BREWS WHERE Name = ? and BrewType = ? ".
        " and (subtype = ? OR ( subtype is null and ? is null )) ");
    $sth->execute($name, $type, $subtype, $subtype);
    if ( ($id, $prod, $sty, $al) = $sth->fetchrow_array) {
      if ( !$prod || !$sty || !$al )  {
        my $update_sth = $dbh->prepare("UPDATE BREWS ".
            "SET Producer = COALESCE(?, Producer), BrewStyle = COALESCE(?, BrewStyle), ".
            "Alc = COALESCE(?, Alc)  WHERE Id = ?");
        $update_sth->execute($maker, $style, $alc, $id);
      }
      if ( !$prod && $maker )  {
        my $update_sth = $dbh->prepare("UPDATE BREWS SET Producer = ? WHERE Id = ?");
        $update_sth->execute($maker, $id);
      }
      if ( !$sty && $style)  {
        my $update_sth = $dbh->prepare("UPDATE BREWS SET BrewStyle= ? WHERE Id = ?");
        $update_sth->execute($style, $id);
      }
      if ( !$al && $alc)  {
        my $update_sth = $dbh->prepare("UPDATE BREWS SET Alc= ? WHERE Id = ?");
        $update_sth->execute($alc, $id);
      }
    } else {
        # Insert new brew record
        $insert_brew->execute($type, $subtype, $name, $maker, $style, $alc, $country);
        $id = $dbh->last_insert_id(undef, undef, "BREWS", undef);
    }
    return $id;
}

# Helper to insert a Glass record
my $insert_glass = $dbh->prepare("INSERT INTO GLASSES " .
  "(Username, Timestamp, Location, BrewType, Brew, Price, Volume, Alc, RecordNumber) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)");
sub insert_glass {
    my ($data) = @_;
    $insert_glass->execute($data->{username}, $data->{timestamp}, $data->{location}, $data->{type}, $data->{brew}, $data->{price},
       $data->{volume}, $data->{alc}, $data->{recordnumber});
    return $dbh->last_insert_id(undef, undef, "GLASSES", undef);
}


# Helper to insert a Comment record
my $insert_comment = $dbh->prepare("INSERT INTO COMMENTS (Glass, ReferTo, Comment, Rating, Person, Photo) VALUES (?, ?, ?, ?, ?, ?)");
sub insert_comment {
    my ($data) = @_;
    $insert_comment->execute($data->{glass_id}, $data->{refer_to}, $data->{comment}, $data->{rating}, $data->{person}, $data->{photo});
    return $dbh->last_insert_id(undef, undef, "COMMENTS", undef);
}


############
# Main program

# Insert known geo coords for my home
# They tend to be far away from the actual location, esp on my desktop machine
# Note the trailing spaces to make the names different. The UI will strip those
get_or_insert_location("Home ", "55.6588 12.0825"); # Special case for FF.
get_or_insert_location("Home  ", "55.6531712 12.5042688"); # Chrome
get_or_insert_location("Home   ", "55.6717389 12.5563058"); # Chrome on my phone

readwines();
readfile();
$dbh->disconnect();
