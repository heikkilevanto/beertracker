package stats;

################################################################################
# Variosu statistics of my beer database
################################################################################


use strict;
use warnings;

use feature 'unicode_strings';
use utf8;  # Source code and string literals are utf-8

################################################################################
# Sub-menu for the various statistics pages
################################################################################
sub statsmenu {
  my $c = shift;
  print "Other stats: \n";
  my %stats;
  $stats{"short"} = "Days";
  $stats{"Months"} = "Months";
  $stats{"Years"} = "Years";
  $stats{"DataStats"} = "Datafile";
  for my $k ( keys(%stats) ) {
    my $tag= "span";
    $tag = "b" if ( $k =~ /$c->{op}/i ) ;
    print "<a href='$c->{url}?o=k'><$tag>$stats{$k}</$tag></a>&nbsp;\n";
  }
  print "<hr/>\n";
}



################################################################################
# Statistics of the data file
################################################################################
# TODO - Get more interesting stats.
# NOTE - Maybe later get global values and values for current user.
sub datastats {
  my $c = shift;
  statsmenu($c);

  print "<table>\n";
  print "<tr><td></td><td><b>Data file stats</b></td></tr>\n";

  print "<tr></tr>\n";
  print "<tr><td></td><td><b>General</b></td></tr>\n";
  my $dfsize = -s $c->{databasefile};
  $dfsize = int($dfsize / 1024);
  print "<tr><td align='right'>$dfsize</td><td>kb in $c->{databasefile}</td></tr>\n";

  print "<tr><td>&nbsp;</td></tr>\n";
  print "<tr><td></td><td><b>Users</b></td></tr>\n";
  my $sql = "select username as username, count(*) as recs from glasses group by username";
  my $sth = $c->{dbh}->prepare($sql);
  $sth->execute();
  while ( my $rec = $sth->fetchrow_hashref ) {
    #print STDERR "U: ", JSON->new->encode($rec), "\n";
    print "<tr>\n";
    print "<td><b>$rec->{username}</b> </td>\n";
    print "<td>$rec->{recs} glasses</td>\n";
    print "</tr>\n";
  }
  $sth->finish;

  print "<tr><td>&nbsp;</td></tr>\n";
  print "<tr><td></td><td><b>Glasses </b></td></tr>\n";
  $sql = "select brewtype, count(*) as count from glasses " .
         "group by brewtype order by count desc";
  $sth = $c->{dbh}->prepare($sql);
  $sth->execute();
  while ( my $rec = $sth->fetchrow_hashref ) {
    #print STDERR "U: ", JSON->new->encode($rec), "\n";
    print "<tr>\n";
    print "<td><b>$rec->{BrewType}</b> </td>\n";
    print "<td>$rec->{count} glasses</td>\n";
    print "</tr>\n";
  }
  $sth->finish;

  print "<tr><td>&nbsp;</td></tr>\n";
  print "<tr><td></td><td><b>Brews </b></td></tr>\n";
  $sql = "select brewtype, count(*) as count from brews " .
         "group by brewtype order by count desc";
  $sth = $c->{dbh}->prepare($sql);
  $sth->execute();
  while ( my $rec = $sth->fetchrow_hashref ) {
    #print STDERR "U: ", JSON->new->encode($rec), "\n";
    print "<tr>\n";
    print "<td><b>$rec->{BrewType}</b> </td>\n";
    print "<td>$rec->{count} brews</td>\n";
    print "</tr>\n";
  }
  $sth->finish;
  # TODO: Find brews that have one or no glasses associated with them

  print "<tr><td>&nbsp;</td></tr>\n";
  print "<tr><td></td><td><b>Producers</b></td></tr>\n";
  $sql = "select LocType, LocSubType, count(name) as count ".
         "from locations where LocType = 'Producer' " .
         "group by LocType, LocSubType " .
         "order by LocType, count desc,  LocSubType ";
  $sth = $c->{dbh}->prepare($sql);
  $sth->execute();
  while ( my $rec = $sth->fetchrow_hashref ) {
    #print STDERR "U: ", JSON->new->encode($rec), "\n";
    print "<tr>\n";
    print "<td><b>$rec->{LocSubType}</b> </td>\n";
    print "<td>$rec->{count} producers</td>\n";
    print "</tr>\n";
  }
  $sth->finish;

  print "<tr><td>&nbsp;</td></tr>\n";
  print "<tr><td></td><td><b>Locations</b></td></tr>\n";
  $sql = "select LocType, LocSubType, count(name) as count ".
         "from locations where LocType <> 'Producer' " .
         "group by LocType, LocSubType " .
         "order by LocType, count desc,  LocSubType ";
  $sth = $c->{dbh}->prepare($sql);
  $sth->execute();
  while ( my $rec = $sth->fetchrow_hashref ) {
    #print STDERR "U: ", JSON->new->encode($rec), "\n";
    print "<tr>\n";
    print "<td><b>$rec->{LocType}, $rec->{LocSubType}</b> </td>\n";
    print "<td>$rec->{count} locations</td>\n";
    print "</tr>\n";
  }
  $sth->finish;

  # TODO: Comments, on brew type, night, restaurant
  # TODO: Ratings, min/max/avg/count, on brewtype
  # TODO: Photos, on brewtype (night/rest) or person
  # TODO: Persons - what to say of them? Have no categories.

  print "</table>\n";
} # datastats

################################################################################
# Daily Statistics
################################################################################
# Also known as thje short list
sub dailystats {
  my $c = shift;
  statsmenu($c);
  my @weekdays = ( "Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun" );

  print "<div style='overflow-x: auto;'>";
  print "<table style='white-space: nowrap;'>\n";
  print "<tr><td></td><td colspan='3'><b>Daily stats</b></td></tr>\n";

  my $sql = "SELECT
    strftime('%Y-%m-%d %w', Glasses.TimeStamp, '-06:00' ) as date,
    floor(julianday( Glasses.TimeStamp, '-06:00', '12:00' )) as julian,
    sum(StDrinks) as drinks,
    SUM(glasses.price) AS price,
    GROUP_CONCAT(DISTINCT locations.name) AS locations
    FROM glasses
    LEFT JOIN locations ON glasses.location = locations.id
    GROUP BY date
    ORDER BY date desc";

  my $sth = $c->{dbh}->prepare($sql);
  $sth->execute();
  my $prev = 0;
  while ( my $rec = $sth->fetchrow_hashref ) {
    my $jul = $rec->{julian};
    my $daydiff = $prev - $jul;
    $prev = $jul;
    if ( $daydiff > 1 ) {
      print "<tr><td colspan='2'>... ";
      $daydiff--; # Count only empty days in between)
      print "$daydiff days ..." if ( $daydiff > 1 );
      print "</td></tr>\n";
    }
    print "<tr>";
    my ($date, $wd) = util::splitdate($rec->{date});
    $wd =~ s/Sun/<b>Sun<\/b>/;
    print "<td>$date $wd</td>";
    print "<td align='right'>" . util::unit($rec->{drinks},"d") . "</td>";
    print "<td align='right'>" . util::unit($rec->{price},".-") . "</td>";
    my $locs = $rec->{locations};
    $locs =~ s/,/, /g;
    print "<td>&nbsp; $locs</td>\n";
    #print "<td>", JSON->new->encode($rec), "</td>", "\n";
    print "</tr>";
  }

  print "</table></div>\n";

} # dailystats
################################################################################
1;  # Module loaded ok
