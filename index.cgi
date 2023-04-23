#!/usr/bin/perl -w

# Heikki's simple beer tracker
#
# Keeps beer drinking history in a flat text file.
#
# This is a simple CGI script
# See https://github.com/heikkilevanto/beertracker/
#



###################
# Modules and UTF-8 stuff
use POSIX qw(strftime localtime locale_h);
use JSON;
use feature 'unicode_strings';
use utf8;  # Source code and string literals are utf-8
use locale; # The data file can contain locale overrides
setlocale(LC_COLLATE, "da_DK.utf8"); # but dk is the default
setlocale(LC_CTYPE, "da_DK.utf8");
use open ':encoding(UTF-8)';  # Data files are in utf-8
binmode STDOUT, ":utf8"; # Stdout only. Not STDIN, the CGI module handles that

use URI::Escape;
use CGI qw( -utf8 );
my $q = CGI->new;
$q->charset( "UTF-8" );

####################
# Constants and setup
my $mobile = ( $ENV{'HTTP_USER_AGENT'} =~ /Android/ );

# Constants
my $onedrink = 33 * 4.6 ; # A regular danish beer, 33 cl at 4.6%
my $datadir = "./beerdata/";
my $scriptdir = "./scripts/";  # screen scraping scripts
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
if ( ! -w $datafile ) {
  error ("Bad username: $datafile not writable\n");
}
my @ratings = ( "Undrinkable", "Bad", "Unpleasant", "Could be better",
"Ok", "Goes down well", "Nice", "Pretty good", "Excellent", "Perfect",
"I'm in love" );

# Links to beer lists at the most common locations and breweries
my %links;
$links{"Ølbaren"} = "http://oelbaren.dk/oel/";
$links{"Ølsnedkeren"} = "https://www.olsnedkeren.dk/";
$links{"Fermentoren"} = "http://fermentoren.com/index";
$links{"Dry and Bitter"} = "https://www.dryandbitter.com/collections/beer/";
   # Used to be http://www.dryandbitter.com/products.php, changed in Dec-2020
#$links{"Dudes"} = "http://www.dudes.bar"; # R.I.P Dec 2018
$links{"Taphouse"} = "http://www.taphouse.dk/";
$links{"Slowburn"} = "https://slowburn.coop/";
$links{"Brewpub"} = "https://brewpub.dk/vores-l";
$links{"Penyllan"} = "https://penyllan.com/";

# Beerlist scraping scrips
my %scrapers;
$scrapers{"Ølbaren"} = "oelbaren.pl";
$scrapers{"Taphouse"} = "taphouse.pl";
$scrapers{"Fermentoren"} = "fermentoren.pl";
$scrapers{"Ølsnedkeren"} = "oelsnedkeren.pl";

# Short names for the most commong watering holes
my %shortnames;
$shortnames{"Home"} = "H";
$shortnames{"Fermentoren"} = "F";
$shortnames{"Ølbaren"} = "Øb";
$shortnames{"Ølsnedkeren"} = "Øls";
$shortnames{"Hooked, Vesterbro"} = "Hooked Vbro";
$shortnames{"Hooked, Nørrebro"} = "Hooked Nbro";
$shortnames{"Dennis Place"} = "Dennis";

# currency conversions
my %currency;
$currency{"eur"} = 7.5;
$currency{"e"} = 7.5;
$currency{"usd"} = 6.3;  # Varies bit over time
#$currency{"\$"} = 6.3;  # € and $ don't work, get filtered away in param

###################
# Input Parameters - data file fields are the same order
# from when POSTing a new beer entry
my $stamp = param("st");
my $origstamp = $stamp; # Remember if we had a stamp from the input, indicating editing
my $wday = param("wd");  # weekday
my $effdate = param("ed");  # effective date. Drinks after midnight count as night before
my $loc = param("l");  # location
my $locparam = $loc; # Actual parameter, without being clever
my $mak = param("m");  # brewery (maker) (or "wine, red", or "restaurant, thai"
my $beer= param("b");  # beer
my $vol = param("v");  # volume, in cl
my $sty = param("s");  # style
my $alc = param("a");  # alc, in %vol, up to 1 decimal
my $pr  = param("p");  # price, DKK
my $rate= param("r");  # rating, 0=worst, 10=best
my $com = param("c");  # Comments
my $geo = param("g");  # Geolocation f ex "[55.6531712/12.5042688]"
  # The rest are not in the data file
my $date = param("d"); # Date, if entered. Overrides stamp and effdate.
my $time = param("t"); # Time, if entered.
my $del = param("x");  # delete/update last entry
my $qry = param("q");  # filter query, greps the list
my $qrylim = param("f"); # query limit, "c" or "r" for comments or ratings, "l" for extra links
my $yrlim = param("y"); # Filter by year
my $op  = param("o");  # operation, to list breweries, locations, etc
my $edit= param("e");  # Record to edit
my $maxlines = param("maxl") || "$yrlim$yrlim" || "25";  # negative = unlimited
   # Defaults to 25, unless we have a year limit, in which case defaults to something huge.
my $sortlist = param("sort") || 0; # default to unsorted, chronological lists
my $url = $q->url;

# Default sizes
my $defaultvol = 40;
if ( $mak =~ /^Wine,/i ) {
  $defaultvol = 16;
} elsif ( $mak =~ /Booze,/i ) {
  $defaultvol = 4;
} elsif ( $mak =~ /,/i ) {
  $defaultvol = ""; # for restaurants, time zones, and other strange stuff
}

my %volumes = ( # Comment is displayed on the About page
   'T' => " 2 Taster, sizes vary, always small",
   'G' => "16 Glass of wine - 12 in places, at home 16 is more realistic",
   'S' => "25 Small, usually 25",
   'M' => "33 Medium, typically a bottle beer",
   'L' => "40 Large, 40cl in most places I frequent",
   'C' => "44 A can of 44 cl",
   'W' => "75 Bottle of wine",
   'B' => "75 Bottle of wine",
);

my $half;  # Volumes can be prefixed with 'h' for half measures.
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
if ( $vol =~ /([0-9]+) *oz/i ) {  # Convert (us) fluid ounces
  $vol = $1 * 3;   # Actually, 2.95735 cl, no need to mess with decimals
}

# Both $stamp and $effdate may get rewritten every time we see a tz line in the file
if (!$origstamp) { # but $origstamp stays, telling us we can overwrite $stamp
  $stamp = datestr( "%F %T", 0,1 ); # no offset, actual time
}
if ( ! $effdate ) { # Effective date can be the day before
  $effdate = datestr( "%a; %F", -0.3, 1); # effdate changes at 08
} else {
  $effdate = "$wday; $effdate";
}

#######################
# Dump of the data file
# Needs to be done before the HTML head, since we output text/plain

if ( $op eq "Datafile" ) {
  print $q->header(
    -type => "text/plain;charset=UTF-8",
    -Cache_Control => "no-cache, no-store, must-revalidate",
    -Pragma => "no-cache",
    -Expires => "0",
    -X_beertracker => "This beertracker is my hobby project. It is open source",
    -X_author => "Heikki Levanto",
    -X_source_repo => "https://github.com/heikkilevanto/beertracker" );
  open F, "<$datafile"
    or error("Could not open $datafile for reading: $!" );

  print "# Dump of beerdata file for '". $q->remote_user() .
    "' as of ". datestr() . "\n";
  my $max = param("maxl");
  my $skip = -1;
  if ($max) {
    print "# Only the last $max lines\n";
    my $len = `wc -l $datafile`;
    chomp($len);
    $len =~ s/[^0-9]//g;
    $skip = $len-$max;
  }
  print "# Date Time; Weekday; Effective-date; Location; Brewery; Beer; Vol; " .
    "Style; Alc; Price; Rating; Comment; GeoCoords\n";
  while (<F>) {
    chomp();
    print "$_ \n" unless ($skip-- >0);
  }
  close(F);
  exit();
}

##############################
# Read the file
# Remembers the last line for defaults, and collects all kind of stats
# to be used later.
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
my %seen; # Count how many times various names seen before
my %ratesum; # sum of ratings for every beer
my %ratecount; # count of ratings for every beer, for averaging
my %restaurants; # maps location name to restaurant types
my $allfirstdate = "";
my $lasttimestamp = "";
my %monthdrinks; # total drinks for each calendar month
my %monthprices; # total money spent. Indexed with "yyyy-mm"
my $weekago = datestr("%F", -7);
my $weeksum = 0;
my $weekmsum = 0;
my %weekdates; # count the dates within last week where we have an entry
my $calmon; # YYYY-MM for montly stats
my $lastmonthday = "";
my $tz = "";
my %daydsums; # Sum of drinks for each date   # TODO Sum these up here (See #142)
my %daymsums; # Sum of prices for each date   # and reuse in graphs, summaries
my %years;  # Keep track which years we have seen, for the "more" links
my $boxno = 1; # Box number, from a comment like (B17:240)
my $boxvol = ""; # Remaining volume in the box
my $boxline = ""; # Values for the 'box' beer ('B' or 'B17');
while (<F>) {
  chomp();
  s/#.*$//;  # remove comments
  next unless $_; # skip empty lines

  my ( $t, $wd, $ed, $l, $m, $b, $v, $s, $a, $p, $r, $c, $g ) = split( / *; */ );
  next unless $wd; # We can get silly comment lines, Bom mark, etc
  push @lines, $_; # collect them all
  if (!$allfirstdate) {
    $allfirstdate=$ed;
    # TODO Clear daydsums and daymsums for every date from $ed to today
  }
  $lasttimestamp = $t;
  if ( /$qry/ ) {
    if ( $ed =~ /^(\d+)/ ) {
      $years{$1}++;
    }
  }
  my $restname = "";
  $m = $m || "";
  $restname = "$1$l" if ( $m  =~ /^(Restaurant,)/i );
  $thisloc = $l if $l;
  $seen{$l}++;
  $seen{$m}++;
  $seen{$b}++;
  $seen{$s}++;
  $seen{$restname}++;
  if ($r && $b) {
    $ratesum{$b} += $r;
    $ratecount{$b}++;
  }
  if ( ! $edit || ($edit eq $t) ) {
    $foundline = $_;
  }
  $lastline = $_;
  $a = number($a);  # Sanitize numbers
  $v = number($v);
  $p = price($p);
  if ( $m  =~ /^tz *, *([^ ]*) *$/i ) { # New time zone (optional spaces)
    $tz = $1;
    if (!$tz || $tz eq "X") {
      $ENV{"TZ"} = "/etc/localtime";  # clear it
    } else {
      foreach $zonedir ( "/usr/share/zoneinfo", "/usr/share/zoneinfo/Europe",
        "/usr/share/zoneinfo/US") {
        my $zonefile = "$zonedir/$tz";
        if ( -f $zonefile ) {
          $ENV{"TZ"} = $zonefile;
          last;
        }
      }
    }
    if ( ! $origstamp ) { # Recalculate $stamp and effdate, unless given as inputs
      $stamp = datestr( "%F %T", 0, 1);
      $effdate = datestr( "%a; %F", -0.3, 1);
    }
    next;
  } # tz
  if ( ( $m  =~ /^Restaurant,/i ) ) {
    $restaurants{$l} = $m; # Remember style
    next; # do not sum restaurant lines, drinks filed separately
  }

  $c = "" unless ($c);
  if ($c =~ /\(B(\d+):\d+\)/ ) {
    my $bn = $1;
    if ($bn > $boxno) {
      $boxno = $bn;
    }
    if ($beer =~ /^B(\d*)$/i) {
      my $curbox = $1 || $bn;
      if ( $curbox eq $bn ) {  # Same (or default) box
        $boxline = $lastline;
        #print STDERR "Found box '$beer' line: '$boxline'\n";
      }
    }
  }
  if ( $thisdate ne "$wd; $ed" ) { # new date
    $lastdatesum = 0.0;
    $lastdatemsum = 0;
    $thisdate = "$wd; $ed";
    $lastwday = $wd;
  }
  $lastdatesum += ( $a * $v ) if ($a && $v && $p>=0); # neg price means whole box
  $lastdatemsum += $1 if ( $p =~ /(\d+)/ );
  if ( $effdate eq "$wd; $ed" ) { # today
      $todaydrinks = sprintf("%3.1f", $lastdatesum / $onedrink ) . " d " ;
      $todaydrinks .= ", $lastdatemsum kr." if $lastdatemsum > 0  ;
  }
  if ( $ed gt $weekago && $p >= 0 ) {
    $weeksum += $a * $v;
    $weekmsum += $p;
    $weekdates{$ed}++;
    #print STDERR "wa=$weekago ed=$ed a=$a v=$v av=" . $a*$v / $onedrink .
    # " p=$p ws=$weeksum =" . $weeksum/$onedrink . " wms=$weekmsum\n";
  }
  if ( $ed =~ /(^\d\d\d\d-\d\d)/ )  { # collect stats for each month
    $calmon = $1;
    $monthdrinks{$calmon} += $a * $v if ( $p >= 0);
    $monthprices{$calmon} += abs($p);
  }
  $lastmonthday = $1 if ( $ed =~ /^\d\d\d\d-\d\d-(\d\d)/ );
}

if ( ! $todaydrinks ) { # not today
  $todaydrinks = "($lastwday: " .
    sprintf("%3.1f", $lastdatesum / $onedrink ) . "d $lastdatemsum kr)" ;
  $copylocation = 1;
  my $today = datestr("%F");
  if ( $calmon && $today =~ /$calmon-(\d\d)/ ) {
    $lastmonthday = $1;
    # TODO - When today is in the next month, it shows prev month up to the last
    # entry date, not to end of the month. I can live with that for now, esp
    # since the entry must be pretty close to the end of the month. Showing
    # zeroes for the current month would be no fun.
  }
}
if ($boxline) {
  $lastline = $boxline;  # Found the line corresponding to a box wine
    ( undef, undef, undef, $loc, $mak, $beer,
      undef, $sty, $alc, undef, undef, undef, undef) =
         split( / *; */, $boxline );   # Copy values over
  $pr=0; # Already paid
  ($defaultvol) = $volumes{'G'} =~ /^(\d+)/;
}

# Remember some values to display in the comment box when no comment to show
$weeksum = sprintf( "%3.1fd (=%3.1f/day)", $weeksum / $onedrink,  $weeksum / $onedrink /7);
$todaydrinks .= "\nWeek: $weeksum $weekmsum kr. " . (7 - scalar( keys(%weekdates) ) ) . "z";
$todaydrinks .= "\n$calmon: " . sprintf("%3.1fd (=%3.1f/d)",
       $monthdrinks{$calmon}/$onedrink, $monthdrinks{$calmon}/$onedrink/$lastmonthday).
  " $monthprices{$calmon} kr."
  if ($calmon);

################################
# POST data into the file
# Try to guess missing values from last entries
if ( $q->request_method eq "POST" ) {
  error("Can not see $datafile") if ( ! -w $datafile ) ;
  my $sub = $q->param("submit") || "";
  # Check for missing values in the input, copy from the most recent beer with
  # the same name.
  if ( !$origstamp) { # New record, process date and time if entered
    #print STDERR "BEFOR D='$date' T='$time' S='$stamp' E='$effdate'\n";
    if ($date =~ /^L$/i ) { # 'L' for last date
      if ( $lastline =~ /(^[0-9-]+) +(\d+):(\d+)/ ) {
        $date = $1;
        if (! $time ){ # Guess a time
          my $hr = $2;
          my $min = $3;
          $min += 5;  # 5 min past the previous looks right
          if ($min > 59 ) {
            $min -= 60;
            $hr++;
            $hr -= 24 if ($hr >= 24);
          }
          $time = sprintf("%02d:%02d", $hr,$min);
        }
      }
    } # date 'L'
    if ( $date =~ /^Y$/i ) { # 'Y' for yesterday
      $date = datestr( "%F", -1, 1);
    }
    $time = "" if ($time !~ /^\d/); # Remove real bad times, default to now
    $time =~ s/^([0-9:]*p?).*/$1/i; # Remove AM markers (but not the p in pm)
    $time =~ s/^(\d\d?)(\d\d)(p?)/$1:$2$3/i; # expand 0130 to 01:30, keeping the p
    if ( $time =~ /^(\d\d?) *(p?)$/i ) { # default to full hrs
      $time = "$1:00$2";
    }
    if ( $time =~ /^(\d+):(\d+)(:\d+)? *(p)/i ) { # Convert 'P' or 'PM' to 24h
      $time = sprintf( "%02d:%02d%s", $1+12, $2, $3);
    }
    if ( $time =~ /^(\d+:\d+)$/i ) { # Convert 'P' or 'PM' to 24h
      $time = "$1:" . datestr("%S", 0,1); # Get seconds from current time
    }   # That keeps timestamps somewhat different, even if adding several entries in the same minute
    # Default to current date and time
    $date = $date || datestr( "%F", 0, 1);
    $time = $time || datestr( "%T", 0, 1);
    $stamp = "$date $time";
    my $effdatestr = `date "+%F;%a" -d "$date $time 8 hours ago"`;
    if ( $effdatestr =~ /([0-9-]+) *;(\w+)/ ) {
      $effdate = $1;
      $stamp .= "; $2";
    }
    #$lasttimestamp =~ s/\d\d$//;  # XXX Trick to make the bug easier to reproduce
    if (  $stamp =~ /^$lasttimestamp/ ) {
      if ( $stamp =~ /^(.*:)(\d\d)(;.*)$/ ) {
        my $sec = $2;
        $sec++;  # increment the seconds, even past 59.
        $stamp = "$1$sec$3";
      }
      print STDERR "Oops, almost inserted a duplicate timestamp '$lasttimestamp'. ".
        "Adjusted it to '$stamp' \n";
    }
    #print STDERR "AFTER D='$date' T='$time' S='$stamp' E='$effdate' L='$lasttimestamp'\n";
  }
  if ( $mak !~ /tz,/i ) {
    $loc = $thisloc unless $loc;  # Always default to the last location, except for tz lines
  }
  if ( $sub =~ /Copy (\d+)/ ) {  # copy different volumes
    $vol = $1 if ( $1 );
  }
  # Try to guess missing values from previous lines
  my $priceguess = "";
  my $i = scalar( @lines )-1;
  while ( $i > 0 && $beer
    && ( !$mak || !$vol || !$sty || !$alc || $pr eq '' || !$boxvol)) {
    ( undef, undef, undef,
      $iloc, $imak, $ibeer, $ivol, $isty, $ialc, $ipr,
      undef, $icom, undef) =
       split( / *; */, $lines[$i] );
    if ( !$priceguess &&    # Guess a price
         uc($iloc) eq uc($loc) &&   # if same location and volume
         $vol eq $ivol ) { # even if different beer, good fallback
      $priceguess = $ipr;
    }
    if ( uc($beer) eq uc($ibeer) ) { # Same beer, copy values over if not set
      $beer = $ibeer; # with proper case letters
      $mak = $imak unless $mak;
      $sty = $isty unless $sty;
      $alc = $ialc unless $alc;
      if ( $vol eq $ivol && $ipr=~/^ *[0-9.]+ *$/) {
        # take price only from same volume, and only if numerical
        $pr  = $ipr if $pr eq "";
      }
      $vol = $ivol unless $vol;
      if ( ! $boxvol && $com !~ /\(B\d+:\d+\)/) {
        if ( $icom =~ /\(B(\d+): *(\d*) *\) *$/i ) {
          $boxno = $1;
          $boxvol = $2;
        }
      }
    }
    $i--;
  }
  $pr = $priceguess if $pr eq "";
  if ( uc($vol) eq "X" ) {  # 'X' is an explicit way to indicate a null value
    $vol = "";
  } else {
    $vol = number($vol);
    if ($vol<=0) {
      $vol = $defaultvol;
    }
  }
  my $curpr = curprice($pr);
  if ($curpr) {
    $com =~ s/ *\[\d+\w+\] *$//i; # Remove old currency price comment "[12eur]"
    $com .= " [$pr]";
    $pr = $curpr;
  } else {
    $pr = price($pr);
  }
  if ($vol < 0 ) { # Neg vol means not consumed (by me).
    $pr = "";
    $alc = "";
  }
  $alc = number($alc);
  if ($mak =~ /tz,/i ) {
    $vol = "";
    $alc = "";
    $pr = "";
  }
  if ($pr < 0 ) {  # Negative price means buying a box
    $boxno++;
    $com =~ s/\(B\d+:\d+\) *$//;
    $com .= " (B$boxno:$vol)";
  }
  if ( $boxvol ) {
    $boxvol -= abs($vol);
    $com =~ s/\(B\d+:\d+\) *$//;
    $com .= " (B$boxno:$boxvol)";
  }
  my $line = "$loc; $mak; $beer; $vol; $sty; $alc; $pr; $rate; $com; $geo";
  if ( $sub eq "Record" || $sub =~ /^Copy/ || $sub =~ /^Rest/ || $sub =~ /\d+ cl/ ) {
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
      my ( $stp, undef) = split( / *; */ );
      if ( $stp ne $edit ) {
        print F $_;
      } else { # found the line
        print F "#" . $_ ;  # comment the original line out
        if ( $sub eq "Save" ) {
          print F "$stamp; $effdate; $line \n";
        }
        $edit = "XXX"; # Do not delete another line, even if same timestamp
      }
    }
    close F
      or error("Error closing $datafile: $!");
    close BF
      or error("Error closing $bakfile: $!");
  }
  # Redirect to the same script, without the POST, so we see the results
  if ($sub =~ /^Rest/i ) {
    my ($recid) =  $stamp =~ /^([0-9-: ]+);/ ;
    print $q->redirect( "$url?e=" . uri_escape_utf8($recid) );
    # Get into edit mode for the just-inserted restaurant record
  } else {
    print $q->redirect( "$url?o=$op" );
    # Usually just show the page
  }
  exit();
}

############################
# Get new values from the file we ingested earlier
my ( $laststamp, undef, undef, $lastloc, $lastbeer, undef ) =
    split( / *; */, $lastline );
if ($foundline) {  # can be undef, if a new data file
  ( $stamp, $wday, $effdate, $loc, $mak, $beer, $vol, $sty, $alc, $pr, $rate, $com, $geo) =
      split( / *; */, $foundline );   # do not copy geo
  }
if ( ! $edit ) { # not editing, do not default rates and comments from last beer
  $rate = "";
  $com = "";
  $geo = "";  # Also geolocation
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
print "<!DOCTYPE html>\n";
print "<html><head>\n";
print "<title>Beer</title>\n";
print "<meta http-equiv='Content-Type' content='text/html;charset=UTF-8'>\n";
print "<meta name='viewport' content='width=device-width, initial-scale=1.0'>\n";
# Background color. Normally a dark green (matching the "racing green" at Øb),
# but with experimental versions of the script, a dark blue, to indicate that
# I am not running the real thing.
my $bgcolor = "#003000";
$bgcolor = "#003050" unless ( $ENV{"SCRIPT_NAME"} =~ /index.cgi/ );
# Style sheet - included right in the HTML headers
print "<style rel='stylesheet'>\n";
print '@media screen {';
print "  * { background-color: $bgcolor; color: #FFFFFF; }\n";
print "  * { font-size: small; }\n";
print "}\n";
print '@media screen and (max-width: 700px){';
print "  .only-wide, .only-wide * { display: none !important; }\n";
print "}\n";
print '@media screen and (min-width: 700px){';
print "  .no-wide, .no-wide * { display: none !important; }\n";
print "}\n";
print '@media print{';
print "  * { font-size: xx-small; }\n";
print "  .no-print, .no-print * { display: none !important; }\n";
print "  .no-wide, .no-wide * { display: none !important; }\n";
print "}\n";
print "</style>\n";
print "<link rel='shortcut icon' href='beer.png'/>\n";
print "</head>\n";
print "<body>\n";
print "\n<!-- Read " . scalar(@lines). " lines from $datafile -->\n\n" ;

################
# Default new users to the about page
if ( !@lines && ! $op ) {
  $op = "About";
}

######################
# Javascript trickery. Most of the logic is on the server side, but a few
# things have to be done in the browser.

# If fielfs should clear when clicked on
# Easier to use on my phone. Can be disabled with the Clr checkbox.

my $script = <<'SCRIPTEND';
  var clearonclick = true; // Clear inputs when clicked
SCRIPTEND

$script .= <<'SCRIPTEND';
  function clearinputs() {  // Clear all inputs, used by the 'clear' button
    var inputs = document.getElementsByTagName('input');
    for (var i = 0; i < inputs.length; i++ ) {
      if ( inputs[i].type == "text" )
        inputs[i].value = "";
    }
  };
SCRIPTEND

# A simple two-liner to redirect to a new page from the 'Show' menu when
# that changes
$script .= <<'SCRIPTEND';
  var changeop = function(to) {
    document.location = to;
  }
SCRIPTEND

# Try to get the geolocation. Async function, to wait for the user to give
# permission (for good, we hope)
# Seems not to work on FF. Ok on Chrome, which I still use on my mobile
$script .= <<'SCRIPTEND';
  var geoloc = "";
  console.log("Starting geoloc script");
  function savelocation (myposition) {
    console.log("Reading location from ");
    console.log(myposition);
    geoloc = "[" + myposition.coords.latitude + "/" + myposition.coords.longitude + "]";
    console.log("Got location: " + geoloc );
    //document.write("Got location: " + geoloc + "<br/" );
    if ( ! document.getElementById("editrec") ) {
      //var geo = document.getElementById("geo");
      //if(geo) { geo.value = geoloc; }
      var el = document.getElementsByName("g");
      if (el) {
        for ( i=0; i<el.length; i++) {
          el[i].value=geoloc;
        }
      }
      console.log("Saved the location in " + el.length + " inputs");
    }
  }
  function geoerror(err) {
    console.log("GeoError" );
    console.log(err);
  }
  function getlocation () {
    if (navigator.geolocation) {
        console.log("Getting location");
        navigator.geolocation.getCurrentPosition(savelocation,geoerror);
        console.log("Get location done: " + geoloc);
      } else {
        console.log("No geoloc support");
      }
  }
  getlocation();
SCRIPTEND

print "<script>\n$script</script>\n";


#############################
# Main input form
print "\n<form method='POST' accept-charset='UTF-8' class='no-print' >\n";
print "<table >";
my $clr = "Onclick='if (clearonclick) {value=\"\";}'";
my $c2 = "colspan='2'";
my $c3 = "colspan='3'";
my $c4 = "colspan='4'";
my $c6 = "colspan='6'";
my $sz1n = "size='15'";
my $sz1 = "$sz1n $clr";
my $sz2n = "size='2'";
my $sz2 = "$sz2n $clr";
my $sz3n = "size='8'";
my $sz3 = "$sz3n $clr";
$geo = $geo || "";  # Old lines don't have a geo field
if ( $edit && $foundline ) {
  # Still produces lot of warnings if editing a non-existing record, all values
  # are undefined. Should not happen anyway.
  print "<tr><td $c2><b>Editing record '$edit'</b> ".
      "<input name='e' type='hidden' value='$edit' id='editrec' /></td></tr>\n";
  print "<tr><td><input name='st' value='$stamp' $sz1n placeholder='Stamp' /></td>\n";
  print "<td><input name='wd' value='$wday' $sz2n placeholder='wday' />\n";
  print "<input name='ed' value='$effdate' $sz3n placeholder='Eff' /></td></tr>\n";
} else {
  # fields to enter date and time
  print "<tr><td><input name='d' value='' $sz1n placeholder='" . datestr ("%F") . "' /></td>\n";
  print "<td><input name='t' value='' $sz3n placeholder='" .  datestr ("%H:%M",0,1) . "' /></td></tr>\n";
}
# Geolocation
print "<tr><td $c2><input name='g' value='$geo' placeholder='geo' size='30' $clr id='geo'/></td></tr>\n";

print "<tr><td><input name='l' value='$loc' placeholder='Location' $sz1 id='loc' /></td>\n";
print "<td><input name='s' value='$sty' $sz1
placeholder='Style'/></td></tr>\n";
print "<tr><td>
  <input name='m' value='$mak' $sz1 placeholder='Brewery'/></td>\n";
print "<td>
  <input name='b' value='$beer' $sz1 placeholder='Beer'/></td></tr>\n";
print "<tr><td><input name='v' value='$vol cl' $sz2 placeholder='Vol' />\n";
print "<input name='a' value='$alc %' $sz2 placeholder='Alc' />\n";
my $prc = $pr;
$prc =~ s/(-?[0-9]+).*$/$1.-/;
print "<input name='p' value='$prc' $sz2 placeholder='Price' /></td>\n";
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
if ( $edit && $foundline ) {
  print "<tr><td><input type='submit' name='submit' value='Save'/>&nbsp;&nbsp;";
  print "&nbsp;<span align=right>Clr ";
  print "<input type='checkbox' checked=clearonclick onclick='clearonclick=this.checked;'/></span></td>\n";
  print "<td>";
  print "<a href='$url' >cancel</a>";
  print "&nbsp;<input type='submit' name='submit' value='Delete'/></td></tr>\n";
} else {
  print "<tr><td><input type='submit' name='submit' value='Record'/>\n";
  print "&nbsp;<input type='button' value='clear' onclick='getlocation();clearinputs()'/></td>\n";
  print "<td><select name='ops' " .
              "onchange='document.location=\"$url?\"+this.value;' >";
  print "<option value='' >Show</option>\n";
  print "<option value='o=full&q=$qry' >Full List</option>\n";
  print "<option value='o=board&q=$qry' >Beer Board</option>\n";
  print "<option value='o=short&q=$qry' >Short List</option>\n";
  my @ops = ("Graph",
    "Location","Brewery", "Beer",
    "Wine", "Booze", "Restaurant", "Style", "Months", "Years", "Datafile", "About");
  for my $opt ( @ops ) {
    print "<option value='o=$opt&q=$qry'>$opt</option>\n";
  }
  print "</select>\n";
  if ( $op && $op ne "graph" ) {
    print " &nbsp; <a href='$url'>G</a>\n";
  } else {
    print " &nbsp; <a href='$url?o=board'>B</a>\n";
  }
  print "</td></tr>\n";
}
print "</table>\n";
print "</form>\n";

if ( !$op) {
  $op = "Graph";  # Default to showing the graph
} # also on mobile devices

#############
# Beer list for the location. Scraped from their website
if ( $op =~ /board/i ) {
  $locparam = $loc unless ($locparam); # can happen after posting
  print "<hr/>\n"; # Pull-down for choosing the bar
  print "\n<form method='POST' accept-charset='UTF-8' style='display: inline; 'class='no-print' >\n";
  print "Beer list for\n";
  print "<select onchange='document.location=\"$url?o=board&l=\" + this.value;' >\n";
  if (!$scrapers{$locparam}) { #Include the current location, even if no scraper
    $scrapers{$locparam} = ""; #that way, the pulldown looks reasonable
  }
  for my $l ( sort(keys(%scrapers)) ) {
    my $sel = "";
    $sel = "selected" if ( $l eq $locparam);
    print "<option value='$l' $sel>$l</option>\n";
  }
  print "</select>\n";
  print "</form>\n";
  if ($links{$locparam} ) {
    print loclink($locparam,"www"," ");
  }
  print "&nbsp; (<a href='$url?o=$op&l=$locparam&q=PA'>PA</a>) "
    if ($qry ne "IPA" && $scrapers{$locparam});
  print "<p/>\n";
  if (!$scrapers{$locparam}) {
    print "Sorry, no  beer list for $locparam - showing Ølbaren instead<br/>\n";
    $locparam="Ølbaren"; # A good default
  } ;
  {
    my $script = $scriptdir . $scrapers{$locparam};
    my $json = `perl $script`;
    chomp($json);
    if (! $json) {
      print "Sorry, could not get the list from $locparam\n";
      print "<!-- Error running " . $scrapers{$locparam} . ". \n";
      print "Result: '$json'\n -->\n";
    }else {
      #print "<!--\nPage:\n$json\n-->\n";  # for debugging
      my $beerlist = JSON->new->utf8->decode($json);
      if ($qry) {
      print "Filter:<b>$qry</b> " .
        "(<a href='$url?o=$op&l=$locparam'>Clear</a>) " .
        "<p/>\n";
      }
      print "<table>\n";
      foreach $e ( @$beerlist )  {
        # Skip brewery if the name contains same words, etc
        $mak = $e->{"maker"} || "" ;
        $beer = $e->{"beer"} || "" ;
        $sty = $e->{"type"} || "";
        $loc = $locparam;
        $alc = $e->{"alc"} || 0;
        if ( $qry ) {
          my $line = "$mak $beer $sty";
          next unless ( $sty =~ /$qry/i );
        }

        my $disp = $mak;
        $disp =~ s/\b(the|brouwerij|brasserie|van|den)\b//ig; #stop words
        $disp =~ s/ &amp; /&amp;/;  # Special case for Dry & Bitter (' & ' -> '&')
        $disp =~ s/ & /&/;  # Special case for Dry & Bitter (' & ' -> '&')
        $disp =~ s/^ +//;
        $disp =~ s/^([^ ]{1,4}) /$1&nbsp;/; #Combine initial short word "To Øl"
        $disp =~ s/[ -].*$// ; # first word
        if ( $beer =~ /$disp/ || !$mak) {
          $disp = ""; # Same word in the beer, don't repeat
        } else {
          $disp = filt($mak, "i", $disp,"board&l=$locparam") . ": ";
        }
        $disp .= filt($beer, "b", substr($beer,0,44), "board&l=$loc");
        if ( length($disp) + length($sty) < 55 && $disp !~ /$sty/ ) {
          $disp .= " " .$sty;
        }
        print "<tr><td>#" . $e->{"id"} . ":</td>";
        print "<td>$disp</td></tr>\n";
        $mak =~ s/'//g; # Apostrophes break the input form below
        $beer =~ s/'//g; # So just drop them
        $sty =~ s/'//g;
        my $origsty = $sty ;
        $sty =~ s/\b(Beer|Style)\b//i; # Stop words
        $sty =~ s/\W+/ /g;  # non-word chars, typically dashes
        $sty =~ s/\s+/ /g;
        if ( $sty =~ /IPA/i ) {
          $sty =~ s/.*Session.*/SIPA/i;
          $sty =~ s/.*(Black).*/BIPA/i;
          $sty =~ s/.*(Double|Triple).*(New England|NE).*/DNE/i;
          $sty =~ s/.*(Double|Dipa).*/DIPA/i;
          $sty =~ s/.*Wheat.*/WIPA/i;
          $sty =~ s/.*(New England).*/NE/i;
          $sty =~ s/.*(New Zealand|NZ).*/NZ/i;
          $sty =~ s/.*(West Coast|WC).*/WC/i;
        }
        $sty =~ s/India Lager/IL/i;
        $sty =~ s/Pale Lager/PL/i;
        $sty =~ s/^Keller.*/Kel/i;
        $sty =~ s/.*(Pilsner|Pilsener).*/Pils/i;
        $sty =~ s/.*Hefe.*/Hefe/i;
        $sty =~ s/.*Wit.*/Wit/i;
        $sty =~ s/.*Dunkel.*/Dunk/i;
        $sty =~ s/.*Doppelbock.*/Dbock/i;
        $sty =~ s/.*Bock.*/Bock/i;
        $sty =~ s/.*(Smoke|Rauch).*/Smoke/i;
        $sty =~ s/.*(Lambic|Sour) *(\w+).*/$1/i;   # Lambic Fruit - Fruit
        $sty =~ s/.*Berliner.*/Berl/i;
        $sty =~ s/.*(America|US)Pale Ale.*/APA/i;
        $sty =~ s/.*Pale Ale.*/PA/i;
        $sty =~ s/.*(Imperial).*/Imp/i;
        $sty =~ s/.*(Stout).*/Stout/i;
        $sty =~ s/.*(Porter).*/Port/i;
        $sty =~ s/.*Farm.*/Farm/i;
        $sty =~ s/.*Saison.*/Saison/i;
        $sty =~ s/.*(Double|Dubbel).*/Dub/i;
        $sty =~ s/.*(Triple|Tripel|Tripple).*/Trip/i;
        $sty =~ s/.*(Quadruple|Quadrupel).*/Quad/i;
        $sty =~ s/.*(Blond|Brown|Strong).*/$1/i;
        $sty =~ s/.*\b(\d+)\b.*/$1/i; # Abt 12 -> 12 etc
        $sty =~ s/.*Belg.*/Belg/i;
        $sty =~ s/.*Barley.*Wine.*/BW/i;
        $sty =~ s/^ *([^ ]{1,6}).*/$1/; # Only six chars   ### Remove this later
        print STDERR "sty='$origsty' -> '$sty'    '$beer'  '$mak'\n";
        my $country = $e->{'country'} || "";
        print "<tr><td style='font-size: xx-small'>&nbsp;&nbsp;$country</td>" .
          "<td>$sty $alc% &nbsp;";
        my $sizes = $e->{"sizePrice"};
        foreach $sp ( sort( {$a->{"vol"} <=> $b->{"vol"}} @$sizes) ) {
          $vol = $sp->{"vol"};
          $pr = $sp->{"price"};
          print "<form method='POST' accept-charset='UTF-8' style='display: inline;' class='no-print' >\n";
          print "<input type='hidden' name='m' value='$mak' />\n" ;
          print "<input type='hidden' name='b' value='$beer' />\n" ;
          print "<input type='hidden' name='s' value='$origsty' />\n" ;
          print "<input type='hidden' name='a' value='$alc' />\n" ;
          print "<input type='hidden' name='l' value='$loc' />\n" ;
          print "<input type='hidden' name='v' value='$vol' />\n" ;
          print "<input type='hidden' name='p' value='$pr' />\n" ;
          print "<input type='hidden' name='g' value='' />\n" ;  # will be set by the geo func
          print "<input type='hidden' name='o' value='board' />\n" ;  # come back to the board display
          print "<input type='submit' name='submit' value='$vol cl - $pr kr'/> &nbsp;\n";
          print "</form>\n";
        }
        print "</td></tr>\n";
      }
      print "</table>\n";
    }
  }
  $op = "Graph"; # Continue with a graph and a full list after that
  # Keep $qry, so we filter the big list too
} # Board

##############
# Graph

my %averages; # floating average by effdate
if ( $allfirstdate && $op && $op =~ /Graph([BS]?)-?(\d+)?-?(-?\d+)?/i ) { # make a graph (only if data)
  my $defbig = $mobile ? "S" : "B";
  my $bigimg = $1 || $defbig;
  my $startoff = $2 || 30; # days ago
  my $endoff = $3 || -1;  # days ago, -1 defaults to tomorrow
  my $startdate = datestr ("%F", -$startoff );
  my $enddate = datestr( "%F", -$endoff);
  my $havedata = 0;
  #print STDERR "Origin dates to $startoff $startdate - $endoff $enddate  - f= $allfirstdate\n";
  while ( $startdate lt $allfirstdate) { # Normalized limits to where we have data
    $startoff --;
    $startdate = datestr ("%F", -$startoff );
    if ($endoff >= 0 ) {
      $endoff --;
      $enddate = datestr( "%F", -$endoff);
    }
  }
  #print STDERR "Rolled dates to $startoff $startdate - $endoff $enddate  - f= $allfirstdate\n";
  print "\n<!-- " . $op . " $startdate to $enddate -->\n";
  my %sums; # drink sums by (eff) date
  my $futable = ""; # Table to display the 'future' values
  for ( my $i = 0; $i < scalar(@lines); $i++ ) { # calculate sums
    ( $stamp, $wday, $effdate, $loc, $mak, $beer, $vol, $sty, $alc, $pr, $rate, $com, $geo ) =
       split( / *; */, $lines[$i] );
    next if ( $mak =~ /^restaurant/i );
    $pr = 0 unless ( $pr =~/^-?[0-9]+$/i);
    $sums{$effdate} = ($sums{$effdate} || 0 ) + $alc * $vol if ( $alc && $vol && $pr >= 0 );
  }
  my $ndays = $startoff+35; # to get enough material for the running average
  my $date;
  open F, ">$plotfile"
      or error ("Could not open $plotfile for writing");
  my $legend = "# Date  WkDay WkEnd  Sum30  Sum7  Zeromark  Future";
  print F "$legend \n".
    "#Plot $startdate ($startoff) to $enddate ($endoff) \n";
  my $sum30 = 0.0;
  my @month;
  my @week;
  my $wkday;
  my $zerodays = -1;
  my $fut = "NaN";
  my $lastavg = ""; # Last floating average we have seen
  my $lastwk = "";
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
    #print "<!-- $date [" . join(', ', @week). "] = $sumweek " . $sumweek/$cntweek . "-->\n";
    my $daystartsum = ( $sum30 - $tot *(scalar(@month)+1) ) / $sumw; # The avg excluding today
    $sum30 = $sum30 / $sumw;
    $sumweek = $sumweek / $cntweek;
    $averages{$date} = sprintf("%1.2f",$sum30); # Save it for the long list
    my $zero = "";
    if ($tot > 0.4 ) { # one small mild beer still gets a zero mark
      $zerodays = 0;
    } elsif ($zerodays >= 0) { # have seen a real $tot
      $zero = 0.1 + ($zerodays % 7) * 0.35 ; # makes the 7th mark nicely on 2.0d
      $zerodays ++; # Move the subsequent zero markers higher up
    }
    if ( $ndays <=0 ) {
      $zero = "NaN"; # no zero mark for current or next date, it isn't over yet
    }
    if ( $ndays <=0 && $sum30 > 0.1 && $endoff < -13) {
      # Display future numbers in table form, if asking for 2 weeks ahead
      my $weekday = ( "Mon", "Tue", "Wed", "Thu", "<b>Fri</b>", "<b>Sat</b>", "<b>Sun</b>" ) [$wkday-1];
      $futable .= "<tr><td>&nbsp;$weekday&nbsp;</td><td>&nbsp;$date&nbsp;</td>";
      $futable .= "<td align=right>&nbsp;" . sprintf("%3.1f %3.1f",$sum30,$sum30*7) . "</td>";
      $futable .= "<td align=right>&nbsp;" . sprintf("%3.1f %3.1f",$sumweek, $sumweek*7) ."</td>" if ($sumweek > 0.1);
      $futable .= "</tr>\n";
    }
    if ( $ndays >=0 && $endoff<=0) {  # On the last current date, add averages to legend
      $lastavg = sprintf("(%2.1f/d %0.0f/w)", $sum30, $sum30*7) if ($sum30 > 0);
      $lastwk = sprintf("(%2.1f/d %0.0f/w)", $sumweek, $sumweek*7) if ($sumweek > 0);
    }
    if ( $ndays == 0 ){  # Plot the start of the day
      if ( $tot ) {
        $fut= $daystartsum; # with a '+' if some beers today
      } else {
        $zero = $daystartsum; # And with a zero mark, if not
      }
    }
    if ( $ndays == -1 ) { # Break the week avg line to indicate future
                          # (none of the others plot at this time)
      print F "$date NaN NaN  NaN NaN  NaN Nan \n";
    }
    if ( $ndays <0 ) {
      $fut = $sum30;
      $fut = "NaN" if ($fut < 0.1); # Hide (almost)zeroes
      $sum30="NaN"; # No avg for next date, but yes for current
      if (!$sumweek) { # Don't plot zero weeksums
        $sumweek = "NaN";
      }
    }
    my $wkend = 0;
    if ($wkday > 4) {
       $wkend = $tot;
       $tot = 0;
       #if ( $ndays <= 0 || $zerodays > 1) { # fut graph, or zero-mark day
         $wkend = $wkend || -0.2 ; # mark weekend days
       #}
    }
    #print "$ndays: $date / $wkday -  $tot $wkend z: $zero $zerodays m=$sum30 w=$sumweek f=$fut <br/>"; ###
    print F "$date  $tot $wkend   $sum30 $sumweek   $zero  $fut\n"  if ($zerodays >= 0);
    $havedata = 1;
  }
  print F "$legend \n";
  close(F);
  if ($havedata) {
    my $oneday = 24 * 60 * 60 ; # in seconds
    my $oneweek = 7 * $oneday ;
    my $onemonth = 365.24 * $oneday / 12;
    my $numberofdays=7;
    my $xformat = "\"%d\\n%b\"";  # 14 Jul
    if ($startoff > 365) {
      $xformat = "\"%d\\n%b\\n%y\"";  # 14 Jul 20
    }
    my $xtic = $oneweek;
    my $pointsize = "";
    if ( $startoff - $endoff > 400 ) {
      $xformat="\"%b\\n%y\"";  # Jul 19
      #$xformat="\"%Y\"";  # 2019
      #$xtic = $oneday * 365.24 ;
      if ( $startoff - $endoff > 1200 ) {
        $xtic = $onemonth * 12;
      } else {
        $xtic = $onemonth * 3;
      }
      $pointsize = "set pointsize 0.2\n" ;
    } elsif ( $startoff - $endoff > 120 ) {
      $xformat="\"%b\\n%y\"";  # Jul 19
      $xtic = $onemonth;
      $pointsize = "set pointsize 0.5\n" ;
    }
    my $imgsz = "340,240";
    if ($bigimg eq "B") {
      $imgsz = "640,480";
    }
    my $cmd = "" .
        "set term png small size $imgsz \n".
        $pointsize .
        "set out \"$pngfile\" \n".
        "set xdata time \n".
        "set timefmt \"%Y-%m-%d\" \n".
        "set xrange [ \"$startdate\" : \"$enddate\" ] \n".
        "set y2range [ -.5 : ] \n" .
        "set format x $xformat \n" .
        "set link y2 via y/7 inverse y*7\n".  #y2 is drink/day, y is per week
        "set ytics 7\n" .
        "set y2tics 0,1 out format \"%2.0f\"\n" .   # 0,1
        #"set y2tics add (\"\" 3, \"\" 5)\n" . # Add scale lines for 3 and 5,
        #"set my2tics 2 \n".
        "set xtics \"2015-11-01\", $xtic out\n" .  # Happens to be sunday, and first of month
        "set style fill solid \n" .
        "set boxwidth 0.7 relative \n" .
        "set key left top horizontal \n" .
        "set grid xtics y2tics  linewidth 0.1 linecolor 4 \n".
        "plot " .
              # linecolor lc 0=grey 1=red, 2=green, 3=blue 9=purple
              # pointtype pt 0: dot, 1:+ 2:x 3:* 4:square 5:filled 6:o 7:filled 8:
              # note the order of plotting, later ones get on top
              # so we plot weekdays, weekends, avg line, zeroes
          "\"$plotfile\" using 1:3 with boxes lc \"royalblue\" axes x1y2 title \"std drinks/day\"," .  # weekends
          "\"$plotfile\" using 1:2 with boxes lc \"grey60\" axes x1y2 notitle ," .  # weekdays
          "\"$plotfile\" " .
              "using 1:5 with line lc \"gray30\" axes x1y2 title \"wk $lastwk\", " .
          "\"$plotfile\" " .
              "using 1:4 with line lc \"dark-violet\" lw 3 axes x1y2 title \" 30d avg $lastavg\", " .  # avg30
                # smooth csplines
          "\"$plotfile\" " .
              "using 1:7 with points pointtype 1 lc \"dark-blue\" axes x1y2 notitle, " .  # future tail
          "\"$plotfile\" " .
              "using 1:6 with points lc \"#00dd10\" pointtype 11 axes x1y2 notitle \n" .  # zeroes (greenish)
          "";
    open C, ">$cmdfile"
        or error ("Could not open $plotfile for writing");
    print C $cmd;
    close(C);
    system ("gnuplot $cmdfile ");
    print "<hr/>\n";
    if ($bigimg eq "B") {
      print "<a href='$url?o=GraphS-$startoff-$endoff'><img src=\"$pngfile\"/></a><br/>\n";
    } else {
      print "<a href='$url?o=GraphB-$startoff-$endoff'><img src=\"$pngfile\" style=\"max-width: 100%;\" /></a><br/>\n";
    }
  } # havedata
  print "<div class='no-print'>\n";
  my $len = $startoff - $endoff;
  my $es = $startoff + $len;
  my $ee = $endoff + $len;
  print "<a href='$url?o=Graph$bigimg-$es-$ee'>&lt;&lt;</a> &nbsp; \n"; # '<<'
  my $ls = $startoff - $len;
  my $le = $endoff - $len;
  if ($le < 0 ) {
    $ls += $ls;
    $le = 0;
  }
  if ($endoff>0) {
    print "<a href='$url?o=Graph$bigimg-$ls-$le'>&gt;&gt;</a>\n"; # '>>'
  } else { # at today, '>' plots a zero-tail
    my $newend = $endoff;
    if ($newend > -3) {
      $newend = -7;
    } else {
      $newend = $newend - 7;
    }
    print "<a href='$url?o=Graph$bigimg-$startoff-$newend'>&gt;</a>\n"; # '>'
  }
  print " &nbsp; <a href='$url?o=Graph$bigimg'>Month</a>\n";
  print " <a href='$url?o=Graph$bigimg-365'>Year</a> \n";
  if (scalar(@lines)>500) {
    my $all = scalar(@lines); # can't be more days than we have entries
    print " <a href='$url?o=Graph$bigimg-$all'>All</a> \n"; # graph will trunc
  }

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
  print "</div>\n";
  if ( $futable ){
    print "<hr/><table border=1>";
    print "<tr><td colspan=2><b>Projected</b></td>";
    print "<td>Avg</td><td>Week</td></tr>\n";
    print "$futable</table><hr/>\n";
  }


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
  my $filts = splitfilter($qry);
  print "<hr/>Filter: <b>$yrlim $filts</b> (<a href='$url?o=short'>Clear</a>)" .
    "&nbsp;(<a href='$url?q=$qry'>Full</a>)<br/>" if ($qry||$yrlim);
  print searchform(). "<hr/>" if $qry;
  while ( $i > 0 ) {
    $i--;
    next unless ( !$qry || $lines[$i] =~ /\b$qry\b/i || $i == 0 );
    next unless ( !$yrlim || $lines[$i] =~ /^$yrlim/ || $i == 0 );
    ( $stamp, $wday, $effdate, $loc, $mak, $beer,
      $vol, $sty, $alc, $pr, $rate, $com, $geo ) = split( / *; */, $lines[$i] );
    if ( $i == 0 ) {
      $lastdate = "";
      if (!$entry) { # make sure to count the last entry too
        $entry = filt($effdate, "") . " " . $wday ;
        $daysum += ( $alc * $vol ) if ($alc && $vol && $pr && $pr >= 0);
        $daymsum += abs($pr);
        if ( $places !~ /$loc/ ) {
          my $bold = "";
          if ( !defined($locseen{$loc}) ) {
            $bold = "b";
            }
          $places .= " " . filt($loc, $bold, $loc, "short");
          $locseen{$loc} = 1;
        }
      }
    }
    if ( $lastdate ne $effdate ) {
      if ( $entry ) {
        my $daydrinks = sprintf("%3.1f", $daysum / $onedrink) ;
        $entry .= " " . unit($daydrinks,"d") . " " . unit($daymsum,"kr");
        print "$entry";
        print "$places<br/>\n";
        $maxlines--;
        last if ($maxlines == 0); # if negative, will go for ever
      }
      # Check for empty days in between
      if (!$qry) {
        my $ndays = 1;
        my $zerodate;
        do { # TODO - Do this in perl, with datestr()
            # TODO - Make this like the graph, build an array of entries first
            # At the moment this is too slow to use in filtered lists.
          $zerodate = `date +%F -d "$lastdate + $ndays days ago" `;
          $ndays++;  # that seems to work even without $lastdate, takes today!
          if ($yrlim && $zerodate !~ /$yrlim/) {
            $ndays = 0;
            $zerodate = $effdate; # force the loop to end
          }
        } while ( $zerodate gt $effdate );
        $ndays-=3;
        if ( $ndays == 1 ) {
          print "... (1 day) ...<br/>\n";
        } elsif ( $ndays > 1) {
          print "... ($ndays days) ...<br/>\n";
        }
      }
      my $thismonth = substr($effdate,0,7); #yyyy-mm
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
      # Abbreviate some names
      my $full=$loc;
      for my $k ( keys(%shortnames) ) {
        my $s = $shortnames{$k};
        $loc =~ s/$k/$s/i;
      }
      $loc =~ s/ /&nbsp;/gi;   # Prevent names breaking in the middle
      if ( $places !~ /$loc/ ) {
        my $bold = "";
        if ( !defined($locseen{$loc}) ) {
          $bold = "b";
          }
        $places .= " " . filt($full, $bold, $loc, "short");
        $locseen{$loc} = 1;
        }
      $lastloc = $loc;
    }
    $daysum += ( $alc * $vol ) if ($alc && $vol && $pr =~ /^\d+$/) ;
    $daymsum += abs($pr) if ($pr =~ /^\d+$/);
  }

  print "<hr/>\n";
  if ( $maxlines == 0 || $yrlim ) {
    print "More: <br/>\n";
    my  $ysum ;
    if ( scalar(keys(%years)) > 1 ) {
      for $y ( reverse sort(keys(%years)) ) {
        print "<a href='$url?o=short&y=$y&q=".uri_escape_utf8($qry)."'>$y</a> ($years{$y})<br/>\n" ;
        $ysum += $years{$y};
      }
    }
    print "<a href='$url?maxl=-1&" . $q->query_string(). ">" .
      "All</a> ($ysum)<p/>\n";
  } else {
    print "<br/>That was the whole list<p/>\n" unless ($yrlim);
  }
  exit(); # All done


#######################
# Annual summary
} elsif ( $op =~ /Years(d?)/i ) {
  my $sortdr = $1;
  my %sum;
  my %alc;
  my $ysum = 0;
  my $yalc = 0;
  my $thisyear = "";
  my $sofar = "so far";
  my $y;
  if ( $qry ) {
    $sofar = "";
  }
  my $nlines = param("maxl") || 10;
  print "<hr/>\n";
  if ($sortdr) {
    print "Sorting by drinks (<a href='$url?o=Years&q=" . uri_escape_utf8($qry) .
       "' class='no-print'>Sort by money</a>)\n";
  } else {
    print "Sorting by money (<a href='$url?o=YearsD&q=" . uri_escape_utf8($qry) .
       "' class='no-print'>Sort by drinks</a>)\n";
  }
  print "<table border=1>\n";
  my $i = scalar( @lines );
  while ( $i > 0 ) {
    $i--;
    #print "$thisyear $i: $lines[$i]<br/>\n";
    ( $stamp, $wday, $effdate, $loc, $mak, $beer, $vol, $sty, $alc, $pr, $rate, $com, $geo ) =
      split( / *; */, $lines[$i] );
    $y = substr($effdate,0,4);
    #print "  y=$y, ty=$thisyear <br/>\n";
    next if ($mak =~ /restaurant/i );

    if ($i == 0) { # count also the last line
      $thisyear = $y unless ($thisyear);
      $y = "END";
      $pr = number($pr);
      $alc = number($alc);
      $vol = number($vol);
      $sum{$loc} = ( $sum{$loc} || 0 ) + abs($pr);
      $alc{$loc} = ( $alc{$loc} || 0 ) + ( $alc * $vol ) if ($alc && $vol && $pr>=0);
      $ysum += abs($pr) if ($pr);
      $yalc += $alc * $vol if ($alc && $vol && $pr>=0);
      #print "$i: $loc: $mak:  " . $sum{$loc} . " " . $alc{$loc} . "<br/>\n";
    }
    if ( $y ne $thisyear ) {
      if ($thisyear && (!$qry || $thisyear == $qry) ) {
        if ( $thisyear ne datestr("%Y") ) { # We are in the next year already
          $sofar = "";
        }
        my $yrlink = $thisyear;
        if (!$qry) {
          $yrlink = "<a href='$url?o=$op&q=$thisyear&maxl=20'>$thisyear</a>";
        }
        print "<tr><td colspan='3'><br/>Year <b>$yrlink</b> $sofar</td></tr>\n";
        my @kl;
        if ($sortdr) {
          @kl = sort { $alc{$b} <=> $alc{$a} }  keys %alc;
        } else {
          @kl = sort { $sum{$b} <=> $sum{$a} }  keys %sum;
        }
        $k = 0;
        while ( $k < $nlines && $kl[$k] ) {
          my $loc = $kl[$k];
          my $alc = unit(sprintf("%5.0f", $alc{$loc} / $onedrink),"d");
          my $pr = unit(sprintf("%6.0f", $sum{$loc}),"kr");
          print "<tr><td align='right'>$pr&nbsp;</td>\n" .
            "<td align=right>$alc&nbsp;</td>" .
            "<td>&nbsp;". filt($loc)."</td></tr>\n";
          $k++;
        }
        my $alc = unit(sprintf("%5.0f", $yalc / $onedrink),"d");
        my $pr = unit(sprintf("%6.0f", $ysum),"kr");
        print "<tr><td align=right>$pr&nbsp;</td>" .
          "<td align=right>$alc&nbsp;</td>" .
          "<td> &nbsp;  = TOTAL for $thisyear $sofar</td></tr> \n";
        my $daynum = 365;
        if ($sofar) {
          $daynum = datestr("%j"); # day number in year
          my $alcp = unit(sprintf("%5.0f", $yalc / $onedrink / $daynum * 365),"d");
          my $prp = unit(sprintf("%6.0f", $ysum / $daynum * 365),"kr");
          print "<tr><td align=right>$prp&nbsp;</td>".
            "<td align=right>$alcp&nbsp;</td>".
            "<td>&nbsp; = PROJECTED for whole $thisyear</td></tr>\n";
        }
        my $alcday = $yalc / $onedrink / $daynum;
        my $prday = $ysum / $daynum;
        my $alcdayu = unit(sprintf("%5.1f", $alcday),"d");
        my $prdayu = unit(sprintf("%6.0f", $prday),"kr");
        print "<tr><td align=right>$prdayu&nbsp;</td>" .
          "<td align=right>$alcdayu&nbsp;</td>" .
          "<td>&nbsp; = per day</td></tr>\n";
        $alcday = unit(sprintf("%5.1f", $alcday *7),"d");
        $prday = unit(sprintf("%6.0f", $prday *7),"kr");
        print "<tr><td align=right>$prday&nbsp;</td>" .
          "<td align=right>$alcday&nbsp;</td>" .
          "<td>&nbsp; = per week</td></tr>\n";
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
    $sum{$loc} = ( $sum{$loc} || 0.1 / ($i+1) ) + abs($pr) ;  # $i keeps sort order
    $alc{$loc} = ( $alc{$loc} || 0 ) + ( $alc * $vol ) if ($alc && $vol && $pr >= 0);
    $ysum += abs($pr);
    $yalc += $alc * $vol if ($alc && $vol && $pr>=0);
    #print "$i: $effdate $loc: $mak:  $pr:" . $sum{$loc} . "kr  " .$alc * $vol .":" . $alc{$loc} . " <br/>\n" ;
    #if ($loc =~ /Home/i) {
    #  print "$i: $effdate $loc: $mak:  p=$pr: " . $sum{$loc} . "kr  a=" .$alc * $vol .": " . $alc{$loc} . " <br/>\n" ;
    #}
  }
  print "</table>\n";
  print "Show ";
  for $top ( 5, 10, 20, 50, 100, 999999 ) {
    print  "&nbsp; <a href='$url?o=$op&q=" . uri_escape($qry) . "&maxl=$top'>Top-$top</a>\n";
  }
    print  "<hr/>\n";

  exit();

############################+
# Monthly statistics from %monthdrinks and %monthprices
} elsif ( $op =~ /Months([BS])?/ ) {
  my $defbig = $mobile ? "S" : "B";
  my $bigimg = $1 || $defbig;
  $bigimg =~ s/S//i ;
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
    $t .= "<br/><table border=1 >\n";
  $t .="<tr><td>&nbsp;</td>\n";
  my @months = ( "", "Jan", "Feb", "Mar", "Apr", "May", "Jun",
                 "Jul", "Aug", "Sep", "Oct", "Nov", "Dec");
  foreach $y ( reverse($firsty .. $lasty) ) {
    $t .= "<td align='right'><b>&nbsp;$y</b></td>";
  }
  $t .= "<td align='right'><b>&nbsp;Avg</b></td>";
  $t .= "</tr>\n";
  foreach $m ( 1 .. 12 ) {
    $t .= "<tr><td><b>$months[$m]</b></td>\n";
    print F "$months[$m] ";
    my $mdrinks = 0;
    my $mprice = 0;
    my $mcount = 0;
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
          $d = "~" . unit($dd,"/d");
          $ydays[$y] += $dayofmonth - 30;
        } else {
          $dd = sprintf("%3.1f", $d / 30); # scale to dr/day, approx
          $d = unit($dd,"/d");
        }
        $mdrinks += $dd;
        $mcount++;
      }
      my $p = $monthprices{$calm}||"";
      my $dw = $1 if ($d=~/([0-9.]+)/);
      $dw = $dw || 0;
      $dw = unit(int($dw *7 +0.5), "/w");
      $t .= "<td align=right>$d<br/>$dw<br/>$p";
      if ($calm eq $lastym && $monthprices{$calm} ) {
        $p = "";
        $p = int($monthprices{$calm} / $dayofmonth * 30);
        $t .= "<br/>~$p";
      }
      $mprice += $p if ($p);
      $t .= "</td>\n";
      if ($y == $lasty ) { # First column is special for projections
        print F "NaN ";
      }
      if ( !$d ) { # Don't plot after the current month,
        print F "NaN ";  # not known yet
      } else {
        print F "$dd ";
      }
    }
    if ( $mcount) {
      $mdrinks = sprintf("%3.1f", $mdrinks/$mcount);
      $mprice = sprintf("%3.1d", $mprice/$mcount);
      my $dw = $1 if ($mdrinks=~/([0-9.]+)/);
      $dw = unit(int($dw*7+0.5), "/w");
      $t .= "<td align=right>". unit($mdrinks,"/d") .
        "<br/>$dw" .
        "<br/>&nbsp;$mprice</td>\n";
   }
    $t .= "</tr>";
    print F "\n";
  }
  # Projections
  my $curmonth = datestr("%m",0);
  my $cur = $months[$curmonth];
  $curmonth = datestr("%Y-%m",0);
  $d = ($monthdrinks{$curmonth}||0) / $onedrink ;
  my $min = sprintf("%3.1f", $d / 30);  # for whole month
  my $avg = $d / $dayofmonth;
  my $max = 2 * $avg - $min;
  $max = sprintf("%3.1f", $max);
  print F "\n";
  print F "$cur $min\n";
  print F "$cur $max\n";
  close(F);
  $t .= "<tr><td>Avg</td>\n";
  foreach $y ( reverse($firsty .. $lasty) ) {
    my $d = "";
    my $dw = "";
    if ( $ydays[$y] ) { # have data for the year
      $d = sprintf("%3.1f", $ydrinks[$y] / $ydays[$y] / $onedrink) ;
      $dw = $1 if ($d=~/([0-9.]+)/);
      $dw = unit(int($dw*7+0.5), "/w");
      $d = unit($d, "/d");
      my $pr = sprintf("%3d", $yprice[$y]/$ydays[$y]);
    }
    $t .= "<td align=right>$d<br/>$dw</td>";
  }
  $t .= "</tr>";
  $t .= "<tr><td>Sum</td>\n";
  my $grandtot = 0;
  foreach $y ( reverse($firsty .. $lasty) ) {
    my $pr  = "";
    if ( $ydays[$y] ) { # have data for the year
      $pr = unit(sprintf("%5.0f", ($yprice[$y]+500)/1000), "kkr") ;
      $grandtot += $yprice[$y];
    }
    $t .= "<td align=right>$pr</td>";
  }
  $grandtot = unit(sprintf("%5.0f",($grandtot+500)/1000), "kkr");
  $t .= "<td align=right>$grandtot</td>";
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
       "set ytics 1\n".
       "set mytics 2\n".
       "set link y2 via y*7 inverse y/7\n".
       "set y2tics 7\n".
       "set grid xtics ytics\n".
       "set xdata time \n".
       "set timefmt \"%b\" \n".
       "set format x \"%b\"\n" .
       "plot ";
  my $lw = 2;
  my $lc = 1;
  for ( my $i = $lasty - $firsty +3; $i > 2; $i--) {
    $cmd .= "\"$plotfile\" " .
            "using 1:$i with line lc $lc lw $lw notitle," ;
    $lw+= 1;
    $lc++;
  }
  # Finish by plotting low/high projections for current month
  $lc--;
  $cmd .= "\"$plotfile\" " .
            "using 1:2 with points pt 1 lc $lc lw 1 notitle," ;
  $cmd .= "\n";
  open C, ">$cmdfile"
      or error ("Could not open $plotfile for writing");
  print C $cmd;
  close(C);
  system ("gnuplot $cmdfile ");
  if ($bigimg) {
    print "<a href='$url?o=MonthsS'><img src=\"$pngfile\"/></a><br/>\n";
  } else {
    print "<a href='$url?o=MonthsB'><img src=\"$pngfile\"/></a><br/>\n";
  }
  print $t;  # The table we built above
  exit();

#############################
# About page
} elsif ( $op eq "About" ) {

  print "<hr/><h2>Beertracker</h2>\n";
  print "Copyright 2016-2023 Heikki Levanto. <br/>";
  print "Beertracker is my little script to help me remember all the beers I meet.\n";
  print "It is Open Source.\n";
  print "<br/>To get started, look at the " .
    aboutlink("documentation", "https://github.com/heikkilevanto/beertracker/blob/master/manual.md", "nop");
  print "<hr/>";

  print "Some links I may find useful: <ul>";
  print aboutlink("GitHub","https://github.com/heikkilevanto/beertracker");
  print aboutlink("Bugtracker", "https://github.com/heikkilevanto/beertracker/issues");
  print aboutlink("Ratebeer", "https://www.ratebeer.com");
  print aboutlink("Untappd", "https://untappd.com");
  print "</ul><p/>\n";
  print "Some of my favourite bars and breweries<ul>";
  for my $k ( sort keys(%links) ) {
    print aboutlink($k, $links{$k});
  }
  print "</ul><p/>\n";
  print "<hr/>";
  if ($tz) {
    print "Your time zone is: $tz<br>\n";
  } else  {
    print "You have not set your timezone. <br/>\n";
  }
  print "You can set it with a 'brewery' line like 'tz, Copenhagen'<br/>\n";
  print "<hr/>";
  print "Shorthand for drink volumes<br/><ul>\n";
  for my $k ( sort { $volumes{$a} cmp $volumes{$b} } keys(%volumes) ) {
    print "<li><b>$k</b> $volumes{$k}</li>\n";
  }
  print "</ul>\n";
  print "You can prefix them with 'h' for half, as in HW = half wine = 37cl<br/>\n";
  print "Of course you can just enter the number of centiliters <br/>\n";
  print "Or even ounces, when traveling: '6oz' = 18 cl<br/>\n";

  print "<p/>\n";
  print "For a new box wine (or booze bottle, etc), enter the price as negative.<br/>\n";
  print "When using wine for cooking, or for guests, enter a negative volume. That <br/>\n";
  print "gets subtracted from the box without affecting your stats.<br/>\n";

  print "<p/><hr/>\n";
  print "Debug info <br/>\n";
  print "<a href=$url?o=Datafile&maxl=50>Tail of the data file</a><br/>\n";
  exit();

} elsif ( $op eq "full" ) {
  # Ignore for now, we print the full list later.

} elsif ( $op ) {

#######################
# various lists (beer, location, etc)
  print "<hr/><a href='$url'><b>$op</b> list</a>\n";
  print "<div class='no-print'>\n";
  if ( !$sortlist) {
    print "(<a href='$url?o=$op&sort=1' >sort</a>) <br/>\n";
  } else {
    print "(<a href='$url?o=$op'>Recent</a>) <br/>\n";
  }
  my $filts = splitfilter($qry);
  print "Filter: $filts " .
     "(<a href='$url?o=$op'>clear</a>) <br/>" if $qry;
  print "Filter: <a href='$url?y=$yrlim'>$yrlim</a> " .
     "(<a href='$url?o=$op'>clear</a>) <br/>" if $yrlim;
  print searchform();
  print "</div>\n";
  my $i = scalar( @lines );
  my $fld;
  my $line;
  my @displines;
  my %lineseen;
  my $anchor="";
  my $odd = 1;
  print "&nbsp;<br/><table style='background-color: #00600;' >\n";
  # For some reason this sets a color between the cells, not within them.
  # which is ok, makes it easier to see what is what.
  while ( $i > 0 ) {
    $i--;
    next unless ( !$qry || $lines[$i] =~ /\b$qry\b/i );
    next unless ( !$yrlim || $lines[$i] =~ /^$yrlim/ );
    ( $stamp, $wday, $effdate, $loc, $mak, $beer, $vol, $sty, $alc, $pr, $rate,
$com, $geo ) =
       split( / *; */, $lines[$i] );
    next if ( $mak =~ /tz,/ );
    $fld = "";

    if ( $op eq "Location" ) {
      $fld = $loc;
      $line = "<td>" . filt($loc,"b","","full") .
        "<span class='no-print'> ".
        "&nbsp; " . loclink($loc, "Www") . "  " . glink($loc, "G") . "</span>" .
        "</td>" .
        "<td>$wday $effdate ($seen{$loc}) <br class='no-wide'/>" .
        lst("Location",$mak,"i") . ": " . lst($op,$beer) . "</td>";

    } elsif ( $op eq "Brewery" ) {
      next if ( $mak =~ /^wine/i );
      next if ( $mak =~ /^booze/i );
      next if ( $mak =~ /^restaurant/i );
      $fld = $mak;
      $mak =~ s"/"/<br/>"; # Split collab brews on two lines
      $line = "<td>" . filt($mak,"b","","full") . "<br/ class='no-wide'>&nbsp;&nbsp;" . glink($mak) . "</td>" .
      "<td>$wday $effdate " . lst($op,$loc) . " ($seen{$fld}) " .  # $mak before cleaning
            "<br class='no-wide'/> " . lst($op,$sty,"","[$sty]") . "  " . lst("full",$beer,"b")  ."</td>";

    } elsif ( $op eq "Beer" ) {
      next if ( $mak =~ /^wine/i );
      next if ( $mak =~ /^booze/i );
      next if ( $mak =~ /^restaurant/i );
      $fld = $beer;
      $line = "<td>" . filt($beer,"b","","full") . "&nbsp; ($seen{$beer}) &nbsp;" . glink($mak,"G") ."</td>" .
            "<td>$wday $effdate ".
            lst($op,$loc) .  " <br class='no-wide'/> " .
            lst($op,$sty,"","[$sty]"). " " . unit($alc,'%') .
            lst($op,$mak,"i") . "&nbsp;</td>";

    } elsif ( $op eq "Wine" ) {
      next unless ( $mak =~ /^wine, *(.*)$/i );
      $fld = $beer;
      my $stylename = $1;
      $line = "<td>" . filt($beer,"b","","full")  . "&nbsp; $stylename &nbsp;" . glink($beer, "G") . "</td>" .
            "<td>$wday $effdate ".
            lst($op,$loc) . " ($seen{$beer}) " .
            "<br class='no-wide'/> " . lst($op,$sty,"","[$sty]"). "</td>";

    } elsif ( $op eq "Booze" ) {
      next unless ( $mak =~ /^booze, *(.*)$/i );
      $fld = $beer;
      my $stylename = $1;
      $line = "<td>" .filt($beer,"b","","full") . "&nbsp;" . glink($beer, "G") ."</td>" .
            "<td>$wday $effdate ".
            lst($op,$loc) ." ($seen{$beer}) " .
            "<br class='no-wide'/> " . lst($op,$sty,"","[$sty]"). " " . unit($alc,'%') .
              lst($op, $mak,"i", $stylename) . "</td>";

    } elsif ( $op eq "Restaurant" ) {
      next unless ( $mak =~ /^restaurant,? *(.*)$/i );
      my $rstyle="";  # op,qry,tag,dsp
      if ( $1 ) { $rstyle = lst($op, "Restaurant, $1", "", $1); }
      $fld = "$loc";
      my $ratestr = "";
      $ratestr = "$rate: <b>$ratings[$rate]</b>" if $rate;
      my $restname = "Restaurant,$loc";
      my $rpr = "";
      $rpr = "&nbsp; $pr kr" if ($pr && $pr >0) ;
      $line = "<td>" . filt($loc,"b","","full") . "&nbsp; ($seen{$restname}) <br class='no-wide'/> ".
              "$rstyle  &nbsp;" . glink("Restaurant $loc") . "</td>" .
              "<td><i>$beer</i>". " $rpr <br class='no-wide'/> " .
              "$wday $effdate $ratestr</td>";

    } elsif ( $op eq "Style" ) {
      next if ( $mak =~ /^wine/i );
      next if ( $mak =~ /^booze/i );
      next if ( $mak =~ /^restaurant/i );
      next if ( $sty =~ /^misc/i );
      $fld = $sty;
      $line = "<td>" . filt("[$sty]","b","","full") . " ($seen{$sty})" . "</td><td>$wday $effdate " .
            lst("Beer",$loc,"i") .
            " <br class='no-wide'/> " . lst($op,$mak,"i") . ": " . lst("full",$beer,"b") . "</td>";
    } else {
      print "<!-- unknown shortlist '$op' -->\n";
      last;
    }
    next unless $fld;
    $fld = uc($fld);
    next if $lineseen{$fld};
    $lineseen{$fld} = $line;
    #print "<tr>$line</tr>\n";
    push @displines, "$line";
  }
  if ($sortlist) {
    @displines = ();
    for $k ( sort { "\U$a" cmp "\U$b" } keys(%lineseen) ) {
      print "<tr>$lineseen{$k}</tr>\n";
    }
  } else {
    foreach my $dl (@displines) {
      print "<tr>$dl</tr>\n";
    }
  }
  print "</table>\n";
  print "<br/>Total " . scalar(@displines) . " entries <br/>\n" if (scalar(@displines));
  my $rsum = 0;
  my $rcnt = 0;
  print "<hr/>\n" ;
  my  $ysum ;
  if ( scalar(keys(%years)) > 1 ) {
    print "More: <br/>\n";
    for $y ( reverse sort(keys(%years)) ) {
      print "<a href='$url?o=$op&y=$y&q=" . uri_escape($qry) .
         "'>$y</a><br/>\n" ;
      $ysum += $years{$y};
    }
  }
  print "<a href='$url?maxl=-1&" . $q->query_string() . "'>" .
    "All</a> ($ysum)<p/>\n" if($ysum);

  exit();
}
########################
# Regular list, on its own, or after graph
if ( !$op || $op eq "full" ||  $op =~ /Graph(\d*)/ ) {
  my @ratecounts = ( 0,0,0,0,0,0,0,0,0,0,0);
  print "\n<!-- Full list -->\n ";
  my $filts = splitfilter($qry);
  print "<hr/>Filter:<b>$yrlim $filts</b> (<a href='$url'>Clear</a>)" if ($qry || $qrylim || $yrlim);
  print " -".$qrylim if ($qrylim);
  print " &nbsp; \n";
  print "<br/>" . searchform() . "<br/>" . glink($qry) . " " . rblink($qry) . " " . utlink($qry) .
    filt($qry, "", "Short", "short")  ."\n" if ($qry);

  print "<br/>"if ($qry || $qrylim);
  print "<span class='no-print'>\n";
  print "<a href='$url?q=" . uri_escape_utf8($qry) .
      "&f=r' >Ratings</a>\n";
  print "<a href='$url?q=" . uri_escape_utf8($qry) .
      "&f=c' >Comments</a>\n";
  print "<a href='$url?q=" . uri_escape_utf8($qry) .
      "&f=l' >Links</a>\n";
  if ($qrylim) {
    print "<a href='$url?q=" . uri_escape_utf8($qry) . "'>All</a><br/>\n";
    for ( my $i = 0; $i < 11; $i++) {
      print "<a href='$url?q=" . uri_escape_utf8($qry) . "&f=r$i' >$i</a> &nbsp;";
    }
  }
  print "</span>\n";
  my $i = scalar( @lines );
  my $todaydate = datestr("%F");
  if ($averages{$todaydate} && $lines[$i-1] !~ /$todaydate/) {
    # We have an average from the graph for today, but the last entry is not
    # for today, so we have a zero day. Display the average
    print "<hr/>\n";
    print "<b>". datestr("%a %F"). "</b> (a=$averages{$todaydate}) <br/>\n";
  }
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
  $maxlines = $i*10 if ($maxlines <0); # neg means all of them
  while ( $i > 0 ) {  # Usually we exit at end-of-day
    $i--;
    next unless ( !$qry || $lines[$i] =~ /\b$qry\b/i );
    next unless ( !$yrlim || $lines[$i] =~ /^$yrlim/ );
    ( $stamp, $wday, $effdate, $loc, $mak, $beer,
      $vol, $sty, $alc, $pr, $rate, $com, $geo ) = split( / *; */, $lines[$i] );
    next if ( $qrylim eq "c" && (! $com || $com =~ /^ *\(/ ) );
      # Skip also comments like "(4 EUR)"
    if ( $qrylim =~ /^r(\d*)/ ){  # any rating
      my $rlim = $1 || "";
      next if ( !$rlim && !$rate); # l=r: Skip all that don't have a rating
      next if ( $rlim && $rate ne $rlim );  # filter on "r7" or such
      }
    $maxlines--;
    #last if ($maxlines == 0); # if negative, will go for ever

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
        print "<form method='POST' style='display: inline;' class='no-print'>\n";
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
        if ($maxlines <= 0) {
          $maxlines = 0; # signal that there is more data to come
          last;
        }
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
      $daydsum += ( $alc * $vol ) if ($alc && $vol && $pr >= 0) ;
      $daymsum += abs($pr) if ($pr) ;
      $locdsum += ( $alc * $vol ) if ($alc && $vol && $pr >= 0) ;
      $locmsum += abs($pr) if ($pr) ;
      $loccnt++;
    }
    $anchor = $stamp || "";
    $anchor =~ s/[^0-9]//g;
    print "\n<a id='$anchor'/>\n";
    print "<br class='no-print'/>$time " . filt($mak,"i") . newmark($mak) .
            " : " . filt($beer,"b") . newmark($beer, $mak) .
      "<br class='no-wide'/>\n";
    if ( $sty || $pr || $vol || $alc || $rate || $com ) {
      print filt("[$sty]") . newmark($sty) . " "   if ($sty);
      if ($sty || $pr || $alc) {
        print units($pr, $vol, $alc);
        #print "" . ($seen{$b} || ""). " ";
        if ( $ratecount{$beer} ) {
          #print "s=$seen{$beer} rs=$ratesum{$beer} rc=$ratecount{$beer} "; # ###
          #printf (" (%d:%3.1f)", $seen{$beer},$ratesum{$beer}/$ratecount{$beer});
          # Doesn't look good on the phone
        }
        print "<br/>\n" ;
      }
      if ($rate || $com) {
        print "<span class='only-wide'>&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;</span>\n";
        print " <b>'$rate'-$ratings[$rate]</b>" if ($rate);
        print ": " if ($rate && $com);
        print "<i>$com</i>" if ($com);
        print "<br/>\n";
      }
      $ratecounts[$rate] ++ if ($rate);
    }

    my %vols;     # guess sizes for small/large beers
    $vols{$vol} = 1 if ($vol);
    if ( $mak  =~ /^Restaurant,/i ) {
      $vols{"R"} = 1;
    } elsif ( $mak  =~ /^tz,/i ) {
      %vols=();
    } elsif ( $mak  =~ /^Wine,/i ) {
      $vols{12} = 1;
      $vols{16} = 1;
      $vols{37} = 1;
      $vols{75} = 1;
    } elsif ( $mak  =~ /^Booze,/i ) {
      $vols{2} = 1;
      $vols{4} = 1;
    } else { # Default to beer, usual sizes in craft beer world
      $vols{25} = 1;
      $vols{40} = 1;
    }
    print "<form method='POST' style='display: inline;' class='no-print' >\n";
    print "<a href='$url?e=" . uri_escape_utf8($stamp) ."' >Edit</a> \n";

    # Copy values
    print "<input type='hidden' name='m' value='$mak' />\n";
    print "<input type='hidden' name='b' value='$beer' />\n";
    print "<input type='hidden' name='v' value='' />\n";
    print "<input type='hidden' name='s' value='$sty' />\n";
    print "<input type='hidden' name='a' value='$alc' />\n";
    print "<input type='hidden' name='l' value='$loc' />\n" if ( $copylocation);
    print "<input type='hidden' name='g' id='geo' value='' />\n";
    if ($pr && $pr <0) { # If it is a box, assume price of zero
      print "<input type='hidden' name='p' value='X' />\n"
    }

    foreach my $volx (sort {no warnings; $a <=> $b || $a cmp $b} keys(%vols) ){
      # The sort order defaults to numerical, but if that fails, takes
      # alphabetical ('R' for restaurant). Note the "no warnings".
      print "<input type='submit' name='submit' value='Copy $volx'
                  style='display: inline; font-size: small' />\n";
    }
    if ( $qrylim eq "l" ) {
      print "<br/>";
      print glink("$mak $beer", "Google") . "&nbsp;\n";
      print rblink("$mak $beer", "RateBeer") . "&nbsp;\n";
      print utlink("$mak $beer", "Untappd") . "&nbsp;\n";
    }
    print"<br/>\n";
    print "</form>\n";
    $lastloc = $dateloc;
    $lastloc2 = $loc;
    $lastdate = $effdate;
    $lastwday = $wday;
  } # line loop

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
  if ( $i > 0 || $yrlim ) {
    print "More: <br/>\n";
    my  $ysum;
    if ( scalar(keys(%years)) > 1 ) {
      for $y ( reverse sort(keys(%years)) ) {
        print "<a href='$url?y=$y&q=" . uri_escape($qry) .
            "'>$y</a> ($years{$y})<br/>\n" ;  # TODO - Skips some ??!!
        $ysum += $years{$y};
      }
    }
    $anchor = "#".$anchor if ($anchor);
    $ysum = $ysum || "";
    print "<a href='$url?maxl=-1$anchor' >All</a> ($ysum)<p/>\n";
  } else {
    print "<br/>That was the whole list<p/>\n" unless ($yrlim);
  }
  my $rsum = 0;
  my $rcnt = 0;
  print "<p/>Ratings:<br/>\n";
  for (my $i = 0; $i<11; $i++) {
    $rsum += $ratecounts[$i] * $i;
    $rcnt += $ratecounts[$i];
    print "&nbsp;<b>" . sprintf("%3d",$ratecounts[$i]). "</b> ".
      "times <i>$i: $ratings[$i]</i> <br/>" if ($ratecounts[$i]);
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
  my $val = $q->param($tag) || "";
  $val =~ s/[^a-zA-ZåÅæÆøØÅöÖäÄéÉáÁāĀ\/ 0-9.,&:\(\)\[\]?%-]/_/g;
  $val =~ s/^ +//; # Trim leading spaces
  $val =~ s/ +$//; # and trailing
  return $val;
}

# Helper to make a filter link
sub filt {
  my $f = shift; # filter term
  my $tag = shift || "nop";
  my $dsp = shift || $f;
  my $op = shift || $op || "";
  $op = "o=$op&" if ($op);
  my $param = $f;
  $param =~ s"[\[\]]""g; # remove the [] around styles etc
  my $link = "<a href='$url?$op"."q=".uri_escape_utf8($param) ."'><$tag>$dsp</$tag></a>";
  return $link;
}

# Helper to split the filter string into individual words, each of which is
# a new filter link. Useful with long beer names etc
sub splitfilter {
  my $f = shift || "";  # current filter term
  my $ret = "";
  for my $w ( split ( /\W+/, $f) ) {
    $ret .= "<a href='$url?o=$op&q=".uri_escape_utf8($w)."'>$w</a> ";
  }
  return $ret;
}

# Helper to pring a search form
sub searchform {
  my $r = "" .
    "<form method=GET accept-charset='UTF-8'> " .
    "<input type=hidden name=o value=$op />\n" .
    "<input type=text name=q />  \n " .
    "<input type=submit value='Search'/> \n " .
    "</form> \n" .
    "";
  return $r;

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
  $qry = "&q=" . uri_escape_utf8($qry) if $qry;
  $op = uri_escape_utf8($op);
  my $link = "<a href='$url?o=$op" . $qry ."' ><$tag>$dsp</$tag></a>";
  return $link;
}

# Helper to make a link to a bar of brewery web page and/or scraped beer menu
sub loclink {
  my $loc = shift;
  my $www = shift || "www";
  my $scrape = shift || "List";
  my $lnk = "";
  if (defined($scrapers{$loc}) && $scrape ne " ") {
    $lnk .= " &nbsp; <i><a href='$url?o=board&l=$loc'>$scrape</a></i>" ;
  }
  if (defined($links{$loc}) && $www ne " ") {
    $lnk .= " &nbsp; <i><a href='" . $links{$loc} . "' target='_blank' >$www</a></i>" ;
  }
  return $lnk
}

# Helper to make a link on the about page
# These links should have the URL visible
# They all are inside a bullet list, so we enclose them in li tags
# Unless third argument gives another tag to use
# Displaying only a part of the url on narrow devices
sub aboutlink {
  my $name = shift;
  my $url = shift;
  my $tag = shift || "li";
  my $long = $url;
  $long =~ s/^https?:\/\/(www)?\.?\/?//i;  # remove prefixes
  $long =~ s/\/$//;
  my $short = $1 if ( $long =~ /([^#\/]+)\/?$/ );  # last part of the path
  return "<$tag>$name: <a href='$url' target='_blank' > ".
    "<span class='only-wide'>$long</span>".
    "<span class='no-wide'>$short</span>".
  "</a></$tag>\n";
}

# Helper to make a google link
sub glink {
  my $qry = shift;
  my $txt = shift || "Google";
  return "" unless $qry;
  $qry = uri_escape_utf8($qry);
  my $lnk = "&nbsp;<i>(<a href='https://www.google.com/search?q=" .
    uri_escape($qry) . "' target='_blank' class='no-print'>$txt</a>)</i>\n";
  return $lnk;
}

# Helper to make a Ratebeer search link
sub rblink {
  my $qry = shift;
  my $txt = shift || "Ratebeer";
  return "" unless $qry;
  $qry = uri_escape_utf8($qry);
  my $lnk = "<i>(<a href='https://www.ratebeer.com/search?q=" . uri_escape($qry) .
    "' target='_blank' class='no-print'>$txt</a>)</i>\n";
  return $lnk;
}
# Helper to make a Untappd search link
sub utlink {
  my $qry = shift;
  my $txt = shift || "Untappd";
  return "" unless $qry;
  $qry = uri_escape_utf8($qry);
  my $lnk = "<i>(<a href='https://untappd.com/search?q=" . uri_escape($qry) .
    "' target='_blank' class='no-print'>$txt</a>)</i>\n";
  return $lnk;
}

# Helper to sanitize numbers
sub number {
  my $v = shift || "";
  $v =~ s/,/./g;  # occasionally I type a decimal comma
  $v =~ s/[^0-9.-]//g; # Remove all non-numeric chars
  $v =~ s/-$//; # No trailing '-', as in price 45.-
  $v =~ s/\.$//; # Nor trailing decimal point
  $v = 0 unless $v;
  return $v;
}

# Sanitize prices to whole ints
sub price {
  my $v = shift || "";
  $v = number($v);
  $v =~ s/[^0-9-]//g; # Remove also decimal points etc
  return $v;
}

# Convert prices to DKK if in other currencies
sub curprice {
  my $v = shift;
  #print STDERR "Checking '$v' for currency";
  for my $c (keys(%currency)) {
    if ( $v =~ /^(-?[0-9.]+) *$c/i ) {
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
  if ( $alc && $vol && $pr >= 0) {
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
my $starttime = "";

sub datestr {
  my $form = shift || "%F %T";  # "YYYY-MM-DD hh:mm:ss"
  my $delta = shift || 0;  # in days, may be fractional. Negative for ealier
  my $exact = shift || 0;  # Pass non-zero to use the actual clock, not starttime
  if (!$starttime) {
    $starttime = time();
    my $clockhours = strftime("%H", localtime($starttime));
    $starttime = $starttime - $clockhours*3600 + 12 * 3600;
    # Adjust time to the noon of the same date
    # This is to fix dates jumping when script running close to miodnight,
    # when we switch between DST and normal time. See issue #153
  }
  my $usetime = $starttime;
  if ( $form =~ /%T/ || $exact ) { # If we want the time (when making a timestamp),
    $usetime = time();   # base it on unmodified time
  }
  my $dstr = strftime ($form, localtime($usetime + $delta *60*60*24));
  return $dstr;
}
