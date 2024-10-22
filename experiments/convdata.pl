#!/usr/bin/perl -w

# Convert the beer tracker data file to the new format
#
# Reads the data file, and produces a new one, where all the "Old" type
# records have been replaced by more modern record types.




################################################################################
# Modules and UTF-8 stuff
################################################################################
use strict;
use POSIX qw(strftime localtime locale_h);
use JSON;
use Cwd qw(cwd);
use File::Copy;

use feature 'unicode_strings';
use utf8;  # Source code and string literals are utf-8

use locale; # The data file can contain locale overrides
setlocale(LC_COLLATE, "da_DK.utf8"); # but dk is the default
setlocale(LC_CTYPE, "da_DK.utf8");

use open ':encoding(UTF-8)';  # Data files are in utf-8
binmode STDOUT, ":utf8"; # Stdout only. Not STDIN, the CGI module handles that

my $onedrink = 33 * 4.6 ; # A regular danish beer, 33 cl at 4.6%



################################################################################
# Constants and setup
################################################################################

# Data line types - These define the field names on the data line for that type
# as well as which input fields will be visible.
my %datalinetypes;
# Pseudo-type "None" indicates a line not worth saving, f.ex. no beer on it

my %subtypes;

# The old style lines with no type.
$datalinetypes{"Old"} = [
  "stamp",  # Time stamp, as in "yyyy-mm-dd hh:mm:ss"
  "wday",   # Weekday, "Mon" to "Sun"
  "effdate",# Effective date "yyyy-mm-dd". Beers after midnight count as the night before. Changes at 08.
  "loc",    # Location
  "mak",    # Maker, or brewer
  "beer",   # Name of the beer
  "vol",    # Volume, in cl
  "sty",    # Style of the beer
  "alc",    # Alcohol percentage, with one decimal
  "pr",     # Price in default currency, in my case DKK
  "rate",   # Rating
  "com",    # Comment
  "geo"];   # Geo coordinates

# A dedicated beer entry. Almost like above. But with a type and subtype
$datalinetypes{"Beer"} = [
  "stamp", "type", "wday", "effdate", "loc",
  "maker",  # Brewery
  "name",   # Name of the beer
  "vol", "style", "alc", "pr", "rate", "com", "geo",
  "subtype", # Taste of the beer, could be fruits, special hops, or type of barrel
  "photo" ]; # Image file name

# Wine
$datalinetypes{"Wine"} = [ "stamp", "type", "wday", "effdate", "loc",
  "subtype", # Red, White, Bubbly, etc
  "maker", # brand or house
  "name", # What it says on the label
  "style", # Can be grape (chardonnay) or country/region (rioja)
  "vol", "alc", "pr", "rate", "com", "geo", "photo"];

# Booze. Also used for coctails
$datalinetypes{"Booze"} = [ "stamp", "type", "wday", "effdate", "loc",
  "subtype",   # whisky, snaps
  "maker", # brand or house
  "name",  # What it says on the label
  "style", # can be coctail, country/(region, or flavor
  "vol", "alc",  # These are for the alcohol itself
  "pr", "rate", "com", "geo", "photo"];


# A comment on a night out.
$datalinetypes{"Night"} = [ "stamp", "type", "wday", "effdate", "loc",
  "subtype",# bar discussion, concert, lunch party, etc
  "com",    # Any comments on the night
  "people", # Who else was here
  "geo", "photo" ];

# Restaurants and bars
$datalinetypes{"Restaurant"} = [ "stamp", "type", "wday", "effdate", "loc",
  "subtype",  # Type of restaurant, "Thai"
  "rate", "pr", # price for the night, per person
  "food",   # Food and drink
  "people",
  "com", "geo",
  "photo"];



################################################################################
# Convert the data
################################################################################

#my $datafile = "../beerdata/heikki.data";
my $datafile = $ARGV[0];
die ("Can not read '$datafile' \n") unless ( -r $datafile );

my $nlines = 0;
my $ncom = 0;
open F, "<$datafile"
  or error("Could not open $datafile for reading: $!".
    "<br/>Probably the user hasn't been set up yet" );

while (<F>) {
  chomp();
  next unless $_; # skip empty lines
  if ( /^[^0-9a-z]*#(20)?/i ) {
    print "$_\n";
    $ncom++;
    next;
  }
  my $rec = parseline($_);
  my $n = makeline($rec);
  $nlines++;
  print "$n\n";
}
close(F);
print STDERR "Processed $nlines records, $ncom comment lines\n";
exit();



################################################################################
# Various small helpers
################################################################################

# Helper to trim leading and trailing spaces
sub trim {
  my $val = shift || "";
  $val =~ s/^ +//; # Trim leading spaces
  $val =~ s/ +$//; # and trailing
  $val =~ s/\s+/ /g; # and repeated spaces in the middle
  return $val;
}



# Helper to sanitize numbers
sub number {
  my $v = shift || "";
  $v =~ s/,/./g;  # occasionally I type a decimal comma
  $v =~ s/[^0-9.-]//g; # Remove all non-numeric chars
  $v =~ s/-$//; # No trailing '-', as in price 45.-
  $v =~ s/\.$//; # Nor trailing decimal point
  $v = 0 unless $v;
  return $v;
}

# Sanitize prices to whole ints
sub price {
  my $v = shift || "";
  $v = number($v);
  $v =~ s/[^0-9-]//g; # Remove also decimal points etc
  return $v;
}


# Helper to make an error message
sub error {
  my $msg = shift;
  die($msg);
}


# Helper to make a seenkey, an index to %lastseen and %seen
# Normalizes the names a bit, to catch some misspellings etc
sub seenkey {
  my $rec= shift;
  my $maker;
  my $name = shift;
  my $key;
  if (ref($rec)) {
    $maker = $rec->{maker} || "";
    $name = $rec->{name} || "";
    if ($rec->{type} eq "Beer") {
      $key = "$rec->{maker}:$rec->{name}"; # Needs to match m:b in beer board etc
    } elsif ( $rec->{type} =~ /Restaurant|Night/ ) {
      $key = "$rec->{type}:$rec->{loc}";  # We only have loc to match (and subkey?)
    } elsif ( $rec->{name} && $rec->{subkey} ) {  # Wine and booze: Wine:Red:Foo
      $key = "$rec->{type}:$rec->{subkey}:$rec->{name}";
    } elsif ( $rec->{name} ) {  # Wine and booze: Wine::Mywine
      $key = "$rec->{type}::$rec->{name}";
    } else { # TODO - Not getting keys for many records !!!
      #print STDERR "No seenkey for $rec->{rawline} \n";
      return "";  # Nothing to make a good key from
    }
  } else { # Called  the old way, like for beer board
    $maker = $rec;
    $key = "$maker:$name";
    #return "" if ( !$maker && !$name );
  }
  $key = lc($key);
  return "" if ( $key =~ /misc|mixed/ );
  $key =~ s/&amp;/&/g;
  $key =~ s/[^a-zåæø0-9:]//gi;  # Skip all special characters and spaces
  return $key;
}


# Helper to shorten a beer style
sub shortbeerstyle {
  my $sty = shift;
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
    return "SIPA" if ( $sty =~ /Session/i);
    return "BIPA" if ( $sty =~ /Black/i);
    return "DNE"  if ( $sty =~ /(Double|Triple).*(New England|NE)/i);
    return "DIPA" if ( $sty =~ /Double|Dipa/i);
    return "WIPA" if ( $sty =~ /Wheat/i);
    return "NEIPA" if ( $sty =~ /New England|NE|Hazy/i);
    return "NZIPA" if ( $sty =~ /New Zealand|NZ/i);
    return "WC"   if ( $sty =~ /West Coast|WC/i);
    return "AIPA" if ( $sty =~ /America|US/i);
    return "IPA";
  }
  return "IL"   if ( $sty =~ /India Lager/i);
  return "Lag"  if ( $sty =~ /Pale Lager/i);
  return "Kel"  if ( $sty =~ /^Keller.*/i);
  return "Pils" if ( $sty =~ /.*(Pils).*/i);
  return "Hefe" if ( $sty =~ /.*Hefe.*/i);
  return "Wit"  if ( $sty =~ /.*Wit.*/i);
  return "Dunk" if ( $sty =~ /.*Dunkel.*/i);
  return "Wbock" if ( $sty =~ /.*Weizenbock.*/i);
  return "Dbock" if ( $sty =~ /.*Doppelbock.*/i);
  return "Bock" if ( $sty =~ /.*[^DW]Bock.*/i);
  return "Smoke" if ( $sty =~ /.*(Smoke|Rauch).*/i);
  return "Berl" if ( $sty =~ /.*Berliner.*/i);
  return "Imp"  if ( $sty =~ /.*(Imperial).*/i);
  return "Stout" if ( $sty =~ /.*(Stout).*/i);
  return "Port"  if ( $sty =~ /.*(Porter).*/i);
  return "Farm" if ( $sty =~ /.*Farm.*/i);
  return "Saison" if ( $sty =~ /.*Saison.*/i);
  return "Dubl" if ( $sty =~ /.*(Double|Dubbel).*/i);
  return "Trip" if ( $sty =~ /.*(Triple|Tripel|Tripple).*/i);
  return "Quad" if ( $sty =~ /.*(Quadruple|Quadrupel).*/i);
  return "Blond" if ( $sty =~ /Blond/i);
  return "Brown" if ( $sty =~ /Brown/i);
  return "Strong" if ( $sty =~ /Strong/i);
  return "Belg" if ( $sty =~ /.*Belg.*/i);
  return "BW"   if ( $sty =~ /.*Barley.*Wine.*/i);
  $sty =~ s/.*(Lambic|Sour) *(\w+).*/$1/i;   # Lambic Fruit - Fruit
  $sty =~ s/.*\b(\d+)\b.*/$1/i; # Abt 12 -> 12 etc
  $sty =~ s/^ *([^ ]{1,6}).*/$1/; # Only six chars, in case we didn't get it above
  return $sty;
}

# Check that the record has a short style
sub checkshortstyle {
  my $rec = shift;
  return unless $rec;
  return unless ( $rec->{style} );
  return if $rec->{shortstyle}; # already have it
  $rec->{shortstyle} = shortbeerstyle($rec->{style});
}


# Split a data line into a hash. Precalculate some fields
sub splitline {
  my $line = shift;
  my @datafields = split(/ *; */, $line);
  my $linetype = $datafields[1]; # This is either the type, or the weekday for old format lines (or comment)
  my $v = {};
  return $v unless ($linetype); # Can be an empty line, BOM mark, or other funny stuff
  return $v if ( $line =~/^#/ ); # skip comment lines
  $linetype =~ s/(Mon|Tue|Wed|Thu|Fri|Sat|Sun)/Old/i; # If we match a weekday, we have an old-format line with no type
  $v->{type} = $linetype; # Likely to be overwritten below, this is just in case (Old)
  $v->{rawline} = $line; # for filtering
  $v->{name} = ""; # Default, make sure we always have something
  $v->{maker} = "";
  $v->{style} = "";
  my $fieldnamelist = $datalinetypes{$linetype} || "";
  if ( $fieldnamelist ) {
    my @fnames = @{$fieldnamelist};
    for ( my $i = 0; $fieldnamelist->[$i]; $i++ ) {
      $v->{$fieldnamelist->[$i]} = $datafields[$i] || "";
    }
  } else {
    error ("Unknown line type '$linetype' in $line");
  }
  # Normalize some common fields
  $v->{alc} = number( $v->{alc} );
  $v->{vol} = number( $v->{vol} );
  $v->{pr} = price( $v->{pr} );
  # Precalculate some things we often need
  ( $v->{date}, $v->{year}, $v->{time} ) = $v->{stamp} =~ /^(([0-9]+)[0-9-]+) +([0-9:]+)/;
  my $alcvol = $v->{alc} * $v->{vol} || 0 ;
  $alcvol = 0 if ( $v->{pr} < 0  );  # skip box wines
  $v->{alcvol} = $alcvol;
  $v->{drinks} = $alcvol / $onedrink;
  return $v;
}

# Parse a line to a proper $rec
# Converts Old type records to more modern types, etc
sub parseline {
  my $line = shift;
  my $rec = splitline( $line );

  # Make sure we accept missing values for fields
  nullfields($rec);

  # Convert "Old" records to better types if possible
  if ( $rec->{type} eq "Old") {
    if ($rec->{mak} =~ /^Tz,/i){ # Skip Time Zone lines, almost never used
      $rec = {};
      return;
    }
    if ($rec->{mak} !~ /,/ ) {
      $rec->{type} = "Beer";
      $rec->{maker} = $rec->{mak};
      $rec->{name} = $rec->{beer};
      $rec->{style} = $rec->{sty};
    } elsif ( $rec->{mak} =~ /^(Wine|Booze)[ ,]*(.*)/i ) {
      $rec->{type} = ucfirst($1);
      $rec->{subtype} = $2;
      $rec->{name} = $rec->{beer};
    } elsif ( $rec->{mak} =~ /^Drink/i ) {
      $rec->{type} = "Booze";
      $rec->{name} = $rec->{beer};
    } elsif ( $rec->{mak} =~ /^Restaurant *, *(.*)/i ) {
      $rec->{type} = "Restaurant";
      $rec->{subtype} = $1;
      $rec->{food} = $rec->{beer};
      $rec->{sty} = "";
    } else {
      print STDERR "Unconverted 'Old' line: $rec->{rawline} \n";
    }
    $rec->{beer} = "";  # Kill old style fields, no longer used
    $rec->{mak} = "";
    $rec->{sty} = "";
    nullfields($rec); # clear undefined fields again, we may have changed the type
  }
  $rec->{seenkey} = seenkey($rec); # Do after normalizing name and type
  return $rec;
}


# Get all field names for a type, or all
sub fieldnames {
  my $type = shift || "";
  my @fields;
  my @typelist;
  if ( $type ) {
    @typelist = ( $type ) ;
  } else {
    @typelist = sort( keys ( %datalinetypes ) );
  }
  my %seen;
  foreach my $t ( @typelist ) {
    next if ( $t =~ /Old/i );
    my $fieldnamelistref = $datalinetypes{$t};
    my @fieldnamelist = @{$fieldnamelistref};
    foreach my $f ( @fieldnamelist ) {
      push @fields, $f unless ( $seen{$f} );
      $seen{$f} = 1;
    }
  }
  return @fields;
}

# Create a line out of a record
sub makeline {
  my $rec = shift;
  my $linetype = $rec->{type} || "Old";
  my $line = "";
  return "" if ($linetype eq "None"); # Not worth saving
  foreach my $f ( fieldnames($linetype) ) {
    $line .=  $rec->{$f} || "";
    $line .= "; ";
  }
  return trim($line);
}

# Make sure we have all fields defined, even as empty strings
sub nullfields {
  my $rec = shift;
  my $linetype = shift || $rec->{type} || "Old";
  my $fieldnamelistref = $datalinetypes{$linetype};
  my @fieldnamelist = @{$fieldnamelistref};
  foreach my $f ( fieldnames($linetype) ) {
    $rec->{$f} = ""
      unless defined($rec->{$f});
  }
}

# Make sure we have all possible fields defined, for all types
# otherwise the user changing record type would hit us with undefined values
# in the input form
sub nullallfields{
  my $rec = shift;
  for my $k ( keys(%datalinetypes) ) {
    nullfields($rec, $k);
  }
}
