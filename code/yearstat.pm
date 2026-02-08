# Small helper routines

package yearstat;
use strict;
use warnings;

use feature 'unicode_strings';
use utf8;  # Source code and string literals are utf-8

use POSIX qw(strftime localtime locale_h);
use URI::Escape;



################################################################################
# Annual summary
################################################################################
# TODO - Maybe count zero days as well
# TODO - Now loops through all possible lines to get the sums, they could
# be got a bit faster from the db. But it is fast enough as it is.

# Helper to make one line of the table
sub yearline {
  my ( $price, $drinks, $visits, $name ) = @_;
  my $s = "<tr>";
  $price  = util::unit( sprintf( "%6d",   $price ),  ".-" ) || "";
  $drinks = util::unit( sprintf( "%7.1f", $drinks ), "d" ) if ($drinks);
  $visits = sprintf( "%4d", $visits ) if ($visits);
  $s .= "<td align='right'>&nbsp; $price &nbsp; </td>";
  $s .= "<td align='right'> &nbsp; $drinks  &nbsp; </td>";
  $s .= "<td align='right'> &nbsp; $visits  &nbsp; </td>";
  $s .= "<td> &nbsp; $name </td>";
  $s .= "</tr>\n";
  return $s;
}

sub yearsummary {
  my $c      = shift;
  my $sortdr = ( $c->{sort} );

  my $sofar = "so far";
  my @years;
  if ( $c->{qry} ) {
    @years = ( $c->{qry} );
    $sofar = "";              # no projections
  }
  else {
    my $sqly =
        "select distinct strftime('%Y',Timestamp) as yy "
      . " from glasses "
      . " where Username = ? "
      . " order by yy desc";
    my $years_ref =
      $c->{dbh}->selectcol_arrayref( $sqly, undef, $c->{username} );
    @years = @$years_ref;
  }

  my $sql = "
    select
      locations.Name as name,
      sum(glasses.Price) as price,
      sum(glasses.StDrinks) as drinks,
      count(distinct(strftime('%Y-%m-%d',glasses.timestamp, '-06:00'))) as visits
    from glasses
    left join locations on glasses.Location = LOCATIONS.Id
    where strftime('%Y', glasses.Timestamp, '-06:00') = ?
    and glasses.Username = ?
    and glasses.Brew is not null
    group by name ";
  if ($sortdr) {
    $sql .= "order by drinks desc, name COLLATE NOCASE";
  }
  else {
    $sql .= "order by price desc, name COLLATE NOCASE";
  }
  print STDERR "u='$c->{username}' y=" . join( '-', @years ) . " $sql \n";
  my $sth = $c->{dbh}->prepare($sql);

  my $nlines = util::param( $c, "maxl" ) || 10;
  if ($sortdr) {
    print "Sorting by drinks (<a href='$c->{url}?o=Years&q="
      . uri_escape_utf8( $c->{qry} )
      . "' class='no-print'><span>Sort by money</span></a>)\n";
  }
  else {
    print "Sorting by money (<a href='$c->{url}?o=Years&s=d&q="
      . uri_escape_utf8( $c->{qry} )
      . "' class='no-print'><span>Sort by drinks</span></a>)\n";
  }

  print "<div style='overflow-x: auto;'>";
  print "<table class=data style='white-space: nowrap;' >\n";

  foreach my $y (@years) {
    my $ypr = 0;
    my $ydr = 0;
    my $yv  = 0;
    my $yrlink =
      "<a href='$c->{url}?o=$c->{op}&q=$y&maxl=20'><span>$y</span></a>";
    print "<tr><td colspan='4'><br/>Year <b>$yrlink</b> $sofar</td></tr>\n";
    print "<tr><td align='right'>Kroner &nbsp;</td>"
      . "<td align='right'>Drinks &nbsp;</td>"
      . "<td align='right'>Visits&nbsp;</td><td></td></tr>\n";
    $sth->execute( "$y", $c->{username} );
    my $ln = $nlines;

    while (1) {
      my ( $name, $price, $drinks, $visits ) = $sth->fetchrow_array;
      last unless ($name);
      $ypr += $price if ($price);
      $ydr += $drinks if ($drinks);
      $yv  += $visits if ($visits);
      print yearline( $price, $drinks, $visits, $name ) if ( $ln-- > 0 );
    }
    print "<tr>";
    print yearline( $ypr, $ydr, $yv, "=TOTAL for $y $sofar" );
    my $days = 365;
    if ($sofar) {    # Project to the whole year
      $sofar = "";
      $days  = util::datestr("%j");
      my $pp = 365 * $ypr / $days;
      my $pd = 365 * $ydr / $days;
      my $pv = 365 * $yv / $days;
      print yearline( $pp, $pd, $pv, "=PROJECTED for whole $y &nbsp;" );
    }
    print yearline( $ypr / $days,     $ydr / $days,     "", "=per day" );
    print yearline( 7 * $ypr / $days, 7 * $ydr / $days, "", "=per week" );

  }    # year loop

  print "</table></div>\n";    # Page footer
  print "Show ";
  for my $top ( 5, 10, 20, 50, 100, 999999 ) {
    print "&nbsp; <a href='$c->{url}?o=$c->{op}&q="
      . uri_escape( $c->{qry} )
      . "&maxl=$top'><span>Top-$top</span></a>\n";
  }
  if ( $c->{qry} ) {
    my $prev =
        "<a href='$c->{url}?o=Years&q="
      . ( $c->{qry} - 1 )
      . "&maxl="
      . util::param( $c, 'maxl' )
      . "'><span>Prev</span></a> \n";
    my $all =
        "<a href='$c->{url}?o=Years&&maxl="
      . util::param( $c, 'maxl' )
      . "'><span>All</span></a> \n";
    my $next =
        "<a href='$c->{url}?o=Years&q="
      . ( $c->{qry} + 1 )
      . "&maxl="
      . util::param( $c, 'maxl' )
      . "'><span>Next</span></a> \n";
    print "<br/> $prev &nbsp; $all &nbsp; $next \n";
  }
  print "<hr/>\n";
  return;

}    # yearsummary


################################################################################
# Report module loaded ok
1;
