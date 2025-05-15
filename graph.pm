# Part of my beertracker
# Drawing the graph of daily drinks



package graph;

use strict;
use warnings;
use feature 'unicode_strings';
use utf8;  # Source code and string literals are utf-8
use Time::Piece;

# Useful constants
my $oneday = 24 * 60 * 60 ; # in seconds
my $halfday = $oneday / 2;
my $threedays = 3 * $oneday;
my $oneweek = 7 * $oneday ;
my $oneyear = 365.24 * $oneday;
my $onemonth = $oneyear / 12;

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
  my $day = shift;
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
  if ( $v > $g->{maxd} && $day ge $g->{start} ) {
    $g->{maxd} = $v;   # Max y for scaling the graph
  } # But only on the visible part.
  if ( $g->{avg30} > $g->{maxd} ) { # Scale for the avg graph as well
    $g->{maxd} = $g->{avg30}; # so future graphs look fair
  } # Count also the hidden part of the graph here.
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
  $g->{sth}->execute( $c->{username}, $day );
  my $sum = 0;
  my $drinksline = ""; # Individual drinks
  my @drinks;
  while ( my $rec = $g->{sth}->fetchrow_hashref ) {
    print STDERR "$rec->{Id}: $rec->{EffDate} $rec->{BrewType}/$rec->{SubType} ='$rec->{StDrinks}' \n"
      if ( ! $rec->{StDrinks}) ;
    $sum += $rec->{StDrinks};
    push (@drinks, $rec);
  }
  my $top = $sum;
  my $cnt = 20;
  my $loc = "";
  for (my $i= scalar(@drinks)-1; $i >= 0; $i--){
    my $r = $drinks[$i];
    my $style = $r->{BrewType};
    $style .= ",$r->{SubType}" if ($r->{SubType});
    #print "i=$i top=$top r=$r->{Id} $r->{EffDate} $r->{Location} sty='$style' <br/>";
    if ( $loc && $r->{Location} ne $loc ) {
      my $y = $top +.2 ;
      #print "$r->{Id} $r->{Location} top=$top y=$y<br/>";
      $drinksline .= "$y 0xffffff "; # White separator for locaton changes
      $cnt--;
    }
    my $color = brews::brewcolor($style);
    my $y = $top;
    if ( $r->{StDrinks} < 0.2 ) {
      $y = $top + 0.2; # Show at least something visible
    } # without messing with total height
    $drinksline .= "$y 0x$color ";
    $top -= $r->{StDrinks};
    $loc = $r->{Location};
    $cnt--;
  }
  if ( $cnt < 0 ) {
    print STDERR "graph::oneday: Day '$day' has too many drinks. " .
        "Increase here and in the plot command\n";
  }
  while ( $cnt-- > 0 ) {
    $drinksline .= "NaN 0x0 "; # Unused values
  }
  addsums($g,$sum,$day);
  #print "=== $sum $day s7=$g->{sum7} = @{$g->{last7}} <br/>\n";
  $sum = sprintf("%5.1f", $sum);
  my $s7 = sprintf("%5.1f", $g->{sum7}/7);
  my $a30 = sprintf("%5.1f", $g->{avg30});
  $g->{lastavg} = $a30; # Save the last for legend
  $g->{lastwk} = $s7;
  my $zero = " NaN ";
  if ( $sum > 0.4 || $s7 < 0.1 || $g->{range} > 93 ) {
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
} # oneday

# Create the data file for plotting
sub makedatafile {
  my $g = shift;
  my $c = $g->{c};

  my $start = Time::Piece->strptime( $g->{start}, "%Y-%m-%d" );
  my $end = Time::Piece->strptime( $g->{end}, "%Y-%m-%d" );
  $g->{range} = ($end - $start) / $oneday;
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
    where username = ?
      and effdate = ?
      and StDrinks > 0
      and Brew is not null
    order by effdate, Time ";
  #print STDERR "$sql \n";
  $g->{sth} = $c->{dbh}->prepare($sql);

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
  $g->{wkendtag} = 2; # 1 is for the global background
  $g->{weekends} = "";
  #print "Making data file for " . $start->ymd . " to " . $end->ymd . "<br/>\n";
  while ( $date <= $end ) {
    my $line = oneday( $g, $date->ymd);
    print F $line;
    if ( $date->wday == 6 ) { # Sat
      my $wkendcolor = $c->{bgcolor};
      $wkendcolor =~ s/003/005/;
      my $fri = $date->epoch - $halfday;
      my $sun = ($date + $oneday*2.5)->epoch;
      #$g->{weekends} .= "set object $g->{wkendtag} rect from \"$fri\",-0.5 to \"$sun\",50 " .
      $g->{weekends} .= "set object $g->{wkendtag} rect from $fri,-0.5 to $sun,50 " .
        #"size $threedays,200
        "behind  fc rgbcolor \"$wkendcolor\"  fillstyle solid noborder \n";
      $g->{wkendtag}++;
      }
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
  my $xformat; # = "\"%d\\n%b\"";  # 14 Jul
  my $weekline = "";
  my $batitle = "notitle" ;
  $batitle =  "title \"ba\" " if ( $g->{bigimg} eq "B" );
  my $plotweekline =
    "'$g->{plotfile}' using 1:4 with linespoints lc \"#00dd10\" pointtype 7 axes x1y2 title \"$g->{lastwk} wk\", " . #weekly
    "'' using 1:5 with points lc \"red\" pointtype 3 axes x1y2 $batitle, ";  # bloodalc
  my $xtic = 1;
  # Different range grasphs need different options
  my @xyear = ( $oneyear, "\"%y\"" );   # xtics value and xformat
  my @xquart = ( $oneyear / 4, "\"%b\\n%y\"" );  # Jan 24
  my @xmonth = ( $onemonth, "\"%b\\n%y\"" ); # Jan 24
  my @xweek = ( $oneweek, "\"%d\\n%b\"" ); # 15 Jan
  my $pointsize = "set pointsize 1\n";
  my $fillstyle = "fill solid noborder";  # no gaps between drinks or days
  my $fillstyleborder = "fill solid border linecolor \"$c->{bgcolor}\""; # Small gap around each drink
  if ( $g->{bigimg} eq "B" ) {  # Big image
    $g->{maxd} = $g->{maxd} + 1.5; # Make room at the top of the graph for the legend
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
    $pointsize = "set pointsize 0.3\n" ;  # Smaller zeroday marks, etc
    $g->{maxd} = $g->{maxd} + 2; # Make room at the top of the graph for the legend
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
      "set xrange [ \"$g->{start} 12:00\" : \"$g->{end} 12:00\" ] \n".
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
      "set xtics \"2007-01-01\", $xtic out nomirror $white \n" .  # Happens to be sunday, and first of year/month
      "set style $fillstyle \n" .
      "set boxwidth 86400 * 0.9 absolute \n" .
      "set key left top horizontal textcolor \"white\" \n" .
      "set grid xtics ytics  linewidth 0.1 linecolor \"white\" \n".
      "set object 1 rect noclip from screen 0, screen 0 to screen 1, screen 1 " .
        "behind fc \"$c->{bgcolor}\" fillstyle solid border \n";  # green bkg
    for (my $m=1; $m<$g->{maxd}; $m+= 4) {
      $cmd .= "set arrow from \"$g->{start}\", $m to \"$g->{end}\", $m nohead linewidth 1 linecolor \"#00dd10\" \n"
        if ( $g->{maxd} > $m + 1 );
    }
    $cmd .= $g->{weekends};
    $cmd .= "plot ";
                  # note the order of plotting, later ones get on top
                  # so we plot weekdays, avg line
    $cmd .=  "'$g->{plotfile}' using 1:6 with points lc \"#00dd10\" pointtype 11 notitle, "; # zero days
    my $col = 7; # Column of the first value
    while ( $col < 45 ) {
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


# Helper to produce one link under the graph
sub onelink {
  my $g = shift;
  my $txt = shift;
  my $start = shift || "";
  my $end = shift || "" ;
  $start = "&gstart=$start" if ($start);
  $end = "&gend=$end" if ($end);
  my $c = $g->{c};
  print "<a href='$c->{href}".$start.$end. "' >" .
    #"<span>$txt</span></a>\n";
    "<span style='border:1px solid white; padding: 1px 4px; color: white' >$txt</span></a>\n";
}

# Helper to produce the links under the graph
sub graphlinks {
  my $g = shift;
  my $width = shift;
  my $c = $g->{c};
  my $t = localtime;
  my $start = Time::Piece->strptime($g->{start},"%F");
  my $end = Time::Piece->strptime($g->{end},"%F");
  my $range = $end - $start;
  onelink($g, "<<", ($start-$range)->ymd, ($end-$range)->ymd );
  onelink($g, ">>", ($start+$range)->ymd, ($end+$range)->ymd );
  onelink($g, "2w", ($t-14*$oneday)->ymd );
  onelink($g, "Month"); # default values
  onelink($g, "3m", $t->add_months(-3)->ymd );
  onelink($g, "6m", $t->add_months(-6)->ymd );
  onelink($g, "Year", $t->add_years(-1)->ymd );
  onelink($g, "2y", $t->add_years(-2)->ymd );
  onelink($g, "all", "2016-01-01",$t->ymd );  # Earlest known data in the system
}

# The graph itself
sub graph {
  my $c = shift;
  my $g = {};  # Collects all graph-related parameters
  $g->{c} = $c;
  # Parameters.
  $g->{bigimg} = $c->{mobile} ? "S" : "B";
  my $reload = 0;
  if ($c->{op} =~ /Graph([BS]?)(X?)/i ) {
    $g->{bigimg} = $1 if ($1);
    $reload = $2;
  }
  $g->{imgsz}="320,250";
  if ( $g->{bigimg} eq "B" ) {  # Big image
    $g->{imgsz} = "640,480";
  }
  # Date range, default to 30 days leading to tomorrow
  $g->{start} = util::param($c,"gstart", util::datestr("%F",-30) );
  $g->{end} = util::param($c,"gend", util::datestr("%F",1) );
  # TODO - Keep start and stop as Time::Piece refs in g

  $g->{plotfile} = $c->{datadir} . $c->{username} . ".plot";
  $g->{cmdfile} = $c->{datadir} . $c->{username} . ".cmd";
  $g->{pngfile} = $c->{datadir} . $c->{username} . "$g->{start}-$g->{end}-$g->{bigimg}.png";

  if (  -r $g->{pngfile} && !$reload ) { # Have a cached file
    print "\n<!-- Cached graph op='$c->{op}' file='$g->{pngfile}' -->\n";
    print STDERR "graph: Reusing a cached file $g->{pngfile} \n";
  } else { # Have to plot a new one
    print STDERR "graph: Generating $g->{pngfile} for op '$c->{op}' \n";
    #print  "graph: b='$g->{bigimg}' r='$g->{reload}' gs='$g->{start}' ge='$g->{end}' <br/>\n";
    makedatafile($g);
    plotgraph($g);
  }
  # Finally, prine the HTML to display the graph
  my ( $imw,$imh ) = $g->{imgsz} =~ /(\d+),(\d+)/;
  my $htsize = "width=$imw height=$imh" if ($imh) ;
  if ($g->{bigimg} eq "B") {
    print "<a href='$c->{url}?o=GraphS&gstart=$g->{start}&gend=$g->{end}'><img src=\"$g->{pngfile}\" $htsize/></a><br/>\n";
  } else {
    print "<a href='$c->{url}?o=GraphB'&gstart=$g->{start}&gend=$g->{end}'><img src=\"$g->{pngfile}\" $htsize/></a><br/>\n";
  }
  graphlinks($g, $imw);
  print "<hr/>\n";


} # graph



################################################################################
# Report module loaded ok
1;
