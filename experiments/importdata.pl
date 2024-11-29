#!/usr/bin/perl -w

# Script to import old beerdata text files into sqlite
# Created with a lot of help from ChatGTP, and lots of cursing at its stupidity
#
# At stage 2: Getting ChatGPT to propose changes, but editing them in manually.
# Do not reproduce the script with GPT any more!


# TODO
#  - Separate wine styles into country and region. Normalize country codes. Check duplicates.
#  - Get location details at least for the most common watering holes
#  - Clean up the code. Similar parameter passing for all the insert_ functions



use strict;
use warnings;
use Data::Dumper;
use DBI;


my $username = $ARGV[0] || "heikki";

$| =  1; # Force perl to flush STDOUT after every write
# Database setup
my $databasefile = "../beerdata/beertracker.db";
die ("Database '$databasefile' not writable" ) unless ( -w $databasefile );

my $dbh = DBI->connect("dbi:SQLite:dbname=$databasefile", "", "", { RaiseError => 1, AutoCommit => 1 })
    or error($DBI::errstr);

# $dbh->trace(1);  # Log every SQL statement while debugging

# Define the path to the data file
#my $datafile = "../beerdata/$username.data";
# Read directly from production data, we don't have a local data file any more in dev
my $datafile = "../../beertracker/beerdata/$username.data";

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

my $onedrink = 33 * 4.6 ; # A regular danish beer, 33 cl at 4.6%


# Read the old type lines from the old file, in order to fix wine styles
my %winestyles;  # indexed by timestamp
sub readwines {
  if ( -r $oldfile ) {
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
    print "Got " . scalar(keys(%winestyles)) . " wine styles from $oldfile\n";
  }
}

sub readfile {
  # Open the data file
  open F, '<', $datafile or die("Could not open $datafile for reading: $!");
  print "Reading $datafile \n";

  my $nlines = 0;
  my $nrecords = 0;
  my $nfixes = 0;
  my $line;
  # Main logic: Read each line, parse, and send data for insertion
  while (<F>) {
      $nlines++;
      chomp;
      $line = $_;
      next unless $line;          # Skip empty lines
      next if /^.?.?.?#/;             # Skip comment lines (with BOM)
      #print sprintf("%6d: ", $nrecords), substr($line,0,100 ), " \n" if ($nrecords % 1000 == 0);
      print $nrecords/1000, " " if ($nrecords % 1000 == 0);

      # Parse the line and map fields to $rec hash
      my @datafields = split(/ *; */, $line);
      my $linetype = $datafields[1]; # Determine the type (Beer, Wine, Booze, etc.)
      my $rec = {};

      my $fieldnamelist = $datalinetypes{$linetype} || "";
      die ("Bad line (old format?) \n$line\n ") unless $fieldnamelist;
      my @fnames = @{$fieldnamelist};

      for (my $i = 0; $fieldnamelist->[$i]; $i++) {
          $rec->{$fieldnamelist->[$i]} = $datafields[$i] || "";
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
        $rec->{type} = "Cider";
        $rec->{style} =~ s/cider\W*//i; # don't repeat that in the style
      }

      my $fixstyle = $winestyles{ $rec->{stamp} };
      if ( $fixstyle && ! $rec->{style} ) {
        $rec->{style} = $fixstyle;
        $nfixes++;
      }

      if ( $linetype eq "Beer" ) { # We used to have country in the subtype
        $rec->{country} = $rec->{subtype};
        $rec->{subtype} = shortbeerstyle($rec->{style}) || "";
      } elsif ( $linetype eq "Wine" ) {  # Try to separate country, region, grapes, and such
        winestyle($rec);
      } elsif ( $linetype eq "Booze" ) {
        $linetype = "Spirit";
        $rec->{type} = $linetype;
        $rec->{subtype} =~ s/sc?h?napp?s/Snaps/i;
      }

      # Pre-calculate standard drinks
      #
      $rec->{stdrinks} = 0;
      $rec->{stdrinks} = sprintf("%6.2f", $rec->{alc} * $rec->{vol} / $onedrink)
        if ( (!$rec->{pr} || $rec->{pr} > 0 )   # Box wines can have neg price
          && $rec->{vol} && $rec->{vol} > 0  #
          && $rec->{alc} && $rec->{alc} > 0 );
      # Complain of really bad records
      die ("\n$line\n") unless $rec->{stamp};

      # Pass the parsed record and line type to insert_data for processing
      insert_data($linetype, $rec);
  }
  print "\n";
  close(F);

  print "\n";
  print "Got $nrecords records out of $nlines lines. Fixed $nfixes wines. Last line: \n";
  print "$line \n";
}

# Insert data into the database based on parsed fields and line type
sub insert_data {
    my ($type, $rec) = @_;


    # Begin transaction
    $dbh->do("BEGIN TRANSACTION");

    # Determine the location and brew IDs.
    my $location_id = get_or_insert_location($rec->{loc}, $rec->{geo});

    my $brew_id = get_or_insert_brew($rec);

    # Insert the GLASSES record itself
    my $insert_glass = $dbh->prepare("INSERT INTO GLASSES " .
        "(Username, Timestamp, Location, BrewType, SubType, Brew, Price, Volume, Alc, StDrinks) " .
        "VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)");
    $insert_glass->execute($username, $rec->{stamp}, $location_id, $type,  $rec->{subtype},
       $brew_id, $rec->{pr},  $rec->{vol}, $rec->{alc}, $rec->{stdrinks} );
    my $glass_id = $dbh->last_insert_id(undef, undef, "GLASSES", undef);

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
        my $insert_loc = $dbh->prepare("INSERT INTO LOCATIONS (Name, GeoCoordinates) VALUES (?, ?)");
        $insert_loc->execute($location_name, $geo);
        return $dbh->last_insert_id(undef, undef, "LOCATIONS", undef);
    }
}

# Helper to get or insert a Person record
sub get_or_insert_person {
    my ($person_name) = @_;

    # Don't insert persons without names
    return undef unless $person_name;
    $person_name =~ s/^D$/Dennis/i;

    # Check if the person already exists
    my $sth_check = $dbh->prepare("SELECT Id FROM PERSONS WHERE Name = ?");
    $sth_check->execute($person_name);

    if (my $person_id = $sth_check->fetchrow_array) {
        return $person_id;
    } else {
        # Insert new person record if it does not exist
        my $insert_person = $dbh->prepare("INSERT INTO PERSONS (Name) VALUES (?)");
        $insert_person->execute($person_name);
        return $dbh->last_insert_id(undef, undef, "PERSONS", undef);
    }
}



# Helper to get or insert a Brew record
# TODO - Pass $rec, insert year and region as well
# TODO - Check country and region in matching
sub get_or_insert_brew {
    my $rec = shift;
    my $id;
    my($prod, $sty, $al);

    # Skip some misc/misc records
    return undef if ( !$rec->{name}|| $rec->{name} =~ /misc/i );

    # Check if the brew exists in the BREWS table
    my $sql = q{
      SELECT
        Id, Producer, Brewstyle, Alc
      FROM BREWS
      WHERE Name = ?
      AND Producer = ?
      AND BrewType = ?
      AND (subtype = ? OR ( subtype is null and ? is null ) )
    };
    my $sth = $dbh->prepare($sql);
    $sth->execute($rec->{name}, $rec->{maker}, $rec->{type}, $rec->{subtype}, $rec->{subtype});
    if ( ($id, $prod, $sty, $al) = $sth->fetchrow_array) {
      # Found the brew, check optional fields
      if ( !$prod && $rec->{maker} )  {
        my $update_sth = $dbh->prepare("UPDATE BREWS SET Producer = ? WHERE Id = ?");
        $update_sth->execute($rec->{maker}, $id);
      }
      if ( !$sty && $rec->{style})  {
        my $update_sth = $dbh->prepare("UPDATE BREWS SET BrewStyle= ? WHERE Id = ?");
        $update_sth->execute($rec->{style}, $id);
      }
      if ( !$al && $rec->{alc})  {
        my $update_sth = $dbh->prepare("UPDATE BREWS SET Alc= ? WHERE Id = ?");
        $update_sth->execute($rec->{alc}, $id);
      }
    } else {
        # Insert new brew record
        my $insert_brew = $dbh->prepare(
            "INSERT INTO BREWS (Brewtype, SubType, Name, Producer, BrewStyle, Alc, Country, Region, Flavor, Year) " .
            "VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)");
        $insert_brew->execute($rec->{type}, $rec->{subtype}, $rec->{name},
          $rec->{maker}, $rec->{style}, $rec->{alc}, $rec->{country}||'', $rec->{region} ||'',
          $rec->{flavor} ||'', $rec->{year}||'');
        $id = $dbh->last_insert_id(undef, undef, "BREWS", undef);
    }
    return $id;
}



# Helper to insert a Comment record
my $insert_comment = $dbh->prepare("INSERT INTO COMMENTS (Glass, ReferTo, Comment, Rating, Person, Photo) VALUES (?, ?, ?, ?, ?, ?)");
sub insert_comment {
    my ($data) = @_;
    $insert_comment->execute($data->{glass_id}, $data->{refer_to}, $data->{comment}, $data->{rating}, $data->{person}, $data->{photo});
    return $dbh->last_insert_id(undef, undef, "COMMENTS", undef);
}

sub shortbeerstyle {
  my $sty = shift || "";
  return "" unless $sty;
  $sty =~ s/\b(Beer|Style)\b//i; # Stop words
  $sty =~ s/\W+/ /g;  # non-word chars, typically dashes
  $sty =~ s/\s+/ /g;  # multiple spaces etc
  if ( $sty =~ /(\WPA|Pale Ale)/i ) {
    return "APA"   if ( $sty =~ /America|US/i );
    return "BelPA" if ( $sty =~ /Belg/i );
    return "NEPA"  if ( $sty =~ /Hazy|Haze|New England|NE/i);
    return "PA";
  }
  if ( $sty =~ /(IPA|India)/i ) {
    return "SIPA"  if ( $sty =~ /Session/i);
    return "BIPA"  if ( $sty =~ /Black/i);
    return "DNE"   if ( $sty =~ /(Double|Triple).*(New England|NE)/i);
    return "DIPA"  if ( $sty =~ /Double|Dipa|Triple/i);
    return "WIPA"  if ( $sty =~ /Wheat/i);
    return "NEIPA" if ( $sty =~ /New England|NE|Hazy/i);
    return "NZIPA" if ( $sty =~ /New Zealand|NZ/i);
    return "WC"    if ( $sty =~ /West Coast|WC/i);
    return "AIPA"  if ( $sty =~ /America|US/i);
    return "IPA";
  }
  return "Dunk"  if ( $sty =~ /.*Dunkel.*/i);
  return "Bock"  if ( $sty =~ /Bock/i);
  return "Smoke" if ( $sty =~ /(Smoke|Rauch)/i);
  return "Lager" if ( $sty =~ /Lager|Keller|Pils|Zwickl|Altbier/i);
  return "Berl"  if ( $sty =~ /Berliner/i);
  return "Weiss" if ( $sty =~ /Hefe|Weizen|Hvede|Wit/i);
  return "Stout" if ( $sty =~ /Stout|Porter|Imperial/i);
  return "Farm"  if ( $sty =~ /Farm/i);
  return "Sais"  if ( $sty =~ /Saison/i);
  return "Dubl"  if ( $sty =~ /(Double|Dubbel)/i);
  return "Trip"  if ( $sty =~ /(Triple|Tripel|Tripple)/i);
  return "Quad"  if ( $sty =~ /(Quadruple|Quadrupel)/i);
  return "Trap"  if ( $sty =~ /Trappist/i);
  return "Blond" if ( $sty =~ /Blond/i);
  return "Brown" if ( $sty =~ /Brown/i);
  return "Strng" if ( $sty =~ /Strong/i);
  return "Belg"  if ( $sty =~ /Belg/i);
  return "BW"    if ( $sty =~ /Barley.*Wine/i);
  return "Sour"  if ( $sty =~ /Lambic|Gueuze|Sour|Kriek|Frmaboise/i);
  $sty =~ s/^ *([^ ]{1,5}).*/$1/; # First word, only five chars, in case we didn't get it above
  return ucfirst($sty);
}

# Try to extract country, region, grapes, vintage, etc from a style as entered
# in the old system.
sub winestyle {
  my $rec = shift;
  return unless $rec;
  $rec->{style} = "" unless ( $rec->{style} );
  my $sty = $rec->{style};
  if ($sty =~ /^misc/i ) {
    $rec->{style} = "";  # Drop the misc stuff
  }
  $rec->{style} =~ s/_//g; # Remove underscores
  $rec->{year} = $1
    if ( $rec->{style} =~ s/\b(20\d\d)\b// ); #Fails 1900's and 2100's Never mind
  my @countries = ( # Country, alt regexp, region...
    [ "Argentina" ],
    [ "Australia", "Australian" ],
    [ "Austria",   "Austrian" ],
    [ "Canada" ],
    [ "Chile" ],
    [ "France", "French", "Bordeaux", "Bourgogne", "Alsace", "Chateauneuf du Pape",
                          "Cotes du Rhone", "Haut.Medoc", "La Bourgondie", "Langedoc",
                          "Loire", "Pays d Oc", "Pomerol", "Rhone", "Saint Emillion",
                          "Champagne", "Chablis", "Corbieres", "Sancerre", "Anjou",
                          "Vouvray" ],
    [ "Germany", "German", "Mosel", "Pfalz" ],
    [ "Greece", "Greek" ],
    [ "Italy", "Italian", "Puglia", "Toscan.", "Valpolicella", "Verona",
                          "Abruzzo", "Piemonte", "Amarone",
                          "Alba", "Asti", "Barolo", "Brunello",
                          "Chianti", "Corsica", "Langhe", "Salice Salentino",
                          "Sicily", "Veneto", "Val di Neto" ],
    [ "New Zealand", "NZ" ],
    [ "Portugal", "Portugese", "Douro" ],
    [ "South Africa", "South African", "Stellenbosh" ],
    [ "Spain", "Spanish", "Rioja", "Priorat", "Ribera del Duero", "Gordoba",
                          "Sierra de Malaga", "Malaga", "Catalonia", "Navarra",
                          "Penedes", "Ronda", "Valdepenas"],
    [ "Switzerland", "Swiss", "Sudtirol" ],
    [ "United States", "US",  "California" ],
    [ "Mexico", "Mexican" ],
  );
  for my $c ( @countries ) {
    my @reg = @$c;
    # Check if a country matches
    if ( ( $rec->{style} =~ s/\b($reg[0])\b//i ) ||
           ( $reg[1] && $rec->{style} =~ s/\b($reg[1])\b//i ) ) {
      $rec->{country} = $reg[0];
    }
    # Check the region. May overwrite the country from above, but that is ok
    for ( my $i = 2; $reg[$i]; $i++ ) {
      if ( $rec->{style} =~ s/\b($reg[$i])\b//i ){
        $rec->{region} = $1;
        $rec->{country} = $reg[0];
        }
    }
  }
  my @grapes = (
    "Riesling", "Savignon Blanc", "Shiraz", "Merlot", "Barberra", "Malbec",
    "Cabernet Sauvignon", "Chardonnay Blanc", "Savignon Blanc", "Chardonnay", "Zinfandel",
    "Tempranillo", "Grenache", "Granach", "Primitivo", "Spätburgunder", "Syrah",
    "Negroamaro", "Pinotage", "Cinsault", "Tempranillo", "Muscat", "Chenin Blanc",
    "Pinot Noir", "Montepulciano", "Cabernet Franc",
    "Grun Veltliner", "Grün Veltliner", "Gruner Veltliner", "Grüner Veltliner",
    "Pinot Gris",
    "Cab Sav", "Cab-Sav", "Cab Sauv", "Sav Blanc",   # Common abbreviations
  );
  for my $g ( @grapes ) {
    $rec->{flavor} .= "$g, " if ( $rec->{style} =~ s/\b($g)\b//i );  # There can be more than one
  }
  if ( $rec->{flavor} ) {
    $rec->{flavor} =~ s/Cab[ -]+Sau?v/Cabernet Sauvignon/i ;
    $rec->{flavor} =~ s/Sav Blacn/Sauvignon Blacn/i ;
    $rec->{flavor} =~ s/Gr[uü]n(er?) Veltliner/Grüner Veltliner/i;
    $rec->{flavor} =~ s/[ ,]*$//; # trim
  }
  my @details = (
     # Classifications
     "Gran Reserva", "Reserva", "Crianza",
     "Riserva",
     "Grand Cru", "1er Cru",
     "Lbv",
     # Methods
     "Ripasso", "Spumante",
     # Other
     "Organic",
  );
  for my $d ( @details ) {
    $rec->{details} .= "$d " if ( $rec->{style} =~ s/\b($d)\b//i );  # There can be more than one
  }

  # Clean up what is left of the stype
  $rec->{style} =~ s/^\s*(d|di|de|dei)\s*$//;  # Remains of barb di asti etc
  $rec->{style} =~ s/^\W+//; # Trim non-word characters away
  $rec->{style} =~ s/\W+$//;
  $rec->{style} =~ s/\s+$/ /g; # And space sequences
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
# Remove cached graphs, since we have new data
system("rm -f ../beerdata/*png");