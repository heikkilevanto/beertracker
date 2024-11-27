# Part of my beertracker
# The main form for inputting a glass record, with all its extras
# And the routine to save it in the database
# Also a list of most recent glasses I've drunk

package glasses;
use strict;
use warnings;



# Structure of the input form
# - Choose a brew, or enter a new one. Should be the first part, as submitting a
#   new brew will have to reload the page.
# - Location. Default to same as before. Later add geo magic for an option to
#   choose a nearby location.
# - Volume and price.
# - Submit the glass
# - Once submitted, allow adding comments and ratings to it

################################################################################
# The input form
################################################################################
sub inputform {
  my $c = shift;
  my $rec = findrec($c); # Get defaults, or the record we are editing
  print "Main input form <hr/>";
  print "<table>\n";
  print "<tr><td>Location</td>\n";
  print "<td>" . locations::selectlocation($c, $rec->{Location}, "newloc") . "</td></tr>\n";
  print "<tr><td>" . selectbrewtype($c,$rec->{BrewType}) ."</td>\n";
  print "<td>". brews::selectbrew($c,$rec->{Brew},$rec->{BrewType}). "</td></tr>\n";
  print "</table>\n";
  print "<hr>\n";
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
