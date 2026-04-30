# Small helper routines

package yearstat;
use strict;
use warnings;

use feature 'unicode_strings';
use utf8;  # Source code and string literals are utf-8

use POSIX qw(strftime localtime locale_h);
use URI::Escape;



################################################################################
# Annual bar graph of money spent per year, stacked by location
################################################################################

# Hard-coded colors for up to 12 locations; last slot is for "Other"
my @BARCOLS = qw(
  e6194b 3cb44b ffe119 4363d8 f58231 911eb4
  42d4f4 f032e6 bfef45 fabed4 469990 aaffc3
);

# Query per-year/per-location totals and return data structure:
#   $result->{data}{$year}{$loc} = total_price
#   $result->{years}   = [ sorted asc ]
#   $result->{toplocs} = [ top-N loc names sorted desc by grand total ]
#   $result->{colors}  = { locname => hex_color, "Other" => hex_color }
sub yearbarsql {
  my $c = shift;
  my $n = shift;  # number of top locations

  my $sql = "
    SELECT
      strftime('%Y', glasses.Timestamp, '-06:00') AS yr,
      locations.Name AS loc,
      SUM(ABS(glasses.Price)) AS total
    FROM glasses
    LEFT JOIN locations ON glasses.Location = locations.Id
    WHERE glasses.Username = ?
      AND glasses.Brew IS NOT NULL
      AND glasses.Price IS NOT NULL
      AND strftime('%Y', glasses.Timestamp, '-06:00') IS NOT NULL
    GROUP BY yr, loc
    ORDER BY yr, total DESC";

  my $sth = db::query($c, $sql, $c->{username});

  my %data;
  my %grandtotal;
  my %yearset;

  while (my ($yr, $loc, $total) = $sth->fetchrow_array) {
    $loc = "(no location)" unless defined $loc && length $loc;
    $data{$yr}{$loc} += $total;
    $grandtotal{$loc} += $total;
    $yearset{$yr} = 1;
  }

  my @years = sort keys %yearset;
  return undef unless @years;  # no data

  # Pick top N locations by grand total
  my @sorted = sort { $grandtotal{$b} <=> $grandtotal{$a} } keys %grandtotal;
  my @toplocs = @sorted[0 .. $n - 1 ];

  # Build color map
  my %colors;
  my $idx = 0;
  foreach my $loc (@toplocs) {
    $colors{$loc} = $BARCOLS[$idx % scalar(@BARCOLS)];
    $idx++;
  }
  $colors{"Other"} = $BARCOLS[-1];

  return {
    data    => \%data,
    years   => \@years,
    toplocs => \@toplocs,
    colors  => \%colors,
  };
} # yearbarsql

# Generate the gnuplot PNG for the stacked bar chart
sub yearbar_plot {
  my $c      = shift;
  my $res    = shift;
  my $pngfile = shift;

  my $data    = $res->{data};
  my $years   = $res->{years};
  my $toplocs = $res->{toplocs};
  my $colors  = $res->{colors};

  # Write data file (reuse $c->{plotfile})
  open my $fh, '>', $c->{plotfile}
    or util::error("yearbar_plot: could not open $c->{plotfile}: $!");
  foreach my $yr (@$years) {
    my $yrlabel = "'" . substr($yr, 2, 2);  # apostrophe + two-digit label e.g. "'26"
    my $line = $yrlabel;
    my $other = 0;
    foreach my $loc (@$toplocs) {
      my $val = $data->{$yr}{$loc} || 0;
      $line .= sprintf(" %.0f", $val);
    }
    # Sum everything not in toplocs into Other
    foreach my $loc (keys %{$data->{$yr}}) {
      next if grep { $_ eq $loc } @$toplocs;
      $other += $data->{$yr}{$loc} || 0;
    }
    $line .= sprintf(" %.0f", $other);
    print $fh "$line\n";
  }
  close $fh;

  # Build plot command — one 'using' clause per column, explicit color
  my $ncols = scalar(@$toplocs) + 1;  # toplocs + Other
  my $col = 2;
  my $plotcmd = "";
  foreach my $loc (@$toplocs) {
    my $color = $colors->{$loc};
    $plotcmd .= "'$c->{plotfile}' using $col:xtic(1) lc rgb \"#$color\" notitle, \\\n";
    $col++;
  }
  $plotcmd .= "'$c->{plotfile}' using $col:xtic(1) lc rgb \"#$colors->{Other}\" notitle";

  my $bgcolor = $c->{bgcolor};
  my $cmd = ""
    . "set term png small size 700,300\n"
    . "set out \"$pngfile\"\n"
    . "set style data histograms\n"
    . "set style histogram rowstacked\n"
    . "set style fill solid noborder\n"
    . "set boxwidth 0.8\n"
    . "set yrange [0:]\n"
    . "set xtics textcolor \"white\"\n"
    . "set ytics textcolor \"white\"\n"
    . "set border linecolor \"white\"\n"
    . "set grid ytics lc \"white\" lw 0.5 dt 3\n"
    . "set object 1 rect noclip from screen 0,0 to screen 1,1 "
    . "behind fc \"$bgcolor\" fillstyle solid border\n"
    . "unset key\n"
    . "plot $plotcmd\n";

  open my $cfh, '>', $c->{cmdfile}
    or util::error("yearbar_plot: could not open $c->{cmdfile}: $!");
  print $cfh $cmd;
  close $cfh;

  system("gnuplot $c->{cmdfile}");
} # yearbar_plot

# Top-level: generate (or reuse cached) bar chart, return color map for table dots
sub yearbar {
  my $c = shift;
  my $n = util::param($c, "maxl") || 8;

  my $pngfile = $c->{datadir} . $c->{username} . ".yearbars-$n.png";

  my $res = yearbarsql($c, $n);
  return $res unless $res;  # no price data

  if (-r $pngfile) {
    print { $c->{log} } "yearbar: reusing cached $pngfile\n";
  } else {
    print { $c->{log} } "yearbar: generating $pngfile\n";
    yearbar_plot($c, $res, $pngfile);
  }

  print "<img src=\"$pngfile\" style='max-width:95vw'/><br/>\n";
  return $res->{colors};
} # yearbar

################################################################################
# Annual summary
################################################################################
# TODO - Maybe count zero days as well
# TODO - Now loops through all possible lines to get the sums, they could
# be got a bit faster from the db. But it is fast enough as it is.

# Helper to make one line of the table
sub yearline {
  my ( $price, $drinks, $visits, $name, $dot ) = @_;
  my $s = "<tr>";
  $price  = util::unit( sprintf( "%6d",   $price ),  ".-" ) || "";
  $drinks = util::unit( sprintf( "%7.1f", $drinks ), "d" ) if ($drinks);
  $visits = sprintf( "%4d", $visits ) if ($visits);
  $s .= "<td class='num'>&nbsp; $price &nbsp; </td>";
  $s .= "<td class='num'> &nbsp; $drinks  &nbsp; </td>";
  $s .= "<td class='num'> &nbsp; $visits  &nbsp; </td>";
  my $dothtml = $dot
    ? " <span style='display:inline-block;width:10px;height:10px;background:#$dot;margin-left:4px;vertical-align:middle'></span>"
    : "";
  $s .= "<td> &nbsp;$name$dothtml </td>";
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
        "select distinct strftime('%Y',Timestamp, '-06:00') as yy "
      . " from glasses "
      . " where Username = ? "
      . " and Brew is not null "
      . " and strftime('%Y',Timestamp, '-06:00') is not null "
      . " order by yy desc";
    my $years_ref =
      $c->{dbh}->selectcol_arrayref( $sqly, undef, $c->{username} );
    @years = @$years_ref;
  }

  # Show stacked bar graph when viewing all years
  my %dotcolors;
  if ( !$c->{qry} ) {
    my $colors = yearbar($c);
    %dotcolors = %$colors if $colors;
  }

  my $sql = "
    select
      locations.Name as name,
      sum(ABS(glasses.Price)) as price,
      sum(glasses.StDrinks) as drinks,
      count(distinct(strftime('%Y-%m-%d',glasses.timestamp, '-06:00'))) as visits
    from glasses
    left join locations on glasses.Location = locations.Id
    where strftime('%Y', glasses.Timestamp, '-06:00') = ?
    and glasses.Username = ?
    and glasses.Brew is not null
    and strftime('%Y', glasses.Timestamp, '-06:00') is not null
    group by name ";
  if ($sortdr) {
    $sql .= "order by drinks desc, name COLLATE NOCASE";
  }
  else {
    $sql .= "order by price desc, name COLLATE NOCASE";
  }
  print { $c->{log} } "u='$c->{username}' y=" . join( '-', @years ) . " $sql \n";
  my $sth = db::query($c, $sql,  $c->{username});

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
    print "<tr><td class='num'>Kroner &nbsp;</td>"
      . "<td class='num'>Drinks &nbsp;</td>"
      . "<td class='num'>Visits&nbsp;</td><td></td></tr>\n";
    $sth->execute( "$y", $c->{username} );
    my $ln = $nlines;

    while (1) {
      my ( $name, $price, $drinks, $visits ) = $sth->fetchrow_array;
      last unless ($name);
      $ypr += $price if ($price);
      $ydr += $drinks if ($drinks);
      $yv  += $visits if ($visits);
      if ( $ln-- > 0 ) {
        my $dot = $dotcolors{$name};
        print yearline( $price, $drinks, $visits, $name, $dot );
      }
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
