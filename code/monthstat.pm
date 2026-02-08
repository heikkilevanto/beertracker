# Small helper routines

package monthstat;
use strict;
use warnings;

use feature 'unicode_strings';
use utf8;  # Source code and string literals are utf-8

use POSIX qw(strftime localtime locale_h);


# --- insert new functions here ---

sub monthstat {
  my $c      = shift;
  my $firsty = "";
  my %monthdrinks;
  my %monthprices;
  my $lastmonthday;    # last day of the last month

  # Optional date range filters from gstart and gend parameters (month-based)
  # Default gstart to 2000-01; support YYYY-MM or YYYY-MM-DD (we trim to YYYY-MM)
  my $gstart = util::param($c, "gstart", "2000-01");
  my $gend   = util::param($c, "gend", "");

  # Normalize to YYYY-MM
  $gstart =~ s/^(\d{4}-\d{2})-\d{2}$/$1/;
  $gend   =~ s/^(\d{4}-\d{2})-\d{2}$/$1/ if $gend;

  my $calmon_expr = "strftime ('%Y-%m', timestamp,'-06:00')";
  my $where_clause = "where Username = ?";
  my @sql_params = ( $c->{username} );
  if ( $gstart ) {
    $where_clause .= " and $calmon_expr >= ?";
    push( @sql_params, $gstart );
  }
  if ( $gend ) {
    $where_clause .= " and $calmon_expr <= ?";
    push( @sql_params, $gend );
  }
  $where_clause .= " and Brew is not null";

  my $sumsql = qq{
  select
    distinct strftime ('%Y-%m', timestamp,'-06:00') as calmon,
  	sum(price) as pr,
  	sum(stdrinks) as drinks,
 	  max( strftime ('%d', timestamp,'-06:00')) as last
  from glasses
  $where_clause
  group by calmon
  order by calmon
  };

  my $sum_sth = $c->{dbh}->prepare($sumsql);
  $sum_sth->execute( @sql_params );
  while ( my ( $calmon, $pr, $drinks, $last ) = $sum_sth->fetchrow_array ) {
    $monthdrinks{$calmon} = $drinks;
    $monthprices{$calmon} = $pr;       # negative prices for buying box wines
    $lastmonthday         = $last;     # Remember the last day
    if ( !$firsty ) {
      $firsty = $1 if ( $calmon =~ /^(\d\d\d\d)/ );
    }
  }

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
  my $dayofmonth = ($gend && $lastmonthday) ? $lastmonthday : util::datestr("%d");

  open F, ">$c->{plotfile}"
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
  $yearcolors[ $y-- ] = "#C000C0";    # purple 2014 # not yet visible in 2024
  $yearcolors[ $y-- ] = "#800080";
  $yearcolors[ $y-- ] = "#400040";

  while ( $y > $firsty - 2 ) {
    $yearcolors[ $y-- ] = "#808080";    # The rest in some kind of grey
  }

  # Anything after this will be white by default
  # Should work for a few years
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
  foreach my $m ( 1 .. 12 ) {
    my $plotline;
    $t .= "<tr><td><b>$months[$m]</b></td>\n";
    $plotyear-- if ( $m == $lastm + 1 );
    $plotline = sprintf( "%4d-%02d ", $plotyear, $m );
    my $mdrinks = 0;
    my $mprice  = 0;
    my $mcount  = 0;
    my $prevdd  = "NaN";

    foreach $y ( reverse( $firsty .. $lasty ) ) {
      my $calm = sprintf( "%d-%02d", $y, $m );
      my $d    = "";
      my $dd;
      if ( $monthdrinks{$calm} ) {
        $ydrinks[$y] += $monthdrinks{$calm};
        $yprice[$y]  += $monthprices{$calm};
        $ydays[$y]   += 30;
        $d  = ( $monthdrinks{$calm} || 0 );
        $dd = sprintf( "%3.1f", $d / 30 );    # scale to dr/day, approx
        if ( $calm eq $lastym ) {             # current month
          $dd = sprintf( "%3.1f", $d / $dayofmonth );    # scale to dr/day
          $d  = "~" . util::unit( $dd, "/d" );
          $ydays[$y] += $dayofmonth - 30;
        }
        else {
          $dd = sprintf( "%3.1f", $d / 30 );    # scale to dr/day, approx
          if ( $dd < 10 ) {
            $d = util::unit( $dd, "/d" );       #  "9.3/d"
          }
          else {
            $d = $dd;                           # but "10.3", no room for the /d
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
      if ($p) {    # Skips the fake Feb
        $t .= "$d<br/>$dw<br/>$p";
        if ( $calm eq $lastym && $monthprices{$calm} ) {
          $p = "";
          $p = int( $monthprices{$calm} / $dayofmonth * 30 );
          $t .= "<br/>~$p";
        }
        $mprice += $p;
      }
      $t .= "</td>\n";
      if ( $y == $lasty ) {    # First column is special for projections
        $plotline .= "NaN  ";
      }
      $dd = "NaN" unless ($d);      # unknown value
      if ( $plotyear == 2001 ) {    # After current month
        if ( $m == 1 ) {
          $plotline .= "$dd $prevdd  ";
        }
        else {
          $plotline .= "$dd NaN  ";
        }
      }
      else {
        $plotline .= "NaN $dd  ";
      }
      $prevdd = $dd;
    }
    if ($mcount) {
      $mdrinks = sprintf( "%3.1f", $mdrinks / $mcount );
      $mprice  = sprintf( "%3.1d", $mprice / $mcount );
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
  print F sort(@plotlines);

  # Projections
  # Projections for the visible last month (respect filters)
  my $cur      = $lastm;              # month number of last visible month
  my $curmonth = $lastym;             # YYYY-MM of last visible month
  my $d        = ( $monthdrinks{$curmonth} || 0 );
  my $min      = ($d > 0) ? ($d / 30) : "NaN";  # if no data, keep as NaN
  my $avg      = ($d > 0 && $dayofmonth) ? ($d / $dayofmonth) : "NaN";
  my $max      = ($avg ne "NaN" && $min ne "NaN") ? (2 * $avg - $min) : "NaN";
  if ( $max ne "NaN" ) {
    $max = "NaN" if ( $max > 10 );
    $max = 0  if ( $max < 0 );
  }
  my $min_s = ( $min eq "NaN" ) ? "NaN" : sprintf( "%3.1f", $min );
  my $avg_s = ( $avg eq "NaN" ) ? "NaN" : sprintf( "%3.1f", $avg );
  my $max_s = ( $max eq "NaN" ) ? "NaN" : sprintf( "%3.1f", $max );
  print F "\n";
  print F "2001-$cur $min_s\n";  # low
  print F "2001-$cur $avg_s\n";  # mid (current average)
  print F "2001-$cur $max_s\n";  # high
  close(F);
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
  my $xrange_end = ( $lastm == 1 ) ? "\"2001-01\"" : "";
  my $cmd    = ""
    . "set term png small size $imgsz \n"
    . "set out \"$pngfile\" \n"
    . "set yrange [0:] \n"
    . "set xtics $white\n"
    . "set mxtics 1 \n"
    . "set ytics 1 $white\n"
    . "set mytics 2 \n"
    . "set link y2 via y*7 inverse y/7\n"
    . "set y2tics 7 $white\n"
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
    . "set arrow from \"2000-$firstm_str\", 1 to \"2001-$lastm_str\", 1 nohead linewidth 0.1 linecolor \"green\" \n"
    . "set arrow from \"2000-$firstm_str\", 4 to \"2001-$lastm_str\", 4 nohead linewidth 0.1 linecolor \"yellow\" \n"
    . "set arrow from \"2000-$firstm_str\", 7 to \"2001-$lastm_str\", 7 nohead linewidth 0.1 linecolor \"orange\" \n"
    . "set arrow from \"2000-$firstm_str\", 10 to \"2001-$lastm_str\", 10 nohead linewidth 0.1 linecolor \"red\" \n"
    . "set arrow from \"2000-$firstm_str\", 13 to \"2001-$lastm_str\", 13 nohead linewidth 0.1 linecolor \"#f409c9\" \n"
    . "set arrow from \"2001-01\", 0 to \"2001-01\", 10 nohead linewidth 0.1 linecolor \"white\" \n"
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
  open C, ">$c->{cmdfile}"
    or util::error("Could not open $c->{plotfile} for writing");
  print C $cmd;
  close(C);
  system("gnuplot $c->{cmdfile} ");

  my $sz = "style='max-width:95vw;max-height:120vh'";
  print "<img src=\"$pngfile\" $sz /><br/>\n";
  print $t;    # The table we built above
  exit();
}    # Monthly stats


################################################################################
# Report module loaded ok
1;
