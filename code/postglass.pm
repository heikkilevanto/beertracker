# Part of my beertracker
# POST handling for glass records

package postglass;
use strict;
use warnings;

use feature 'unicode_strings';
use utf8;  # Source code and string literals are utf-8

use POSIX qw(strftime localtime locale_h);

# Required modules
require "./code/util.pm";
require "./code/db.pm";
require "./code/brews.pm";
require "./code/locations.pm";
require "./code/graph.pm";
require "./code/glasses.pm";  # For findrec and volumes

################################################################################
# POST handler for glass records
################################################################################
sub postglass {
  my $c = shift; # context

  my $sub = $c->{cgi}->param("submit") || "";

  if ( $sub eq "Del" ) {
    my $sql = "delete from GLASSES
      where id = ? and username = ?";
    my $sth = $c->{dbh}->prepare($sql);
    $sth->execute( $c->{edit}, $c->{username} );
    print STDERR "Deleted " . $sth->rows .
      " Glass records for id '$c->{edit}'  \n";
    $c->{edit} = ""; # don't try to edit it any more
    graph::clearcachefiles($c);
    return;
  } # delete


  my $glass = glasses::findrec($c); # Get defaults from last glass or the record we are editing
    # TODO Is this needed?
  my $brewid = util::param($c,"Brew");
  if ( $brewid eq "new" ) {
    $brewid = brews::postbrew($c, "new" );
  }
  my $brew;
  if ( $brewid ) {
    $brew = db::getrecord($c, "BREWS", $brewid );
    print STDERR "postglass: Got brew '$brewid' = '$brew->{Name}' \n";
  }
  my $locid = util::param($c,"Location");
  if ( !$locid ) { # Should not happen
    util::error ("postglass: No 'Location' parameter! ");
  }
  if ( $locid eq "new" ) {
    $locid = locations::postlocation($c, "new" );
  }
  my $location = db::getrecord($c, "LOCATIONS", $locid);
  $glass->{Location} = $locid;

  my $selbrewtype = util::param($c,"selbrewtype") || $brew->{BrewType};
  $glass->{BrewType} = $selbrewtype;  # Trust the input more than location
  if ( glasses::isemptyglass($selbrewtype) ) { # 'empty' glass
    $glass->{Brew} = undef;  
    $glass->{Volume} = undef;
    $glass->{Alc} = undef;
    $glass->{StDrinks} = "0";
    $glass->{SubType} = util::param($c,"selbrewsubtype") ;
    gettimestamp($c, $glass);
    $glass->{Price} = util::paramnumber($c, "pr");
  } else { # real glass
    $glass->{Brew} = $brewid;
    $glass->{SubType} = $brew->{SubType} || $glass->{SubType};
    {
      no warnings;
      print STDERR "postglass: sel='$selbrewtype'  ".
      "gl.brewtype='$glass->{BrewType}'  br.brewtype='$brew->{BrewType} '" .
      "gl.subtype='$glass->{SubType}' br.subtype='$brew->{SubType}' \n";
    }

    # Get input values into $glass
    getvalues($c, $glass, $brew, $sub);
    gettimestamp($c, $glass);
    fixvol($c, $glass, $brew);
    fixprice($c, $glass);



  } # normal glass

  $glass->{Tap} = util::param($c, "tap");
  $glass->{Tap} =~ s/\D//g if $glass->{Tap};

  { no warnings;
    print STDERR "postglass: Op:'$sub' U:'$c->{username},' " .
      "Bt:'$glass->{BrewType}' Su:'$glass->{SubType}' Br:'$glass->{Brew}' " .
      "Lo:'$glass->{Location}' ".
      "Pr:'$glass->{Price}' Vo:'$glass->{Volume}' Al:'$glass->{Alc}' " .
      "dr:'$glass->{StDrinks}' N:'$glass->{Note}' tap:'$glass->{tap}'\n";
  }

  if ( $sub eq "Save" ) {  # Update existing glass
    my $sql = "update GLASSES set
        TimeStamp = ?,
        BrewType = ?,
        SubType = ?,
        Location = ?,
        Brew = ?,
        Price = ?,
        Volume = ?,
        Alc = ?,
        StDrinks = ?,
        Note = ?,
        tap = ?
      where id = ? and username = ?
    ";
  my $sth = $c->{dbh}->prepare($sql);
  $sth->execute(
    $glass->{Timestamp},
    $glass->{BrewType},
    $glass->{SubType},
    $glass->{Location},
    $glass->{Brew},
    $glass->{Price},
    $glass->{Volume},
    $glass->{Alc},
    $glass->{StDrinks},
    $glass->{Note},
    $glass->{Tap},
    $glass->{Id}, $c->{username} );
  print STDERR "Updated " . $sth->rows .
    " Glass records for id '$c->{edit}'  \n";

  } else { # Create a new glass
    my $sql = "insert into GLASSES
      ( Username, TimeStamp, BrewType, SubType,
        Location, Brew, Price, Volume, Alc, StDrinks, Note, Tap )
      values ( ?, ?, ?, ?, ?,  ?, ?, ?, ?, ?, ?, ? )
      ";
    my $sth = $c->{dbh}->prepare($sql);
    $sth->execute(
      $c->{username},
      $glass->{Timestamp},
      $glass->{BrewType},
      $glass->{SubType},
      $glass->{Location},
      $glass->{Brew},
      $glass->{Price},
      $glass->{Volume},
      $glass->{Alc},
      $glass->{StDrinks},
      $glass->{Note},
      $glass->{Tap}
      );
    my $id = $c->{dbh}->last_insert_id(undef, undef, "GLASSES", undef) || undef;
    print STDERR "Inserted Glass id '$id' \n";
  }

  # If the brew has no DefPrice, set it from this glass
  if ( $brew && !$brew->{DefPrice} && $glass->{Price} && $glass->{Volume} ) {
    my $sql = "UPDATE BREWS SET DefPrice = ?, DefVol = ? WHERE Id = ?";
    my $sth = $c->{dbh}->prepare($sql);
    $sth->execute($glass->{Price}, $glass->{Volume}, $brewid);
    print STDERR "Updated brew '$brewid' with DefPrice '$glass->{Price}' and DefVol '$glass->{Volume}'\n";
  }

  # If setdef checkbox is checked, update brew defaults
  if ( util::param($c, "setdef") && $brewid && $glass->{Price} && $glass->{Volume} ) {
    brews::update_brew_defaults($c, $brewid, $glass->{Price}, $glass->{Volume});
  }

  graph::clearcachefiles($c);
} # postglass

################################################################################
# Helper for timestamp parsing
################################################################################
sub gettimestamp {
  my $c = shift;
  my $glass = shift;
  my $d = util::param($c, "date") || util::datestr("%F",0,1);
  my $t = util::param($c, "time") || util::datestr("%H:%M",0,1);  # Precise time
  if ( $c->{edit} ) { # Keep old values unless explicitly changed
    my ($origd, $origt) = split(' ',$glass->{Timestamp});
    $d = $origd if ( $d =~ /^ / );
    $t = $origt if ( $t =~ /^ / );
  } else {
    $d = util::trim($d);
    $t = util::trim($t);
  }
  # Normalize time
  if ( $t =~ /^(\d?)(\d)(\d\d)(\d\d)?$/ ) {  # 2358 235859 123
    $t = ($1 ||"0") . "$2:$3";  #23:59 01:23
    $t .= ":$4" if ($4); #23:58:59
  }
  if ( $t =~ /^(\d)?(\d):?$/ ) {  # 1 15 15:
    $t = ($1 || "0") . $2. ":";  # 01 or 15, always with a colon
  }
  if ( $t =~ /^\d+:$/ ) {  #21: -> 21:00
    $t .= "00";
  }
  $t .= ":" if ( $t =~ /^\d+:\d+$/ ); # 21:00 -> 21:00:
  $t .= util::datestr("%S",0,1) if ( $t =~ /^\d+:\d+:$/ );  # 21:00: -> 21:00:31
  # Get seconds from current time, to make timestamps a bit more unique and
  # sortable. We are not likely to display them ever, and even then they won't
  # matter much.

  # "Y" means date of yesterday
  if ( $d =~ /^Y/i ) {
    $d = util::datestr("%F", -1, 1);
  }

  # "L" in date or time means 5 minutes after the previous one
  if ( $d =~ /^L/i || $t =~ /^L/i ) {
    my $sql = "select strftime('%Y-%m-%d %H:%M:%S', Timestamp, '+5 minutes') " .
      "from GLASSES where username = ?  ".
      "order by Timestamp desc limit 1";
    my $sth = $c->{dbh}->prepare($sql);
    $sth->execute( $c->{username} );
    my $newstamp = $sth->fetchrow_array;
    print STDERR "gettimestamp: 'L' is '$newstamp' \n";
    ($d, $t) = split(" ",$newstamp);
  }
  util::error("Bad date '$d' ") unless ( $d =~ /^\d\d-\d\d-\d\d|$/ );
  util::error("Bad time '$t' ") unless ( $t =~ /^\d\d:\d\d(:\d\d|)?$/ );
  $glass->{Timestamp} = "$d $t";

  print STDERR "gettimestamp: '$glass->{Timestamp}' \n";
} # gettimestamp

################################################################################
# Helper to get input values
################################################################################
sub getvalues {
  # TODO - So little left here, move into fix routines
  my $c = shift;
  my $glass = shift;
  my $brew = shift;
  my $sub = shift;
  $glass->{Price} = util::paramnumber($c, "pr");
  $glass->{Volume} = util::param($c, "vol", "L");  # Default to a large one
  $glass->{Alc} = util::paramnumber($c, "alc", $brew->{Alc} || "0");
  if ( $sub =~ /Copy (\d+)/ ) {
    $glass->{Volume} = $1;
    print STDERR "getvalues: s='$sub' v='$1' \n";
  }
  $glass->{Note} = util::param($c,"note");
} # getvalues

############## Helpers for alc, volume, etc
sub fixvol {
  my $c = shift;
  my $glass = shift;
  my $brew = shift;
  my $vol = $glass->{Volume} ||"0";
  if ( $vol =~ /^x/i ) { # 'X' means no volume
    $glass->{Volume} = 0;
    $glass->{StDrinks} = 0;
    return;
  }
  my $half;  # Volumes can be prefixed with 'h' for half measures.
  if ( $vol =~ s/^(H)(.+)$/$2/i ) {
    $half = $1;
  }
  my $volunit = uc(substr($vol,0,1)); # S or L or such
  if ( $glasses::volumes{$volunit} && $glasses::volumes{$volunit} =~ /^ *(\d+)/ ) {
    my $actvol = $1;
    $vol =~s/$volunit/$actvol/i;
  }
  if ($half) {
    $vol = int($vol / 2) ;
  }
  if ( $vol =~ /([0-9]+) *oz/i ) {  # Convert (us) fluid ounces
    $vol = $1 * 3;   # Actually, 2.95735 cl, no need to mess with decimals
  }
  $glass->{Volume} = util::number($vol);
  $glass->{Alc} =~ s/[.,]+/./;  # I may enter a comma occasionally
  if ( $glass->{Alc} =~ /^X/i ) {
    $glass->{Alc} = "0";
  }
  my $std = $glass->{Volume} * $glass->{Alc} / $c->{onedrink};
  $glass->{StDrinks} = sprintf("%6.2f", $std );
} # fixvol

############## Helper to fix the price
sub fixprice {
  my $c = shift;
  my $glass = shift;

  my $pr = $glass->{Price} || "";
  if  ( $pr =~ /^(\d+)[,.-]*$/ ){  # Already a good price, only digits
    $glass->{Price} = $1; # just the digits
    return
  }
  # TODO - Currencies, next time I travel
  if ( $pr =~ /^x/i ) {  # X indicates no price, no guessing
    $glass->{Price} = "0";
    return;
  }
 } # fixprice

# currency conversions
# Not used at the moment, kept here for future reference
my %currency;
$currency{"eur"} = 7.5;
$currency{"e"} = 7.5;
$currency{"usd"} = 6.3;  # Varies bit over time
#$currency{"\$"} = 6.3;  # € and $ don't work, get filtered away in param

############## Helper for currency conversion (not currently used)
sub curprice {
  my $v = shift;
  #print STDERR "Checking '$v' for currency";
  for my $c (keys(%currency)) {
    if ( $v =~ /^(-?[0-9.]+) *$c/i ) {
      #print STDERR "Found currency $c, worth " . $currency{$c};
      my $dkk = int(0.5 + $1 * $currency{$c});
      #print STDERR "That makes $dkk";
      return $dkk;
    }
  }
} # curprice

################################################################################
# Report module loaded ok
1;