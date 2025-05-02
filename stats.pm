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
      " order by yy desc";
    my $sthy = $c->{dbh}->prepare($sqly);
    $sthy->execute;
    my $years_ref = $c->{dbh}->selectcol_arrayref($sqly);
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
    and glasses.BrewType <> 'Restaurant'
    and glasses.BrewType <> 'Night'
    group by name ";
  if ( $sortdr ) {
    $sql .= "order by drinks desc, name";
  } else {
    $sql .= "order by price desc, name";
  }
  my $sth = $c->{dbh}->prepare($sql);

  my $nlines = util::param($c,"maxl") || 10;
  if ($sortdr) {
    print "Sorting by drinks (<a href='$c->{url}?o=Years&q=" . uri_escape_utf8($c->{qry}) .
       "' class='no-print'><span>Sort by money</span></a>)\n";
  } else {
    print "Sorting by money (<a href='$c->{url}?o=YearsD&q=" . uri_escape_utf8($c->{qry}) .
       "' class='no-print'><span>Sort by drinks</span></a>)\n";
  }
  print "<table border=1>\n";

  foreach my $y ( @years ) {
    my $ypr = 0;
    my $ydr = 0;
    my $yv = 0;
    my $yrlink = "<a href='$c->{url}?o=$c->{op}&q=$y&maxl=20'><span>$y</span></a>";
    print "<tr><td colspan='4'><br/>Year <b>$yrlink</b> $sofar</td></tr>\n";
    print "<tr><td align='right'>Kroner &nbsp;</td>" .
          "<td align='right'>Drinks &nbsp;</td>".
          "<td>Visits &nbsp;</td><td></td></tr>\n";
    $sth->execute("$y" );
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
      print yearline($pp, $pd, $pv,  "=PROJECTED for whole $y");
    }
    print yearline( $ypr/$days, $ydr/$days, "", "=per day");
    print yearline( 7*$ypr/$days, 7*$ydr/$days, "", "=per week");

  } # year loop

  print "</table>\n";  # Page footer
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

my $OLDCODE = <<'EOF'
  # FIXME Old code, delete soon
  my $i = scalar( @lines );
  while ( $i > 0 ) {
    $i--;
    my $rec = getrecord($i);
    next unless ($rec);
    next if ($rec->{type} =~ "Restaurant|Night" );
    my $loc = $rec->{loc};
    $y = substr($rec->{effdate},0,4);
    #print "  y=$y, ty=$thisyear <br/>\n";

    if ($i == 0) { # count also the last line
      $thisyear = $y unless ($thisyear);
      $y = "END";
      $sum{$loc} += abs($rec->{pr});
      $alc{$loc} += $rec->{alcvol};
      $ysum += abs($rec->{pr});
      $yalc += $rec->{alcvol};
    }
    if ( $y ne $thisyear ) {
      if ($thisyear && (!$qry || $thisyear == $qry) ) {
        if ( $thisyear ne datestr("%Y") ) { # We are in the next year already
          $sofar = "";
        }
        my $yrlink = $thisyear;
        if (!$qry) {
          $yrlink = "<a href='$url?o=$op&q=$thisyear&maxl=20'><span>$thisyear</span></a>";
        }
        print "<tr><td colspan='3'><br/>Year <b>$yrlink</b> $sofar</td></tr>\n";
        my @kl;
        if ($sortdr) {
          @kl = sort { $alc{$b} <=> $alc{$a} }  keys %alc;
        } else {
          @kl = sort { $sum{$b} <=> $sum{$a} }  keys %sum;
        }
        my $k = 0;
        while ( $k < $nlines && $kl[$k] ) {
          my $loc = $kl[$k];
          my $alc = unit(sprintf("%5.0f", $alc{$loc} / $onedrink),"d");
          my $pr = unit(sprintf("%6.0f", $sum{$loc}),".-");
          print "<tr><td align='right'>$pr&nbsp;</td>\n" .
            "<td align=right>$alc&nbsp;</td>" .
            "<td>&nbsp;". filt($loc)."</td></tr>\n";
          $k++;
        }
        my $alc = unit(sprintf("%5.0f", $yalc / $onedrink),"d");
        my $pr = unit(sprintf("%6.0f", $ysum),".-");
        print "<tr><td align=right>$pr&nbsp;</td>" .
          "<td align=right>$alc&nbsp;</td>" .
          "<td> &nbsp;  = TOTAL for $thisyear $sofar</td></tr> \n";
        my $daynum = 365;
        if ($sofar) {
          $daynum = datestr("%j"); # day number in year
          my $alcp = unit(sprintf("%5.0f", $yalc / $onedrink / $daynum * 365),"d");
          my $prp = unit(sprintf("%6.0f", $ysum / $daynum * 365),".-");
          print "<tr><td align=right>$prp&nbsp;</td>".
            "<td align=right>$alcp&nbsp;</td>".
            "<td>&nbsp; = PROJECTED for whole $thisyear</td></tr>\n";
        }
        my $alcday = $yalc / $onedrink / $daynum;
        my $prday = $ysum / $daynum;
        my $alcdayu = unit(sprintf("%5.1f", $alcday),"d");
        my $prdayu = unit(sprintf("%6.0f", $prday),".-");
        print "<tr><td align=right>$prdayu&nbsp;</td>" .
          "<td align=right>$alcdayu&nbsp;</td>" .
          "<td>&nbsp; = per day</td></tr>\n";
        $alcday = unit(sprintf("%5.1f", $alcday *7),"d");
        $prday = unit(sprintf("%6.0f", $prday *7),".-");
        print "<tr><td align=right>$prday&nbsp;</td>" .
          "<td align=right>$alcday&nbsp;</td>" .
          "<td>&nbsp; = per week</td></tr>\n";
        $sofar = "";
      }
      %sum = ();
      %alc = ();
      $ysum = 0;
      $yalc = 0;
      $thisyear = $y;
      last if ($y eq "END");
    } # new year
    $sum{$loc} = 0.1 / ($i+1) unless $sum{$loc}; # $i keeps sort order
    $sum{$loc} += abs($rec->{pr}) ;
    $alc{$loc} += $rec->{alcvol};
    $ysum += abs($rec->{pr});
    $yalc += $rec->{alcvol};
  }
  print "</table>\n";
  print "Show ";
  for my $top ( 5, 10, 20, 50, 100, 999999 ) {
    print  "&nbsp; <a href='$url?o=$op&q=" . uri_escape($qry) . "&maxl=$top'><span>Top-$top</span></a>\n";
  }
  if ($qry) {
    my $prev = "<a href=$url?o=Years&q=" . ($qry - 1) . "&maxl=" . param('maxl') ."><span>Prev</span></a> \n";
    my $all = "<a href=$url?o=Years&&maxl=" . param('maxl') ."><span>All</span></a> \n";
    my $next = "<a href=$url?o=Years&q=" . ($qry + 1) . "&maxl=" . param('maxl') ."><span>Next</span></a> \n";
    print "<br/> $prev &nbsp; $all &nbsp; $next \n";
  }
  print  "<hr/>\n";
EOF
} # yearsummary





################################################################################
1;  # Module loaded ok
