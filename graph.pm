# Part of my beertracker
# Drawing the graph of daily drinks



package graph;

use strict;
use warnings;
use feature 'unicode_strings';
use utf8;  # Source code and string literals are utf-8
use Time::Piece;

################################################################################
# Helper to clear the cached files from the data dir.
################################################################################
sub clearcachefiles {
  my $c = shift;
  my $datadir = $c->{datadir};
  print STDERR "clear: d='$datadir'\n";
  foreach my $pf ( glob($datadir."*") ) {
    next if ( $pf =~ /(\.data)|(.db.*)$/ ); # Always keep data files
    next if ( -d $pf ); # Skip subdirs, if we have such
    if ( $pf =~ /\/$c->{username}.*png/ ||   # All png files for this user
         -M $pf > 7 ) {  # And any file older than a week
      unlink ($pf)
        or error ("Could not unlink $pf $!");
      }
  }
} # clearcachefiles

################################################################################
# The graph itself
################################################################################

# Helper for the 30 day weighted average and the 7 day sum
sub addsums {
  my $g = shift;
  my $v = shift;
  if ( $v > $g->{maxd} ) {
    $g->{maxd} = $v;   # Max y for scaling the graph
  }
  push( @{ $g->{last7} }, $v);
  $g->{sum7} += $v;
  if ( scalar(@{ $g->{last7} } > 7 ) ) {
    $g->{sum7} -= shift( @{$g->{last7} } );
  }
  push( @{ $g->{last30} }, $v);
  if ( scalar(@{ $g->{last30} } > 30 ) ) {
    shift( @{$g->{last30} } );
  }
  my $w = 1;
  my $sum = 0.0001; # to avoid division by zero
  my $wsum = 0;
  for my $v ( @{ $g->{last30} } ) {
    $sum += $v * $w;
    $wsum += $w;
    $w++;
  }
  $g->{avg30} = $sum / $wsum;
  # TODO check exponential average
} # addsums

# Make a data file line for one day
sub oneday {
  my $g = shift;
  my $day = shift;
  my $c = $g->{c};
  my $alc = "NaN";
  if ( $g->{range} < 95 ) { # Over 3m we don't show them anyway.
    my $bloodalc = mainlist::bloodalc($c,$day);
    $alc = $bloodalc->{max} * 10 ; # scale to display
    $alc = "NaN" if ($alc < 0.1 );
    # TODO - Refactor the stepwise calculation into its own routine in mainlist,
    # and use that wihtin in the loop below.
  }
  my $sql = "
    SELECT
      Id,
      strftime('%Y-%m-%d', Timestamp, '-06:00') as EffDate,
      strftime('%H:%M', Timestamp ) as Time,
      BrewType,
      SubType,
      StDrinks,
      Location
    from GLASSES
    where effdate = ?
    order by effdate ";
  my $sth = $c->{dbh}->prepare($sql);
  $sth->execute( $day );
  my $sum = 0;
  my $drinksline = ""; # Individual drinks
  my @drinks;
  while ( my $rec = $sth->fetchrow_hashref ) {
    #print "$rec->{Id}: $rec->{EffDate} $rec->{BrewType}/$rec->{SubType} =$rec->{StDrinks} <br/>";
    $sum += $rec->{StDrinks};
    push (@drinks, $rec);
  }
  my $top = $sum;
  my $cnt = 20;
  for my $r ( reverse(@drinks) ){
    my $style = $r->{BrewType};
    $style .= ",$r->{SubType}" if ($r->{SubType});
    my $color = brews::brewcolor($style);
    $drinksline .= "$top 0x$color ";
    $top -= $r->{StDrinks};
    $cnt--;
  }
  while ( $cnt-- > 0 ) {
    $drinksline .= "NaN 0x0 "; # Unused values
  }
  addsums($g,$sum);
  #print "=== $sum $day s7=$g->{sum7} = @{$g->{last7}} <br/>\n";
  $sum = sprintf("%5.1f", $sum);
  my $s7 = sprintf("%5.1f", $g->{sum7}/7);
  my $a30 = sprintf("%5.1f", $g->{avg30});
  $g->{lastavg} = $a30; # Save the last for legend
  $g->{lastwk} = $s7;
  my $zero = " NaN ";
  if ( $sum > 0.4 || $s7 < 0.1) {
    $g->{zeroheight} = 0.1;
  } else {
    $zero = $g->{zeroheight};
    $g->{zeroheight} += 0.3; # Fits nicely with 7 marks in a week
    if ( $g->{zeroheight} > 2 ) {
      $g->{zeroheight} = 0.1;
    }
  }
  $s7 = "NaN" if ( $s7 < 0.1 );  # Hide zero lines
  $a30 = "NaN" if ( $a30 < 0.1 );
  my $line = "$day $sum $a30 $s7 $alc $zero $drinksline\n";
  return $line;
}

# Create the data file for plotting
sub makedatafile {
  my $g = shift;
  my $c = $g->{c};
  my $oneday = 24 * 60 * 60;
  my $start = Time::Piece->strptime( $g->{start}, "%Y-%m-%d" );
  my $end = Time::Piece->strptime( $g->{end}, "%Y-%m-%d" );
  $g->{range} = ($end - $start) / $oneday;
  my $date = $start;
  $date -= 7 * $oneday; # Start earlier to prime the average
  open F, ">$g->{plotfile}"
      or util::error ("Could not open $g->{plotfile} for writing");
  my $legend = "# Date    Drinks Avg30 Avg7  Balc Zero Fut   Drink Color Drink Color ...";
  print F "$legend \n".
    "# Plot $g->{start} to $g->{end} \n";

  $g->{last7} = [];
  $g->{sum7} = 0;
  $g->{last30} = [];
  $g->{avg30} = 0;
  $g->{maxd} = 0;
  $g->{zeroheight} = 0;
  print "Making data file for " . $start->ymd . " to " . $end->ymd . "<br/>\n";
  while ( $date <= $end ) {
    my $line = oneday( $g, $date->ymd );
    print F $line;
    $date += $oneday;
  }
  print F "$legend \n";
  close(F);
} # makedatafile



# Helper to do the acual plotting
sub plotgraph {
  my $g = shift;
  my $c = $g->{c};
  my $white = "textcolor \"white\" ";
  $g->{imgsz}="320,250";
  if ( $g->{bigimg} eq "B" ) {  # Big image
    $g->{imgsz} = "640,480";
  }
  my $oneday = 24 * 60 * 60 ; # in seconds
  my $threedays = 3 * $oneday;
  my $oneweek = 7 * $oneday ;
  my $oneyear = 365.24 * $oneday;
  my $onemonth = $oneyear / 12;
  my $xformat; # = "\"%d\\n%b\"";  # 14 Jul
  my $weekline = "";
  my $batitle = "notitle" ;
  $batitle =  "title \"ba\" " if ( $g->{bigimg} eq "B" );
  my $plotweekline =
    "'$g->{plotfile}' using 1:4 with linespoints lc \"#00dd10\" pointtype 7 axes x1y2 title \"$g->{lastwk} wk\", " . #weekly
    "'' using 1:5 with points lc \"red\" pointtype 1 pointsize 0.5 axes x1y2 $batitle, ";  # bloodacl
  my $xtic = 1;
  # Different range grasphs need different options
  my @xyear = ( $oneyear, "\"%y\"" );   # xtics value and xformat
  my @xquart = ( $oneyear / 4, "\"%b\\n%y\"" );  # Jan 24
  my @xmonth = ( $onemonth, "\"%b\\n%y\"" ); # Jan 24
  my @xweek = ( $oneweek, "\"%d\\n%b\"" ); # 15 Jan
  my $pointsize = "";
  my $fillstyle = "fill solid noborder";  # no gaps between drinks or days
  my $fillstyleborder = "fill solid border linecolor \"$c->{bgcolor}\""; # Small gap around each drink
  #my $fillstyleborder = "fill solid border linecolor \"$c->{bgcolor}\""; # Small gap around each drink
  #my $fillstyleborder = "fill solid noborder ";# Small gap around each drink
  if ( $g->{bigimg} eq "B" ) {  # Big image
    $g->{maxd} = $g->{maxd} + 3; # Make room at the top of the graph for the legend
    if ( $g->{range} > 365*4 ) {  # "all"
      ( $xtic, $xformat ) = @xyear;
    } elsif ( $g->{range} > 400 ) { # "2y"
      ( $xtic, $xformat ) = @xquart;
    } elsif ( $g->{range} > 120 ) { # "y", "6m"
      ( $xtic, $xformat ) = @xmonth;
    } else { # 3m, m, 2w
      ( $xtic, $xformat ) = @xweek;
      $weekline = $plotweekline;
      $fillstyle = $fillstyleborder;
    }
  } else { # Small image
    $pointsize = "set pointsize 0.5\n" ;  # Smaller zeroday marks, etc
    $g->{maxd} = $g->{maxd} + 6; # Make room at the top of the graph for the legend
    if ( $g->{range} > 365*4 ) {  # "all"
      ( $xtic, $xformat ) = @xyear;
    } elsif ( $g->{range} > 360 ) { # "2y", "y"
      ( $xtic, $xformat ) = @xquart;
    } elsif ( $g->{range} > 80 ) { # "6m", "3m"
      ( $xtic, $xformat ) = @xmonth;
      $weekline = $plotweekline;
    } else { # "m", "2w"
      ( $xtic, $xformat ) = @xweek;
      $fillstyle = $fillstyleborder;
      $weekline = $plotweekline;
    }
  }

  my $cmd = "" .
      "set term png small size $g->{imgsz} \n".
      $pointsize .
      "set out \"$g->{pngfile}\" \n".
      "set xdata time \n".
      "set timefmt \"%Y-%m-%d\" \n".
      "set xrange [ \"$g->{start}\" : \"$g->{end}\" ] \n".
      "set format x $xformat \n" .
      "set yrange [ -.5 : $g->{maxd} ] \n" .
      "set y2range [ -.5 : $g->{maxd} ] \n" .
      #"set link y2 via y/7 inverse y*7\n".  #y2 is drink/day, y is per week
      "set border linecolor \"white\" \n" .
      "set ytics out nomirror 1 $white \n" .
      "set y2tics out nomirror 1 $white \n" .
#      "set mytics 7 \n" .
#      "set my2tics 7 \n" .
      #"set y2tics 0,1 out format \"%2.0f\" $white \n" .   # 0,1
      "set xtics \"2007-01-01\", $xtic out $white \n" .  # Happens to be sunday, and first of year/month
      "set style $fillstyle \n" .
      "set boxwidth 86400*0.7 absolute \n" .
      "set key left top horizontal textcolor \"white\" \n" .
      "set grid xtics ytics  linewidth 0.1 linecolor \"white\" \n".
      "set object 1 rect noclip from screen 0, screen 0 to screen 1, screen 1 " .
        "behind fc \"$c->{bgcolor}\" fillstyle solid border \n";  # green bkg
    for (my $m=1; $m<$g->{maxd}; $m+= 4) {
      $cmd .= "set arrow from \"$g->{start}\", $m to \"$g->{end}\", $m nohead linewidth 1 linecolor \"#00dd10\" \n"
        if ( $g->{maxd} > $m + 1 );
    }

    $cmd .= "plot ";
                  # note the order of plotting, later ones get on top
                  # so we plot weekdays, avg line
    $cmd .=  "'$g->{plotfile}' using 1:6 with points lc \"#00dd10\" pointtype 11 notitle, "; # zero days
    my $col = 7; # Column of the first value
    while ( $col < 20 ) {
      $cmd .= "'' using 1:" . $col++ . ":" . $col++ . " with boxes lc rgbcolor variable notitle, ";
    }

    $cmd .=   "'' using 1:3 axes x1y2 with lines  lc \"#FfFfFf\" lw 3  title \"$g->{lastavg} 30d\" , ";   # monthly avg
    $cmd .= $weekline . "\n";


    open C, ">$g->{cmdfile}"
          or util::error ("Could not open $g->{cmdfile} for writing: $!");
    print C $cmd;
    close(C);
    system ("gnuplot $g->{cmdfile} ");
}


# The graph itself
sub graph {
  my $c = shift;
  my $g = {};  # Collects all graph-related parameters
  $g->{c} = $c;
  # Parameters.
  $g->{bigimg} = $c->{mobile} ? "S" : "B";
  $g->{reload} = 0;
  if ($c->{op} =~ /Graph([BS]?)(X?)/ ) {
    $g->{bigimg} = $1 if ($1);
    $g->{reload} = $2;
  }
  # Date range, default to 30 days leading to tomorrow
  $g->{start} = util::param($c,"gstart", util::datestr("%F",-30) );
  $g->{end} = util::param($c,"gend", util::datestr("%F",0) );

  $g->{plotfile} = $c->{datadir} . $c->{username} . ".plot";
  $g->{cmdfile} = $c->{datadir} . $c->{username} . ".cmd";
  $g->{pngfile} = $c->{datadir} . $c->{username} . "$g->{start}-$g->{end}-$g->{bigimg}.png";
  # TODO Check cache

  print  "graph: b='$g->{bigimg}' r='$g->{reload}' gs='$g->{start}' ge='$g->{end}' <br/>\n";
  makedatafile($g);
  plotgraph($g);

  # Finally, prine the HTML to display the graph
  my ( $imw,$imh ) = $g->{imgsz} =~ /(\d+),(\d+)/;
  my $htsize = "width=$imw height=$imh" if ($imh) ;
  if ($g->{bigimg} eq "B") {
    print "<a href='$c->{url}?o=GraphS&gstart=$g->{start}&gend=$g->{end}'><img src=\"$g->{pngfile}\" $htsize/></a><br/>\n";
  } else {
    print "<a href='$c->{url}?o=GraphB'&gstart=$g->{start}&gend=$g->{end}'><img src=\"$g->{pngfile}\" $htsize/></a><br/>\n";
  }

  print "<hr/>\n";


} # graph



################################################################################
# Report module loaded ok
1;
