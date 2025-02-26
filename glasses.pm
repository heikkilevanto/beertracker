# Part of my beertracker
# The main form for inputting a glass record, with all its extras
# And the routine to save it in the database

package glasses;
use strict;
use warnings;

use feature 'unicode_strings';
use utf8;  # Source code and string literals are utf-8

use POSIX qw(strftime localtime locale_h);


our %volumes = ( # Comment is displayed on the About page
  'T' => " 2 Taster, sizes vary, always small",
  'G' => "16 Glass of wine - 12 in places, at home 16 is more realistic",
  'S' => "25 Small, usually 25",
  'M' => "33 Medium, typically a bottle beer",
  'L' => "40 Large, 40cl in most places I frequent",
  'C' => "44 A can of 44 cl",
  'W' => "75 Bottle of wine",
  'B' => "75 Bottle of wine",
);

################################################################################
# The input form
################################################################################
# This is a fairly small, but rather complex form. For now it is hard coded,
# without using the util::inputform helper, as almost every field has some
# special considerations.
# TODO - Del button to go back to here, with an option to ask if sure
#        Could also ask to delete otherwise unused locations and brews
# TODO - JS Magic to get geolocation to work
# TODO - Display comments for the current glass. Also persons and photos
# TODO - Form to add a new comment, or edit one
sub inputform {
  my $c = shift;
  my $rec = findrec($c); # Get defaults, or the record we are editing

  # Formatting magic
  my $clr = "Onfocus='value=value.trim();select();' autocapitalize='words'";
  my $sz4 = "size='4' style='text-align:right' $clr";
  my $sz8 = "size='8'  $clr";

  print "\n<form method='POST' accept-charset='UTF-8' class='no-print' " .
        "onClick='setdate();' " .
        "enctype='multipart/form-data'>\n";
  print "<table>\n";

  print "<tr><td>Id $rec->{Id}</td>\n";
  my $stamp = main::datestr("%F %T");
  print "<td>" ; # <input name='stamp' value='$stamp' size=25 $clr/>";
  my ($date,$time) = ( "", "");
  ($date,$time) = split ( ' ',$rec->{Timestamp} ) if ($rec->{Timestamp} );
  if ( !$c->{edit} ) {
    $date =" $date";  # Mark the time as speculative
    $time =" $time";
  }
  print "<input name='date' id='date' value='$date' " .
        "pattern=' ?([LlYy])?(\\d\\d\\d\\d-\\d\\d-\\d\\d)?' " .
        "placeholder='YYYY-MM-DD' $sz8 /> &nbsp;\n";
        # Could not make alternative pattern work, so I use a sequence of L/Y
        # and a valid date. Note also the leading space
  print "<input name='time' id='time' value='$time' " .
        "pattern=' ?\\d\\d(:?\\d\\d)?(:?\\d\\d)?' ".
        "placeholder='HH:MM' $sz8/> &nbsp;\n";
  print "<tr><td>Location</td>\n";
  print "<td>" . locations::selectlocation($c, "Location", $rec->{Location}, "newlocname", "non") .
    "</td></tr>\n";

  # Brew style
  print "<tr><td style='vertical-align:top'>" . selectbrewtype($c,$rec->{BrewType}) ."</td>\n";
  my $isemptyglass = 0;
  if ( $rec->{BrewType} =~ /(Restaurant|Night)/i ) {
    $isemptyglass = 1;  # Mark this as an empty glass
    # TODO - Select subtypes for rest/night, once we know where to put them
  } else { # A drinkable glass, select a brew
    print "<td>". brews::selectbrew($c,$rec->{Brew},$rec->{BrewType}). "</td></tr>\n";
  }

  # Vol, Alc, and Price
  print "<tr><td>&nbsp;</td><td id='avp'>\n";
  if ( ! $isemptyglass ) {
    my $vol = $rec->{Volume} || "";
    $vol .= "c" if ($vol);
    print "<input name='vol' placeholder='vol' $sz4 value='$vol' />\n";
    my $alc = $rec->{Alc} || "";
    $alc .= "%" if ($alc);
    print "<input name='alc' id='alc' placeholder='alc' $sz4 value='$alc' />\n";
  }
  my $pr = $rec->{Price} || "";
  $pr .= ".-" if ($pr);
  print "<input name='pr' placeholder='pr' $sz4 value='$pr' />\n";
  print "</td></tr>\n";

  # Buttons
  print "<tr><td>\n";
  print " <input type='hidden' name='o' value='$c->{op}' />\n";
  if ($c->{edit}) {
    print " <input type='hidden' name='e' value='$rec->{Id}' />\n";
    print " <input type='submit' name='submit' value='Save' id='save' />\n";
    print "</td><td>\n";
    print " <input type='submit' name='submit' value='Del'/>\n";
    print "<a href='$c->{url}?o=$c->{op}' ><span>cancel</span></a>";
  } else { # New glass
    print "<input type='submit' name='submit' value='Record'/>\n";
    print "</td><td>\n";
    print " <input type='submit' name='submit' value='Save' id='save' />\n";
    print " <input type='button' value='Clr' onclick='clearinputs()'/>\n";
  }
  print "&nbsp;" ;
  print util::showmenu($c);

  print "</td></tr>\n";
  print "</table>\n";
  print "</form>\n";
  print comments::listcomments($c, $rec->{Id});
  print "<hr>\n";

  # Javascript trickery
  my $script = <<'SCRIPTEND';

    function clearinputs() {  // Clear all inputs, used by the 'clear' button
      var inputs = document.getElementsByTagName('input');  // all regular input fields
      for (var i = 0; i < inputs.length; i++ ) {
        if ( inputs[i].type == "text" )
          inputs[i].value = "";
      }
    }

    function setdate() {  // Set date and time, if not already set by the user
      var di = document.getElementById("date");
      var ti = document.getElementById("time");
      const now = new Date();
      if ( di.value && di.value.startsWith(" ") ) {
        const year = now.getFullYear();
        const month = String(now.getMonth() + 1).padStart(2, '0'); // Zero-padded month
        const day = String(now.getDate()).padStart(2, '0'); // Zero-padded day
        const dat = `${year}-${month}-${day}`;
        di.value = " " + dat;
      }
      if ( ti.value && ti.value.startsWith(" ") ) {
        const hh = String(now.getHours()).padStart(2, '0');
        const mm = String(now.getMinutes()).padStart(2, '0');
        const tim = `${hh}:${mm}`;
        ti.value = " " + tim;
      }
    }
    setdate();

    // hide newBrewType, we use SelBrewType always
    var nbt = document.getElementsByName("newbrewBrewType");
    if ( nbt.length > 0 ) {
      nbt[0].hidden = true;
      var br = nbt[0].nextElementSibling;
      br.hidden = true;
    }
SCRIPTEND
  print "<script defer>$script</script>\n";
} # inputform

################################################################################
# Update, insert, or delete a glass from the form above
################################################################################


############## Helper to get the timestamp right
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
    $d = util::datestr("%F", -1,1) ;
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
  util::error("Bad date '$d' ") unless ( $d =~ /^\d\d-\d\d-\d\d|$/ );  # TODO - HOw to validate the fields in js?
  util::error("Bad time '$t' ") unless ( $t =~ /^\d\d:\d\d(:\d\d|)?$/ );  # TODO - HOw to validate the fields in js?
  $glass->{Timestamp} = "$d $t";

  print STDERR "gettimestamp: '$glass->{Timestamp}' \n";
} # gettimestamp

############## Helper to get input values into $glass with some defaults
sub getvalues {
  my $c = shift;
  my $glass = shift;
  my $brew = shift;
  my $sub = shift;

  $glass->{BrewType} =  util::param($c, "selbrewtype") || $glass->{BrewType} || $brew->{BrewType} || "WRONG";
  #util::error("getvalues.1: No Brew Type for glass $glass->{Id}") if ( $glass->{BrewType} eq "WRONG" );
  $brew->{BrewType} = util::param($c, "selbrewtype")  || $brew->{BrewType} || $glass->{BrewType} || "WRONG";
  #util::error("getvalues.2: No Brew Type for brew $brew->{Id}") if ( $brew->{BrewType} eq "WRONG" );
  $glass->{SubType} = util::param($c, "subtype") || $glass->{SubType} || $brew->{SubType} || "WRONG";
  #util::error("getvalues.3: No Brew SubType for glass $glass->{Id}")
  #  if (! $brew->{SubType} || $brew->{SubType} eq "WRONG" );
    # TODO - The "WRONG" is just a placeholder for missing value, should not happen.

  $glass->{Location} = util::param($c, "Location", undef) || $glass->{Location};
  $glass->{Brew} = util::param($c, "Brew") || $glass->{Brew};
  $glass->{Price} = util::paramnumber($c, "pr");
  $glass->{Volume} = util::param($c, "vol", "L");  # Default to a large one
  $glass->{Alc} = util::paramnumber($c, "alc", $brew->{Alc} || "0");
  if ( $sub =~ /Copy (\d+)/ ) {
    $glass->{Volume} = $1;
    print STDERR "getvalues: s='$sub' v='$1' \n";
  }
} # getvalues

############## Helper for alc, volume, etc
# TODO - Guess volume from previous glass (same location, brew)
# TODO - Guess price from previous glass (same location, size, brew - in that order)
sub fixvol {
  my $c = shift;
  my $glass = shift;
  my $brew = shift;
  if ( $glass->{BrewType} =~ /Restaurant|Night/ ) { # those don't have volumes
    $glass->{Volume} = "";
    $glass->{Alc} = "";
    $glass->{Price} = $glass->{Price} || "";  # but may have a price
    $glass->{StDrinks} = 0;
    $glass->{Brew} = undef;
  } else {
    my $vol = $glass->{Volume} ||"0";
    my $half;  # Volumes can be prefixed with 'h' for half measures.
    if ( $vol =~ s/^(H)(.+)$/$2/i ) {
      $half = $1;
    }
    my $volunit = uc(substr($vol,0,1)); # S or L or such
    if ( $volumes{$volunit} && $volumes{$volunit} =~ /^ *(\d+)/ ) {
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
    my $std = $glass->{Volume} * $glass->{Alc} / $c->{onedrink};
    $glass->{StDrinks} = sprintf("%6.2f", $std );
  }
} # fixvol


############## Helper to fix the price
sub guessprice {
  my $c = shift;
  my $where = shift;
  my $grec = util::getfieldswhere( $c, "GLASSES", "Price",
      "WHERE Price > 0 AND $where",
      "ORDER BY Timestamp DESC" );
  if ( $grec && $grec->{Price} ) {
    print STDERR "Found price '$grec->{Price}' with $where \n";
    return $grec->{Price};
  }
  return 0;
}

sub fixprice {
  my $c = shift;
  my $glass = shift;

  my $pr = $glass->{Price} || "";
  return if  ( $pr =~ /^\d+$/ );  # Already a good price, only digits
  # TODO - Currencies, next time I travel
  if ( $pr =~ /^x/i ) {  # X indicates no price, no guessing
    $glass->{Price} = "";
    return;
  }
  print STDERR "No price, guessing\n";
  # Sql where clause fragments
  my $br = "Brew=$glass->{Brew}";
  my $vo = "Volume=$glass->{Volume}";
  my $lo = "Location=$glass->{Location}";
  $pr = 0;
  if ( $glass->{Brew} && $glass->{Brew} ne "new" && $glass->{Volume} ) {
    # Have brew, try to find similar glasses
    $pr = guessprice($c,"$br AND $lo AND $vo" );
    if ( $pr == 0 ) {
      $pr = guessprice($c,"$br AND $vo" );
    }
  }
  if ( $pr == 0 ) {
    $pr = guessprice($c, "$lo AND $vo" );
  }
  if ( $pr > 0 ) {
    $glass->{Price} = $pr;
  } else {
    print STDERR "Could not guess a price with $br $vo $lo \n";
  }
}

############## postglass itself
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

  my $glass = findrec($c); # Get defaults from last glass or the record we are editing
  # my $brew = brews::getbrew($c, scalar $c->{cgi}->param("Brew") );
  my $brew;
  my $brewname = util::param($c,"Brew");
  if ( $brewname && $brewname ne "new" ) {
    $brew = util::getrecord($c, "BREWS", $brewname );
    if (! $brew)  {  # Can happen with the beer board
      # TODO - Happens also with Rest/Night buttons, which go wrong here !
      my $brewid  = brews::insert_old_style_brew($c);
      $brew = util::getrecord($c, "BREWS", $brewid );
      $glass->{Brew} = $brewid;
      $glass->{BrewType} = $brew->{BrewType};
      $glass->{SubType} = $brew->{SubType};
    }
  }
  #print STDERR "postglass: sel='" . util::param($c, "selbrewtype") . "' glt='$glass->{BrewType}'  brt='$brew->{BrewType}' \n";

  # Get input values into $glass
  getvalues($c, $glass, $brew, $sub);
  gettimestamp($c, $glass);
  fixvol($c, $glass, $brew);
  fixprice($c, $glass);

  $glass->{BrewType} = $glass->{BrewType} || $brew->{BrewType} || "WRONG";
  util::error("Post: No Brew Type for glass $glass->{Id}") if ( $glass->{BrewType} eq "WRONG" );
  $glass->{SubType} = $glass->{SubType} || $brew->{SubType} || "WRONG";
  util::error("Post: No Brew SubType for glass $glass->{Id}") if ( $brew->{SubType} eq "WRONG" );
  #print STDERR "postglass: L='" . util::param($c,"Location")  ."' l='" .util::param($c,"loc") . "'\n";
  if ( ! util::param($c,"Location") && util::param($c,"loc") ) { # Old style loc name
    my $location = util::findrecord($c, "LOCATIONS", "Name", util::param($c,"loc")) ;
    $glass->{Location} = $location->{Id} if ($location);
    print STDERR "Fixed location " . util::param($c,"loc") . " to $location->{Id} \n";
  }

  # New Location and/or Brew
  if ($glass->{Location} && $glass->{Location} eq "new" ) {
    $glass->{Location} = locations::postlocation($c, "new" );
  }
  if ($glass->{Brew} && $glass->{Brew} eq "new" ) {
    $glass->{Brew} = brews::postbrew($c, "new" );
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
        StDrinks = ?
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
    $glass->{Id}, $c->{username} );
  print STDERR "Updated " . $sth->rows .
    " Glass records for id '$c->{edit}'  \n";

  } else { # Create a new glass

    my $sql = "insert into GLASSES
      ( Username, TimeStamp, BrewType, SubType,
        Location, Brew, Price, Volume, Alc, StDrinks )
      values ( ?, ?, ?, ?, ?,  ?, ?, ?, ?, ? )
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
      $glass->{StDrinks}
      );
      #or error($DBI::errstr);
      # This fails if the database is locked by Sqlitebrowser.
      # TODO - Better error handling with db errors. Make a dedicated module for the db!
    my $id = $c->{dbh}->last_insert_id(undef, undef, "GLASSES", undef) || undef;
    print STDERR "Inserted Glass id '$id' \n";
  }
  graph::clearcachefiles($c);
} # postglass

################################################################################
# Helper to select a brew type
################################################################################
# Selecting from glasses, not brews, so that we get 'empty' glasses as well,
# f.ex. "Restaurant"
sub selectbrewtype {
  my $c = shift;
  my $selected = shift || "";
  my $sql = "select distinct BrewType from Glasses";
  my $sth = $c->{dbh}->prepare($sql);
  $sth->execute( );
  my $s = "<select name='selbrewtype' id='selbrewtype' >\n";
  while ( my $bt = $sth->fetchrow_array ) {
    my $se = "";
    $se = "selected" if ( $bt eq $selected );
    $s .= "<option value='$bt' $se>$bt</option>\n";
  }
  $s .= "</select>\n";
  return $s;
}

################################################################################
# Helper to get the latest glasss record for editing or defaults
################################################################################
sub findrec {
  my $c = shift;
  my $id = $c->{edit};
  if ( ! $id ) {  # Not editing, just get the latest
    my $sql = "select id from glasses " .
              "where username = ? " .
              "order by timestamp desc ".
              "limit 1";
    my $sth = $c->{dbh}->prepare($sql);
    $sth->execute( $c->{username} );
    $id = $sth->fetchrow_array;
  }
  my $sql = "select * from glasses " .
            "where id = ? and username = ? ";
  if ( $id =~ /^\d\d\d\d-\d\d/ ) { # Called with old-style timestamp
    $sql =~ s/id =/timestamp =/;   # TODO - Drop this when no longer needed
    #print STDERR "glasses::findrec called with timestamp '$id' instead of proper id\n";
  }
  my $sth = $c->{dbh}->prepare($sql);
  $sth->execute( $id, $c->{username} );
  my $rec = $sth->fetchrow_hashref;
  util::error ("Can not find record id '$id' for username '$c->{username}' ") unless ( $rec->{Timestamp} );
  return $rec;
}

################################################################################
# Report module loaded ok
1;
