# Part of my beertracker
# The main form for inputting a glass record, with all its extras
# And the routine to save it in the database

package glasses;
use strict;
use warnings;

################################################################################
# The input form
################################################################################
# TODO - The timestamp processing is overly simplified, now always puts current time in the form
#        It still updatyes the record with the entered value, but won't display it
#        Best would be to let the browser fill it in, but not overwrite existing data
sub inputform {
  my $c = shift;
  my $rec = findrec($c); # Get defaults, or the record we are editing

  # Formatting magic
  my $clr = "Onfocus='value=value.trim();select();' autocapitalize='words'";
  my $sz = "size='4' style='text-align:right' $clr";

  print "\n<form method='POST' accept-charset='UTF-8' class='no-print' " .
        "enctype='multipart/form-data'>\n";
  print "<table>\n";

  print "<tr><td>Id $rec->{Id}</td>\n";
  my $stamp = main::datestr("%F %T");
  print "<td><input name='stamp' value='$stamp' size=25 $clr/>";
  print "<tr><td>Location</td>\n";
  print "<td>" . locations::selectlocation($c, $rec->{Location}, "newlocname") . "</td></tr>\n";

  # Brew style and brew selection
  print "<tr><td style='vertical-align:top'>" . selectbrewtype($c,$rec->{BrewType}) ."</td>\n";
  print "<td>". brews::selectbrew($c,$rec->{Brew},$rec->{BrewType}). "</td></tr>\n";

  # Vol, Alc, and Price
  print "<tr><td>&nbsp;</td><td id='avp'>\n";
  my $vol = $rec->{Volume} || "";
  $vol .= "c" if ($vol);
  print "<input name='vol' placeholder='vol' $sz value='$vol' />\n";
  my $alc = $rec->{Alc} || "";
  $alc .= "%" if ($alc);
  print "<input name='alc' id='alc' placeholder='alc' $sz value='$alc' />\n";
  my $pr = $rec->{Price} || "";
  $pr .= ".-" if ($pr);
  print "<input name='pr' placeholder='pr' $sz value='$pr' />\n";
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

  my $script = <<'SCRIPTEND';
    function clearinputs() {  // Clear all inputs, used by the 'clear' button
      var inputs = document.getElementsByTagName('input');  // all regular input fields
      for (var i = 0; i < inputs.length; i++ ) {
        if ( inputs[i].type == "text" )
          inputs[i].value = "";
      }
      const ids = [ "brewsel" ];
      for ( var i = 0; i < ids.length; i++) {
        var r = document.getElementById(ids[i]);
        if (r)
          r.value = "";
      };
   }
SCRIPTEND
  print "<script>$script</script>\n";
} # inputform

################################################################################
# Update or insert a glass from the form above
################################################################################



############## Helper to get input values into $glass with some defaults
sub getvalues {
  my $c = shift;
  my $glass = shift;
  my $brew = shift;
  $glass->{TimeStamp} = util::param($c, "stamp");
  $glass->{BrewType} = util::param($c, "selbrewtype");
  $glass->{SubType} = util::param($c, "newbrewsub", $glass->{SubType} || "");
  $glass->{Location} = util::param($c, "loc", undef);
  $glass->{Brew} = util::param($c, "brewsel");
  $glass->{Price} = util::paramnumber($c, "pr");
  $glass->{Volume} = util::paramnumber($c, "vol", "0");
  $glass->{Alc} = util::paramnumber($c, "alc", $brew->{Alc} || "0");
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
    return;
  }

  $glass->{Volume} = $glass->{Volume} || "0";

  $glass->{Alc} =~ s/[.,]+/./;  # I may enter a comma occasionally

  my $std = $glass->{Volume} * $glass->{Alc} / $c->{onedrink};
  $glass->{StDrinks} = sprintf("%6.2f", $std );
} # fixvol


############## postglass itself
sub postglass {
  my $c = shift; # context

  if ( 1 ) {
    foreach my $param ($c->{cgi}->param) { # Debug dump params while developing
      my $value = $c->{cgi}->param($param);
      print STDERR "$param = '$value'\n";
    }
  }

  my $sub = $c->{cgi}->param("submit") || "";

  my $glass = findrec($c); # Get defaults from last glass or the record we are editing
  my $brew = brews::getbrew($c, scalar $c->{cgi}->param("brewsel") );

  # Get input values into $glass
  getvalues($c, $glass, $brew);
  fixvol($c, $glass, $brew);

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
    $glass->{TimeStamp},
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
    # TODO - Timestamps, Subtypes,

    my $sql = "insert into GLASSES
      ( Username, TimeStamp, BrewType, SubType,
        Location, Brew, Price, Volume, Alc, StDrinks )
      values ( ?, ?, ?, ?, ?,  ?, ?, ?, ?, ? )
      ";
    my $sth = $c->{dbh}->prepare($sql);
    $sth->execute(
      $c->{username},
      $glass->{TimeStamp},
      $glass->{BrewType},
      $glass->{SubType},
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
  my $s = "<select name='selbrewtype' id='selbrewtype' onchange='populatebrews(this.value)' >\n";
  while ( my $bt = $sth->fetchrow_array ) {
    my $se = "";
    $se = "selected" if ( $bt eq $selected );
    $s .= "<option value='$bt' $se>$bt</option>\n";
  }
  $s .= "</select>\n";
  return $s;
}

################################################################################
# Helper to get the record for editing or defaults
################################################################################
sub findrec {
  my $c = shift;
  my $id = $c->{edit};
  if ( ! $id ) {  # Not editing, get the latest
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
