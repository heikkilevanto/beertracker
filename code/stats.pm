package stats;

################################################################################
# Various statistics of my beer database
################################################################################
# More stats in modules like monthstat and yearstat

use strict;
use warnings;

use feature 'unicode_strings';
use utf8;    # Source code and string literals are utf-8
use open ':encoding(UTF-8)';  # Data files are in utf-8
use File::Basename;


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
  my $sql = "SELECT username AS username, count(*) AS recs " .
            "FROM glasses GROUP BY username ORDER BY username";
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
  $sql = "SELECT brewtype, count(*) AS count FROM glasses "
    . "GROUP BY brewtype ORDER BY count DESC";
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
  $sql = "SELECT brewtype, count(*) AS count FROM brews "
       . "GROUP BY brewtype ORDER BY count DESC";
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
      "SELECT LocType, LocSubType, count(name) AS count "
    . "FROM locations WHERE LocType = 'Producer' "
    . "GROUP BY LocType, LocSubType "
    . "ORDER BY LocType, count DESC,  LocSubType ";
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
      "SELECT LocType, LocSubType, count(name) AS count "
    . "FROM locations WHERE LocType <> 'Producer' "
    . "GROUP BY LocType, LocSubType "
    . "ORDER BY LocType, count DESC,  LocSubType COLLATE NOCASE";
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

  # TODO: Photos, on brewtype (night/rest) or person
  # TODO: Persons - what to say of them? Have no categories. Tags?

  print "</table>\n";
} # datastats

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
    SUM(CASE WHEN glasses.BrewType = 'Adjustment' THEN glasses.price
             ELSE ABS(glasses.price) END) AS \"Pr\",
    GROUP_CONCAT(locations.id || '::' || COALESCE(locations.name, '')) AS \"Locations\"
    FROM glasses
    LEFT JOIN locations ON glasses.location = locations.id
    WHERE Username = ?
    GROUP BY \"Day\" ORDER BY \"Day\" DESC";
  print listrecords::listrecords($c, $sql, {
    params    => [$c->{username}],
    title     => "Daily stats",
    gap_column => "X_Gap",
    no_new_link => 1,
    maxrecords  => 0,
  });
}    # dailystats


################################################################################
1;   # Module loaded ok
