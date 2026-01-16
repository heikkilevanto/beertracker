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

# currency conversions
# Not used at the moment, kept here for future reference
my %currency;
$currency{"eur"} = 7.5;
$currency{"e"} = 7.5;
$currency{"usd"} = 6.3;  # Varies bit over time
#$currency{"\$"} = 6.3;  # € and $ don't work, get filtered away in param

################################################################################
# Helper to decide if a glass is "empty"
################################################################################
sub isemptyglass {
  my $type = shift;
  return $type =~ /Restaurant|Night|Bar|Feedback/;
}

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
  my $opts = "";
  while ( my $bt = $sth->fetchrow_array ) {
    my $se = "";
    $se = "selected" if ( $bt eq $selected );
    my $em = "data-isempty=1";
    $em = "" if ( ! isemptyglass($bt) );
    $opts .= "<option value='$bt' $em $se>$bt</option>\n";
  }
  util::error ("No brew types in the database. Insert some dummy glasses")
    unless ($opts);
  my $s = "<select name='selbrewtype' id='selbrewtype' onChange='selbrewchange(this);'>\n" .
    $opts . "</select>\n";
  my $script = <<'SCRIPT';
    <script>
      replaceSelectWithCustom(document.getElementById("selbrewtype"));

      function selbrewchange(el) {
        const selbrew = document.getElementById("selbrewtype");
        const val = selbrew.value;
        const selected = el.options[el.selectedIndex];
        const isempty = selected.getAttribute("data-isempty");
        const table = el.closest('table');
        for ( const td of table.querySelectorAll("[data-empty]") ) {
          const te = td.getAttribute("data-empty");
          if ( te == 1 ) {
            if ( isempty )
              td.style.display = 'none';
            else
              td.style.display = '';
          } else if ( te == 2 ) {
              if ( isempty )
                td.style.display = '';
              else
                td.style.display = 'none';
            }
          else if ( te ) {
            if ( te == val )
                td.style.display = '';
              else
                td.style.display = 'none';
          }
        }
      }
    </script>
SCRIPT
  $s .= $script;
  return $s;
} # selectbrewtype

################################################################################
# Select a glass subtype
################################################################################
sub selectbrewsubtype {
  my $c = shift;
  my $rec = shift;
  my $sql = 'SELECT BrewType, SubType, MAX(timestamp) AS last_time
    FROM glasses
    WHERE BrewType in ("Restaurant","Night", "Bar","Feedback")
    GROUP BY brewtype,SubType
    ORDER BY last_time DESC ';
  my $sth = $c->{dbh}->prepare($sql);
  $sth->execute( );
  my $s = "";
  while ( my $bt = $sth->fetchrow_hashref ) {
    next unless ( $bt->{SubType} );
    my $sel = "";
    $sel = "selected" if ( $rec->{SubType} && $rec->{SubType} eq $bt->{SubType} );
    my $em = "data-empty=\"$bt->{BrewType}\" ";
    $s .= "<option value='$bt->{SubType}' $em $sel>$bt->{SubType}</option>\n";
  }
  $s = "<select name='selbrewsubtype' id='selbrewsubtype'>\n" .
    $s . "</select>\n";
  return $s;
} # selectbrewsubtype

################################################################################
# The input form
################################################################################
# This is a fairly small, but rather complex form. For now it is hard coded,
# without using the util::inputform helper, as almost every field has some
# special considerations.
# TODO - Del button to go back to here, with an option to ask if sure
#        Could also ask to delete otherwise unused locations and brews
# TODO - JS Magic to get geolocation to work
sub inputform {
  my $c = shift;
  my $rec = findrec($c); # Get defaults, or the record we are editing

  # Formatting magic
  my $clr = "Onfocus='value=value.trim();select();' autocapitalize='words'";
  my $sz4 = "size='4' style='text-align:right' $clr";
  my $sz8 = "size='8'  $clr";
  my $sz20 = "size='20' $clr";

  print "\n<form method='POST' accept-charset='UTF-8' class='no-print' " .
        "onClick='setdate();' " .
        "enctype='multipart/form-data'>\n";
  print "<table>\n";

  print "<tr><td width='100px'>Id $rec->{Id}</td>\n";
  my $stamp = util::datestr("%F %T");
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
  my $onclick = "onclick='selectNearest(\"#dropdown-Location\")'";
  print "<tr><td $onclick>Location</td>\n";
  print "<td>" . locations::selectlocation($c, "Location", $rec->{Location}, "newlocname", "non") .
    "</td></tr>\n";

  # Brew style
  print "<tr><td style='vertical-align:top'>" . selectbrewtype($c,$rec->{BrewType}) ."</td>\n";
  print "<td>\n";

  # Brew, or  subtype
  my $hidesub = "";
  my $hidebrew = "";
  if (isemptyglass($rec->{BrewType}) ) {
    $hidebrew = "style=display:none";
  } else {
    $hidesub = "style=display:none";
  }
  print "<span $hidesub data-empty=2>". selectbrewsubtype($c,$rec). "</span>";
  print "<span $hidebrew data-empty=1>". brews::selectbrew($c,$rec->{Brew},$rec->{BrewType}). "</span>";
  print "</td>\n";

  print "</tr>\n";

  # Note for the glass
  my $hidenote = "hidden";
  $rec->{Note} = "" unless ( $c->{edit} );  # Do not inherit from previous
  $hidenote = "" if ( $rec->{Note} );
  print "<tr id='noteline' $hidenote><td>Note</td><td>\n";
  print "<input name='note' placeholder='note' value='$rec->{Note}' $sz20/>\n";
  print "</td></tr>\n";

  # (note toggle),  Vol, Alc, and Price
  print "<tr>";
  my $notetxt = "(note)";
  $notetxt = "" if ( !$hidenote);
  print "<td><div id='notetag' onclick='shownote();'>$notetxt</id></td>";
  print "<td id='avp' >\n";
  my $vol = $rec->{Volume} || "";
  $vol .= "c" if ($vol);
  print "<input name='vol' placeholder='vol' $sz4 value='$vol' data-empty=1 />\n";
  my $alc = $rec->{Alc} || "";
  $alc .= "%" if ($alc);
  print "<input name='alc' id='alc' placeholder='alc' $sz4 value='$alc' data-empty=1 />\n";
  my $pr = $rec->{Price} || "0";
  $pr .= ".-" if ($pr);
  print "<input name='pr' placeholder='pr' $sz4 value='$pr' required />\n";
    # Price is required, but a space or zero are allowed
  print "</td></tr>\n";

  # Buttons
  print "<tr><td>\n";
  print " <input type='hidden' name='o' value='$c->{op}' />\n";
  if ($c->{edit}) {
    print " <input type='hidden' name='e' value='$rec->{Id}' />\n";
    print " <input type='submit' name='submit' value='Save' id='save' />\n";
    print "</td><td>\n";
    print " <input type='submit' name='submit' value='Del' formnovalidate />\n";
    print "<a href='$c->{url}?o=$c->{op}' ><span>cancel</span></a>";
  } else { # New glass
    print "<input type='submit' name='submit' value='Record'/>\n";
    print "</td><td>\n";
    print " <input type='submit' name='submit' value='Save' id='save' />\n";
    print " <input type='button' value='Clr' onclick='clearinputs()'/>\n";
  }
  print "&nbsp;" ;
  print "</td></tr>\n";
  print "</table>\n";
  print "</form>\n";
  print comments::listcomments($c, $rec->{Id});
  print "<hr/>";

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
      const dis = document.getElementsByName("date");
      const tis = document.getElementsByName("time");
      const now = new Date();
      for ( const di of dis ) {
        if ( di.value && di.value.startsWith(" ") ) {
          const year = now.getFullYear();
          const month = String(now.getMonth() + 1).padStart(2, '0'); // Zero-padded month
          const day = String(now.getDate()).padStart(2, '0'); // Zero-padded day
          const dat = `${year}-${month}-${day}`;
          di.value = " " + dat;
        }
      }
      for ( const ti of tis ) {
        if ( ti.value && ti.value.startsWith(" ") ) {
          const hh = String(now.getHours()).padStart(2, '0');
          const mm = String(now.getMinutes()).padStart(2, '0');
          const tim = `${hh}:${mm}`;
          ti.value = " " + tim;
        }
      }
    }
    setdate();

    function shownote() {
      const noteline = document.getElementById("noteline");
      noteline.hidden = false;
      const toggle = document.getElementById("notetag");
      toggle.hidden = true;
    }

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
  util::error("Bad date '$d' ") unless ( $d =~ /^\d\d-\d\d-\d\d|$/ );
  util::error("Bad time '$t' ") unless ( $t =~ /^\d\d:\d\d(:\d\d|)?$/ );
  $glass->{Timestamp} = "$d $t";

  print STDERR "gettimestamp: '$glass->{Timestamp}' \n";
} # gettimestamp

############## Helper to get input values into $glass with some defaults
sub getvalues {
  # TODO - So little left here, move into fix routines
  my $c = shift;
  my $glass = shift;
  my $brew = shift;
  my $sub = shift;
  #$glass->{Price} = util::paramnumber($c, "pr");
  $glass->{Price} = util::param($c, "pr", "?");
  $glass->{Volume} = util::param($c, "vol", "L");  # Default to a large one
  $glass->{Alc} = util::paramnumber($c, "alc", $brew->{Alc} || "0");
  if ( $sub =~ /Copy (\d+)/ ) {
    $glass->{Volume} = $1;
    print STDERR "getvalues: s='$sub' v='$1' \n";
  }
  $glass->{Note} = util::param($c,"note");
} # getvalues

############## Helper for alc, volume, etc
# TODO - Guess volume from previous glass (same location, brew)
# TODO - Guess price from previous glass (same location, size, brew - in that order)
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
  if ( $glass->{Alc} =~ /^X/i ) {
    $glass->{Alc} = "0";
  }
  my $std = $glass->{Volume} * $glass->{Alc} / $c->{onedrink};
  $glass->{StDrinks} = sprintf("%6.2f", $std );
} # fixvol


############## Helper to fix the price

# Convert prices to DKK if in other currencies
# TODO - Not in use at the moment
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
  return "";
}

sub guessoneprice {
  my $c = shift;
  my $where = shift;
  my $grec = db::getfieldswhere( $c, "GLASSES", "Price",
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
  if  ( $pr =~ /^(\d+)[.-]*$/ ){  # Already a good price, only digits
    $glass->{Price} = $1; # just the digits
    return
  }
  # TODO - Currencies, next time I travel
  if ( $pr =~ /^x/i ) {  # X indicates no price, no guessing
    $glass->{Price} = "0";
    return;
  }
  if ( $pr eq "?" ) {
    print STDERR "No price, guessing p='$glass->{Price}'\n";
    # Sql where clause fragments
    my $br = "Brew=$glass->{Brew}";
    my $vo = "Volume=$glass->{Volume}";
    my $lo = "Location=$glass->{Location}";
    $pr = 0;
    if ( $glass->{Brew} && $glass->{Brew} ne "new" &&
        $glass->{Volume} ) {
      # Have brew, try to find similar glasses
      if ( $glass->{Location} ne "new" ) {
        $pr = guessoneprice($c,"$br AND $lo AND $vo" );
      }
      if ( $pr == 0 ) {
        $pr = guessoneprice($c,"$br AND $vo" );
      }
    }
    if ( $pr == 0 && $glass->{Location} ne "new") {
      $pr = guessoneprice($c, "$lo AND $vo" );
    }
    if ( $pr > 0 ) {
      $glass->{Price} = $pr;
    } else {
      print STDERR "Could not guess a price with $br $vo $lo \n";
    }
  }
} # fixprice

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
  if ( isemptyglass($selbrewtype) ) { # 'empty' glass
    $glass->{Brew} = undef;  # "WRONG" to provoke a DB error when recordin a night
    #$glass->{Brew} = "WRONG";  # "WRONG" to provoke a DB error when recordin a night COMMENT THIS OUT!
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

  $glass->{tap} = util::param($c, "tap");

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
    $glass->{tap},
    $glass->{Id}, $c->{username} );
  print STDERR "Updated " . $sth->rows .
    " Glass records for id '$c->{edit}'  \n";

  } else { # Create a new glass
    my $sql = "insert into GLASSES
      ( Username, TimeStamp, BrewType, SubType,
        Location, Brew, Price, Volume, Alc, StDrinks, Note, tap )
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
      $glass->{tap}
      );
    my $id = $c->{dbh}->last_insert_id(undef, undef, "GLASSES", undef) || undef;
    print STDERR "Inserted Glass id '$id' \n";
  }
  graph::clearcachefiles($c);
} # postglass


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
    print STDERR "glasses::findrec called with timestamp '$id' instead of proper id\n";
  }
  my $sth = $c->{dbh}->prepare($sql);
  $sth->execute( $id, $c->{username} );
  my $rec = $sth->fetchrow_hashref;
  return $rec;
}

################################################################################
# Report module loaded ok
1;
