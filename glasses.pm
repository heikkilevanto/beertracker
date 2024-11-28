# Part of my beertracker
# The main form for inputting a glass record, with all its extras
# And the routine to save it in the database
# Also a list of most recent glasses I've drunk

package glasses;
use strict;
use warnings;



# Structure of the input form
# - Location. Default to same as before. Later add geo magic for an option to
#   choose a nearby location.
# - Choose a brew, or enter a new one.
# - Volume and price.
# - Submit the glass
# - Once submitted, allow adding comments and ratings to it

################################################################################
# The input form
################################################################################
# TODO - (Hidden) line for date and time
# TODO - Turn into a form that submits. Process it
sub inputform {
  my $c = shift;
  my $rec = findrec($c); # Get defaults, or the record we are editing
  print "\n<form method='POST' accept-charset='UTF-8' class='no-print' " .
        "enctype='multipart/form-data'>\n";
  print "<table>\n";

  print "<tr><td>Location</td>\n";
  print "<td>" . locations::selectlocation($c, $rec->{Location}, "newloc") . "</td></tr>\n";

  # Brew style and brew selection
  print "<tr><td>" . selectbrewtype($c,$rec->{BrewType}) ."</td>\n";
  print "<td>". brews::selectbrew($c,$rec->{Brew},$rec->{BrewType}). "</td></tr>\n";

  # Vol, Alc, and Price
  print "<tr><td>&nbsp;</td><td id='avp'>\n";
  print "<input name='vol' placeholder='vol' size='3' value='$rec->{Volume}' />\n";
  print "<input name='alc' placeholder='alc' size='3' value='$rec->{Alc}' />\n";
  print "<input name='pr' placeholder='pr' size='3' value='$rec->{Price}' />\n";
  print "</td></tr>\n";

  # Buttons
  print "<tr><td>\n";
  if ($c->{edit}) {
    print " <input type='submit' name='submit' value='Save' id='save' />\n";
    print "</td><td>\n";
    print " <input type='submit' name='submit' value='Del'/>\n";
    print "<a href='$c->{url}?o=$c->{op}' ><span>cancel</span></a>";
    print "</td>\n";
  } else { # New glass
    print "<input type='submit' name='submit' value='Record'/>\n";
    print "</td><td>\n";
    print " <input type='submit' name='submit' value='Save' id='save' />\n";
    print " <input type='button' value='Clr' onclick='clearinputs()'/>\n";
  }
  print "&nbsp;" ;
  persons::showmenu($c);

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
  my $sth = $c->{dbh}->prepare($sql);
  $sth->execute( $id, $c->{username} );
  my $rec = $sth->fetchrow_hashref;
  main::error ("Can not find record id '$id' for username '$c->{username}' ") unless ( $rec->{Timestamp} );
  return $rec;
}

################################################################################
# Report module loaded ok
1;
