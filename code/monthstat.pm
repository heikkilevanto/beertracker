# Small helper routines

package monthstat;
use strict;
use warnings;

use feature 'unicode_strings';
use utf8;  # Source code and string literals are utf-8


# TODO - Split this into smaller functions, it is quite long as it is

sub monthstat {
  my $c      = shift;
  my $firsty = "";
  my %monthdrinks;
  my %monthprices;
  my $money_mode = (util::param($c, "s") =~ /^m/);
  my $lastmonthday;    # last day of the last month

  # Optional date range filters from gstart and gend parameters (month-based)
  # Default gstart to 2000-01; support YYYY-MM or YYYY-MM-DD (we trim to YYYY-MM)
  my $gstart = util::param($c, "gstart", "2000-01");
  my $gend   = util::param($c, "gend", "");

  # Normalize to YYYY-MM
  $gstart =~ s/^(\d{4}-\d{2})-\d{2}$/$1/;
  $gend   =~ s/^(\d{4}-\d{2})-\d{2}$/$1/ if $gend;

  my $calmon_expr = "strftime ('%Y-%m', timestamp,'-06:00')";
  my $where_clause = "WHERE Username = ?";
  my @sql_params = ( $c->{username} );
  if ( $gstart ) {
    $where_clause .= " AND $calmon_expr >= ?";
    push( @sql_params, $gstart );
  }
  if ( $gend ) {
    $where_clause .= " AND $calmon_expr <= ?";
    push( @sql_params, $gend );
  }
  $where_clause .= " AND (Brew IS NOT NULL OR BrewType = 'Adjustment')";

  my $sumsql = qq{
  SELECT
    DISTINCT strftime ('%Y-%m', timestamp,'-06:00') AS calmon,
    sum(CASE WHEN BrewType = 'Adjustment'
             THEN price
             ELSE ABS(price) END) AS pr,
  	sum(stdrinks) AS drinks,
  	min( strftime ('%d', timestamp,'-06:00')) AS first,
 	  max( strftime ('%d', timestamp,'-06:00')) AS last
  FROM glasses
  $where_clause
  GROUP BY calmon
  ORDER BY calmon
  };

  my $sum_sth = db::query($c, $sumsql, @sql_params);
  my %monthfirstday;
  while ( my ( $calmon, $pr, $drinks, $first, $last ) = $sum_sth->fetchrow_array ) {
    $monthdrinks{$calmon} = $drinks;
    $monthprices{$calmon} = $pr;
    $monthfirstday{$calmon} = $first;
    $lastmonthday         = $last;     # Remember the last day
    if ( !$firsty ) {
      $firsty = $1 if ( $calmon =~ /^(\d\d\d\d)/ );
    }
  }

  # Determine user's overall first month for partial-month divisor
  my ($firstym) = $c->{dbh}->selectrow_array(
    "SELECT min(strftime('%Y-%m', Timestamp, '-06:00')) FROM glasses"
    . " WHERE Username = ? AND Brew IS NOT NULL",
    undef, $c->{username});

  if ( !$firsty ) {
    util::error("No data found");
  }

  my $pngfile = $c->{plotfile};
  $pngfile =~ s/\.plot/-stat.png/;

  # Use filtered end month for x-axis range, or current date if not filtered
  my $lasty      = util::datestr( "%Y", 0 );
  my $lastm      = util::datestr( "%m", 0 );
  if ( $gend ) {
    if ( $gend =~ /^(\d{4})-(\d{2})/ ) {
      $lasty = $1;
      $lastm = $2;
    }
  }

  my $lastym     = "$lasty-$lastm";
  # Use actual last day from data when filtering to past months to avoid inflating averages
  my $dayofmonth = util::datestr("%d");
  $dayofmonth = $lastmonthday if ($gend && $lastmonthday);
  # Don't count today unless there are beers recorded for it
  if (!$gend && $lastmonthday && $lastmonthday < $dayofmonth) {
    $dayofmonth--;
    $dayofmonth = 1 if $dayofmonth < 1;
  }

  open my $fh, ">", $c->{plotfile}
    or util::error("Could not open $c->{plotfile} for writing");
  my @ydays;
  my @ydrinks;
  my @yprice;
  my @yearcolors;
  my $y = $lasty + 1;
  $yearcolors[ $y-- ] = "#FFFFFF";    # Next year, not really used
  $yearcolors[ $y-- ] = "#FF0000";    # current year, in bright red
  $yearcolors[ $y-- ] = "#800000";    # Prev year, in darker red
  $yearcolors[ $y-- ] = "#00F0F0";    # Cyan
  $yearcolors[ $y-- ] = "#00C0C0";
  $yearcolors[ $y-- ] = "#008080";
  $yearcolors[ $y-- ] = "#00FF00";    # Green
  $yearcolors[ $y-- ] = "#00C000";
  $yearcolors[ $y-- ] = "#008000";
  $yearcolors[ $y-- ] = "#FFFF00";    # yellow
  $yearcolors[ $y-- ] = "#C0C000";
  $yearcolors[ $y-- ] = "#808000";
  $yearcolors[ $y-- ] = "#C000C0";    # purple 2014 # not yet visible in 2026
  $yearcolors[ $y-- ] = "#800080";
  $yearcolors[ $y-- ] = "#400040";

  while ( $y > $firsty - 2 ) {
    $yearcolors[ $y-- ] = "#808080";    # The rest in some kind of grey
  }

  # Anything after this will be white by default
  # Should work for a few years. We don't have data from before 2016.
  my $t = "";
  $t .= "<br/><table class=data >\n";
  $t .= "<tr><td>&nbsp;</td>\n";
  my @months = (
    "",    "Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul",
    "Aug", "Sep", "Oct", "Nov", "Dec"
  );
  my @plotlines;    # data lines for plotting
  my $plotyear = 2001;
  foreach $y ( reverse( $firsty .. $lasty ) ) {
    $t .=
      "<td align='right' ><b style='color:$yearcolors[$y]'>&nbsp;$y</b></td>";
  }
  $t .= "<td align='right'><b>&nbsp;Avg</b></td>";
  $t .= "</tr>\n";
  my $max_plot_val = 0;
  foreach my $m ( 1 .. 12 ) {
    my $plotline;
    $t .= "<tr><td><b>$months[$m]</b></td>\n";
    $plotyear-- if ( $m == $lastm + 1 );
    $plotline = sprintf( "%4d-%02d ", $plotyear, $m );
    my $mdrinks = 0;
    my $mprice  = 0;
    my $mcount  = 0;
    my $prevplotval = "NaN";

    foreach $y ( reverse( $firsty .. $lasty ) ) {
      my $calm = sprintf( "%d-%02d", $y, $m );
      my $d    = "";
      my $dd;
      if ( $monthdrinks{$calm} ) {
        my $div = 30;
        if ( $calm eq $firstym ) {
          my $fd = $monthfirstday{$calm};
          if ( $calm eq $lastym ) {
            $div = $dayofmonth - $fd + 1;
          } else {
            $div = 30 - $fd + 1;
          }
        } elsif ( $calm eq $lastym ) {
          $div = $dayofmonth;
        }
        $ydrinks[$y] += $monthdrinks{$calm};
        $yprice[$y]  += $monthprices{$calm};
        $ydays[$y]   += $div;
        $d  = ( $monthdrinks{$calm} || 0 );
        $dd = sprintf( "%3.1f", $d / $div );
        if ( $calm eq $lastym ) {
          $d  = "~" . util::unit( $dd, "/d" );
        }
        else {
          if ( $dd < 10 ) {
            $d = util::unit( $dd, "/d" );
          }
          else {
            $d = $dd;
          }
        }
        $mdrinks += $dd;
        $mcount++;
      }
      my $p  = $monthprices{$calm} || "";
      my $dw = $1 if ( $d =~ /([0-9.]+)/ );
      $dw = $dw || 0;
      $dw = util::unit( int( $dw * 7 + 0.5 ), "/w" );
      $t .= "<td align=right>";
      if ($p) {
        $t .= "$d<br/>$dw<br/>$p";
        if ( $calm eq $lastym && $monthprices{$calm} ) {
          $p = "";
my $price_div = $dayofmonth;
          $price_div = $dayofmonth - $monthfirstday{$calm} + 1 if ($calm eq $firstym);
          $p = int( $monthprices{$calm} / $price_div * 30 );
          $t .= "<br/>~$p";
        }
        $mprice += $p;
      }
      $t .= "</td>\n";
      if ( $y == $lasty ) {    # First column is special for projections
        $plotline .= "NaN  ";
      }
      $dd = "NaN" unless ($d);      # unknown value
      my $plotval = $dd;
      $plotval = $monthprices{$calm} // "NaN" if ($money_mode);
      if ($money_mode && $monthprices{$calm} && $calm eq $lastym) {
        my $price_div = $dayofmonth;
        $price_div = $dayofmonth - $monthfirstday{$calm} + 1 if ($calm eq $firstym);
        $plotval = int($plotval / $price_div * 30);
      }
      if ($plotval ne "NaN" && $plotval =~ /^[0-9.]+$/ && $calm ne $lastym && $plotval > $max_plot_val) {
        $max_plot_val = $plotval;
      }
      if ( $plotyear == 2001 ) {    # After current month
        if ( $m == 1 ) {
          $plotline .= "$plotval $prevplotval  ";
        }
        else {
          $plotline .= "$plotval NaN  ";
        }
      }
      else {
        $plotline .= "NaN $plotval  ";
      }
      $prevplotval = $plotval;
    }
    if ($mcount) {
      $mdrinks = sprintf( "%3.1f", $mdrinks / $mcount );
      $mprice  = sprintf( "%3.1f", $mprice / $mcount );
      my $dw = $1 if ( $mdrinks =~ /([0-9.]+)/ );
      $dw = util::unit( int( $dw * 7 + 0.5 ), "/w" );
      $t .=
          "<td align=right>"
        . util::unit( $mdrinks, "/d" )
        . "<br/>$dw"
        . "<br/>&nbsp;$mprice</td>\n";
    }
    $t        .= "</tr>";
    $plotline .= "\n";
    push( @plotlines, $plotline );
  }
  print $fh sort(@plotlines);

  # Projections
  # Projections for the visible last month (respect filters)

  my $cur      = $lastm;              # month number of last visible month
  my $curmonth = $lastym;             # YYYY-MM of last visible month

  # Compute cap for projection dot based on max value seen on graph
  my $proj_cap = 10;
  $proj_cap = $max_plot_val * 1.05 if ($max_plot_val > 0);

  my $d;
  my $min;
  my $avg;
  my $max;
  my $arrow_max_s = "NaN";
  if ($money_mode) {
    $d   = ( $monthprices{$curmonth} || 0 );
    if ($d > 0) {
      $min = $d;
      $avg = "NaN";
      $avg = int($d / $dayofmonth * 30) if ($dayofmonth);
      $max = "NaN";
      $max = int(2 * $avg - $min) if ($avg ne "NaN");
      $max = 0 if ($max ne "NaN" && $max < 0);
$arrow_max_s = "NaN";
      $arrow_max_s = sprintf("%3.1f", $max) if ($max ne "NaN");
      $max = "NaN" if ($max ne "NaN" && $max > $proj_cap);
    } else {
      $min = "NaN";
      $avg = "NaN";
      $max = "NaN";
    }
  } else {
    $d   = ( $monthdrinks{$curmonth} || 0 );
    $min = "NaN";
    $min = $d / 30 if ($d > 0);
    $avg = "NaN";
    $avg = $d / $dayofmonth if ($d > 0 && $dayofmonth);
    $max = "NaN";
    $max = 2 * $avg - $min if ($avg ne "NaN" && $min ne "NaN");
    $arrow_max_s = "NaN";
    $arrow_max_s = sprintf("%3.1f", $max) if ($max ne "NaN");
    if ( $max ne "NaN" ) {
      $max = "NaN" if ( $max > $proj_cap );
      $max = 0  if ( $max < 0 );
    }
  }
  my $min_s = sprintf("%3.1f", $min);
  $min_s = "NaN" if ($min eq "NaN");
  my $avg_s = sprintf("%3.1f", $avg);
  $avg_s = "NaN" if ($avg eq "NaN");
  my $max_s = sprintf("%3.1f", $max);
  $max_s = "NaN" if ($max eq "NaN");
  my $metric_char = "d";
  $metric_char = "m" if ($money_mode);
  print { $c->{log} } "monthstat $curmonth $metric_char: min=$min_s avg=$avg_s max=$max_s maxy=$max_plot_val cap=$proj_cap\n";
  print $fh "\n";

  print $fh "2001-$cur $min_s\n";  # low

  print $fh "2001-$cur $avg_s\n";  # mid (current average)

  print $fh "2001-$cur $max_s\n";  # high
  close($fh);

  # Dashed red lines from previous month value to low/high projection dots
  my $proj_arrow_cmd = "";
  my $prev_m = $cur - 1;
  if ($prev_m >= 1) {
    my $prev_calmon = sprintf("%d-%02d", $lasty, $prev_m);
    my $prev_plotval = "NaN";
    my $prev_m_str = sprintf("%02d", $prev_m);
    if ($money_mode) {
      if (defined $monthprices{$prev_calmon} && $monthprices{$prev_calmon}) {
        $prev_plotval = $monthprices{$prev_calmon};
      }
    } else {
      if ($monthdrinks{$prev_calmon}) {
        my $prev_div = 30;
        if ($prev_calmon eq $firstym) {
          my $fd = $monthfirstday{$prev_calmon};
          $prev_div = 30 - $fd + 1;
        }
        $prev_plotval = sprintf("%3.1f", $monthdrinks{$prev_calmon} / $prev_div);
      }
    }
    if ($prev_plotval ne "NaN" && $min_s ne "NaN") {
      $proj_arrow_cmd .= "set arrow from \"2001-$prev_m_str\", $prev_plotval to \"2001-$cur\", $min_s nohead linecolor \"red\" linewidth 1 dashtype 2\n";
    }
    if ($prev_plotval ne "NaN" && $arrow_max_s ne "NaN") {
      $proj_arrow_cmd .= "set arrow from \"2001-$prev_m_str\", $prev_plotval to \"2001-$cur\", $arrow_max_s nohead linecolor \"red\" linewidth 1 dashtype 2\n";
    }
  }
  $t .= "<tr><td>Avg</td>\n";
  my $granddr    = 0;
  my $granddays  = 0;
  my $grandprice = 0;
  my $p;

  foreach $y ( reverse( $firsty .. $lasty ) ) {
    my $d  = "";
    my $dw = "";
    if ( $ydays[$y] ) {    # have data for the year
      $granddr   += $ydrinks[$y];
      $granddays += $ydays[$y];
      $d  = sprintf( "%3.1f", $ydrinks[$y] / $ydays[$y] );
      $dw = $1 if ( $d =~ /([0-9.]+)/ );
      $dw = util::unit( int( $dw * 7 + 0.5 ), "/w" );
      $d  = util::unit( $d,                   "/d" );
      $p  = int( 30 * $yprice[$y] / $ydays[$y] + 0.5 );
      $grandprice += $yprice[$y];
    }
    $t .= "<td align=right>$d<br/>$dw<br/>$p</td>\n";
  }
  $d = sprintf( "%3.1f", $granddr / $granddays );
  my $dw = $1 if ( $d =~ /([0-9.]+)/ );
  $dw = util::unit( int( $dw * 7 + 0.5 ), "/w" );
  $d  = util::unit( $d,                   "/d" );
  $p  = int( 30 * $grandprice / $granddays + 0.5 );
  $t .= "<td align=right>$d<br/>$dw<br>$p</td>\n";
  $t .= "</tr>\n";

  $t .= "<tr><td>Sum</td>\n";
  my $grandtot = 0;
  foreach $y ( reverse( $firsty .. $lasty ) ) {
    my $pr = "";
    if ( $ydays[$y] ) {    # have data for the year
      $pr =
        util::unit( sprintf( "%5.0f", ( $yprice[$y] + 500 ) / 1000 ), " k" );
      $grandtot += $yprice[$y];
    }
    $t .= "<td align=right>$pr";
    if ( $y eq $lasty && $yprice[$lasty] ) {
      $pr = $yprice[$lasty] / $ydays[$lasty] * 365;
      $pr = util::unit( sprintf( "%5.0f", ( $pr + 500 ) / 1000 ), " k" );
      $pr =~ s/^ *//;    # Remove leading space
      $t .= "<br/>~$pr";
    }
    $t .= "</td>\n";
  }
  $grandtot =
    util::unit( sprintf( "%5.0f", ( $grandtot + 500 ) / 1000 ), " k" );
  $t .= "<td align=right>$grandtot</td>\n";
  $t .= "</tr>\n";

  # Column legends again
  $t .= "<tr><td>&nbsp;</td>\n";
  foreach $y ( reverse( $firsty .. $lasty ) ) {
    $t .=
      "<td align='right'><b style='color:$yearcolors[$y]'>&nbsp;$y</b></td>";
  }
  $t .= "<td align='right'><b>&nbsp;Avg</b></td>";
  $t .= "</tr>\n";

  $t .= "</table>\n";
  my $imgsz = "640,480";
  my $white  = "textcolor \"white\" ";
  my $firstm = $lastm + 1;
  my $firstm_str = sprintf( "%02d", $firstm );
  my $lastm_str  = sprintf( "%02d", $lastm );
  my $xrange_end = "";
  $xrange_end = "\"2001-01\"" if ($lastm == 1);
  my $y2_cmd = "set link y2 via y inverse y\nset y2tics $white\nset format y2 '%.0s%c'\n";
  my $ytics_args = "1 $white";
  $ytics_args = $white if ($money_mode);
  my $ytics_cmd = "set ytics $ytics_args\n"
    . "set format y '%.0s%c'\n";
  my $arrow_cmd = $proj_arrow_cmd;
  if (!$money_mode) {
    $arrow_cmd = "set arrow from \"2000-$firstm_str\", 1 to \"2001-$lastm_str\", 1 nohead linewidth 0.1 linecolor \"green\" \n"
      . "set arrow from \"2000-$firstm_str\", 4 to \"2001-$lastm_str\", 4 nohead linewidth 0.1 linecolor \"yellow\" \n"
      . "set arrow from \"2000-$firstm_str\", 7 to \"2001-$lastm_str\", 7 nohead linewidth 0.1 linecolor \"orange\" \n"
      . "set arrow from \"2000-$firstm_str\", 10 to \"2001-$lastm_str\", 10 nohead linewidth 0.1 linecolor \"red\" \n"
      . "set arrow from \"2000-$firstm_str\", 13 to \"2001-$lastm_str\", 13 nohead linewidth 0.1 linecolor \"#f409c9\" \n"
      . "set arrow from \"2001-01\", 0 to \"2001-01\", 10 nohead linewidth 0.1 linecolor \"white\" \n"
      . $proj_arrow_cmd;
  }
  my $cmd = ""
    . "set term png small size $imgsz \n"
    . "set out \"$pngfile\" \n"
    . "set yrange [0:$proj_cap] \n"
    . "set tmargin 0 \n"
    . "set xtics $white\n"
    . "set mxtics 1 \n"
    . $ytics_cmd
    . $y2_cmd
    . "set mytics 2 \n"
    . "set grid xtics ytics\n"
    . "set xdata time \n"
    . "set timefmt \"%Y-%m\" \n"
    . "set format x \"%b\"\n"

    . "set xrange [\"2000-$firstm_str\" : $xrange_end] \n "
    . "set key right top horizontal textcolor \"white\" \n "
    . "set object 1 rect noclip from screen 0, screen 0 to screen 1, screen 1 "
    . "behind fc \"$c->{bgcolor}\" fillstyle solid border \n"
    .    # green bkg
    "set border linecolor \"white\" \n"
    . $arrow_cmd
    . "plot ";
  my $lw = 2;
  my $yy = $firsty;
  for ( my $i = 2 * ( $lasty - $firsty ) + 3 ; $i > 2 ; $i -= 2 )
  {      # i is the column in plot file
    $lw++ if ( $yy == $lasty );
    my $col = "$yearcolors[$yy]";
    $cmd .= "\"$c->{plotfile}\" "
      . "using 1:$i with line lc \"$col\" lw $lw notitle , ";
    my $j = $i + 1;
    $cmd .= "\"$c->{plotfile}\" "
      . "using 1:$j with line lc \"$col\" lw $lw notitle , ";
    $lw += 0.35;
    $yy++;
  }

  # Finish by plotting low/high projections for current month
  $cmd .= "\"$c->{plotfile}\" "
    . "using 1:2 with points pt 6 lc \"$yearcolors[$lasty]\" lw 2 notitle,";
  $cmd .= "\n";
  open my $ch, ">", $c->{cmdfile}
    or util::error("Could not open $c->{cmdfile} for writing");
  print $ch $cmd;
  close($ch);
  system("gnuplot $c->{cmdfile} ");

  my $sz = "style='max-width:95vw;max-height:120vh'";
  print "<br/><img src=\"$pngfile\" $sz /><br/>\n";
  # Toggle between drinks and money graph
  my $filter_qs = "";
  $filter_qs .= "&gstart=$gstart" if $c->{cgi}->param("gstart");
  $filter_qs .= "&gend=$gend" if $c->{cgi}->param("gend");
  if ($money_mode) {
    print "<a href='$c->{url}?o=Months$filter_qs'><span>Show drinks</span></a><br/>\n";
  } else {
    print "<a href='$c->{url}?o=Months&s=money$filter_qs'><span>Show money spent</span></a><br/>\n";
  }
  print $t;    # The table we built above
}  # monthstats


################################################################################
# Report module loaded ok
1;
