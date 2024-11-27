# Part of my beertracker
# Stuff for listing, selecting, adding, and editing brews

# TODO - Select a brew
# TODO - Insert a new one
# TODO - Edit a brew

package brews;
use strict;
use warnings;



################################################################################
# List of brews
################################################################################
# TODO - More display fields. Country, region, etc
# TODO - Filtering by brew type, subtype, name, producer, etc
sub listbrews {
  my $c = shift; # context
  persons::listsmenubar($c);

  if ( $c->{edit} =~ /^\d+$/ ) {  # Id for full info
    #editbrew($c);  # TODO
    return;
  }

  # Sort order or filtering
  my $sort = "last DESC";
  $sort = "BREWS.Id" if ( $c->{sort} eq "id" );
  $sort = "BREWS.Name" if ( $c->{sort} eq "name" );
  $sort = "BREWS.Producer" if ( $c->{sort} eq "maker" );
  $sort = "BREWS.BrewType, BREWS.Subtype COLLATE NOCASE" if ( $c->{sort} eq "type" );
  $sort = "last DESC" if ( $c->{sort} eq "last" );
  $sort = "LOCATIONS.Name" if ( $c->{sort} eq "where" );

  # Print list of people
  my $sql = "
  select
    BREWS.Id,
    BREWS.Name,
    BREWS.Producer,
    BREWS.BrewType,
    BREWS.Subtype,
    strftime ( '%Y-%m-%d %w', max(GLASSES.Timestamp), '-06:00' ) as last,
    LOCATIONS.Name as loc,
    count(COMMENTS.Id) as count
  from BREWS
  left join GLASSES on Glasses.Brew = BREWS.Id
  left join COMMENTS on COMMENTS.Glass = GLASSES.Id
  left join LOCATIONS on LOCATIONS.id = GLASSES.Location
  group by BREWS.id
  order by $sort
  ";
  my $list_sth = $c->{dbh}->prepare($sql);
  #$list_sth->execute($c->{username});
  $list_sth->execute();

  print "<table><tr>\n";
  # TODO - Set a max-width for the name, so one long one will not mess up, esp on the phone
  my $url = $c->{url};
  my $op = $c->{op};
  my $maxwidth = "style='max-width:20em;'";
  print "<td><a href='$url?o=$op&s=id'><i>Id</i></a></td>";
  print "<td><a href='$url?o=$op&s=name'><i>Name</i></a></td>";
  print "<td><a href='$url?o=$op&s=maker'><i>Producer</i></a></td>";
  print "<td><a href='$url?o=$op&s=type'><i>Type</i></a></td>";
  print "<td><a href='$url?o=$op&s=last'><i>Last seen</i></a></td>";
  print "<td><a href='$url?o=$op&s=where'><i>Where</i></a></td></tr>";
  while ( my ($id, $name, $maker, $typ, $sub, $last, $loc, $count) = $list_sth->fetchrow_array ) {
    my ($wd, $stamp) = ("", "(never)");
    $loc = "" unless ($loc);
    if ( $last ) {
      ($stamp, $wd ) = split (' ', $last);
      my @weekdays = ( "Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun" );
      $wd = $weekdays[$wd];
    }

    print "<tr><td style='font-size: xx-small' align='right'>$id</td>\n";
    print "<td $maxwidth><a href='$url?o=$op&e=$id'><b>$name</b></a>";
    print " ($count) " if ( $count > 1 );
    print "<td $maxwidth>$maker</td>";
    print "</td>\n";
    print "<td>$typ, $sub </td>\n";
    print "<td>$wd " . main::filt($stamp,"","","full") . "</td>\n";
    print "<td>$loc</td></tr>\n";
  }
  print "</table>\n";
  print "<hr/>\n" ;
} # listpersons

################################################################################
# Select a brew
# A key component of the main input form
################################################################################
# TODO - Many features missing
# TODO - Instead of thje "Brew" label, make a pulldown of brew styles
# TODO - Put the brews in a JS array with id, dispname, style, substyle
# TODO - Make a JS to put only the selected style brews into the list
# TODO - Add an option to filter: Show filter field, redo the list on every change
sub selectbrew {
  my $c = shift; # context
  my $selected = shift || "";  # The id of the selected brew
  my $sql = "
  select
    BREWS.Id,
    BREWS.Name,
    BREWS.Producer,
    strftime ( '%Y-%m-%d %w', max(GLASSES.Timestamp), '-06:00' ) as last
  from BREWS
  left join GLASSES on GLASSES.Brew= BREWS.ID
  group by BREWS.id
  order by GLASSES.Timestamp DESC
  LIMIT 500
  ";
  my $list_sth = $c->{dbh}->prepare($sql);
  $list_sth->execute(); # username ?
  my $s = "";
  $s .= "<div id='newbrewdiv' hidden>";
  $s .= "<input name='newbrewname' placeholder='New Name'/><br/>\n";
  $s .= "<input name='newbrewmaker' width placeholder='Producer'/><br/>\n";
  $s .= "<input name='newalc'  placeholder='Alc'/><br/>\n";
  $s .= "</div>";
  $s .= << "scriptend";
    <script>
      function brewselchange() {
        var sel = document.getElementById("brewsel");
        console.log ("Brew changed to " + sel.value);
        if ( sel.value == "new" ) {
          console.log("Got a 'new'");
          var inp = document.getElementById("newbrewdiv");
          sel.hidden = true;
          inp.hidden = false;
        }
      }
      </script>
scriptend
  $s .= " <select name='brewsel' id='brewsel' onchange='brewselchange();'>\n";
  my $sel = "";
  #$sel = "Selected" unless $selected ;
  $s .= "<option value='' $sel >(select)</option>\n";
  $s .= "<option value='new' >(new)</option>\n" ;
  while ( my ($id, $name, $prod, $last) = $list_sth->fetchrow_array ) {
    $sel = "";
    $sel = "Selected" if $id eq $selected;
    $s .=  "<option value='$id' $sel >$prod: $name</option>\n";
  }
  $s .= "</select>\n";
  return $s;
} # selectbrew



################################################################################
# Report module loaded ok
1;
