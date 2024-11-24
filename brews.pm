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
# Report module loaded ok
1;
