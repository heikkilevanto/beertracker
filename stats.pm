package stats;

################################################################################
# Variosu statistics of my beer database
################################################################################


use strict;
use warnings;

use feature 'unicode_strings';
use utf8;  # Source code and string literals are utf-8
use File::Basename;
use URI::Escape;

################################################################################
# Sub-menu for the various statistics pages
################################################################################
sub statsmenu {
  my $c = shift;
  print "Other stats: \n";
  my %stats;
  $stats{"Short"} = "Days";
  $stats{"DataStats"} = "Datafile";
  for my $k ("Short","Months","Years","DataStats" ) {
    my $tag= "span";
    $tag = "b" if ( $k =~ /$c->{op}/i ) ;
    my $name = $stats{$k} || $k;
    print "<a href='$c->{url}?o=$k'><$tag>$name</$tag></a>&nbsp;\n";
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
  my $dbname = basename($c->{databasefile});
  print "<tr><td align='right'>$dfsize</td><td>kb in <b>$dbname</b></td></tr>\n";

  print "<tr><td>&nbsp;</td></tr>\n";
  print "<tr><td></td><td><b>Users</b></td></tr>\n";
  my $sql = "select username as username, count(*) as recs from glasses group by username order by username";
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
  $sql = "select brewtype, count(*) as count from glasses " .
         "group by brewtype order by count desc";
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
  $sql = "select brewtype, count(*) as count from brews " .
         "group by brewtype order by count desc";
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
  $sql = "select LocType, LocSubType, count(name) as count ".
         "from locations where LocType = 'Producer' " .
         "group by LocType, LocSubType " .
         "order by LocType, count desc,  LocSubType ";
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
  $sql = "select LocType, LocSubType, count(name) as count ".
         "from locations where LocType <> 'Producer' " .
         "group by LocType, LocSubType " .
         "order by LocType, count desc,  LocSubType COLLATE NOCASE";
  $sth = $c->{dbh}->prepare($sql);
  $sth->execute();
  my $singles = "";
  while ( my $rec = $sth->fetchrow_hashref ) {
    #print STDERR "U: ", JSON->new->encode($rec), "\n";
    if ( $rec->{LocType} =~ /Restaurant/i && $rec->{count} == 1 ) {
      $singles .= "$rec->{LocSubType}, ";
    } else {
      print "<tr>\n";
      print "<td align='right'>$rec->{count}</td>\n";
      print "<td><b>$rec->{LocType}, $rec->{LocSubType}</b> </td>\n";
      print "</tr>\n";
    }
  }
  $sth->finish;
  if ( $singles ){
    $singles =~ s/, *$//; # remove trailing comma
    print "<tr><td></td><td>And <b>one</b> of each of these:</td></tr> \n";
    print "<tr><td></td><td>$singles</td></tr> \n";
  }


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
    where Username = ?
    GROUP BY date
    ORDER BY date desc";
  # Unfortunately group_concat will not take a delimiter. If a place name
  # has a comma, it looks a bit silly. Usually clear enough from context.
  my $sth = $c->{dbh}->prepare($sql);
  $sth->execute($c->{username});
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
# Monthly statistics
################################################################################

sub monthstat {
  my $c = shift;
  my $defbig = $c->{mobile} ? "S" : "B";
  my $bigimg = shift || $defbig;
  $bigimg =~ s/S//i ;
  statsmenu($c);

  my $firsty="";

  my %monthdrinks;
  my %monthprices;
  my $lastmonthday;  # last day of the last month

  my $sumsql = q{
  select
    distinct strftime ('%Y-%m', timestamp,'-06:00') as calmon,
  	sum(abs(price)) as pr,
  	sum(stdrinks) as drinks,
 	  max( strftime ('%d', timestamp,'-06:00')) as last
  from glasses
  where Username = ?
  group by calmon
  order by calmon
  };

  my $sum_sth = $c->{dbh}->prepare($sumsql);
  $sum_sth->execute($c->{username});
  while ( my ( $calmon, $pr, $drinks, $last ) = $sum_sth->fetchrow_array ) {
    $monthdrinks{$calmon} = $drinks;
    $monthprices{$calmon} = $pr; # negative prices for buying box wines
    $lastmonthday = $last;  # Remember the last day
    if ( !$firsty ) {
      $firsty = $1 if ( $calmon =~ /^(\d\d\d\d)/ );
    }
  }

  if ( !$firsty ) {
    util::error("No data found");
  }

  my $pngfile = $c->{plotfile};
  $pngfile =~ s/\.plot/-stat.png/;
  my $lasty = util::datestr("%Y",0);
  my $lastm = util::datestr("%m",0);
  my $lastym = "$lasty-$lastm";
  my $dayofmonth = util::datestr("%d");

  open F, ">$c->{plotfile}"
      or util::error ("Could not open $c->{plotfile} for writing");
  my @ydays;
  my @ydrinks;
  my @yprice;
  my @yearcolors;
  my $y = $lasty+1;
  $yearcolors[$y--] = "#FFFFFF";  # Next year, not really used
  $yearcolors[$y--] = "#FF0000";  # current year, in bright red
  $yearcolors[$y--] = "#800000";  # Prev year, in darker red
  $yearcolors[$y--] = "#00F0F0";  # Cyan
  $yearcolors[$y--] = "#00C0C0";
  $yearcolors[$y--] = "#008080";
  $yearcolors[$y--] = "#00FF00";  # Green
  $yearcolors[$y--] = "#00C000";
  $yearcolors[$y--] = "#008000";
  $yearcolors[$y--] = "#FFFF00";  # yellow
  $yearcolors[$y--] = "#C0C000";
  $yearcolors[$y--] = "#808000";
  $yearcolors[$y--] = "#C000C0";  # purple 2014 # not yet visible in 2024
  $yearcolors[$y--] = "#800080";
  $yearcolors[$y--] = "#400040";
  while ( $y > $firsty -2 ) {
    $yearcolors[$y--] = "#808080";  # The rest in some kind of grey
  }
  # Anything after this will be white by default
  # Should work for a few years
  my $t = "";
    $t .= "<br/><table border=1 >\n";
  $t .="<tr><td>&nbsp;</td>\n";
  my @months = ( "", "Jan", "Feb", "Mar", "Apr", "May", "Jun",
                 "Jul", "Aug", "Sep", "Oct", "Nov", "Dec");
  my @plotlines; # data lines for plotting
  my $plotyear = 2001;
  foreach $y ( reverse($firsty .. $lasty) ) {
    $t .= "<td align='right' ><b style='color:$yearcolors[$y]'>&nbsp;$y</b></td>";
  }
  $t .= "<td align='right'><b>&nbsp;Avg</b></td>";
  $t .= "</tr>\n";
  foreach my $m ( 1 .. 12 ) {
    my $plotline;
    $t .= "<tr><td><b>$months[$m]</b></td>\n";
    $plotyear-- if ( $m == $lastm+1 );
    $plotline = sprintf("%4d-%02d ", $plotyear, $m );
    my $mdrinks = 0;
    my $mprice = 0;
    my $mcount = 0;
    my $prevdd = "NaN";
    foreach $y ( reverse($firsty .. $lasty) ) {
      my $calm = sprintf("%d-%02d",$y,$m);
      my $d="";
      my $dd;
      if ($monthdrinks{$calm}) {
        $ydrinks[$y] += $monthdrinks{$calm};
        $yprice[$y] += $monthprices{$calm};
        $ydays[$y] += 30;
        $d = ($monthdrinks{$calm}||0);
        $dd = sprintf("%3.1f", $d / 30); # scale to dr/day, approx
        if ( $calm eq $lastym ) { # current month
          $dd = sprintf("%3.1f", $d / $dayofmonth); # scale to dr/day
          $d = "~" . util::unit($dd,"/d");
          $ydays[$y] += $dayofmonth - 30;
        } else {
          $dd = sprintf("%3.1f", $d / 30); # scale to dr/day, approx
          if ( $dd < 10 ) {
            $d = util::unit($dd,"/d"); #  "9.3/d"
          } else {
            $d = $dd; # but "10.3", no room for the /d
          }
        }
        $mdrinks += $dd;
        $mcount++;
      }
      my $p = $monthprices{$calm}||"";
      my $dw = $1 if ($d=~/([0-9.]+)/);
      $dw = $dw || 0;
      $dw = util::unit(int($dw *7 +0.5), "/w");
      $t .= "<td align=right>";
      if ( $p ) { # Skips the fake Feb
        $t .= "$d<br/>$dw<br/>$p";
        if ($calm eq $lastym && $monthprices{$calm} ) {
          $p = "";
          $p = int($monthprices{$calm} / $dayofmonth * 30);
          $t .= "<br/>~$p";
        }
        $mprice += $p;
      }
      $t .= "</td>\n";
      if ($y == $lasty ) { # First column is special for projections
        $plotline .= "NaN  ";
      }
      $dd = "NaN" unless ($d);  # unknown value
      if ( $plotyear == 2001 ) {  # After current month
        if ( $m == 1 ) {
          $plotline .=  "$dd $prevdd  ";
        } else {
          $plotline .=  "$dd NaN  ";
        }
      } else {
        $plotline .=  "NaN $dd  ";
      }
      $prevdd = $dd;
    }
    if ( $mcount) {
      $mdrinks = sprintf("%3.1f", $mdrinks/$mcount);
      $mprice = sprintf("%3.1d", $mprice/$mcount);
      my $dw = $1 if ($mdrinks=~/([0-9.]+)/);
      $dw = util::unit(int($dw*7+0.5), "/w");
      $t .= "<td align=right>". util::unit($mdrinks,"/d") .
        "<br/>$dw" .
        "<br/>&nbsp;$mprice</td>\n";
   }
    $t .= "</tr>";
    $plotline .=  "\n";
    push (@plotlines, $plotline);
  }
  print F sort(@plotlines);
  # Projections
  my $cur = util::datestr("%m",0);
  my $curmonth = util::datestr("%Y-%m",0);
  my $d = ($monthdrinks{$curmonth}||0) ;
  my $min = sprintf("%3.1f", $d / 30);  # for whole month
  my $avg = $d / $dayofmonth;
  my $max = 2 * $avg - $min;
  $max = "NaN" if ($max > 10) ;  # Don't mess with scaling of the graph
  $max = sprintf("%3.1f", $max);
  print F "\n";
  print F "2001-$cur $min\n";
  print F "2001-$cur $max\n";
  close(F);
  $t .= "<tr><td>Avg</td>\n";
  my $granddr = 0;
  my $granddays = 0;
  my $grandprice = 0;
  my $p;
  foreach $y ( reverse($firsty .. $lasty) ) {
    my $d = "";
    my $dw = "";
    if ( $ydays[$y] ) { # have data for the year
      $granddr += $ydrinks[$y];
      $granddays += $ydays[$y];
      $d = sprintf("%3.1f", $ydrinks[$y] / $ydays[$y] ) ;
      $dw = $1 if ($d=~/([0-9.]+)/);
      $dw = util::unit(int($dw*7+0.5), "/w");
      $d = util::unit($d, "/d");
      $p = int(30*$yprice[$y]/$ydays[$y]+0.5);
      $grandprice += $yprice[$y];
    }
    $t .= "<td align=right>$d<br/>$dw<br/>$p</td>\n";
  }
  $d = sprintf("%3.1f", $granddr / $granddays ) ;
  my $dw = $1 if ($d=~/([0-9.]+)/);
  $dw = util::unit(int($dw*7+0.5), "/w");
  $d = util::unit($d, "/d");
  $p = int (30 * $grandprice / $granddays + 0.5);
  $t .= "<td align=right>$d<br/>$dw<br>$p</td>\n";
  $t .= "</tr>\n";

  $t .= "<tr><td>Sum</td>\n";
  my $grandtot = 0;
  foreach $y ( reverse($firsty .. $lasty) ) {
    my $pr  = "";
    if ( $ydays[$y] ) { # have data for the year
      $pr = util::unit(sprintf("%5.0f", ($yprice[$y]+500)/1000), " k") ;
      $grandtot += $yprice[$y];
    }
    $t .= "<td align=right>$pr";
    if ( $y eq $lasty && $yprice[$lasty] ) {
      $pr = $yprice[$lasty] / $ydays[$lasty] * 365;
      $pr = util::unit(sprintf("%5.0f", ($pr+500)/1000), " k") ;
      $pr =~ s/^ *//;  # Remove leading space
      $t .= "<br/>~$pr";
    }
    $t .= "</td>\n";
  }
  $grandtot = util::unit(sprintf("%5.0f",($grandtot+500)/1000), " k");
  $t .= "<td align=right>$grandtot</td>\n";
  $t .= "</tr>\n";

  # Column legends again
  $t .="<tr><td>&nbsp;</td>\n";
  foreach $y ( reverse($firsty .. $lasty) ) {
    $t .= "<td align='right'><b style='color:$yearcolors[$y]'>&nbsp;$y</b></td>";
  }
  $t .= "<td align='right'><b>&nbsp;Avg</b></td>";
  $t .= "</tr>\n";

  $t .= "</table>\n";
  my $imgsz = "340,240";
  if ($bigimg) {
    $imgsz = "640,480";
  }
  my $white = "textcolor \"white\" ";
  my $firstm = $lastm+1;
  my $cmd = "" .
       "set term png small size $imgsz \n".
       "set out \"$pngfile\" \n".
       "set yrange [0:] \n" .
       "set xtics $white\n".
       "set mxtics 1 \n".
       "set ytics 1 $white\n".
       "set mytics 2 \n".
       "set link y2 via y*7 inverse y/7\n".
       "set y2tics 7 $white\n".
       "set grid xtics ytics\n".
       "set xdata time \n".
       "set timefmt \"%Y-%m\" \n".
       "set format x \"%b\"\n" .
       #"set format x \"%b\"\n" .
       "set xrange [\"2000-$firstm\" : ] \n " .
       "set key right top horizontal textcolor \"white\" \n " .
       "set object 1 rect noclip from screen 0, screen 0 to screen 1, screen 1 " .
          "behind fc \"$c->{bgcolor}\" fillstyle solid border \n".  # green bkg
       "set border linecolor \"white\" \n" .
       "set arrow from \"2000-$firstm\", 1 to \"2001-$lastm\", 1 nohead linewidth 0.1 linecolor \"white\" \n" .
       "set arrow from \"2000-$firstm\", 4 to \"2001-$lastm\", 4 nohead linewidth 0.1 linecolor \"white\" \n" .
       "set arrow from \"2000-$firstm\", 7 to \"2001-$lastm\", 7 nohead linewidth 0.1 linecolor \"white\" \n" .
       "set arrow from \"2000-$firstm\", 10 to \"2001-$lastm\", 10 nohead linewidth 0.1 linecolor \"white\" \n" .
       "set arrow from \"2000-$firstm\", 13 to \"2001-$lastm\", 13 nohead linewidth 0.1 linecolor \"white\" \n" .
       "set arrow from \"2001-01\", 0 to \"2001-01\", 10 nohead linewidth 0.1 linecolor \"white\" \n" .
       "plot ";
  my $lw = 2;
  my $yy = $firsty;
  for ( my $i = 2*($lasty - $firsty) +3; $i > 2; $i -= 2) { # i is the column in plot file
    $lw++ if ( $yy == $lasty );
    my $col = "$yearcolors[$yy]";
    $cmd .= "\"$c->{plotfile}\" " .
            "using 1:$i with line lc \"$col\" lw $lw notitle , " ;
    my $j = $i +1;
    $cmd .= "\"$c->{plotfile}\" " .
            "using 1:$j with line lc \"$col\" lw $lw notitle , " ;
    $lw+= 0.25;
    $yy++;
  }
  # Finish by plotting low/high projections for current month
  $cmd .= "\"$c->{plotfile}\" " .
            "using 1:2 with points pt 6 lc \"$yearcolors[$lasty]\" lw 2 notitle," ;
  $cmd .= "\n";
  open C, ">$c->{cmdfile}"
      or util::error ("Could not open $c->{plotfile} for writing");
  print C $cmd;
  close(C);
  system ("gnuplot $c->{cmdfile} ");
  if ($bigimg) {
    print "<a href='$->{url}?o=MonthsS'><img src=\"$pngfile\"/></a><br/>\n";
  } else {
    print "<a href='$->{url}?o=MonthsB'><img src=\"$pngfile\"/></a><br/>\n";
  }
  print $t;  # The table we built above
  exit();
} # Monthly stats





################################################################################
# Annual summary
################################################################################
# TODO - Maybe count zero days as well
# TODO - Now loops through all possible lines to get the sums, they could
# be got a bit faster from the db. But it is fast enough as it is.


# Helper to make one line of the table
sub yearline {
  my ($price, $drinks, $visits, $name) = @_;
  my $s =  "<tr>";
  $price = util::unit( sprintf("%6d", $price), ".-" ) || "";
  $drinks = util::unit( sprintf("%7.1f", $drinks), "d" ) if ($drinks) ;
  $visits = sprintf("%4d", $visits) if ($visits);
  $s .=  "<td align='right'>&nbsp; $price &nbsp; </td>";
  $s .= "<td align='right'> &nbsp; $drinks  &nbsp; </td>";
  $s .= "<td align='right'> &nbsp; $visits  &nbsp; </td>";
  $s .= "<td> &nbsp; $name </td>";
  $s .= "</tr>\n";
  return $s;
}

sub yearsummary {
  my $c = shift;
  my $sortdr = shift;

  statsmenu($c);

  my $sofar = "so far";
  my @years;
  if ( $c->{qry} ) {
    @years = ( $c->{qry} ) ;
    $sofar = ""; # no projections
  } else {
    my $sqly = "select distinct strftime('%Y',Timestamp) as yy " .
      " from glasses " .
      " where Username = ? " .
      " order by yy desc";
    my $years_ref = $c->{dbh}->selectcol_arrayref($sqly,undef,$c->{username});
    @years = @$years_ref;
  }

  my $sql = "
    select
      locations.Name as name,
      sum(abs(glasses.Price)) as price,
      sum(glasses.StDrinks) as drinks,
      count(distinct(strftime('%Y-%m-%d',glasses.timestamp, '-06:00'))) as visits
    from glasses
    left join locations on glasses.Location = LOCATIONS.Id
    where strftime('%Y', glasses.Timestamp, '-06:00') = ?
    and glasses.Username = ?
    and glasses.BrewType <> 'Restaurant'
    and glasses.BrewType <> 'Night'
    group by name ";
  if ( $sortdr ) {
    $sql .= "order by drinks desc, name COLLATE NOCASE";
  } else {
    $sql .= "order by price desc, name COLLATE NOCASE";
  }
  print STDERR "u='$c->{username}' y=" . join('-',@years). " $sql \n";
  my $sth = $c->{dbh}->prepare($sql);

  my $nlines = util::param($c,"maxl") || 10;
  if ($sortdr) {
    print "Sorting by drinks (<a href='$c->{url}?o=Years&q=" . uri_escape_utf8($c->{qry}) .
       "' class='no-print'><span>Sort by money</span></a>)\n";
  } else {
    print "Sorting by money (<a href='$c->{url}?o=YearsD&q=" . uri_escape_utf8($c->{qry}) .
       "' class='no-print'><span>Sort by drinks</span></a>)\n";
  }

  print "<div style='overflow-x: auto;'>";
  print "<table border='1' style='white-space: nowrap;' >\n";

  foreach my $y ( @years ) {
    my $ypr = 0;
    my $ydr = 0;
    my $yv = 0;
    my $yrlink = "<a href='$c->{url}?o=$c->{op}&q=$y&maxl=20'><span>$y</span></a>";
    print "<tr><td colspan='4'><br/>Year <b>$yrlink</b> $sofar</td></tr>\n";
    print "<tr><td align='right'>Kroner &nbsp;</td>" .
          "<td align='right'>Drinks &nbsp;</td>".
          "<td align='right'>Visits&nbsp;</td><td></td></tr>\n";
    $sth->execute("$y", $c->{username} );
    my $ln = $nlines;
    while (1) {
      my ( $name, $price, $drinks, $visits )  = $sth->fetchrow_array;
      last unless ($name);
      $ypr += $price;
      $ydr += $drinks;
      $yv += $visits;
      print yearline($price, $drinks, $visits, $name) if ( $ln-- > 0);
    }
    print "<tr>";
    print yearline($ypr, $ydr, $yv, "=TOTAL for $y $sofar");
    my $days = 365;
    if ( $sofar ) { # Project to the whole year
      $sofar = "";
      $days = util::datestr("%j");
      my $pp = 365 * $ypr / $days ;
      my $pd = 365 * $ydr / $days ;
      my $pv = 365 * $yv / $days ;
      print yearline($pp, $pd, $pv,  "=PROJECTED for whole $y &nbsp;");
    }
    print yearline( $ypr/$days, $ydr/$days, "", "=per day");
    print yearline( 7*$ypr/$days, 7*$ydr/$days, "", "=per week");

  } # year loop

  print "</table></div>\n";  # Page footer
  print "Show ";
  for my $top ( 5, 10, 20, 50, 100, 999999 ) {
    print  "&nbsp; <a href='$c->{url}?o=$c->{op}&q=" . uri_escape($c->{qry}) . "&maxl=$top'><span>Top-$top</span></a>\n";
  }
  if ($c->{qry}) {
    my $prev = "<a href='$c->{url}?o=Years&q=" . ($c->{qry} - 1) . "&maxl=" . util::param($c,'maxl') ."'><span>Prev</span></a> \n";
    my $all =  "<a href='$c->{url}?o=Years&&maxl=" . util::param($c,'maxl') ."'><span>All</span></a> \n";
    my $next = "<a href='$c->{url}?o=Years&q=" . ($c->{qry} + 1) . "&maxl=" . util::param($c,'maxl') ."'><span>Next</span></a> \n";
    print "<br/> $prev &nbsp; $all &nbsp; $next \n";
  }
  print  "<hr/>\n";
  return;

} # yearsummary





################################################################################
1;  # Module loaded ok
