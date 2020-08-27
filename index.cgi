#!/usr/bin/perl -w

# Heikki's simple beer tracker
#
# Keeps beer drinking history in a flat text file.
#

use CGI;
use URI::Escape;
#use Time::HiRes qw(gettimeofday tv_interval); # while debugging slowness
use POSIX qw(strftime localtime);
use feature 'unicode_strings';

my $q = CGI->new;
my $mobile = ( $ENV{'HTTP_USER_AGENT'} =~ /Android/ );

# Constants
my $onedrink = 33 * 4.6 ; # A regular danish beer, 33 cl at 4.6%
my $datadir = "./beerdata/";
my $datafile = "";
my $plotfile = "";
my $cmdfile = "";
my $pngfile = "";
if ( ($q->remote_user()||"") =~ /^[a-zA-Z0-9]+$/ ) {
  $datafile = $datadir . $q->remote_user() . ".data";
  $plotfile = $datadir . $q->remote_user() . ".plot";
  $cmdfile = $datadir . $q->remote_user() . ".cmd";
  $pngfile = $datadir . $q->remote_user() . ".png";
} else {
  error ("Bad username\n");
}
my @ratings = ( "Undrinkable", "Bad", "Unpleasant", "Could be better",
"Ok", "Goes down well", "Nice", "Pretty good", "Excellent", "Perfect",
"I'm in love" );

# Links to beer lists at the most common locations and breweries
my %links;
$links{"Ølbaren"} = "http://oelbaren.dk/oel/";
$links{"Ølsnedkeren"} = "https://www.olsnedkeren.dk/";
$links{"Fermentoren"} = "http://fermentoren.com/index";
$links{"Dry and Bitter"} = "http://www.dryandbitter.com/products.php";
#$links{"Dudes"} = "http://www.dudes.bar"; # R.I.P Dec 2018
$links{"Taphouse"} = "http://www.taphouse.dk";

# currency conversions
my %currency;
$currency{"eur"} = 7.5;
$currency{"e"} = 7.5;

# Parameters - data file fields are the same order
# but there is a time stamp first, and the $del never gets to the data file
my $stamp = param("st");
my $wday = param("wd");  # weekday
my $effdate = param("ed");  # effective date
my $loc = param("l");  # location
my $mak = param("m");  # brewery (maker) (or "wine, red", or "restaurant, thai"
my $beer= param("b");  # beer
my $vol = param("v");  # volume, in cl
my $sty = param("s");  # style
my $alc = param("a");  # alc, in %vol, up to 1 decimal
my $pr  = param("p");  # price, DKK
my $rate= param("r");  # rating, 0=worst, 10=best
my $com = param("c");  # Comments
  # The rest are not in the data file
my $del = param("x");  # delete/update last entry - not in data file
my $qry = param("q");  # filter query, greps the list
my $qrylim = param("f"); # query limit, "c" or "r" for comments or ratings, "l" for extra links
my $op  = param("o");  # operation, to list breweries, locations, etc
my $edit= param("e");  # Record to edit
my $maxlines = param("maxl") || "25";  # negative = unlimited
my $sortlist = param("sort") || 0; # default to unsorted, chronological lists
my $url = $q->url;
my $localtest = 0; # Local test installation

# Default sizes
my $defaultvol = 40;
if ( $mak =~ /^Wine,/ ) {
  $defaultvol = 16;
}
my %volumes = ( # Comment is displayed on the About page
   'T' => " 2 Taster, sizes vary, always small",
   'G' => "15 Glass of wine - 12 in places, at home 15 is more realistic",
   'S' => "25 Small, usually 25",
   'M' => "33 Medium, typically a bottle beer",
   'L' => "40 Large, 40cl in most places I frequent",
   'C' => "44 A can of 44 cl",
   'W' => "75 Bottle of wine",
   'B' => "75 Bottle of wine",
);
my $half;
if ( $vol =~ s/^(H)(.+)$/$2/i ) {
  $half = $1;
}
my $volunit = uc(substr($vol,0,1));
if ( $volumes{$volunit} && $volumes{$volunit} =~ /^ *(\d+)/ ) {
  $actvol = $1;
  $vol =~s/$volunit/$actvol/i;
}
if ($half) {
  $vol = int($vol / 2) ;
}
if ( $vol =~ /([0-9]+) *oz/i ) {  # (us) fluid ounces
  $vol = $1 * 3;   # Actually, 2.95735 cl, no need to mess with decimals
}

if ( ! $stamp ) {
  $stamp = datestr( "%F %T");
}
if ( ! $effdate ) { # Effective date can be the day before
  $effdate = datestr( "%a; %F", -0.3);
} else {
  $effdate = "$wday; $effdate";
}

##############################
# Read the file
# Set defaults for the form, usually from last line in the file
# Actually, at this point only set $lastline and $foundline
# They get split later. Collects all kind of stats to be used later.
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
my %seen; # Count how many times var names seen before
my %restaurants; # maps location name to restaurant types
my $allfirstdate = "";
my %monthdrinks; # total drinks for each calendar month
my %monthprices; # total money spent. Indexed with "yyyy-mm"
my $weekago = datestr("%F", -7);
my $weeksum = 0;
my $weekmsum = 0;
my $calmon; # YYYY-MM for montly stats
my $lastmonthday = "";
while (<F>) {
  chomp();
  s/#.*$//;  # remove comments
  next unless $_; # skip empty lines
  push @lines, $_; # collect them all
  my ( $t, $wd, $ed, $l, $m, $b, $v, $s, $a, $p, $r, $c ) = split( /; */ );
  $allfirstdate=$ed unless($allfirstdate);
  my $restname = "";
  $restname = "$1$l" if ( $m  =~ /^(Restaurant,)/i );
  $thisloc = $l if $l;
  $seen{$l}++;
  $seen{$m}++;
  $seen{$b}++;
  $seen{$s}++;
  $seen{$restname}++;
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
  $p = price($p);
  if ( !( $m  =~ /^Restaurant,/i ) ) {
    # do not sum restaurant lines, drinks filed separately
    $lastdatesum += ( $a * $v ) if ($a && $v);
    $lastdatemsum += $1 if ( $p =~ /(\d+)/ );
    if ( $effdate eq "$wd; $ed" ) { # today
        $todaydrinks = sprintf("%3.1f", $lastdatesum / $onedrink ) . " d " ;
        $todaydrinks .= ", $lastdatemsum kr." if $lastdatemsum > 0  ;
    }
    if ( $ed gt $weekago ) {
      $weeksum += $a * $v;
      $weekmsum += $p;
      #print STDERR "wa=$weekago ed=$ed a=$a v=$v av=" . $a*$v / $onedrink .
      # " p=$p ws=$weeksum =" . $weeksum/$onedrink . " wms=$weekmsum\n";
    }
    if ( $ed =~ /(^\d\d\d\d-\d\d)/ )  { # collect stats for each month
      $calmon = $1;
      $monthdrinks{$calmon} += $a * $v;
      $monthprices{$calmon} += $p;
    }
    $lastmonthday = $1 if ( $ed =~ /^\d\d\d\d-\d\d-(\d\d)/ );
  }
  if ( ( $m  =~ /^Restaurant,/i ) ) {
    $restaurants{$l} = $m; # Remember style
  }
}
if ( ! $todaydrinks ) { # not today
  $todaydrinks = "($lastwday: " .
    sprintf("%3.1f", $lastdatesum / $onedrink ) . "d $lastdatemsum kr)" ;
  $copylocation = 1;
}
$weeksum = sprintf( "%3.1fd (=%3.1f/day)", $weeksum / $onedrink,  $weeksum / $onedrink /7);
$todaydrinks .= "\nWeek: $weeksum $weekmsum kr";
$todaydrinks .= "\n$calmon: " . sprintf("%3.1fd (=%3.1f/d)",
       $monthdrinks{$calmon}/$onedrink, $monthdrinks{$calmon}/$onedrink/$lastmonthday).
  " $monthprices{$calmon} kr" if ($calmon);

################################
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
  my $i = scalar( @lines )-1;
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
  if (!$vol) {
    $vol = $defaultvol;
  }
  my $curpr = curprice($pr);
  if ($curpr) {
    $com =~ s/ *\[\d+\w+\] *$//i; # Remove old price
    $com .= " [$pr]";
    $pr = $curpr;
  } else {
    $pr = price($pr);
  }
  $alc = number($alc);
  my $line = "$loc; $mak; $beer; $vol; $sty; $alc; $pr; $rate; $com";
  if ( $sub eq "Record" || $sub =~ /^Copy/ || $sub =~ /^Rest/ ) {
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

############################
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

########################
# HTML head
print $q->header(
  -type => "text/html;charset=UTF-8",
  -Cache_Control => "no-cache, no-store, must-revalidate",
  -Pragma => "no-cache",
  -Expires => "0",
  -X_beertracker => "This beertracker is my hobby project. It is open source",
  -X_author => "Heikki Levanto",
  -X_source_repo => "https://github.com/heikkilevanto/beertracker" );
print "<html><head>\n";
print "<title>Beer</title>\n";
print "<meta http-equiv='Content-Type' content='text/html;charset=UTF-8'>\n";
print "<meta name='viewport' content='width=device-width, initial-scale=1.0'>\n";
print "<style rel='stylesheet'>\n";
print   "* { background-color: #003000; color: #FFFFFF; font-size: small }\n";
print "</style>\n";
print "<link rel='shortcut icon' href='beer.png'/>\n";
print "</head>\n";
print "<body>\n";
print "\n<!-- Read " . scalar(@lines). " lines from $datafile -->\n\n" ;

my $script = <<'SCRIPTEND';
  var clearonclick = true;
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


#############################
# Main input form
print "\n<form method='POST'>\n";
print "<table >";
my $clr = "Onclick='if (clearonclick) {value=\"\";}'";
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
print "<tr><td><input name='v' value='$vol cl' $sz2 placeholder='Vol' />\n";
print "<input name='a' value='$alc %' $sz2 placeholder='Alc' />\n";
print "<input name='p' value='$pr.-' $sz2 placeholder='Price' /></td>\n";
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
  print "<tr><td><input type='submit' name='submit' value='Save'/>&nbsp;&nbsp;";
  print "&nbsp;<span align=right>Clr ";
  print "<input type='checkbox' checked=clearonclick onclick='clearonclick=this.checked;'/></span></td>\n";
  print "<td>";
  print "<a href='$url' >cancel</a>";
  print "&nbsp;<input type='submit' name='submit' value='Delete'/></td></tr>\n";
} else {
  print "<tr><td><input type='submit' name='submit' value='Record'/>\n";
  print "&nbsp;<input type='button' value='clear' onclick='clearinputs()'/></td>\n";
  print "<td><select name='ops' " .
              "onchange='document.location=\"$url?\"+this.value;' >";
  print "<option value='' >Show</option>\n";
  print "<option value='o=full' >Full List</option>\n";
  print "<option value='o=short' >Short List</option>\n";
  my @ops = ("Graph",
     "Location","Brewery", "Beer",
     "Wine", "Booze", "Restaurant", "Style", "Months", "Years", "About");
  for my $opt ( @ops ) {
    print "<option value='o=$opt'>$opt</option>\n";
  }
  print "</select></td>\n";
  print "</tr>\n";
}
print "</table>\n";
print "</form>\n";

##############
# Graph
#if ( !$op && $ENV{'HTTP_USER_AGENT'} !~ /Android/ ) {
if ( !$op && !$mobile ) {
  $op = "Graph";  # Default to showing the graph on desktops
} # but not on mobile devics

my %averages; # floating average by effdate
if ( $op && $op =~ /Graph(B?)-?(\d+)?-?(-?\d+)?/i ) { # make a graph
  my $bigimg = $1 ||"";
  my $startoff = $2 || 30; # days ago
  my $endoff = $3 || -1;  # days ago, -1 defaults to tomorrow
  my $startdate = datestr ("%F", -$startoff );
  my $enddate = datestr( "%F", -$endoff);
  if ( $startdate lt $allfirstdate) {
    $startdate = $allfirstdate;
    if ($enddate lt $startdate) {
      $enddate = $allfirstdate;
    }
  }
  print "\n<!-- " . $op . " $startdate to $enddate -->\n";
  my %sums; # drink sums by (eff) date
  for ( my $i = 0; $i < scalar(@lines); $i++ ) { # calculate sums
    ( $stamp, $wday, $effdate, $loc, $mak, $beer, $vol, $sty, $alc, $pr, $rate, $com ) =
       split( /; */, $lines[$i] );
    next if ( $mak =~ /^restaurant/i );
    $sums{$effdate} = ($sums{$effdate} || 0 ) + $alc * $vol if ( $alc && $vol );
  }
  my $ndays = $startoff+35; # to get enough material for the running average
  my $date;
  open F, ">$plotfile"
      or error ("Could not open $plotfile for writing");
  my $sum30 = 0.0;
  my @month;
  my @week;
  my $wkday;
  my $zerodays = -1;
  my $fut = "NaN";
  while ( $ndays > $endoff) {
    $ndays--;
    $rawdate = datestr("%F:%u", -$ndays);
    ($date,$wkday) = split(':',$rawdate);
    my $tot = ( $sums{$date} || 0 ) / $onedrink ;
    @month = ( @month, $tot);
    shift @month if scalar(@month)>=30;
    @week = ( @week, $tot);
    shift @week if scalar(@week)>7;
    $sum30 = 0.0;
    my $sumw = 0.0;
    for ( my $i = 0; $i < scalar(@month); $i++) {
      my $w = $i+1 ;  #+1 to avoid zeroes
      $sum30 += $month[$i] * $w;
      $sumw += $w;
    }
    my $sumweek = 0.0;
    my $cntweek = 0;
    foreach my $t ( @week ) {
      $sumweek += $t;
      $cntweek++;
    }
    #print "<!-- $date " . join(', ', @month). " $sum30 " . $sum30/$sumw . "-->\n";
    #print "<!-- $date " . join(', ', @week). " $sumweek " . $sumweek/$cntweek . "-->\n";
    $sum30 = $sum30 / $sumw;
    $sumweek = $sumweek / $cntweek;
    $averages{$date} = sprintf("%1.2f",$sum30); # Save it for the long list
    my $zero = "";
    if ($tot > 0.15 ) { # one 0.5% "no-alc" beer still gets a zero mark
      $zerodays = 0;
    } elsif ($zerodays >= 0) { # have seen a real $tot
      $zero = -0.1 + ($zerodays % 7) * 0.4 ;
      $zerodays ++; # Move the subsequent zero markers higher up
    }
    if ( $ndays <=0 ) {
      $zero = "NaN"; # no zero mark for current or next date, it isn't over yet
    }
    if ( $ndays <0 ) {
      $fut = $sum30;
      $sum30="NaN"; # No avg for next date, but yes for current
      $sumweek = "NaN"; #
    }
    if ($startoff - $endoff > 45) {
      $sumweek = "NaN"; # Can't see them anyway
    }
    my $wkend = 0;
    if ($wkday > 4) {
       $wkend = $tot;
       $tot = 0;
    }
    #print "$ndays: $date / $wkday -  $tot $wkend z: $zero $zerodays<br/>"; ###
    print F "$date $tot $wkend $sum30 $sumweek $zero $fut\n "  if ($zerodays >= 0);
  }
  close(F);
  my $oneday = 24 * 60 * 60 ; # in seconds
  my $oneweek = 7 * $oneday ;
  my $onemonth = 365.24 * $oneday / 12;
  my $numberofdays=7;
  my $xformat = "\"%d\\n%b\"";  # 14 Jul
  my $xtic = $oneweek;
  my $pointsize = "";
  if ( $startoff - $endoff > 400 ) {
    $xformat="\"%Y\"";  # 2019
    $xtic = $oneday * 365.24 ;
    $pointsize = "set pointsize 0.2\n" ;
  } elsif ( $startoff - $endoff > 120 ) {
    $xformat="\"%b\\n'%y\"";  # Jul 19
    $xtic = $onemonth;
    $pointsize = "set pointsize 0.5\n" ;
  }
  my $imgsz = "340,240";
  if ($bigimg) {
    $imgsz = "640,480";
  }
  my $cmd = "" .
       "set term png small size $imgsz \n".
       $pointsize .
       "set out \"$pngfile\" \n".
       "set xdata time \n".
       "set timefmt \"%Y-%m-%d\" \n".
       "set xrange [ \"$startdate\" : \"$enddate\" ] \n".
       "set yrange [ -.5 : ] \n" .
       "set format x $xformat \n" .
       "set ytics 0,2 out\n" .
       "set xtics \"2015-11-01\", $xtic out\n" .  # Happens to be sunday, and first of month
       "set mytics 2 \n".
       "set style fill solid \n" .
       "set boxwidth 0.7 relative \n" .
       "set grid xtics ytics  linewidth 0.1 linecolor 4 \n".
       "plot " .
             # lc 0=grey 1=red, 2=green, 3=blue
             # note the order of plotting, later ones get on top
             # so we plot weekdays, weekends, avg line, zeroes
        "\"$plotfile\" " .
            "using 1:2 with boxes lc 0 notitle ," .  # weekdays
        "\"$plotfile\" " .
            "using 1:3 with boxes lc 3 notitle," .  # weekends
        "\"$plotfile\" " .
            "using 1:4 with line lc 9 lw 2 notitle, " .  # avg30
        "\"$plotfile\" " .
            "using 1:5 with points pointtype 1 lc \"gray80\" notitle, " .  # avg7
              # (pt 0: dot, 1:+ 2:x 3:* 4:square 5:filled 6:o 7:filled 8:
        "\"$plotfile\" " .
            "using 1:7 with dots lc 9 notitle, " .  # future tail
        "\"$plotfile\" " .
            "using 1:6 with points lc 2 pointtype 11 notitle \n" .  # zeroes
        "";
  open C, ">$cmdfile"
      or error ("Could not open $plotfile for writing");
  print C $cmd;
  close(C);
  my $htcmd = $cmd;
  #$htcmd =~ s/\n/<br\/>\n/g;
  #print "$htcmd <br/>\n";
  system ("gnuplot $cmdfile ");
  print "<hr/>\n";
  if ($bigimg) {
    print "<a href='$url?o=Graph-$startoff-$endoff'><img src=\"$pngfile\"/></a><br/>\n";
  } else {
    print "<a href='$url?o=GraphB-$startoff-$endoff'><img src=\"$pngfile\"/></a><br/>\n";
  }
  my $len = $startoff - $endoff;
  my $es = $startoff + $len;
  my $ee = $endoff + $len;
  print "<a href='$url?o=Graph$bigimg-$es-$ee'>&lt;&lt;</a> &nbsp; \n";
  my $ls = $startoff - $len;
  my $le = $endoff - $len;
  if ($le < 0 ) {
    $ls += $ls;
    $le = 0;
  }
  if ($endoff>0) {
    print "<a href='$url?o=Graph$bigimg-$ls-$le'>&gt;&gt;</a>\n";
  } else { # at today, >> plots a zero-tail
    print "<a href='$url?o=Graph$bigimg-$startoff--14'>&gt;</a>\n";
  }
  print " &nbsp; <a href='$url?o=Graph$bigimg'>Month</a>\n";
  print " <a href='$url?o=Graph$bigimg-365'>Year</a> \n";

  my $zs = $startoff + int($len/2);
  my $ze = $endoff - int($len/2);
  if ( $ze < 0 ) {
    $zs -= $ze;
    $ze = 0 ;
  }
  print " &nbsp; <a href='$url?o=Graph$bigimg-$zs-$ze'>[ - ]</a>\n";
  my $is = $startoff - int($len/4);
  my $ie = $endoff + int($len/4);
  print " &nbsp; <a href='$url?o=Graph$bigimg-$is-$ie'>[ + ]</a>\n";

  print "<br/>\n";


########################
# short list, one line per day
} elsif ( $op eq "short" ) {
  my $i = scalar( @lines );
  my $entry = "";
  my $places = "";
  my $lastdate = "";
  my $lastloc = "";
  my $daysum = 0.0;
  my $daymsum = 0.0;
  my %locseen;
  my $month = "";
  while ( $i > 0 ) {
    $i--;
    ( $stamp, $wday, $effdate, $loc, $mak, $beer, $vol, $sty, $alc, $pr, $rate,
$com ) =
       split( /; */, $lines[$i] );
    if ( $i == 0 ) {
      $lastdate = "";
      if (!$entry) { # make sure to count the last entry too
        $entry = filt($effdate, "") . " " . $wday ;
        $daysum += ( $alc * $vol ) if ($alc && $vol);
        $daymsum += $pr;
        if ( $places !~ /$loc/ ) {
          my $bold = "";
          if ( !defined($locseen{$loc}) ) {
            $bold = "b";
            }
          $places .= " " . filt($loc,$bold);
          $locseen{$loc} = 1;
        }
      }
    }
    if ( $lastdate ne $effdate ) {
      if ( $entry ) {
        my $daydrinks = sprintf("%3.1f", $daysum / $onedrink) ;
        $entry .= " " . unit($daydrinks,"d") . " " . unit($daymsum,"kr");
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
      do { # TODO - Do this in perl, with datestr()
           # TODO - Make this like the graph, build an array of entries first
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
      $wday = "<b>$wday</b>" if ($wday eq "Fri");
      $entry = filt($effdate, $bold) . " " . $wday ;
      $places = "";
      $lastdate = $effdate;
      $lastloc = "";
      $daysum = 0.0;
      $daymsum = 0.0;
    }
    next if ($mak =~ /restaurant/i );
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
    $daymsum += $pr;
  }
  if ( $maxlines >= 0 ) {
    print "<br/><a href='$url?maxl=-1&" . $q->query_string() . "'>" .
      "More</a><br/>\n";
  }


#######################
# Annual summary
} elsif ( $op eq "Years" ) {
  my $i = scalar( @lines );
  my %sum;
  my %alc;
  my $ysum = 0;
  my $yalc = 0;
  my $thisyear = "";
  my $sofar = "so far";
  my $y;
  while ( $i > 0 ) {
    $i--;
    #print "$thisyear $i: $lines[$i]<br/>\n";
    ( $stamp, $wday, $effdate, $loc, $mak, $beer, $vol, $sty, $alc, $pr, $rate, $com ) =
      split( /; */, $lines[$i] );
    $y = substr($effdate,0,4);
    #print "  y=$y, ty=$thisyear <br/>\n";
    next if ($mak =~ /restaurant/i );
    if ($i == 0) {
      $thisyear = $y unless ($thisyear);
      $y = "END";
      $pr = number($pr);  # count also the last line
      $alc = number($alc);
      $vol = number($vol);
      $sum{$loc} = ( $sum{$loc} || 0.1 / ($i+1) ) + $pr if ($pr);  # $i keeps sort order
      $alc{$loc} = ( $alc{$loc} || 0 ) + ( $alc * $vol ) if ($alc && $vol);
      $ysum += $pr if ($pr);
      $yalc += $alc * $vol if ($alc && $vol);
      #print "$i: $loc: $mak:  " . $sum{$loc} . " " . $alc{$loc} . "<br/>\n";
    }
    if ( $y ne $thisyear ) {
      if ($thisyear) {
        print "Year $thisyear $sofar<br/>\n";
        my @kl = sort { $sum{$b} <=> $sum{$a} }  keys %sum;
        $k = 0;
        print "<pre>";
        while ( $k < 12 && $kl[$k] ) {
          my $loc = $kl[$k];
          my $alc = sprintf("%5.0fd", $alc{$loc} / $onedrink) ;
          my $pr = sprintf("%6.0f", $sum{$loc});
          print "$pr $alc $loc\n";
          $k++;
        }
        my $loc = " = TOTAL for $thisyear $sofar";
        my $alc = sprintf("%5.0f", $yalc / $onedrink) ;
        my $pr = sprintf("%6.0f", $ysum);
        print "$pr $alc"."d $loc\n";
        if ($sofar) {
          my $daynum = datestr("%j"); # day number in year
          $alc = sprintf("%5.0fd", $alc / $daynum * 365);
          $pr = sprintf("%6.0f", $pr / $daynum * 365);
          print "$pr $alc  = PROJECTED for whole $thisyear\n";
        }
        print "</pre>";
        $sofar = "";
      }
      %sum = ();
      %alc = ();
      $ysum = 0;
      $yalc = 0;
      $thisyear = $y;
      last if ($y eq "END");
    } # new year
    $pr = number($pr);
    $alc = number($alc);
    $vol = number($vol);
    $sum{$loc} = ( $sum{$loc} || 0.1 / ($i+1) ) + $pr if ($pr);  # $i keeps sort order
    $alc{$loc} = ( $alc{$loc} || 0 ) + ( $alc * $vol ) if ($alc && $vol);
    $ysum += $pr if ($pr);
    $yalc += $alc * $vol if ($alc && $vol);
    #print "$i: $loc: $mak:  " . $sum{$loc} . " " . $alc{$loc} . "<br/>\n";
  }

############################+
# Monthly statistics from %monthdrinks and %monthprices
} elsif ( $op =~ /Months(B?)/ ) {
  my $bigimg = $1 ||"";
  if ( $allfirstdate !~ /^(\d\d\d\d)/ ) {
    print "Oops, no year from allfirstdate '$allfirstdate' <br/>\n";
    exit(); # Never mind missing footers
  }
  my $firsty=$1;
  my $lasty = datestr("%Y",0);
  my $lastym = datestr("%Y-%m",0);
  my $dayofmonth = datestr("%d");
  open F, ">$plotfile"
      or error ("Could not open $plotfile for writing");
  my @ydays;
  my @ydrinks;
  my @yprice;
  my $t = "";
  $t .= "<table border=1 style='align:right'>\n";
  $t .="<tr><td></td>\n";
  my @months = ( "", "Jan", "Feb", "Mar", "Apr", "May", "Jun",
                 "Jul", "Aug", "Sep", "Oct", "Nov", "Dec");
  foreach $y ( reverse($firsty .. $lasty) ) {
    $t .= "<td><b>&nbsp;$y</b></td>";
  }
  $t .= "</tr>\n";
  foreach $m ( 1 .. 12 ) {
    $t .= "<tr><td>$months[$m]</td>\n";
    print F "$months[$m] ";
    foreach $y ( reverse($firsty .. $lasty) ) {
      #print "<td>$y - $m </td>\n";
      my $calm = sprintf("%d-%02d",$y,$m);
      my $d="";
      my $dd;
      if ($monthdrinks{$calm}) {
        $ydrinks[$y] += $monthdrinks{$calm};
        $yprice[$y] += $monthprices{$calm};
        $ydays[$y] += 30;
        $d = ($monthdrinks{$calm}||0) / $onedrink;
        $dd = sprintf("%3.1f", $d / 30); # scale to dr/day, approx
        if ( $calm eq $lastym ) { # current month
          $dd = sprintf("%3.1f", $d / $dayofmonth); # scale to dr/day
          $d = "~" . unit($dd,"d");
          $ydays[$y] += $dayofmonth - 30;
        } else {
          $dd = sprintf("%3.1f", $d / 30); # scale to dr/day, approx
          $d = unit($dd,"d");
        }
      }
      my $p = $monthprices{$calm};
      $t .= "<td align=right>".$d .
        "<br/>".unit($p,"kr");
      if ($calm eq $lastym) {
        $p = int($monthprices{$calm} / $dayofmonth * 30);
        $t .= "<br/>~". unit($p,"kr");
      }
      $t .= "</td>\n";
      #if ( !$d || $calm eq $lastym ) { # Don't plot the current month,
      if ( !$d ) { # Don't plot the current month,
        print F "NaN ";  # not finished with it yet
      } else {
        print F "$dd ";
      }
    }
    $t .= "</tr>";
    print F "\n";
  }
  close(F);
  $t .= "<tr><td>Avg</td>\n";
  foreach $y ( reverse($firsty .. $lasty) ) {
    my $d = sprintf("%3.1f", $ydrinks[$y] / $ydays[$y] / $onedrink) ;
    $d = unit($d, "d");
    my $pr = sprintf("%3d", $yprice[$y]/$ydays[$y]);
    $t .= "<td align=right>$d</td>";
  }
  $t .= "</tr>";
  $t .= "<tr><td>Sum</td>\n";
  foreach $y ( reverse($firsty .. $lasty) ) {
    my $pr = sprintf("%5.0f", $yprice[$y] ) ;
    $pr = unit($pr, "kr");
    $t .= "<td align=right>$pr</td>";
  }
  $t .= "</tr>";

  $t .= "</table>\n";
  my $imgsz = "340,240";
  if ($bigimg) {
    $imgsz = "640,480";
  }
  my $cmd = "" .
       "set term png small size $imgsz \n".
       "set out \"$pngfile\" \n".
       "set yrange [0:] \n" .
       "set mxtics 1\n".
       "set grid xtics ytics\n".
       "set xdata time \n".
       "set timefmt \"%b\" \n".
       "set format x \"%b\"\n" .
       "plot ";
  my $lw = 1;
  my $lc = 1;
  for ( my $i = $lasty - $firsty +2; $i > 1; $i--) {
    $cmd .= "\"$plotfile\" " .
            "using 1:$i with line lc $lc lw $lw notitle," ;
    $lw+= 2;
    $lc++;
  }
  $cmd =~ s/,$//; # Remove last comma
  $cmd .= "\n";
  open C, ">$cmdfile"
      or error ("Could not open $plotfile for writing");
  print C $cmd;
  close(C);
  system ("gnuplot $cmdfile ");
  print "<img src=\"$pngfile\"/>\n";
  print "<hr/>";
  print $t;  # The table we built above

#############################
# About page
} elsif ( $op eq "About" ) {
  print "<hr/><h2>Beertracker</h2>\n";
  print "Copyright 2020 Heikki Levanto. <br/>";
  print "Beertracker is my little script to help me remember all the beers I meet.\n";
  print "It is Open Source.\n";
  print "<hr/>";
  print "Some links I may find useful: <ul>";
  print "<li><a href='https://github.com/heikkilevanto/beertracker' target='_blank'>".
     "Beertracker on GitHub</a></li>\n";
  print "<li><a href='https://www.ratebeer.com' target='_blank'>RateBeer</a></li>\n";
  print "<li><a href='https://untappd.com' target='_blank'>Untappd</a></li>\n";
  print "</ul><p/>\n";
  print "Some of my favourite bars and breweries<ul>";
  for my $k ( sort keys(%links) ) {
    print "<li><a href='$links{$k}'>$k</a></li>";
  }
  print "</ul><p/>\n";
  print "<hr/>";
  print "Shorthand for drink volumes<br/><ul>\n";
  for my $k ( sort { $volumes{$a} cmp $volumes{$b} } keys(%volumes) ) {
    print "<li><b>$k</b> $volumes{$k}</li>\n";
  }
  print "</ul>\n";
  print "You can prefix them with 'h' for half, as in HW = half wine = 37cl<br/>\n";
  print "Of course you can just enter the number of centiliters <br/>\n";
  print "Or even ounces, when traveling: '6oz' = 18 cl<br/>\n";

} elsif ( $op eq "full" ) {
  # Ignore for now, we print the full list later.
} elsif ( $op ) {

#######################
# various lists (beer, location, etc)
  print "<hr/><a href='$url'><b>$op</b> list</a>.\n";
  if ( !$sortlist) {
    print "(<a href='$url?o=$op&sort=1' >sort</a>) <br/>\n";
  } else {
    print "(<a href='$url?o=$op'>Recent</a>) <br/>\n";
  }
  print "Filter: <a href='$url?q=$qry'>$qry</a> " .
     "<a href='$url?o=$op'>(clear) <br/>" if $qry;
  my $i = scalar( @lines );
  my $fld;
  my $line;
  my @displines;
  my %lineseen;
  my $anchor="";
  my $odd = 1;
  print "&nbsp;<br/><table style='background-color: #006000;' >\n";
  # For some reason this sets a color between the cells, not within them.
  # which is ok, makes it easier to see what is what.
  while ( $i > 0 ) {
    $i--;
    next unless ( !$qry || $lines[$i] =~ /\b$qry\b/i );
    ( $stamp, $wday, $effdate, $loc, $mak, $beer, $vol, $sty, $alc, $pr, $rate,
$com ) =
       split( /; */, $lines[$i] );
    $fld = "";
    if ( $op eq "Location" ) {
      $fld = $loc;
      $line = "<td>" . filt($loc,"b") .
        "&nbsp; " . loclink($loc, "L") . "  " . glink($loc, "G") . "</td>" .
        "<td>$wday $effdate ($seen{$loc})<br/>" .
        lst("Beer",$mak,"i") . ": " . filt($beer) . "</td>";
    } elsif ( $op eq "Brewery" ) {
      next if ( $mak =~ /^wine/i );
      next if ( $mak =~ /^booze/i );
      next if ( $mak =~ /^restaurant/i );
      $fld = $mak;
      $mak =~ s"/"/<br/>";
      $line = "<td>" . lst("Beer",$mak) . "<br/>&nbsp;&nbsp;" . glink($mak) . "</td>" .
      "<td>$wday $effdate " .lst("Beer",$loc) . " ($seen{$fld})" .  # $mak before cleaning
            "<br/>" . filt("[$sty]") . "  " . filt($beer,"b")  ."&nbsp;</td>";
    } elsif ( $op eq "Beer" ) {
      next if ( $mak =~ /^wine/i );
      next if ( $mak =~ /^booze/i );
      next if ( $mak =~ /^restaurant/i );
      $fld = $beer;
      $line = "<td>" . filt($beer,"b") . "&nbsp; ($seen{$beer}) &nbsp;" . glink($mak,"G") ."</td>" .
            "<td>$wday $effdate ".
            lst("Beer",$loc) .  "<br/>" .
            filt("[$sty]"). " " . unit($alc,'%') .
            lst("Beer",$mak,"i") . "&nbsp;</td>";
    } elsif ( $op eq "Wine" ) {
      next unless ( $mak =~ /^wine, *(.*)$/i );
      $fld = $beer;
      my $stylename = $1;
      $line = "<td>" . filt($beer,"b")  . "&nbsp; $stylename &nbsp;" . glink($beer, "G") . "</td>" .
            "<td>$wday $effdate ".
            lst("Wine",$loc) . " ($seen{$beer})" .
            "<br/>" . filt("[$sty]"). "</td>";
    } elsif ( $op eq "Booze" ) {
      next unless ( $mak =~ /^booze, *(.*)$/i );
      $fld = $beer;
      my $stylename = $1;
      $line = "<td>" .filt($beer,"b") . "&nbsp;" . glink($beer, "G") ."</td>" .
            "<td>$wday $effdate ".
            lst("Booze",$loc) ." ($seen{$beer})" .
            "<br/>" . filt("[$sty]"). " " . unit($alc,'%') . filt($mak,"i", $stylename) . "&nbsp;</td>";
    } elsif ( $op eq "Restaurant" ) {
      next unless ( $mak =~ /^restaurant,? *(.*)$/i );
      my $rstyle="";  # op,qry,tag,dsp
      if ( $1 ) { $rstyle = lst($op, "Restaurant, $1", "", $1); }
      $fld = "$loc";
      $rate = "$rate: <b>$ratings[$rate]</b>" if $rate;
      my $restname = "Restaurant,$loc";
      my $rpr = "";
      $rpr = "&nbsp; $pr kr" if ($pr && $pr >0) ;
      $line = "<td>" . filt($loc,"b") . "&nbsp; ($seen{$restname})<br/>".
              "$rstyle  &nbsp;" . glink("Restaurant $loc") . "</td>" .
              "<td><i>$beer</i>". " $rpr<br/>" .
              "$wday $effdate $rate</td>";
    } elsif ( $op eq "Style" ) {
      next if ( $mak =~ /^wine/i );
      next if ( $mak =~ /^booze/i );
      next if ( $mak =~ /^restaurant/i );
      next if ( $sty =~ /^misc/i );
      $fld = $sty;
      $line = "<td>" . filt("[$sty]","b") . " ($seen{$sty})" . "</td><td>$wday $effdate " .
            lst("Beer",$loc,"i") .
            "<br/>" . lst("Beer",$mak,"i") . ": " . filt($beer,"b") . "</td>";
    } else {
      print "<!-- unknown shortlist '$op' -->\n";
      last;
    }
    next unless $fld;
    $fld = uc($fld);
    next if $lineseen{$fld};
    $lineseen{$fld} = 1;
    #print "<tr>$line</tr>\n";
    push @displines, "<tr>$line</tr>\n";
  }
  @displines = sort { "\U$a" cmp "\U$b" } @displines   if ( $sortlist );
  foreach my $dl (@displines) {
    print $dl;
  }
  print "</table>\n";
  print "<br/>Total " . scalar(@displines) . " entries <br/>\n" if (scalar(@displines));

}
########################
# Regular list, on its own, or after graph
if ( !$op || $op eq "full" ||  $op =~ /Graph(\d*)/ ) {
  my @ratecounts = ( 0,0,0,0,0,0,0,0,0,0,0);
  print "\n<!-- Full list -->\n ";
  print "<hr/>Filter: <a href='$url'><b>$qry (Clear)</b></a>" if ($qry || $qrylim);
  print " -".$qrylim if ($qrylim);
  print " &nbsp; \n";
  print "<br/>" . glink($qry) . " " . rblink($qry) . " " . utlink($qry) ."\n" if ($qry);

  print "<br/>"if ($qry || $qrylim);
  print "<a href='$url?q=" . uri_escape($qry) .
      "&f=r' >Ratings</a>\n";
  print "<a href='$url?q=" . uri_escape($qry) .
      "&f=c' >Comments</a>\n";
  print "<a href='$url?q=" . uri_escape($qry) .
      "&f=l' >Links</a>\n";
  if ($qrylim) {
    print "<a href='$url?q=" . uri_escape($qry) . "'>All</a><br/>\n";
    for ( my $i = 0; $i < 11; $i++) {
      print "<a href='$url?q=" . uri_escape($qry) . "&f=r$i' >$i</a> &nbsp;";
    }
  }
  my $i = scalar( @lines );
  my $lastloc = "";
  my $lastdate = "today";
  my $lastloc2 = "";
  my $lastwday = "";
  #my $maxlines = 25;
  my $daydsum = 0.0;
  my $daymsum = 0;
  my $loccnt = 0;
  my $locdsum = 0.0;
  my $locmsum = 0;
  my $origpr = "";
  while ( $i > 0 ) {
    $i--;
    next unless ( !$qry || $lines[$i] =~ /\b$qry\b/i );
    ( $stamp, $wday, $effdate, $loc, $mak, $beer,
      $vol, $sty, $alc, $pr, $rate, $com ) = split( /; */, $lines[$i] );
    next if ( $qrylim eq "c" && (! $com || $com =~ /^ *\(/ ) );
      # Skip also comments like "(4 EUR)"
    next if ( $qrylim =~ /^r(\d*)/ && ! $rate );  # any rating
    next if ( $1 && $rate ne $1 );  # filter on "r7" or such
    $maxlines--;
    last if ($maxlines == 0); # if negative, will go for ever
    # Stop here, when we know we have more to come, so we can show proper "more" link

    $origpr = $pr;
    $pr = number($pr);
    $alc = number($alc);
    $vol = number($vol);
    my $date = "";
    my $time = "";
    if ( $stamp =~ /(^[0-9-]+) (\d\d?:\d\d?):/ ) {
      $date = $1;
      $time = $2;
    }

    my $dateloc = "$effdate : $loc";

    if ( $dateloc ne $lastloc && ! $qry) { # summary of loc and maybe date
      print "\n";
      my $locdrinks = sprintf("%3.1f", $locdsum / $onedrink) ;
      my $daydrinks = sprintf("%3.1f", $daydsum / $onedrink) ;
      # loc summary: if nonzero, and diff from daysummary
      # or there is a new loc coming,
      if ( $locdrinks > 0.1) {
        print "<br/>$lastwday ";
        print "$lastloc2: " . unit($locdrinks,"d"). unit($locmsum, "kr"). "\n";
        if ($averages{$lastdate} && $locdrinks eq $daydrinks && $lastdate ne $effdate) {
          print " (a=" . unit($averages{$lastdate},"d"). " )<br/>\n";
        } # fl avg on loc line, if not going to print a day summary line
        # Restaurant copy button
        print "<form method='POST' style='display: inline;' >\n";
        print "<input type='hidden' name='l' value='$lastloc2' />\n";
        my $rtype = $restaurants{$lastloc2} || "Restaurant, unspecified";
        print "<input type='hidden' name='m' value='$rtype' />\n";
        $rtype =~ s/Restaurant, //;
        print "<input type='hidden' name='b' value='Food and Drink' />\n";
        print "<input type='hidden' name='v' value='' />\n";
        print "<input type='hidden' name='s' value='$rtype' />\n";
        print "<input type='hidden' name='a' value='0' />\n";
        print "<input type='hidden' name='p' value='$locmsum kr' />\n";
        $rtype =~ s/^Restaurant, //;
        print "<input type='submit' name='submit' value='Rest'
                    style='display: inline; font-size: x-small' />\n";
        print "</form>\n";
        print "<br/>\n";
      }
      # day summary
      if ($lastdate ne $effdate ) {
        if ( $locdrinks ne $daydrinks) {
          print " <b>$lastwday</b>: ". unit($daydrinks,"d"). unit($daymsum,"kr");
          if ($averages{$lastdate}) {
            print " (a=" . unit($averages{$lastdate},"d"). " )\n";
          }
          print "<br/>\n";
        }
        $daydsum = 0.0;
        $daymsum = 0;
      }
      $locdsum = 0.0;
      $locmsum = 0;
      $loccnt = 0;
    }
    if ( $lastdate ne $effdate ) { # New date
      print "<hr/>\n" ;
      $lastloc = "";
    }
    if ( $dateloc ne $lastloc ) { # New location and maybe also new date
      print "<br/><b>$wday $date </b>" . filt($loc,"b") . newmark($loc) . loclink($loc);
      print "<br/>\n" ;
    }
    if ( $date ne $effdate ) {
      $time = "($time)";
    }
    if ( !( $mak  =~ /^Restaurant,/i ) ) { # don't count rest lines
      $daydsum += ( $alc * $vol ) if ($alc && $vol) ;
      $daymsum += $pr if ($pr) ;
      $locdsum += ( $alc * $vol ) if ($alc && $vol) ;
      $locmsum += $pr if ($pr) ;
      $loccnt++;
    }
    $anchor = $stamp || "";
    $anchor =~ s/[^0-9]//g;
    print "\n<a id='$anchor'/>\n";
    print "<form method='POST' style='display: inline;' >\n";
    print "<br/>$time &nbsp;" . filt($mak,"i") . newmark($mak) .
            " : " . filt($beer,"b") . newmark($beer, $mak) .
      "<br/>\n";
    print filt("[$sty]") . newmark($sty) . " "   if ($sty);
    print units($pr, $vol, $alc). "<br/>\n";
    if ($rate || $com) {
      print " <b>$rate-$ratings[$rate]</b>" if ($rate);
      print ": " if ($rate && $com);
      print "<i>$com</i>" if ($com);
      print "<br/>\n";
    }
    $ratecounts[$rate] ++ if ($rate);
    # guess sizes for small/large beers
    my %vols;
    $vols{$vol} = 1 if ($vol);
    if ( $mak  =~ /^Restaurant,/i ) {
      $vols{"R"} = 1;
    } elsif ( $mak  =~ /^Wine,/i ) {
      $vols{12} = 1;
      $vols{16} = 1;
      $vols{38} = 1;
      $vols{75} = 1;
    } elsif ( $mak  =~ /^Booze,/i ) {
      $vols{2} = 1;
      $vols{4} = 1;
    } else { # Default to beer, usual sizes in craft beer world
      $vols{25} = 1;
      $vols{40} = 1;
    }
    print "<a href='$url?e=" . uri_escape($stamp) ."' >Edit</a> \n";

    # No price - the script guesses based on size.
    # No location, reuse the current loc
    print "<input type='hidden' name='m' value='$mak' />\n";
    print "<input type='hidden' name='b' value='$beer' />\n";
    print "<input type='hidden' name='v' value='' />\n";
    print "<input type='hidden' name='s' value='$sty' />\n";
    print "<input type='hidden' name='a' value='$alc' />\n";
    print "<input type='hidden' name='l' value='$loc' />\n"
      if ( $copylocation);

    foreach my $volx (sort {no warnings; $a <=> $b || $a cmp $b} keys(%vols) ){
      # The sort order defaults to numerical, but if that fails, takes
      # alphabetical ('R' for restaurant). Note the "no warnings".
      print "<input type='submit' name='submit' value='Copy $volx'
                  style='display: inline; font-size: small' />\n";
    }
    print "</form>\n";
    if ( $qrylim eq "l" ) {
      print "<br/>";
      print glink("$mak $beer", "Google") . "&nbsp;\n";
      print rblink("$mak $beer", "RateBeer") . "&nbsp;\n";
      print utlink("$mak $beer", "Untappd") . "&nbsp;\n";
    }

    print"<br/>\n";
    $lastloc = $dateloc;
    $lastloc2 = $loc;
    $lastdate = $effdate;
    $lastwday = $wday;
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
      print "<br/>";
    }

  print "<hr/>\n" ;
  if ( $maxlines == 0 && $anchor ) {
    print "<br/><a href='$url?maxl=-1&" . $q->query_string() . "#$anchor'>" .
      "More</a><br/>\n";
  } else {
    print "<br/>That was the whole list<br/>\n";
  }
  my $rsum = 0;
  my $rcnt = 0;
  print "<br/>Ratings:<br/>\n";
  for (my $i = 0; $i<11; $i++) {
    $rsum += $ratecounts[$i] * $i;
    $rcnt += $ratecounts[$i];
    print "&nbsp;<b>" . sprintf("%3d",$ratecounts[$i]). "</b> ".
      "times <i>$ratings[$i] ($i)</i> <br/>" if ($ratecounts[$i]);
  }
  if ($rcnt) {
    print "$rcnt ratings avg <b>" . sprintf("%3.1f", $rsum/$rcnt).
      " " . $ratings[$rsum/$rcnt] .
    "</b><br/>\n";
    print "<br/>\n";
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
  $val =~ s/[^a-zA-ZåæøÅÆØöÖäÄ\/ 0-9.,&:\(\)\[\]?-]/_/g;
  return $val;
}

# Helper to make a filter link
sub filt {
  my $f = shift;
  my $tag = shift || "nop";
  my $dsp = shift || $f;
  my $param = $f;
  $param =~ s"[\[\]]""g; # remove the [] around styles etc
  my $link = "<a href='$url?q=".uri_escape($param) ."'
><$tag>$dsp</$tag></a>";

  return $link;
}


# Helper to print "(NEW)" in case we never seen the entry before
sub newmark {
  my $v = shift;
  my $rest = shift || "";
  return "" if ( $rest =~ /^Restaurant/);
  return "" if ($seen{$v} && $seen{$v} != 1);
  return " <i>new</i> ";
}

# Helper to make a link to a list
sub lst {
  my $op = shift; # The kind of list
  my $qry = shift; # Optional query to filter the list
  my $tag = shift || "nop";
  my $dsp = shift || $qry || $op;
  $qry = "&q=" . uri_escape($qry) if $qry;
  $op = uri_escape($op);
  my $link = "<a href='$url?o=$op" . $qry ."' ><$tag>$dsp</$tag></a>";
  return $link;
}

# Helper to make a link to a bar of brewery web page
sub loclink {
  my $loc = shift;
  my $txt = shift || "List";
  my $lnk = "";
  if (defined($links{$loc})) {
    $lnk = " &nbsp; <i><a href='" . $links{$loc} . "' target='_blank' >$txt</a></i>" ;
  }
  return $lnk
}

# Helper to make a google link
sub glink {
  my $qry = shift;
  my $txt = shift || "(Google)";
  return "" unless $qry;
  $qry = uri_escape($qry);
  my $lnk = "&nbsp;<i><a href='https://www.google.com/search?q=$qry'  target='_blank'>" .
      "$txt</a></i>\n";
  return $lnk;
}

# Helper to make a Ratebeer search link
sub rblink {
  my $qry = shift;
  my $txt = shift || "(Ratebeer)";
  return "" unless $qry;
  $qry = uri_escape($qry);
  my $lnk = "<i><a href='https://www.ratebeer.com/search?q=$qry' target='_blank'>" .
      "$txt</a></i>\n";
  return $lnk;
}
# Helper to make a Untappd search link
sub utlink {
  my $qry = shift;
  my $txt = shift || "(Untappd)";
  return "" unless $qry;
  $qry = uri_escape($qry);
  my $lnk = "<i><a href='https://untappd.com/search?q=$qry' target='_blank'>" .
      "$txt</a></i>\n";
  return $lnk;
}

# Helper to sanitize numbers
sub number {
  my $v = shift;
  $v =~ s/,/./g;  # occasionally I type a decimal comma
  $v =~ s/[^0-9.]//g; # Remove all non-numeric chars
  $v=0 unless  $v;
  return $v;
}

# Sanitize prices to whole ints
sub price {
  my $v = shift;
  $v = number($v);
  $v =~ s/[^0-9]//g; # Remove also decimal points etc
  return $v;
}

# Convert prices to DKK if in other currencies
sub curprice {
  my $v = shift;
  #print STDERR "Checking '$v' for currency";
  for my $c (keys(%currency)) {
    if ( $v =~ /^([0-9.]+) *$c/i ) {
      #print STDERR "Found currency $c, worth " . $currency{$c};
      my $dkk = int(0.5 + $1 * $currency{$c});
      #print STDERR "That makes $dkk";
      return $dkk;
    }
  }
  return "";
}

# helper to make a unit displayed in smaller font
sub unit {
  my $v = shift;
  my $u = shift || "XXX";  # Indicate missing units so I see something is wrong
  return "" unless $v;
  return "$v<span style='font-size: xx-small'>$u</span> ";
}


# helper to display the units string
# price, alc, vol, drinks
sub units {
  my $pr = shift;
  my $vol = shift;
  my $alc = shift;
  my $s = unit($pr,"kr") .
    unit($vol, "cl").
    unit($alc,'%');
  if ( $alc && $vol ) {
    my $dr = sprintf("%1.2f", ($alc * $vol) / $onedrink );
    $s .= unit($dr, "d");
  }
  return $s;
}


# Helper to make an error message
sub error {
  my $msg = shift;
  print $q->header("Content-type: text/plain");
  print "ERROR\n";
  print $msg;
  exit();
}

# Helper to get a date string, with optional delta (in days)
sub datestr {
  my $form = shift || "%F %T";  # "YYYY-MM-DD hh:mm:ss"
  my $delta = shift || 0;   # in days, may be fractional. Negative for ealier
  my $dstr = strftime ($form, localtime(time() + $delta *60*60*24));
  return $dstr;
}
