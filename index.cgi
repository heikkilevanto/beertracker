#!/usr/bin/perl -w

# Heikki's simple beer tracker
#
# Keeps beer drinking history in a flat text file.
# One more useless change


use CGI;
use URI::Escape;
use feature 'unicode_strings';

my $q = CGI->new;

# Constants
my $onedrink = 33 * 4.6 ; # A regular danish beer, 33 cl at 4.6%
my $datadir = "./beerdata/";
my $datafile = "";
my $plotfile = "";
my $cmdfile = "";
my $pngfile = "";
if ( $q->remote_user() =~ /^[a-zA-Z0-9]+$/ ) {
  $datafile = $datadir . $q->remote_user() . ".data";
  $plotfile = $datadir . $q->remote_user() . ".plot";
  $cmdfile = $datadir . $q->remote_user() . ".cmd";
  $pngfile = $datadir . $q->remote_user() . ".png";
} else {
  error ("Bad username");
}
my @ratings = ( "Undrinkable", "Bad", "Unpleasant", "Could be better",
"Ok", "Goes down well", "Nice", "Pretty good", "Excellent", "Perfect",
"I'm in love" );


# Parameters - data file fields are the same order
# but there is a time stamp first, and the $del never gets to the data file
my $stamp = param("st");
my $wday = param("wd");  # weekday
my $effdate = param("ed");  # effective date
my $loc = param("l");  # location
my $mak = param("m");  # brewery (maker)
my $beer= param("b");  # beer
my $vol = param("v");  # volume, in cl
my $sty = param("s");  # style
my $alc = param("a");  # alc, in %vol, up to 1 decimal
my $pr  = param("p");  # price, in local currency
my $rate= param("r");  # rating, 0=worst, 10=best
my $com = param("c");  # Comments
  # The rest are not in the data file
my $del = param("x");  # delete/update last entry - not in data file
my $qry = param("q");  # filter query, greps the list
my $qrylim = param("f"); # query limit, "c" or "r" for comments or ratings
my $op  = param("o");  # operation, to list breweries, locations, etc
my $edit= param("e");  # Record to edit
my $maxlines = param("maxl") || "25";  # negative = unlimited
my $sortlist = param("sort") || 0; # default to unsorted, chronological lists
my $url = $q->url;
my $localtest = 0; # Local test installation
my $hostname = `hostname`;
chomp($hostname);
#if ( $hostname ne "locatelli" ) {
#  $localtest = 1;  # Not on locatelli anymore.
#}  # Running dev and prod on corelli

# Default sizes
$vol =~ s/^T$/2/i;  # Taster, sizes vary, but always small
$vol =~ s/^G$/12/i; # Glass of wine
$vol =~ s/^S$/25/i; # Small, usually 25
$vol =~ s/^M$/33/i; # Medium, typically a bottle beer
$vol =~ s/^L$/40/i; # Large, 40cl in most places I frequent
$vol =~ s/^B$/75/i; # Bottle of wine
if ( $vol =~ /([0-9]+) *oz/i ) {  # (us) fluid ounces
  $vol = $1 * 3;   # Actually, 2.95735 cl, no need to mess with decimals
}

# The query is already cleaned in param()
#$qry =~ s/[&.*+^\$]/./g;  # Remove special characters
#$qry =~ s/[^A-Za-z0-9 ,.-]/./g;  # Remove special characters

if ( ! $stamp ) {
  $stamp = `date "+%F %T"`;  # TODO - Do this in perl
  chomp($stamp);
}
if ( ! $effdate ) { # Effective date can be the day before
  $effdate = `date "+%a; %F" -d '8 hours ago' `;  
  chomp($effdate);
} else {
  $effdate = "$wday; $effdate";
}

# Read the file
# Set defaults for the form, usually from last line in the file
# Actually, at this point only set $lastline and $foundline
# They get split later
open F, "<$datafile" 
  or error("Could not open $datafile for reading: $!".
     "<br/>Probably the user hasn't been set up yet" );
my $foundline = "";
my $lastline = "";
my $thisloc = "";
my $lastdatesum = 0.0;
my $lastdatemsum = 0;
my $todaydrinks = "";
my $copylocation = 0;  # should the copy button copy location too
my $thisdate = "";
my $lastwday = "";
my @lines;
while (<F>) {
  chomp();
  s/#.*$//;  # remove comments
  next unless $_; # skip empty lines
  push @lines, $_; # collect them all
  my ( $t, $wd, $ed, $l, $m, $b, $v, $s, $a, $p, $r, $c ) = split( /; */ );
  $thisloc = $l if $l;
  if ( ! $edit || ($edit eq $t) ) {
    $foundline = $_;
  }
  $lastline = $_;
  if ( $thisdate ne "$wd; $ed" ) { # new date
    $lastdatesum = 0.0;
    $lastdatemsum = 0;
    $thisdate = "$wd; $ed";
    $lastwday = $wd;
  }
  $a = number($a);  # Sanitize numbers
  $v = number($v);
  $p = number($p);
  $lastdatesum += ( $a * $v ) if ($a && $v);
  $lastdatemsum += $1 if ( $p =~ /(\d+)/ );
  if ( $effdate eq "$wd; $ed" ) { # today
    $todaydrinks = sprintf("%3.1f", $lastdatesum / $onedrink ) . " d " ;
    $todaydrinks .= ", $lastdatemsum kr." if $lastdatemsum > 0  ;
  }
  if ( 0 ) {
    $lastdatesum += ( $a * $v ) if ($a && $v);
    $lastdatemsum += $p if ( $p =~ /\d/ );
    $todaydrinks = sprintf("%3.1f", $lastdatesum / $onedrink ) . " d " ;
    $todaydrinks .= ", $lastdatemsum kr." if $lastdatemsum > 0  ;
  }
}
if ( ! $todaydrinks ) { # not today
  $todaydrinks = "($lastwday: " . sprintf("%3.1f", $lastdatesum / $onedrink ) . 
"d)" ;    
  $copylocation = 1;  
}


# POST data into the file
if ( $q->request_method eq "POST" ) {
  error("Can not see $datafile") if ( ! -w $datafile ) ;
  my $sub = $q->param("submit") || "";
  # Check for missing values in the input, copy from the most recent beer with
  # the same name.
  $loc = $thisloc unless $loc;  # Always default to the last one
  if (  $sub =~ /Copy (\d+)/ ) {  # copy different volumes
    $vol = $1 if ( $1 );
  }
  my $priceguess = "";
  #print STDERR "Guessing values. pr='$pr'";
  my $i = scalar( @lines );
  while ( $i > 0 && $beer 
    && ( !$mak || !$vol || !$sty || !$alc || $pr eq '' )) {
    #print STDERR "Considering " . $lines[$i] . "\n";
    ( undef, undef, undef, $iloc, $imak, $ibeer, $ivol, $isty, $ialc, $ipr, 
undef, undef) =
       split( /; */, $lines[$i] );
    if ( !$priceguess &&    # Guess a price
         uc($iloc) eq uc($loc) &&   # if same location and volume
         $vol eq $ivol ) {
      $priceguess = $ipr;
      #print STDERR "Found a price guess $ipr\n";
    }
    if ( uc($beer) eq uc($ibeer) ) {
      $beer = $ibeer; # with proper case letters
      $mak = $imak unless $mak;
      $sty = $isty unless $sty;
      $alc = $ialc unless $alc;
      if ( $vol eq $ivol && $ipr=~/^ *[0-9.]+ *$/) { 
      # take price only from same volume, and only if numerical
        #print STDERR "Found price $ipr. pr='$pr' <br/>\n";
        $pr  = $ipr if $pr eq "";
      }
      $vol = $ivol unless $vol;
    }
    $i--;
  }
  $pr = $priceguess if $pr eq "";
  $vol = number($vol);
  $pr = number($pr);
  $alc = number($alc);
  my $line = "$loc; $mak; $beer; $vol; $sty; $alc; $pr; $rate; $com";
  if ( $sub eq "Record" || $sub =~ /^Copy/ ) {
    if ( $line =~ /[a-zA-Z0-9]/ ) { # has at leas something on it
        open F, ">>$datafile" 
          or error ("Could not open $datafile for appending");
        print F "$stamp; $effdate; $line \n"
          or error ("Could not write in $datafile");
        close(F) 
          or error("Could not close data file");
    }
  } else { # Editing or deleting an existing line
    # Copy the data file to .bak
    my $bakfile = $datafile . ".bak";
    system("cat $datafile > $bakfile");
    open BF, $bakfile
      or error ("Could not open $bakfile for reading");
    open F, ">$datafile"
      or error ("Could not open $datafile for writing");
    while (<BF>) {
      my ( $stp, undef) = split( /; */ );
      if ( $stp ne $edit ) {
        print F $_;
      } else { # found the line
        print F "#" . $_ ;  # comment the original line out
        if ( $sub eq "Save" ) {
          print F "$stamp; $effdate; $line \n";
        }
      }
    }
    close F 
      or error("Error closing $datafile: $!");
    close BF
      or error("Error closing $bakfile: $!");

  }
  # Redirect to the same script, without the POST, so we see the results
  print $q->redirect( $url ); 
  exit();
}


# Get new values from the file we ingested earlier
my ( $laststamp, undef, undef, $lastloc, $lastbeer, undef ) = split( /; */, 
$lastline );
( $stamp, $wday, $effdate, $loc, $mak, $beer, $vol, $sty, $alc, $pr, $rate, $com 
) = 
    split( /; */, $foundline );
if ( ! $edit ) { # not editing, do not default rates and comments from last beer
  $rate = "";
  $com = ""; 
}
print $q->header(
  -type => "text/html;charset=UTF-8",
  -Cache_Control => "no-cache, no-store, must-revalidate",
  -Pragma => "no-cache",
  -Expires => "0");

# HTML head
print "<html><head>\n";
print "<title>Beer</title>\n";
print "<meta http-equiv='Content-Type' content='text/html;charset=UTF-8'>\n";
print "<meta name='viewport' content='width=device-width, 
initial-scale=1.0'>\n";
if ( ! $localtest ) {
    print "<style rel='stylesheet'>\n";
    #print "* { margin: 1px; padding: 0px; }\n";
    print "* { background-color: #493D26; color: #FFFFFF }\n";
    #print "* { background-color: #003000; color: #FFFFFF }\n";
    print "</style>\n";
}
print "<link rel='shortcut icon' href='beer.png'/>\n";
print "</head>\n";
print "<body>\n";

my $script = <<'SCRIPTEND';
  function clearinputs() {
    var inputs = document.getElementsByTagName('input');
    for (var i = 0; i < inputs.length; i++ ) {
      if ( inputs[i].type == "text" ) 
        inputs[i].value = "";
    }
  };
  var changeop = function(to) {
    document.location = to;
  }
SCRIPTEND
print "<script>\n$script</script>\n";


# Status line
if (  $localtest) {
  print "Local test installation<br/>\n";
}

# Main input form
print "<form method='POST'>\n";
print "<table >";
my $clr = "Onclick='value=\"\";'";
my $c2 = "colspan='2'";
my $c3 = "colspan='3'";
my $c4 = "colspan='4'";
my $c6 = "colspan='6'";
my $sz = "size='15' $clr";
my $sz2 = "size='2' $clr";
my $sz3 = "size='8' $clr";
if ( $edit ) {
    print "<tr><td $c2><b>Editing record $edit</b> ".
        "<input name='e' type='hidden' value='$edit' /></td></tr>\n";
    print "<tr><td><input name='st' value='$stamp' $sz placeholder='Stamp'
/></td>\n";
    print "<td><input name='wd' value='$wday'  $sz2 
placeholder='wday' />\n";
    print "<input name='ed' value='$effdate'  
$sz3 placeholder='Eff' /></td></tr>\n";
}
print "<tr><td>
  <input name='l' value='$loc' placeholder='location' $sz /></td>\n";
print "<td><input name='s' value='$sty' $sz 
placeholder='Style'/></td></tr>\n";
print "<tr><td>
  <input name='m' value='$mak' $sz placeholder='brewery'/></td>\n";
print "<td>
  <input name='b' value='$beer' $sz placeholder='beer'/></td></tr>\n";
print "<tr><td><input name='v' value='$vol' $sz2 placeholder='Vol' />\n";
print "<input name='a' value='$alc' $sz2 placeholder='Alc' />\n";
print "<input name='p' value='$pr' $sz2 placeholder='Price' /></td>\n";
print "<td><select name='r' value='$rate' placeholder='Rating' />" .
   "<option value=''></option>\n";
for my $ro (0 .. scalar(@ratings)-1) {
  print "<option value='$ro'" ;
  print " selected='selected'" if ( $ro eq $rate );
  print  ">$ro - $ratings[$ro]</option>\n";
}
print "</select></td></tr>\n";
 print "<tr>";
print " <td $c6><textarea name='c' cols='36' rows='3' 
  placeholder='$todaydrinks'/>$com</textarea></td></tr>\n";
if ( $edit ) {
  print "<tr><td><input type='submit' name='submit' 
value='Save'/></td>\n";
  print "<td><a href='$url' >cancel</a>";
  print "&nbsp;<input type='submit' name='submit' value='Delete'/> 
</td></tr>\n";
} else {
  print "<tr><td><input type='submit' name='submit' 
value='Record'/>\n";
  print "&nbsp;<input type='button' value='clear' 
onclick='clearinputs()'/></td>\n";
  print "<td><select name='ops' " .
              "onchange='document.location=\"$url?\"+this.value;' >";
  print "<option value='' >Show</option>\n";
  print "<option value='' >Full List</option>\n";
  print "<option value='o=short' >Short List</option>\n";
  my @ops = ("Graph", 
     "Location","Brewery", "Beer", 
     "Wine", "Booze", "Restaurant", "Style");
  for my $opt ( @ops ) {
    print "<option value='o=$opt'>$opt</option>\n";
  }
  print "<option value='f=r'>Ratings</option>\n";
  print "<option value='f=c'>Comments</option>\n";
  print "</select></td>\n";
  print "</tr>\n";
}
print "</table>\n";
print "</form>\n";

# List or graph section

if ( $op && $op =~ /Graph(\d*)/ ) { # make a graph
  my $graphtype = $1 || 2;
  my %sums; 
  my $firstdate;
  my $lastdate;
  for ( my $i = 0; $i < scalar(@lines); $i++ ) {
    ( $stamp, $wday, $effdate, $loc, $mak, $beer, $vol, $sty, $alc, $pr, $rate, 
$com ) = 
       split( /; */, $lines[$i] );
    $sums{$effdate} = ($sums{$effdate} || 0 ) + $alc * $vol if ( $alc && $vol );
    $firstdate = $effdate unless $firstdate;
    $lastdate = $effdate;
    #print "$effdate: $sums{$effdate} a:'$alc' v:'$vol'<br/>\n";
  }
  $enddate = `date +%F -d "yesterday"` ;
  chomp($enddate);
  my $ndays = 0;
  my $date = $firstdate;
  open F, ">$plotfile"
      or error ("Could not open $plotfile for writing");
  while ( $date le $enddate) {
    $ndays++;
    $date = `date +%F -d "$firstdate + $ndays days" `;
    chomp($date);
    my $mdate = $1."-15" if ( $date =~ /^(\d+-\d+)-\d+/);
    my $tot = ( $sums{$date} || 0 ) / $onedrink ;
    #print "$ndays: $date / $enddate: $tot <br/>";
    my $zero = "";
    $zero = -0.1 unless ( $tot || $date gt $enddate );
    print F "$date $tot $mdate $zero\n";
  }
  close(F);
  $enddate = `date +%F -d "tomorrow"` ;
  chomp($enddate);
  my $oneweek = 7 * 24 * 60 * 60 ; # in seconds
  my $oneday = 24 * 60 * 60 ; 
  my $xtics = "";
  my $numberofdays=7;
  my $xformat = "\"%d\\n%b\"";
  my $avgline = "";
  if ( $graphtype == 1 ) { # week
    $xformat = "\"%a\\n%d";
    $startdate = `date +%F -d "last sunday -6 days"` ;
    chomp($startdate);
    $xtics =  "set xtics \"$startdate\", $oneday \n";
  } elsif ( $graphtype == 2 ) { # month
    $numberofdays = 35;
    $startdate = `date +%F -d "last sunday -$numberofdays days"` ;
    chomp($startdate);
    $xtics =  "set xtics \"$startdate\", $oneweek \n";
    $avgline = "\"$plotfile\" " .
         "using 3:2 smooth cspline with line lc 1 lw 2 notitle ,";
  } elsif ( $graphtype == 3 ) { # quarter
    $numberofdays = 100;
    $startdate = `date +%F -d "last sunday -$numberofdays days"` ;
    chomp($startdate);
    $avgline = "\"$plotfile\" " .
         "using 3:2 smooth cspline with line lc 1 lw 2 notitle ," .
       "\"$plotfile\" " .
         "using 3:2 smooth unique with points lc 1 pointtype 7 notitle ,";
  } elsif ( $graphtype == 4 ) { # year
    $numberofdays = 370;
    $startdate = `date +%F -d "last sunday -$numberofdays days"` ;
    chomp($startdate);
    $avgline = "\"$plotfile\" " .
         "using 3:2 smooth cspline with line lc 1 lw 2 notitle ," .
       "\"$plotfile\" " .
         "using 3:2 smooth unique with points lc 1 pointtype 7 notitle ,";
  } elsif ( $graphtype == 5 ) { # all
    $startdate = $firstdate;
    chomp($startdate);
    $avgline = "\"$plotfile\" " .
         "using 3:2 smooth cspline with line lc 1 lw 2 notitle ," .
       "\"$plotfile\" " .
         "using 3:2 smooth unique with points lc 1 pointtype 7 notitle ,";
  }
  my $cmd = "" .
       "set term png small size 360,240 \n".
       "set out \"$pngfile\" \n".
       "set xdata time \n".
       "set timefmt \"%Y-%m-%d\" \n".
       "set xrange [ \"$startdate\" : \"$enddate\" ] \n".
       "set yrange [ -.5 : ] \n" .
       "set format x $xformat \n" . 
       "$xtics" .
       "set ytics 0,3\n" .
       "set style fill solid \n" . 
       "set boxwidth 0.1 relative \n" .
       "set grid xtics ytics  linewidth 0.1 linecolor 4 \n".
       "plot " .
             # lc 0=grey 1=red, 2=green, 3=blue
             # note the order of plotting, later ones get on top
             # so we plot weekdays, weekends, avg line, and just one
             # weekday, to handle commas in the avg line
        "\"$plotfile\" " .
            "every 7::6 " .
            "using 1:2 with boxes lc 0 notitle ," .  # mon
        "\"$plotfile\" " .
            "every 7::0 " .
            "using 1:2 with boxes lc 0 notitle ," .  # tue
        "\"$plotfile\" " .
            "every 7::1 " .
            "using 1:2 with boxes lc 0 notitle ," .  # wed
        "\"$plotfile\" " .
            "every 7::2 " .
            "using 1:2 with boxes lc 0 notitle ," .  # thu
        "\"$plotfile\" " .
            "every 7::3 " .
            "using 1:2 with boxes lc 3 notitle ," .  # fri
        "\"$plotfile\" " .
            "every 7::4 " .
            "using 1:2 with boxes lc 3 notitle," .  # sat
        "\"$plotfile\" " .
            "every 7::5 " .
            "using 1:2 with boxes lc 3 notitle, " .  # sun
        $avgline .
        "\"$plotfile\" " .
            "using 1:4 with points lc 2 pointtype 11 notitle \n" .  # zeroes
        "";
  open C, ">$cmdfile"
      or error ("Could not open $plotfile for writing");
  print C $cmd;
  close(C);
  system ("gnuplot $cmdfile ");
  print "<hr/>\n";
  print "<a href='$url?o=Graph1'>Week</a> \n";
  print "<a href='$url?o=Graph2'>Month</a> \n";
  print "<a href='$url?o=Graph3'>Quarter</a> \n";
  print "<a href='$url?o=Graph4'>Year</a> \n";
  print "<a href='$url?o=Graph5'>All</a> \n";
  print "<p/>\n";
  print "<img src=\"$pngfile\"/>\n";

} elsif ( $op eq "short" ) { # short list, one line per day
  my $i = scalar( @lines );
  my $entry = "";
  my $places = "";
  my $lastdate = "";
  my $lastloc = "";
  my $daysum = 0.0;
  my %locseen;
  my $month = "";
  while ( $i > 0 ) {
    $i--;
    ( $stamp, $wday, $effdate, $loc, $mak, $beer, $vol, $sty, $alc, $pr, $rate, 
$com ) = 
       split( /; */, $lines[$i] );
    if ( $lastdate ne $effdate ) {
      if ( $entry ) {
        my $daydrinks = sprintf("%3.1f", $daysum / $onedrink) ;
        $entry .= " " . $daydrinks;
        print "$entry";
        my $shortplaces = $places;
        $shortplaces =~ s/<[^>]+>//g;
        #print "('$shortplaces' " . length($shortplaces) . ")";
        print "<br/>&nbsp;\n" if ( length($shortplaces) > 15 );
        print "$places<br/>\n";
        $maxlines--;
        last if ($maxlines == 0); # if negative, will go for ever
      }
      # Check for empty days in between
      my $ndays = 1;
      my $zerodate;
      do {
        $zerodate = `date +%F -d "$lastdate + $ndays days ago" `;
        $ndays++;  # that seems to work even without $lastdate, takes today!
      } while ( $zerodate gt $effdate );
      $ndays-=3;
      if ( $ndays == 1 ) {
        print "... (1 day) ...<br/>\n";
      } elsif ( $ndays > 1) {
        print "... ($ndays days) ...<br/>\n";
      }
      my $thismonth = substr($effdate,0,7);
      my $bold = "";
      if ( $thismonth ne $month ) {
        $bold = "b";
        $month = $thismonth;
      }
      $entry = filt($effdate, $bold) . " " . $wday ;
      $places = "";
      $lastdate = $effdate;
      $lastloc = "";
      $daysum = 0.0;
    }
    if ( $lastloc ne $loc ) {
      if ( $places !~ /$loc/ ) {
        my $bold = "";
        if ( !defined($locseen{$loc}) ) {
          $bold = "b";
          }
        $places .= " " . filt($loc,$bold);
        $locseen{$loc} = 1;
        }
      $lastloc = $loc;
    }
    $daysum += ( $alc * $vol ) if ($alc && $vol) ;
  }
  if ( $maxlines >= 0 ) {
    print "<p/><a href='$url?maxl=-1&" . $q->query_string() . "'>" .
      "More</a><br/>\n";
  }
} elsif ( $op ) { # various lists
  print "<hr/><a href='$url'><b>$op</b> list</a>.\n";
  if ( !$sortlist) {
    print "(<a href='$url?o=$op&sort=1' >sort</a>) <p/>\n";
  } else {
    print "(<a href='$url?o=$op'>Recent</a>) <p/>\n";
  }
  print "Filter: <a href='$url?q=$qry'>$qry</a> " .
     "<a href='$url?o=$op'>(clear) <p/>" if $qry;
  
  my $i = scalar( @lines );
  my $fld;
  my $line;
  my @displines;
  my %seen;
  my $anchor="";
  print "<table>\n";
  while ( $i > 0 ) {
    $i--;
    next unless ( !$qry || $lines[$i] =~ /\b$qry\b/i );
    ( $stamp, $wday, $effdate, $loc, $mak, $beer, $vol, $sty, $alc, $pr, $rate, 
$com ) = 
       split( /; */, $lines[$i] );
    $fld = "";
    if ( $op eq "Location" ) {
      $fld = $loc;
      $line = "<td>" . filt($loc,"b") . "</td><td>$wday $effdate<br/>" . 
           lst("Beer",$mak,"i") . ":" . filt($beer) . "</td>";
    } elsif ( $op eq "Brewery" ) {
      next if ( $mak =~ /^wine/i );  
      next if ( $mak =~ /^booze/i ); 
      next if ( $mak =~ /^restaurant/i ); 
      $fld = $mak;
      $mak =~ s"/"/<br/>";
      $line = "<td>" . lst("Beer",$mak) . "</td>" .
      "<td>$wday $effdate " .lst("Beer",$loc) .
            "<br/>" . filt("[$sty]") . "  " . filt($beer,"b")  ."&nbsp;</td>";
    } elsif ( $op eq "Beer" ) {
      next if ( $mak =~ /^wine/i );  
      next if ( $mak =~ /^booze/i ); 
      next if ( $mak =~ /^restaurant/i ); 
      $fld = $beer;
      $line = "<td>" . filt($beer,"b")  . "</td><td>$wday $effdate ". 
            lst("Beer",$loc) .  "<br/>" . filt("[$sty]"). " " . 
            lst("Beer",$mak,"i") . "&nbsp;</td>";
    } elsif ( $op eq "Wine" ) {
      next unless ( $mak =~ /^wine/i );
      $fld = $beer;
      $line = "<td>" . filt($beer,"b")  . "</td><td>$wday $effdate ". 
            lst("Wine",$loc) .
            "<br/>" . filt("[$sty]"). " " . filt($mak,"i") . "&nbsp;</td>";
    } elsif ( $op eq "Booze" ) {
      next unless ( $mak =~ /^booze/i );
      $fld = $beer;
      $line = "<td>" .filt($beer,"b") . "</td><td>$wday $effdate ".
            lst("Booze",$loc) .
            "<br/>" . filt("[$sty]"). " " . filt($mak,"i") . "&nbsp;</td>";
    } elsif ( $op eq "Restaurant" ) {
      next unless ( $mak =~ /^restaurant/i );
      $fld = "$loc";
      $rate = "$rate: <b>$ratings[$rate]</b>" if $rate;
      $pr = "$pr kr" if $pr;
      $line = "<td>" . filt($loc,"b") . "<br/>$pr</td><td><i>$beer</i>".
            "<br/>" . "$wday $effdate $rate</td>";
    } elsif ( $op eq "Style" ) {
      next if ( $mak =~ /^wine/i );  
      next if ( $mak =~ /^booze/i ); 
      next if ( $mak =~ /^restaurant/i ); 
      next if ( $sty =~ /^misc/i ); 
      $fld = $sty;
      $line = "<td>" . filt("[$sty]","b")  . "</td><td>$wday $effdate " .  
            lst("Beer",$loc,"i") . 
            "<br/>" . lst("Beer",$mak,"i") . ":" . filt($beer,"b") . "</td>";
    }
    next unless $fld;
    $fld = uc($fld); 
    next if $seen{$fld};
    $seen{$fld} = 1;
    #print "<tr>$line</tr>\n";
    push @displines, "<tr>$line</tr>\n";
  }
  @displines = sort { "\U$a" cmp "\U$b" } @displines   if ( $sortlist );
  foreach my $dl (@displines) {
    print $dl;
  }
  print "</table>\n";
  
} 
if ( !$op || $op =~ /Graph(\d*)/ ) { # Regular list, on its own, or after graph
  if ($qry || $qrylim) {
    print "<hr/> Filter: ";
    print "<a href='$url'><b>$qry (Clear)</b></a>" if ($qry);
    print " -".$qrylim if ($qrylim);
    print " &nbsp; \n";
    print "<br/>";
    print "<a href='$url?q=" . uri_escape($qry) . 
        "&f=r' >Ratings</a>\n";
    print "<a href='$url?q=" . uri_escape($qry) . 
        "&f=c' >Comments</a>\n";
    print "<a href='$url?q=" . uri_escape($qry) . "'>All</a>\n";
    print "<p/>\n";
  }
  my $i = scalar( @lines );
  my $lastloc = "";
  my $lastdate = "today";
  my $lastloc2 = ""; 
  my $lastwday = "";
  #my $maxlines = 25;
  my $daydsum = 0.0;
  my $daymsum = 0;
  my $locdsum = 0.0;
  my $locmsum = 0;
  my $origpr = "";
  while ( $i > 0 ) {
    $i--;
    next unless ( !$qry || $lines[$i] =~ /\b$qry\b/i );
    ( $stamp, $wday, $effdate, $loc, $mak, $beer, $vol, $sty, $alc, $pr, $rate, 
$com ) = 
       split( /; */, $lines[$i] );
    next if ( $qrylim eq "r" && ! $rate );
    next if ( $qrylim eq "c" && ! $com );
    $origpr = $pr;
    $pr = number($pr);
    $alc = number($alc);
    $vol = number($vol);
    #$pr = 0 unless ( $pr =~ /\d/ ); # Skip 'X' and other non-numericals
    my $date = "";
    my $time = "";
    if ( $stamp =~ /(^[0-9-]+) (\d\d?:\d\d?):/ ) {
      $date = $1;
      $time = $2;
    }

    my $dateloc = "$effdate : $loc";

    if ( $dateloc ne $lastloc && ! $qry) { # summary of loc and maybe date
      my $locdrinks = sprintf("%3.1f", $locdsum / $onedrink) ; 
      my $daydrinks = sprintf("%3.1f", $daydsum / $onedrink) ;
      # loc summary: if nonzero, and diff from daysummary 
      # or there is a new loc coming
      if ( $locdrinks > 0.1 ) {
        print "$lastloc2: $locdrinks d, $locmsum kr. <br/>\n";
        $locdsum = 0.0;
        $locmsum = 0;
      }
      # day summary: if nonzero and diff from daysummary and end of day
      #if ( abs ( $daydrinks > 0.1 ) && abs ( $daydrinks - $locdrinks ) > 0.1 &&
      #   $lastdate ne $effdate ) {
      if ( abs ( $daydrinks > 0.1 ) && $lastdate ne $effdate ) {
      #if ( $daydrinks > 0.1 ){
        print " <b>$lastwday</b>: $daydrinks d, $daymsum kr <br/>\n";
        $daydsum = 0.0;
        $daymsum = 0;
      }
      print "<p/>";
    }
    if ( $lastdate ne $effdate ) { # New date
      print "<hr/>\n" ;
      $lastloc = "";
    }
    if ( $dateloc ne $lastloc ) { # New location and maybe also new date
      print "<b>$wday $date </b>" . filt($loc,"b") . "</a><p/>\n" ;
    }
    if ( $date ne $effdate ) {
      $time = "($time)";
    }
    $daydsum += ( $alc * $vol ) if ($alc && $vol) ;
    $daymsum += $pr if ($pr) ;
    $locdsum += ( $alc * $vol ) if ($alc && $vol) ;
    $locmsum += $pr if ($pr) ;
    $anchor = $stamp || "";
    $anchor =~ s/[^0-9]//g;
    print "<a id='$anchor'/>\n";
    print "<form method='POST' style='display: inline;' >\n";
    print "<p>$time &nbsp;" . filt($mak,"i") . " : " . filt($beer,"b") . 
"<br/>\n";
    if ( $sty || $rate ) {
      print filt("[$sty]")   if ($sty);
      print " ($rate: $ratings[$rate])" if ($rate);
      print "<br/>\n";
    }
    print "<i>$com</i> <br/>\n" if ($com);
    print "$pr kr. &nbsp; " if ($origpr =~ /\d+/);
    print "$vol cl " if ($vol);
    print "* $alc % " if ($alc);
    if ( $alc && $vol ) {
      my $dr = sprintf("%1.2f", ($alc * $vol) / $onedrink );
      print "= $dr d ";
    }
    print "<br/>\n";
    # guess sizes for small/large beers
    my %vols;
    $vols{$vol} = 1;
    $vols{25} = 1;
    $vols{40} = 1;

    print "<a href='$url?e=" . uri_escape($stamp) ."' >Edit</a>\n";
    # No price - the script guesses based on size.
    # No location, reuse the current loc
    print "<input type='hidden' name='m' value='$mak' />\n";
    print "<input type='hidden' name='b' value='$beer' />\n";
    print "<input type='hidden' name='v' value='' />\n";
    print "<input type='hidden' name='s' value='$sty' />\n";
    print "<input type='hidden' name='a' value='$alc' />\n";
    print "<input type='hidden' name='l' value='$loc' />\n" if ( $copylocation 
);
    
    foreach my $volx (sort keys(%vols)  ){
      print "<input type='submit' name='submit' value='Copy $volx'
                  style='display: inline;' />\n";
    }
    print "</form>\n";

    print"</p>\n";
    $lastloc = $dateloc;
    $lastloc2 = $loc;
    $lastdate = $effdate;
    $lastwday = $wday;
    $maxlines--;
    last if ($maxlines == 0); # if negative, will go for ever
  }
  if ( ! $qry) { # final summary
    my $locdrinks = sprintf("%3.1f", $locdsum / $onedrink); 
    my $daydrinks = sprintf("%3.1f", $daydsum / $onedrink);
    # loc summary: if nonzero, and diff from daysummary 
    # or there is a new loc coming
    if ( $locdrinks > 0.1 ) {
      print "$lastloc2: $locdrinks d, $locmsum kr. \n";
      }
      # day summary: if nonzero and diff from daysummary and end of day
    if ( abs ( $daydrinks > 0.1 ) && abs ( $daydrinks - $locdrinks ) > 0.1 &&
         $lastdate ne $effdate ) {
      print " <b>$lastwday</b>: $daydrinks d, $daymsum kr\n";
      }
      print "<p/>";
    }

  print "<hr/>\n" ;
  if ( $maxlines >= 0 && $anchor ) {
    print "<p/><a href='$url?maxl=-1&" . $q->query_string() . "#$anchor'>" .
      "More</a><br/>\n";
  } else {
    print "<p/>That was the whole list<br/>\n";
  }
}
 
# HTML footer
print "</body></html>\n";

exit();

############################################

# Helper to sanitize input data
sub param {
  my $tag = shift;
  my $val = $q->param($tag);
  $val = "" if !defined($val);
  $val =~ s/[^a-zA-ZåæøÅÆØöÖäÄ\/ 0-9.,&:-]/_/g; 
  return $val;
}

# Helper to make a filter link
sub filt {
  my $f = shift;
  my $tag = shift || "nop";
  my $param = $f;
  $param =~ s"[\[\]]""g; # remove the [] around styles etc
  my $link = "<a href='$url?q=".uri_escape($param) ."' 
><$tag>$f</$tag></a>";
  return $link;
}

# Helper to make a link to a list
sub lst {
  my $op = shift; # The kind of list
  my $qry = shift; # Optional query to filter the list
  my $tag = shift || "nop";
  my $dsp = $qry || $op;
  $qry = "&q=" . uri_escape($qry) if $qry;
  $op = uri_escape($op);
  my $link = "<a href='$url?o=$op" . $qry ."' ><$tag>$dsp</$tag></a>";
  return $link;
}

# Helper to sanitize numbers
sub number {
  $v = shift;
  $v =~ s/,/./g;  # occasionally I type a decimal comma
  $v =~ s/[^0-9.]//g; # Remove all non-numeric chars
  $v=0 unless  $v;
  return $v;
}

# Helper to make an error message
sub error {
  my $msg = shift;
  print $q->header("Content-type: text/plain");
  print "ERROR\n";
  print $msg;
  exit();
}

