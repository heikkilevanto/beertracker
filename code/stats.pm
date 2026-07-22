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
# TODO - Get more interesting stats. 
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
  my $sql = "select username as username, count(*) as recs " .
            "from glasses group by username order by username";
  my $sth = db::query($c, $sql);
  while ( my $rec = $sth->fetchrow_hashref ) {
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
  $sth = db::query($c, $sql);
  while ( my $rec = $sth->fetchrow_hashref ) {
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
  $sth = db::query($c, $sql);
  while ( my $rec = $sth->fetchrow_hashref ) {
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
  $sth = db::query($c, $sql);
  while ( my $rec = $sth->fetchrow_hashref ) {
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
  $sth = db::query($c, $sql);
  my $singles = "";

  while ( my $rec = $sth->fetchrow_hashref ) {
    if ( $rec->{LocType} =~ /Restaurant/i && $rec->{count} == 1 ) {
      $singles .= "$rec->{LocSubType}; ";
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
    $singles =~ s/; *$//;    # remove trailing semicolon
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
  my $sql = "SELECT
    strftime('%Y-%m-%d %w', glasses.Timestamp, '-06:00') AS \"Day\",
    floor(julianday(glasses.Timestamp, '-06:00', '12:00')) AS \"X_Gap\",
    SUM(StDrinks) AS \"d\",
    SUM(ABS(glasses.price)) AS \"Pr\",
    GROUP_CONCAT(locations.id || '::' || COALESCE(locations.name, '')) AS \"Locations\"
    FROM glasses
    LEFT JOIN locations ON glasses.location = locations.id
    WHERE Username = ?
    GROUP BY \"Day\"";
  print listrecords::listrecords($c, $sql, "Day-", {
    params    => [$c->{username}],
    title     => "Daily stats",
    gap_column => "X_Gap",
    no_new_link => 1,
    maxrecords  => 0,
  });
}    # dailystats


################################################################################
1;   # Module loaded ok
