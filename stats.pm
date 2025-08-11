package stats;

################################################################################
# Various statistics of my beer database
################################################################################
# More stats in modules like monthstat and yearstat

use strict;
use warnings;

use feature 'unicode_strings';
use utf8;    # Source code and string literals are utf-8
use File::Basename;
use URI::Escape;


################################################################################
# Statistics of the data file
################################################################################
# TODO - Get more interesting stats. Histograms of ratings for different things, etc
# NOTE - Maybe later get global values and values for current user.
sub datastats {
  my $c = shift;

  print "<table>\n";
  print "<tr><td></td><td><b>Data file stats</b></td></tr>\n";

  print "<tr></tr>\n";
  print "<tr><td></td><td><b>General</b></td></tr>\n";
  my $dfsize = -s $c->{databasefile};
  $dfsize = int( $dfsize / 1024 );
  my $dbname = basename( $c->{databasefile} );
  print
    "<tr><td align='right'>$dfsize</td><td>kb in <b>$dbname</b></td></tr>\n";

  print "<tr><td>&nbsp;</td></tr>\n";
  print "<tr><td></td><td><b>Users</b></td></tr>\n";
  my $sql =
"select username as username, count(*) as recs from glasses group by username order by username";
  my $sth = $c->{dbh}->prepare($sql);
  $sth->execute();
  while ( my $rec = $sth->fetchrow_hashref ) {

    #print STDERR "U: ", JSON->new->encode($rec), "\n";
    print "<tr>\n";
    print "<td align='right'>$rec->{recs}</td>\n";
    print "<td> glasses for <b>$rec->{username}</b> </td>\n";
    print "</tr>\n";
  }
  $sth->finish;

  print "<tr><td>&nbsp;</td></tr>\n";
  print "<tr><td></td><td><b>Glasses </b></td></tr>\n";
  $sql = "select brewtype, count(*) as count from glasses "
    . "group by brewtype order by count desc";
  $sth = $c->{dbh}->prepare($sql);
  $sth->execute();
  while ( my $rec = $sth->fetchrow_hashref ) {

    #print STDERR "U: ", JSON->new->encode($rec), "\n";
    print "<tr>\n";
    print "<td align='right'>$rec->{count}</td>\n";
    print "<td>glasses of <b>$rec->{BrewType}</b> </td>\n";
    print "</tr>\n";
  }
  $sth->finish;

  print "<tr><td>&nbsp;</td></tr>\n";
  print "<tr><td></td><td><b>Brews </b></td></tr>\n";
  $sql = "select brewtype, count(*) as count from brews "
    . "group by brewtype order by count desc";
  $sth = $c->{dbh}->prepare($sql);
  $sth->execute();
  while ( my $rec = $sth->fetchrow_hashref ) {

    #print STDERR "U: ", JSON->new->encode($rec), "\n";
    print "<tr>\n";
    print "<td align='right'>$rec->{count}</td>\n";
    print "<td>types of <b>$rec->{BrewType}</b> </td>\n";
    print "</tr>\n";
  }
  $sth->finish;

  # TODO: Find brews that have one or no glasses associated with them

  print "<tr><td>&nbsp;</td></tr>\n";
  print "<tr><td></td><td><b>Producers</b></td></tr>\n";
  $sql =
      "select LocType, LocSubType, count(name) as count "
    . "from locations where LocType = 'Producer' "
    . "group by LocType, LocSubType "
    . "order by LocType, count desc,  LocSubType ";
  $sth = $c->{dbh}->prepare($sql);
  $sth->execute();
  while ( my $rec = $sth->fetchrow_hashref ) {

    #print STDERR "U: ", JSON->new->encode($rec), "\n";
    print "<tr>\n";
    print "<td align='right'>$rec->{count}</td>\n";
    print "<td> producers of <b>$rec->{LocSubType}</b> </td>\n";
    print "</tr>\n";
  }
  $sth->finish;

  print "<tr><td>&nbsp;</td></tr>\n";
  print "<tr><td></td><td><b>Locations</b></td></tr>\n";
  $sql =
      "select LocType, LocSubType, count(name) as count "
    . "from locations where LocType <> 'Producer' "
    . "group by LocType, LocSubType "
    . "order by LocType, count desc,  LocSubType COLLATE NOCASE";
  $sth = $c->{dbh}->prepare($sql);
  $sth->execute();
  my $singles = "";

  while ( my $rec = $sth->fetchrow_hashref ) {

    #print STDERR "U: ", JSON->new->encode($rec), "\n";
    if ( $rec->{LocType} =~ /Restaurant/i && $rec->{count} == 1 ) {
      $singles .= "$rec->{LocSubType}, ";
    }
    else {
      $rec->{LocSubType} = "???" unless ( $rec->{LocSubType} );
      print "<tr>\n";
      print "<td align='right'>$rec->{count}</td>\n";
      print "<td><b>$rec->{LocType}, $rec->{LocSubType}</b> </td>\n";
      print "</tr>\n";
    }
  }
  $sth->finish;
  if ($singles) {
    $singles =~ s/, *$//;    # remove trailing comma
    print "<tr><td></td><td>And <b>one</b> of each of these types of Restaurants:</td></tr> \n";
    print "<tr><td></td><td>$singles</td></tr> \n";
  }

  # TODO: Comments, on brew type, night, restaurant
  # TODO: Ratings, min/max/avg/count, on brewtype
  # TODO: Photos, on brewtype (night/rest) or person
  # TODO: Persons - what to say of them? Have no categories.

  print "</table>\n";
}    # datastats

################################################################################
# Daily Statistics
################################################################################
# Also known as the short list

sub dailystats {
  my $c = shift;
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
    where Username = ?
    GROUP BY date
    ORDER BY date desc";

  # Unfortunately group_concat will not take a delimiter. If a place name
  # has a comma, it looks a bit silly. Usually clear enough from context.
  my $sth = $c->{dbh}->prepare($sql);
  $sth->execute( $c->{username} );
  my $prev = 0;
  while ( my $rec = $sth->fetchrow_hashref ) {
    my $jul     = $rec->{julian};
    my $daydiff = $prev - $jul;
    $prev = $jul;
    if ( $daydiff > 1 ) {
      print "<tr><td colspan='2'>... ";
      $daydiff--;    # Count only empty days in between)
      print "$daydiff days ..." if ( $daydiff > 1 );
      print "</td></tr>\n";
    }
    print "<tr>";
    my ( $date, $wd ) = util::splitdate( $rec->{date} );
    $wd =~ s/Sun/<b>Sun<\/b>/;
    print "<td>$date $wd</td>";
    print "<td align='right'>" . util::unit( $rec->{drinks}, "d" ) . "</td>";
    print "<td align='right'>" . util::unit( $rec->{price},  ".-" ) . "</td>";
    my $locs = $rec->{locations};
    $locs =~ s/,/, /g;
    print "<td>&nbsp; $locs</td>\n";

    #print "<td>", JSON->new->encode($rec), "</td>", "\n";
    print "</tr>";
  }

  print "</table></div>\n";

}    # dailystats


################################################################################
1;   # Module loaded ok
