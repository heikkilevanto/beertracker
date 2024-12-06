# Part of my beertracker
# The main form for inputting a glass record, with all its extras
# And the routine to save it in the database

package glasses;
use strict;
use warnings;

use feature 'unicode_strings';
use utf8;  # Source code and string literals are utf-8

use POSIX qw(strftime localtime locale_h);

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
  print "<input name='date' id='date' value='$date' placeholder='YYYY-MM-DD' $sz8 $clr/> &nbsp;\n";
  print "<input name='time' id='time' value='$time' placeholder='HH:MM' $sz8 $clr/> &nbsp;\n";
  print "<tr><td>Location</td>\n";
  print "<td>" . locations::selectlocation($c, "Location", $rec->{Location}, "newlocname") . "</td></tr>\n";

  # Brew style and brew selection
  print "<tr><td style='vertical-align:top'>" . selectbrewtype($c,$rec->{BrewType}) ."</td>\n";
  print "<td>". brews::selectbrew($c,$rec->{Brew},$rec->{BrewType}). "</td></tr>\n";

  # Vol, Alc, and Price
  print "<tr><td>&nbsp;</td><td id='avp'>\n";
  my $vol = $rec->{Volume} || "";
  $vol .= "c" if ($vol);
  print "<input name='vol' placeholder='vol' $sz4 value='$vol' />\n";
  my $alc = $rec->{Alc} || "";
  $alc .= "%" if ($alc);
  print "<input name='alc' id='alc' placeholder='alc' $sz4 value='$alc' />\n";
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
  $d = util::datestr("%F", -1,1) if ( $d =~ /^Y/i );

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
  $brew->{BrewType} = util::param($c, "selbrewtype")  || $brew->{BrewType} || $glass->{BrewType} || "WRONG";
    # TODO - The "WRONG" is just a placeholder for missing value, should not happen.
  $glass->{Location} = util::param($c, "Location", undef) || $glass->{Location};
  $glass->{Brew} = util::param($c, "Brew") || $glass->{Brew};
  $glass->{Price} = util::paramnumber($c, "pr");
  $glass->{Volume} = util::paramnumber($c, "vol", "0");
  $glass->{Alc} = util::paramnumber($c, "alc", $brew->{Alc} || "0");
  if ( $sub =~ /Copy (\d+)/ ) {
    $glass->{Volume} = $1;
    print STDERR "getvalues: s='$sub' v='$1' \n";
  }
} # getvalues

############## Helper for alc, volume, etc
# TODO - Named volumes
# TODO - Guess volume from previous glass (same location, brew)
# TODO - Guess price from previous glass (same location, size, brew - in that order)
sub fixvol {
  my $c = shift;
  my $glass = shift;
  my $brew = shift;
  if ( $glass->{BrewType} =~ /Restaurant|Night/ ) { # those don't have volumes
    $glass->{Volume} = "";
    $glass->{Alc} = "";
    $glass->{Price} = $glass->{Price} || "";
    $glass->{StDrinks} = 0;
    $glass->{Brew} = undef;
  } else {
    $glass->{Volume} = $glass->{Volume} || "0";
    $glass->{Alc} =~ s/[.,]+/./;  # I may enter a comma occasionally
    my $std = $glass->{Volume} * $glass->{Alc} / $c->{onedrink};
    $glass->{StDrinks} = sprintf("%6.2f", $std );
  }
} # fixvol


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
    return;
  } # delete

  my $glass = findrec($c); # Get defaults from last glass or the record we are editing
  my $brew = brews::getbrew($c, scalar $c->{cgi}->param("Brew") );
  if (! $brew) {  # Can happen with the beer board
     my $brewid  = brews::insert_old_style_brew($c);
     $brew = brews::getbrew($c, $brewid);
     $glass->{Brew} = $brewid;
  }

  # Get input values into $glass
  getvalues($c, $glass, $brew, $sub);
  gettimestamp($c, $glass);
  fixvol($c, $glass, $brew);

  $glass->{BrewType} = $glass->{BrewType} || $brew->{BrewType} || "WRONG";
     # TODO - That WRONG is just to catch cases where I don't have any
     # Should not happen.

  # New Location and/or Brew
  if ( $glass->{Location} eq "new" ) {
    $glass->{Location} = locations::postlocation($c, "new" );
  }
  if ( $glass->{Brew} eq "new" ) {
    $glass->{Brew} = brews::postbrew($c, "new" );
  }


  if ( $sub eq "Save" ) {  # Update existing glass
    my $sql = "update GLASSES set
        TimeStamp = ?,
        BrewType = ?,
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
      ( Username, TimeStamp, BrewType,
        Location, Brew, Price, Volume, Alc, StDrinks )
      values ( ?, ?, ?, ?, ?,  ?, ?, ?, ? )
      ";
    my $sth = $c->{dbh}->prepare($sql);
    $sth->execute(
      $c->{username},
      $glass->{Timestamp},
      $glass->{BrewType},
      $glass->{Location},
      $glass->{Brew},
      $glass->{Price},
      $glass->{Volume},
      $glass->{Alc},
      $glass->{StDrinks}
      );
    my $id = $c->{dbh}->last_insert_id(undef, undef, "GLASSES", undef) || undef;
    print STDERR "Inserted Glass id '$id' \n";
  }
   print $c->{cgi}->redirect( "$c->{url}?o=$c->{op}&e=$c->{edit}" );
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
  my $s = "<select name='selbrewtype' id='selbrewtype'  >\n";
    # onchange='populatebrews(this.value)'
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
  main::error ("Can not find record id '$id' for username '$c->{username}' ") unless ( $rec->{Timestamp} );
  return $rec;
}

################################################################################
# Report module loaded ok
1;
