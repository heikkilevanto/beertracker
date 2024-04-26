#!/usr/bin/perl -w

# Heikki's beer tracker
#
# Keeps beer drinking history in a flat text file.
#
# This is a simple CGI script
# See https://github.com/heikkilevanto/beertracker/
#



################################################################################
# Modules and UTF-8 stuff
################################################################################

use POSIX qw(strftime localtime locale_h);
use JSON;
use Cwd qw(cwd);
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


################################################################################
# Constants and setup
################################################################################

my $mobile = ( $ENV{'HTTP_USER_AGENT'} =~ /Android|Mobile|Iphone/i );
my $workdir = cwd();
my $devversion = 0;  # Changes a few display details if on the development version
$devversion = 1 unless ( $ENV{"SCRIPT_NAME"} =~ /index.cgi/ );
$devversion = 1 if ( $workdir =~ /-dev/ );

# Background color. Normally a dark green (matching the "racing green" at Øb),
# but with experimental versions of the script, a dark blue, to indicate that
# I am not running the real thing.
my $bgcolor = "#003000";
$bgcolor = "#003050" if ( $devversion );

# Constants
my $onedrink = 33 * 4.6 ; # A regular danish beer, 33 cl at 4.6%
my $datadir = "./beerdata/";
my $scriptdir = "./scripts/";  # screen scraping scripts
my $datafile = "";
my $plotfile = "";
my $cmdfile = "";
my $username = ($q->remote_user()||"");

# Sudo mode, normally commented out
#$username = "dennis" if ( $username eq "heikki" );  # Fake user to see one with less data

if ( ($q->remote_user()||"") =~ /^[a-zA-Z0-9]+$/ ) {
  $datafile = $datadir . $username . ".data";
  $plotfile = $datadir . $username . ".plot";
  $cmdfile = $datadir . $username . ".cmd";
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
$shortnames{"Væskebalancen"} = "VB";

# currency conversions
my %currency;
$currency{"eur"} = 7.5;
$currency{"e"} = 7.5;
$currency{"usd"} = 6.3;  # Varies bit over time
#$currency{"\$"} = 6.3;  # € and $ don't work, get filtered away in param

my $bodyweight;  # in kg, for blood alc calculations
$bodyweight = 120 if ( $username eq "heikki" );
$bodyweight =  83 if ( $username eq "dennis" );


################################################################################
# Input Parameters - data file fields are the same order
# from when POSTing a new beer entry
################################################################################

my $stamp = param("st");
my $origstamp = $stamp; # Remember if we had a stamp from the input, indicating editing
my $wday = param("wd");  # weekday
my $effdate = param("ed");  # effective date. Drinks after midnight count as night before
my $loc = param("l");  # location
$loc =~ s/ *\[.*$//; # Drop the distance from geolocation
my $locparam = $loc; # Actual parameter, without being clever
my $mak = param("m");  # brewery (maker) (or "wine, red", or "restaurant, thai"
my $beer= param("b");  # beer
my $vol = param("v");  # volume, in cl
my $sty = param("s");  # style
my $alc = param("a");  # alc, in %vol, up to 1 decimal
my $pr  = param("p");  # price, DKK
my $rate= param("r");  # rating, 0=worst, 10=best
my $com = param("c");  # Comments
my $geo = param("g");  # Geolocation old: "[55.6531712/12.5042688]" new "55.6531712 12.5042688"
  # The rest are not in the data file
my $date = param("d",1); # Date, if entered. Overrides stamp and effdate. Keep leading space for logic
my $time = param("t",1); # Time, if entered.
my $del = param("x");  # delete/update last entry
my $qry = param("q");  # filter query, greps the list
my $qrylim = param("f"); # query limit, "c" or "r" for comments or ratings, "x" for extra info, "f" for forcing refresh of board
my $yrlim = param("y"); # Filter by year
my $op  = param("o");  # operation, to list breweries, locations, etc
my $edit= param("e");  # Record to edit
my $maxlines = param("maxl") || "$yrlim$yrlim" || "45";  # negative = unlimited
   # Defaults to 25, unless we have a year limit, in which case defaults to something huge.
my $sortlist = param("sort") || 0; # default to unsorted, chronological lists
my $url = $q->url;

# Disable geo
if ($loc =~ /^\./ ) {  # starts with a dot
  $geo = "X";
  $loc =~ s/^\.//; # remove the dot
}

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


################################################################################
# Dump of the data file
# Needs to be done before the HTML head, since we output text/plain
################################################################################

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
} # Dump of data file


################################################################################
# Read the file
# Remembers the last line for defaults, and collects all kind of stats
# to be used later.
################################################################################

open F, "<$datafile"
  or error("Could not open $datafile for reading: $!".
     "<br/>Probably the user hasn't been set up yet" );
my $foundline = "";
my $lastline = "";
my $thisloc = "";
my $lastdatesum = 0.0;
my $lastdatemsum = 0;
my $lasteffdate = "";
my $todaydrinks = "";  # For a hint in the comment box
my $copylocation = 0;  # should the copy button copy location too
my $thisdate = "";
my $lastwday = "";
my @lines;
my %seen; # Count how many times various names seen before (for NEW marks)
my %lastseen; # Last time I have seen a given beer
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
my %geolocations; # Latest known geoloc for each location name
$geolocations{"Home "} =   "[55.6588/12.0825]";  # Special case for FF.
$geolocations{"Home  "} =  "[55.6531712/12.5042688]";  # Chrome
$geolocations{"Home   "} = "[55.6717389/12.5563058]";  # Chrome on my phone
  # My desktop machine gets the coordinates wrong. FF says Somewhere in Roskilde
  # Fjord, Chrome says in Valby...
  # Note also the trailing space(s), to distinguish from the ordinary 'Home'
  # That gets filtered away before saving.
  # (This could be saved in each users config, if we had such)
my $alcinbody = 0; # Grams of alc inside my body
my $balctime = 0; # Time of the last drink
my %bloodalc; # max blood alc for each day, and current bloodalc for each line
my %drinktypes; # What types for any given date. alc, vol, and type. ;-separated
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
  my $restname = ""; # Restaurants are like "Restaurant, Thai"
  $m = $m || "";
  $restname = "$1$l" if ( $m  =~ /^(Restaurant,)/i );
  $thisloc = $l if $l;
  $seen{$l}++;
  $seen{$restname}++;
  if ( ( $b !~ /misc|mixed|pilsner/i ) &&
       ( $m !~ /misc|mixed/i ) &&
       ( $s !~ /misc|mixed/i ) ) {
    $seen{$m}++;
    $seen{$b}++;
    $lastseen{$b} = $ed;
    $seen{$s}++;
  }
  if ($r && $b) {
    $ratesum{$b} += $r;
    $ratecount{$b}++;
  }
  if ( ! $edit || ($edit eq $t) ) {
    $foundline = $_; # Remember the last line, or the one we have edited
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
  if ($l && $g ) {
    (undef, undef, $g) = geo($g);
    $geolocations{$l} = $g if ($g); # Save the last seen location
    # TODO: Later we may start taking averages, or collect a few data points for each
  } # Let's see how precise it seems to be
  $c = "" unless ($c);
  if ( $thisdate ne "$wd; $ed" ) { # new date
    $lastdatesum = 0.0;
    $lastdatemsum = 0;
    $thisdate = "$wd; $ed";
    $lasteffdate = $ed;
    $lastwday = $wd;
    $alcinbody = 0; # Blood alcohol
    $balctime = 0; # Time of the last drink
  }
  # Blood alcohol
  if ($bodyweight && $a && $v && $p>=0  ) {
    my $burnrate = .12;  # g of alc per kg of weight  (.10 to .15)
    my $drtime = $1 + $2/60 if ( $t =~ / (\d\d):(\d\d)/ );   # time in fractional hours
    if ($drtime < $balctime ) { $drtime += 24; } # past midnight
    my $timediff = $drtime - $balctime;
    $alcinbody -= $bodyweight * $burnrate * $timediff;
    if ($alcinbody < 0) { $alcinbody = 0; }
    $balctime = $drtime;
    $alcinbody += $a * $v / $onedrink * 12 ; # grams of alc in body
    my $ba = $alcinbody / ( $bodyweight * .68 ); # non-fat weight
    if ( $ba > ( $bloodalc{$ed} || 0 ) ) {
      $bloodalc{$ed} = $ba;
    }
    $bloodalc{$t} = $ba;  # indexed by the whole timestamp
    #print STDERR "$t     b:" . sprintf("%8.2f %8.2f",$ba,$bloodalc{$ed}). " \n"  if ($t=~/2023-04-26/) ; # ###
    #print STDERR "$ed '$effdate' : $alcinbody ba= $ba\n" if ( $t =~ /2023-04-2/ );
  }

  $lastdatesum += ( $a * $v ) if ($a && $v);
  $lastdatemsum += $1 if ( $p =~ /(\d+)/ );
  if ( $effdate eq "$wd; $ed" ) { # Today
      $todaydrinks = sprintf("%3.1f", $lastdatesum / $onedrink ) . " d " ;
      $todaydrinks .= " $lastdatemsum kr." if $lastdatemsum > 0  ;
      if ($bloodalc{$ed}) { # Calculate the blood alc at the current time.
        # TODO - Is this necessary?
        $todaydrinks .= sprintf("  %4.2f‰",$bloodalc{$ed}); # max of the day
        # TODO - This replicates the calculations above, move to a helper func
        my $curtime = datestr("%H:%M",0,1);
        my $burnrate = .12;  # g of alc per kg of weight  (.10 to .15)
        my $drtime = $1 + $2/60 if ( $curtime =~ /(\d\d):(\d\d)/ );   # time in fractional hours
        if ($drtime < $balctime ) { $drtime += 24; } # past midnight
        my $timediff = $drtime - $balctime;
        my $curalc = $alcinbody - $bodyweight * $burnrate * $timediff;  # my weight * .12 g/hr burn rate
        if ($curalc < 0) { $curalc = 0; }
        my $ba = $curalc / ( $bodyweight * .68 ); # non-fat weight
        $todaydrinks .= sprintf(" - %0.2f‰",$ba);
           # if ( $bloodalc{$ed} - $ba > 0.01 );
      }
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
  $drinktypes{$ed} .= "$a $v $s $m : $l ;" if ($a > 0 && $v > 0);
} # line loop

if ( ! $todaydrinks ) { # not today
  $todaydrinks = "($lastwday: " .
    sprintf("%3.1f", $lastdatesum / $onedrink ) . "d $lastdatemsum kr ";
  $todaydrinks .=  sprintf("%4.2f‰",($bloodalc{$lasteffdate}))
    if ($lasteffdate && $bloodalc{$lasteffdate});
  $todaydrinks .= ")" ;
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

# Remember some values to display in the comment box when no comment to show
$weeksum = sprintf( "%3.1fd (=%3.1f/day)", $weeksum / $onedrink,  $weeksum / $onedrink /7);
$todaydrinks .= "\nWeek: $weeksum $weekmsum kr. " . (7 - scalar( keys(%weekdates) ) ) . "z";
$todaydrinks .= "\n$calmon: " . sprintf("%3.1fd (=%3.1f/d)",
       $monthdrinks{$calmon}/$onedrink, $monthdrinks{$calmon}/$onedrink/$lastmonthday).
  " $monthprices{$calmon} kr."
  if ($calmon);


################################################################################
# POST data into the file
# Try to guess missing values from last entries
################################################################################

if ( $q->request_method eq "POST" ) {
  error("Can not see $datafile") if ( ! -w $datafile ) ;
  my $sub = $q->param("submit") || "";
  # Check for missing values in the input, copy from the most recent beer with
  # the same name.
  if ( !$origstamp) { # New record, process date and time if entered
    #print STDERR "BEFOR D='$date' T='$time' S='$stamp' E='$effdate'\n";
    if (($date =~ /^\d/ || $time =~ /^\d/ )  # Entering after the fact, possibly at a different location
        && ( $geo =~ /^ / )) {  # And geo is autofilled
      $geo = "";   # Do not remember the suspicious location
    }
    if ( $geo =~ / *\d+/) { # Sanity check, do not accept conflicting locations
      my  ($guess, $dist) = guessloc($geo);
      if ( $loc && $guess  # We have location name, and geo guess
         && $geolocations{$loc} # And we know the geo for the location
         && $loc !~ /$guess/i ) { # And they differ
        print STDERR "Refusing to store '$geo' for '$loc', it is closer to '$guess' \n";
        $geo = "";  # Ignore the suspect geo coords
      }
    } else {
      $geo = "";
    }
    if ( $sub eq "Save" ) {
      $date = trim($date);
      $time = trim($time);
    } else {
      $date = "" if ( $date =~ /^ / );
      $time = "" if ( $time =~ /^ / );
    }
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
          $loc = ""; # Fall back to last values
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
    if ( $time =~ /^(\d+:\d+)$/i ) { # Add seconds if not there
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
    if (  $stamp =~ /^$lasttimestamp/ && $sub eq "Record" ) { # trying to create a duplicate
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
  if ( $sub eq "Save" && $loc =~ /^ /  ) {   # Saving on default values
    $loc = $thisloc; # Ignore that guess, fall back to the latest location # See #301
    $geo = ""; # Drop the geo coords, we don't want to mix $thisloc and random coords
  }
  # Try to guess missing values from previous lines
  my $priceguess = "";
  my $i = scalar( @lines )-1;
  while ( $i > 0 && $beer
    && ( !$mak || !$vol || !$sty || !$alc || $pr eq '' )) {
    ( undef, undef, undef,
      $iloc, $imak, $ibeer, $ivol, $isty, $ialc, $ipr,
      undef, undef, undef) =
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
  if (!$vol || $vol < 0 ) {
    $alc = "";  # Clear alc if no vol
    $vol = "";  # But keep the price for restaurants etc
  }
  $alc = number($alc);
  if ($mak =~ /tz,/i ) {
    $vol = "";
    $alc = "";
    $pr = "";
  }
  (undef, undef, $geo)  = geo($geo);  # Skip bad ones, format right
  my $line = "$loc; $mak; $beer; $vol; $sty; $alc; $pr; $rate; $com; $geo";
  $line = trim($line); # Remove leading spaces from fields
  if ( $sub eq "Record" ) {  # Want to create a new record
    $edit = ""; # so don't edit the current one
  }
  if ( $lasttimestamp gt $stamp && $sub ne "Del" ) {
    $sub = "Save"; # force this to be an updating save, so the record goes into its right place
  }

  if ( $sub ne "Save" && $sub ne "Del" ) { # Regular append
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
      if ( $stamp && $stp =~ /^\d+/ &&  # real line
           $sub eq "Save" && # Not deleting it
           "x$stamp" lt "x$stp") {  # Right Place to insert the line
           # Note the "x" trick, to force pure string comparision
        print F "$stamp; $effdate; $line \n";
        $stamp = ""; # do not write it again
      }
      if ( $stp ne $edit ) {
        print F $_;
      } else { # found the line
        print F "#" . $_ ;  # comment the original line out
        $edit = "XXX"; # Do not delete another line, even if same timestamp
      }
    }
    if ($stamp && $sub eq "Save") {  # have not saved it yet
      print F "$stamp; $effdate; $line \n";  # (happens when editing latest entry)
    }
    close F
      or error("Error closing $datafile: $!");
    close BF
      or error("Error closing $bakfile: $!");
  }

  # Clear the cached files from the data dir
  foreach my $pf ( glob($datadir."*") ) {
    next if ( $pf =~ /\.data$/ );
    if ( $pf =~ /\/$username.*png/ ||   # All png files for this user
         -M $pf > 7 ) {  # And any file older than a week
      unlink ($pf)
        or print STDERR "Could not unlink $pf \n";
      }
  }

  # Redirect to the same script, without the POST, so we see the results
  # But keep $op and $qry (maybe also filters?)
  print $q->redirect( "$url?o=$op&q=$qry" );

  exit();
} # POST data


################################################################################
# Get new values from the file we ingested earlier
################################################################################

my ( $laststamp, undef, undef, $lastloc, $lastbeer, undef ) =
    split( / *; */, $lastline );
if ($foundline) {  # can be undef, if a new data file
  ( $stamp, $wday, $effdate, $loc, $mak, $beer, $vol, $sty, $alc, $pr, $rate, $com, $geo) =
      split( / *; */, $foundline );
  $geo = ""; # do not keep geo
}


################################################################################
# HTML head
################################################################################

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
if ($devversion) {
  print "<title>Beer-DEV</title>\n";
  print "<link rel='shortcut icon' href='beer-dev.png'/>\n";
} else {
  print "<title>Beer</title>\n";
  print "<link rel='shortcut icon' href='beer.png'/>\n";
}
print "<meta http-equiv='Content-Type' content='text/html;charset=UTF-8'>\n";
print "<meta name='viewport' content='width=device-width, initial-scale=1.0'>\n";
# Style sheet - included right in the HTML headers
print "<style rel='stylesheet'>\n";
print '@media screen {';
print "  * { background-color: $bgcolor; color: #FFFFFF; }\n";
print "  * { font-size: small; }\n";
print "  a { color: #666666; }\n";  # Almost invisible grey. Applies only to the
           # underline, if the content is in a span of its own.
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
print "</head>\n";
print "<body>\n";
print "\n<!-- Read " . scalar(@lines). " lines from $datafile -->\n\n" ;


################################################################################
# Default new users to the about page
################################################################################

if ( !@lines && ! $op ) {
  $op = "About";
}


################################################################################
# Javascript trickery. Most of the logic is on the server side, but a few
# things have to be done in the browser.
################################################################################

my $script = "";

# Debug div to see debug output on my phone
$script .= <<'SCRIPTEND';
  function db(msg) {
    var d = document.getElementById("debug");
    if (d) {
      d.hidden = false;
      d.innerHTML += msg + "<br/>";
    }
  }
SCRIPTEND

$script .= <<'SCRIPTEND';
  function clearinputs() {  // Clear all inputs, used by the 'clear' button
    var inputs = document.getElementsByTagName('input');
    for (var i = 0; i < inputs.length; i++ ) {
      if ( inputs[i].type == "text" )
        inputs[i].value = "";
    }
    var r = document.getElementById("r");
    r.value = "";
    var c = document.getElementById("c");
    c.value = "";

  };
SCRIPTEND

# Simple script to show the normally hidden lines for entering date, time,
# and geolocation
$script .= <<'SCRIPTEND';
  function showrows() {
    console.log("Unhiding...");
    var rows = [ "td1", "td2", "td3"];
    for (i=0; i<rows.length; i++) {
      var r = document.getElementById(rows[i]);
      //console.log("Unhiding " + i + ":" + rows[i], r);
      if (r) {
        r.hidden = ! r.hidden;
      }
    }
  }
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
# (Note, on FF I needed to uninstall the geoclue package before I could get
# locations on my desktop machine)

$script .= "var geolocations = [ \n";
for my $k (sort keys(%geolocations) ) {
  my ($lat,$lon, undef) = geo($geolocations{$k});
  if ( $lat && $lon ) {  # defensive coding
    $script .= " { name: '$k', lat: $lat, lon: $lon }, \n";
  }
}
$script .= " ]; \n";

$script .= "var origloc=\" $loc\"; \n";

$script .= <<'SCRIPTEND';
  var geoloc = "";

  function savelocation (myposition) {
    geoloc = " " + myposition.coords.latitude + " " + myposition.coords.longitude;
    var gf = document.getElementById("geo");
    console.log ("Geo field: '" + gf.value + "'" );
    if ( ! gf.value ||  gf.value.match( /^ / )) { // empty, or starts with a space
      var el = document.getElementsByName("g");
      if (el) {
        for ( i=0; i<el.length; i++) {
          el[i].value=geoloc;
        }
      }
      console.log("Saved the location " + geoloc + " in " + el.length + " inputs");
      var loc = document.getElementById("loc");
      var locval = loc.value + " ";
      if ( locval.startsWith(" ")) {
        const R = 6371e3; // earth radius in meters
        var latcorr = Math.cos(myposition.coords.latitude * Math.PI/180);
        var bestdist = 20;  // max acceptable distance
        var bestloc = "";
        for (var i in geolocations) {
          var dlat = (myposition.coords.latitude - geolocations[i].lat) * Math.PI / 180 * latcorr;
          var dlon = (myposition.coords.longitude - geolocations[i].lon) * Math.PI / 180;
          var dist = Math.round(Math.sqrt((dlat * dlat) + (dlon * dlon)) * R);
          if ( dist < bestdist ) {
            bestdist = dist;
            bestloc = geolocations[i].name;
          }
        }
        console.log("Best match: " + bestloc + " at " + bestdist );

        if (bestloc) {
          loc.value = " " + bestloc + " [" + bestdist + "m]";
        } else {
          loc.value = origloc;
        }

      }
    }
  }

  function geoerror(err) {
    console.log("GeoError" );
    console.log(err);
  }

  function getlocation () {
    if (navigator.geolocation) {
        navigator.geolocation.getCurrentPosition(savelocation,geoerror);
      } else {
        console.log("No geoloc support");
      }
  }

  // Get the location in the beginning, when ever window gets focus
  window.addEventListener('focus', getlocation);
  // Do not use document.onload(), or a timer. FF on Android does not like
  // often-repeated location requests, and will disallow location for the page
  // see #272

SCRIPTEND

print "<script>\n$script</script>\n";


################################################################################
# Main input form
################################################################################

if ($devversion) {
  print "\n<b>Dev version!</b><br>\n";
  my @devstat = stat("index.cgi");
  my $devmod = $devstat[9];
  my $devdate = strftime("%F %R", localtime($devmod) );
  print "Script modified '$devdate' <br>\n";
  my @prodstat = stat("../beertracker/index.cgi");
  my $prodmod = $prodstat[9];
  if ( $prodmod - $devmod > 1800) {  # Allow half an hour for last push/pull
    my $proddate = strftime("%F %R", localtime($prodmod) );
    print "Which is older than the prod version <br/>";
    print "Prod modified '$proddate' (git pull?) <br>\n";
    print "d='$devmod' p='$prodmod' <br>\n";
  }
  # Would be nice to get git branch and log tail
  # But git is anal about file/dir ownerships
  print "<hr>\n";
}

print "\n<form method='POST' accept-charset='UTF-8' class='no-print'>\n";
my $clr = "Onfocus='value=value.trim();select();'";
my $c2 = "colspan='2'";
my $c3 = "colspan='3'";
my $c4 = "colspan='4'";
my $c6 = "colspan='8'";
my $sz1n = "size='15'";
my $sz1 = "$sz1n $clr";
my $sz2n = "size='3'";
my $sz2 = "$sz2n $clr";
my $sz3n = "size='8'";
my $sz3 = "$sz3n $clr";
my $hidden = "";
print "<table style='width:100%; max-width:500px' >";
my $editstamp;
if ($edit) {
  print "<tr><td $c2><b>Record '$edit'</b></td></tr>\n";
  $editstamp = $edit;
  ($date,$time) = $edit =~ /^([0-9-]+) ([0-9]+:[0-9]+:[0-9]+)/ ;
  if (!$geo) {
    $geo = "x";  # Prevent autofilling current geo
  }
} else {
  $editstamp = $lasttimestamp;
  ($date,$time) = $lasttimestamp =~ /^([0-9-]+) ([0-9]+:[0-9]+)/ ;
  $geo = " $geo"; # Allow more recent geolocations
  $hidden = "hidden"; # Hide the geo and date fields for normal use
  $loc = " " . $loc; # Mark it as uncertain
}
$date = " $date"; # Detect if editing them´
$time = " $time";
print "<tr><td>\n";
print "<input name='e' type='hidden' value='$editstamp' id='editrec' />\n";
print "<input name='o' type='hidden' value='$op' id='editrec' />\n";
print "<input name='q' type='hidden' value='$qry' id='editrec' />\n";
print "</td></tr>\n";
print "<tr><td id='td1' $hidden ><input name='d' value='$date' $sz1 placeholder='" . datestr ("%F") . "' /></td>\n";
print "<td id='td2' $hidden ><input name='t' value='$time' $sz3 placeholder='" .  datestr ("%H:%M",0,1) . "' /></td></tr>\n";

  # Geolocation
print "<tr><td id='td3' $hidden $c2><input name='g' value='$geo' placeholder='geo' size='30' $clr id='geo'/></td></tr>\n";

print "<tr><td><input name='l' value='$loc' placeholder='Location' $sz1 id='loc' /></td>\n";
print "<td><input name='s' value='$sty' $sz1 placeholder='Style'/></td></tr>\n";
print "<tr><td>
  <input name='m' value='$mak' $sz1 placeholder='Brewery'/></td>\n";
print "<td>
  <input name='b' value='$beer' $sz1 placeholder='Beer'/></td></tr>\n";
print "<tr><td><input name='v' value='$vol cl' $sz2 placeholder='Vol' />\n";
print "<input name='a' value='$alc %' $sz2 placeholder='Alc' />\n";
my $prc = $pr;
$prc =~ s/(-?[0-9]+).*$/$1.-/;
print "<input name='p' value='$prc' $sz2 placeholder='Price' /></td>\n";
print "<td><select name='r' id='r' value='$rate' placeholder='Rating' style='width:4.5em;'>" .
  "<option value=''>Rate</option>\n";
for my $ro (0 .. scalar(@ratings)-1) {
  print "<option value='$ro'" ;
  print " selected='selected'" if ( $ro eq $rate );
  print  ">$ro $ratings[$ro]</option>\n";
}
print "</select>\n";
print  " &nbsp; &nbsp; &nbsp;";
if ( $op && $op !~ /graph/i ) {
  print "<a href='$url'><b>G</b></a>\n";
} else {
  print "<a href='$url?o=board'><b>B</b></a>\n";
}
print "&nbsp; &nbsp; <span onclick='showrows();'  align=right>&nbsp; ^</span>";
print "</td></tr>\n";
print "<tr>";
print " <td $c6><textarea name='c' cols='45' rows='3' id='c'
  placeholder='$todaydrinks'>$com</textarea></td>\n";
print "</tr>\n";
if ( 0 && $edit && $foundline ) {
  print "<tr>\n";
  print "<td><input type='submit' name='submit' value='Save'/>&nbsp;</td>";
  print "<td><a href='$url' ><span>cancel</span></a>";
  print "&nbsp;&nbsp;&nbsp;<input type='submit' name='submit' value='Delete'/></td>";
  print "</tr>\n";
} else {
  print "<tr><td>\n";
  print "<input type='submit' name='submit' value='Record'/>\n";
  print " <input type='submit' name='submit' value='Save'/>\n";
  if ($edit) {
    print " <input type='submit' name='submit' value='Del'/>\n";
    print "</td><td>\n";
    print "<a href='$url' ><span>cancel</span></a>";
  } else {
    print "</td><td>\n";
    print " <input type='button' value='Clr' onclick='getlocation();clearinputs()'/>\n";
  }
  print " <select name='ops' style='width:4.5em;' " .
              "onchange='document.location=\"$url?\"+this.value;' >";
  print "<option value='' >Show</option>\n";
  print "<option value='o=full&q=$qry' >Full List</option>\n";
  print "<option value='o=Graph&q=$qry' >Graph</option>\n";
  print "<option value='o=board&q=$qry' >Beer Board</option>\n";
  print "<option value='o=Months&q=$qry' >Stats</option>\n";
    # All the stats pages link to each other
  print "<option value='o=Beer&q=$qry' >Beers</option>\n";
    # The Beer list has links to locations, wines, and other such lists
  print "<option value='o=About&q=$qry' >About</option>\n";
  print "</select>\n";
  print "</td></tr>\n";
}
print "</table>\n";
print "</form>\n";

print "<div id='debug' hidden ><hr/>Debug<br/></div>\n"; # for javascript debugging
if ( !$op) {
  $op = "Graph";  # Default to showing the graph
}


################################################################################
# Graph
################################################################################

my %averages; # floating average by effdate (used also in the full list below

if ( $allfirstdate && $op && ($op =~ /Graph([BS]?)-?(\d+)?-?(-?\d+)?/i || $op =~ /Board/i)) { # make a graph (only if data)
  my $defbig = $mobile ? "S" : "B";
  my $bigimg = $1 || $defbig;
  my $startoff = $2 || 30; # days ago
  my $endoff = $3 || -1;  # days ago, -1 defaults to tomorrow
  my $startdate = datestr ("%F", -$startoff );
  my $enddate = datestr( "%F", -$endoff);
  my $havedata = 0;

  # Normalize limits to where we have data
  while ( $startdate lt $allfirstdate) {
    $startoff --;
    $startdate = datestr ("%F", -$startoff );
    if ($endoff >= 0 ) {
      $endoff --;
      $enddate = datestr( "%F", -$endoff);
    }
  }
  #print STDERR "Rolled dates to $startoff $startdate - $endoff $enddate  - f= $allfirstdate\n";

  my $pngfile = $plotfile;
  $pngfile =~ s/.plot$/-$startdate-$enddate-$bigimg.png/;

  if (  -r $pngfile ) { # Have a cached file
    print "\n<!-- Cached $op $pngfile -->\n";
  } else { # Have to plot a new one

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
    my $legend = "# Date  Drinks  Sum30  Sum7  Zeromark  Future  Drink Color Drink Color ...";
    print F "$legend \n".
      "# Plot $startdate ($startoff) to $enddate ($endoff) \n";
    my $sum30 = 0.0;
    my @month;
    my @week;
    my $wkday;
    my $zerodays = -1;
    my $fut = "NAN";
    my $lastavg = ""; # Last floating average we have seen
    my $lastwk = "";
    my $weekends; # Code to draw background on weekend days
    my $wkendtag = 2;  # 1 is reserved for global bk
    my $oneday = 24 * 60 * 60 ; # in seconds
    my $threedays = 3 * $oneday;
    my $oneweek = 7 * $oneday ;
    my $oneyear = 365.24 * $oneday;
    my $onemonth = $oneyear / 12;
    my $numberofdays=7;
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
      my $zero = "NAN";
      if ($tot > 0.4 ) { # one small mild beer still gets a zero mark
        $zerodays = 0;
      } elsif ($zerodays >= 0) { # have seen a real $tot
        $zero = 0.1 + ($zerodays % 7) * 0.35 ; # makes the 7th mark nicely on 2.0d
        $zerodays ++; # Move the subsequent zero markers higher up
      }
      if ( $ndays <=0  || # no zero mark for current or next date, it isn't over yet
          $startoff - $endoff > 400 ) {  # nor for graphs that are over a year, can't see them anyway
        $zero = "NaN";
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
        if ($bigimg eq "B") {
          $lastavg = sprintf("(%2.1f/d %0.0f/w)", $sum30, $sum30*7) if ($sum30 > 0);
          $lastwk = sprintf("(%2.1f/d %0.0f/w)", $sumweek, $sumweek*7) if ($sumweek > 0);
        } else {
          $lastavg = sprintf("%2.1f %0.0f", $sum30, $sum30*7) if ($sum30 > 0);
          $lastwk = sprintf("%2.1f %0.0f", $sumweek, $sumweek*7) if ($sumweek > 0);
        }
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
      if ( $wkday == 6 ) {
        $weekends .= "set object $wkendtag rect at \"$date\",50 " .
          "size $threedays,200 behind  fc rgbcolor \"#005000\"  fillstyle solid noborder \n";
        $wkendtag++;
      }
      my $totdrinks = $tot;
      my $drinkline = "";
      my $ndrinks = 0;
      if ( $drinktypes{$date} ) {
        my $lastloc = "";
        foreach my $dt ( reverse(split(';', $drinktypes{$date} ) ) ) {
          my ($alc, $vol, $type, $loc) =  $dt =~ /^([0-9.]+) ([0-9]+) ([^:]*) : (.*)/;
          $lastloc = $loc unless ($lastloc);
          next unless ( $type );
          my $color = beercolor($type,"0x",$date,$dt);
          my $drinks = $alc * $vol / $onedrink;
          if ( $lastloc ne $loc  &&  $startoff - $endoff < 100 ) {
            my $lw = $totdrinks + 0.2; # White line for location change
            $lw += 0.1 unless ($bigimg eq "B");
            $drinkline .= "$lw 0xffffff ";
            $lastloc = $loc;
            $ndrinks++;
          }
          $drinkline .= "$totdrinks $color ";
          $ndrinks ++;
          $totdrinks -= $drinks;
          last if ($totdrinks <= 0 ); #defensive coding, have seen it happen once
        }
      }
      print STDERR "Many ($ndrinks) drink entries on $date \n"
        if ( $ndrinks >= 20 ) ;
      while ( $ndrinks++ < 20 ) {
        $drinkline .= "0 0x0 ";
      }

      #print "$ndays: $date / $wkday -  $tot $wkend z: $zero $zerodays m=$sum30 w=$sumweek f=$fut <br/>"; ###
      if ($zerodays >= 0) {
        print F "$date  $tot $sum30 $sumweek  $zero $fut  $drinkline \n" ;
        $havedata = 1;
      }
    }
    print F "$legend \n";
    close(F);
    if (!$havedata) {
      print "No data for $startdate ($startoff) to $enddate ($endoff) \n";
    } else {
      my $xformat; # = "\"%d\\n%b\"";  # 14 Jul
      my $weekline = "";
      my $plotweekline = "\"$plotfile\" " .
                "using 1:4 with linespoints lc \"#00dd10\" pointtype 7 axes x1y2 title \"wk $lastwk\", " ;
      my $xtic = 1;
      my @xyear = ( $oneyear, "\"%y\"" );   # xtics value and xformat
      my @xquart = ( $oneyear / 4, "\"%b\\n%y\"" );  # Jan 24
      my @xmonth = ( $onemonth, "\"%b\\n%y\"" ); # Jan 24
      my @xweek = ( $oneweek, "\"%d\\n%b\"" ); # 15 Jan
      my $pointsize = "";
      my $fillstyle = "fill solid noborder";  # no gaps between drinks or days
      my $fillstyleborder = "fill solid border linecolor \"#003000\""; # Small gap around each drink
      my $imgsz;
      if ( $bigimg eq "B" ) {  # Big image
        $imgsz = "640,480";
        if ( $startoff - $endoff > 365*4 ) {  # "all"
          ( $xtic, $xformat ) = @xyear;
        } elsif ( $startoff - $endoff > 400 ) { # "2y"
          ( $xtic, $xformat ) = @xquart;
        } elsif ( $startoff - $endoff > 120 ) { # "y", "6m"
          ( $xtic, $xformat ) = @xmonth;
        } else { # 3m, m, 2w
          ( $xtic, $xformat ) = @xweek;
          $weekline = $plotweekline;
          $fillstyle = $fillstyleborder;
        }
      } else { # Small image
        $pointsize = "set pointsize 0.5\n" ;  # Smaller zeroday marks, etc
        $imgsz = "320,250";  # Works on my Fairphone, and Dennis' iPhone
        if ( $startoff - $endoff > 365*4 ) {  # "all"
          ( $xtic, $xformat ) = @xyear;
        } elsif ( $startoff - $endoff > 360 ) { # "2y", "y"
          ( $xtic, $xformat ) = @xquart;
        } elsif ( $startoff - $endoff > 80 ) { # "6m", "3m"
          ( $xtic, $xformat ) = @xmonth;
          $weekline = $plotweekline;
        } else { # "m", "2w"
          ( $xtic, $xformat ) = @xweek;
          $fillstyle = $fillstyleborder;
          $weekline = $plotweekline;
        }
      }
      my $white = "textcolor \"white\" ";
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
          "set border linecolor \"white\" \n" .
          "set ytics 7 $white \n" .
          "set y2tics 0,1 out format \"%2.0f\" $white \n" .   # 0,1
          "set xtics \"2007-01-01\", $xtic out $white \n" .  # Happens to be sunday, and first of year/month
          "set style $fillstyle \n" .
          "set boxwidth 0.7 relative \n" .
          "set key left top horizontal textcolor \"white\" \n" .
          "set grid xtics y2tics  linewidth 0.1 linecolor \"white\" \n".
          "set object 1 rect noclip from screen 0, screen 0 to screen 1, screen 1 " .
            "behind fc \"#003000\" fillstyle solid border \n".  # green bkg
          "set arrow from \"$startdate\", 35 to \"$enddate\", 35 nohead linewidth 0.1 linecolor \"white\" \n" .
          "set arrow from \"$startdate\", 70 to \"$enddate\", 70 nohead linewidth 0.1 linecolor \"white\" \n" .
          "set arrow from \"$startdate\", 105 to \"$enddate\", 105 nohead linewidth 0.1 linecolor \"white\" \n" .
          "set arrow from \"$startdate\", 140 to \"$enddate\", 140 nohead linewidth 0.1 linecolor \"white\" \n" .
          $weekends .
          "plot " .
                # note the order of plotting, later ones get on top
                # so we plot weekdays, avg line, zeroes

            "\"$plotfile\" using 1:7:8 with boxes lc rgbcolor variable axes x1y2 notitle, " .
            "\"$plotfile\" using 1:9:10 with boxes lc rgbcolor variable axes x1y2 notitle, " .
            "\"$plotfile\" using 1:11:12 with boxes lc rgbcolor variable axes x1y2 notitle, " .
            "\"$plotfile\" using 1:13:14 with boxes lc rgbcolor variable axes x1y2 notitle, " .
            "\"$plotfile\" using 1:15:16 with boxes lc rgbcolor variable axes x1y2 notitle, " .
            "\"$plotfile\" using 1:17:18 with boxes lc rgbcolor variable axes x1y2 notitle, " .
            "\"$plotfile\" using 1:19:20 with boxes lc rgbcolor variable axes x1y2 notitle, " .
            "\"$plotfile\" using 1:21:22 with boxes lc rgbcolor variable axes x1y2 notitle, " .
            "\"$plotfile\" using 1:23:24 with boxes lc rgbcolor variable axes x1y2 notitle, " .
            "\"$plotfile\" using 1:25:26 with boxes lc rgbcolor variable axes x1y2 notitle, " .
            "\"$plotfile\" using 1:27:28 with boxes lc rgbcolor variable axes x1y2 notitle, " .
            "\"$plotfile\" using 1:29:30 with boxes lc rgbcolor variable axes x1y2 notitle, " .
            "\"$plotfile\" using 1:31:32 with boxes lc rgbcolor variable axes x1y2 notitle, " .
            "\"$plotfile\" using 1:33:34 with boxes lc rgbcolor variable axes x1y2 notitle, " .
            "\"$plotfile\" using 1:35:36 with boxes lc rgbcolor variable axes x1y2 notitle, " .
            "\"$plotfile\" using 1:37:38 with boxes lc rgbcolor variable axes x1y2 notitle, " .
            "\"$plotfile\" using 1:39:40 with boxes lc rgbcolor variable axes x1y2 notitle, " .
            "\"$plotfile\" using 1:41:42 with boxes lc rgbcolor variable axes x1y2 notitle, " .
            "\"$plotfile\" using 1:43:44 with boxes lc rgbcolor variable axes x1y2 notitle, " .
            "\"$plotfile\" using 1:45:46 with boxes lc rgbcolor variable axes x1y2 notitle, " .

            "$weekline " .
            "\"$plotfile\" " .
                "using 1:3 with line lc \"#FfFfFf\" lw 3 axes x1y2 title \" 30d $lastavg\", " .  # avg30
                  # smooth csplines
            "\"$plotfile\" " .
                "using 1:6 with points pointtype 7 lc \"#E0E0E0\" axes x1y2 notitle, " .  # future tail
            "\"$plotfile\" " .
                "using 1:5 with points lc \"#00dd10\" pointtype 11 axes x1y2 notitle \n" .  # zeroes (greenish)
            "";
      open C, ">$cmdfile"
          or error ("Could not open $plotfile for writing");
      print C $cmd;
      close(C);
      system ("gnuplot $cmdfile ");
    } # havedata
  } # Have to plot

  print "<hr/>\n";
  if ($bigimg eq "B") {
    print "<a href='$url?o=GraphS-$startoff-$endoff'><img src=\"$pngfile\"/></a><br/>\n";
  } else {
    print "<a href='$url?o=GraphB-$startoff-$endoff'><img src=\"$pngfile\" /></a><br/>\n";
  }
  print "<div class='no-print'>\n";
  my $len = $startoff - $endoff;
  my $es = $startoff + $len;
  my $ee = $endoff + $len;
  print "<a href='$url?o=Graph$bigimg-$es-$ee'><span>&lt;&lt;</span></a> &nbsp; \n"; # '<<'
  my $ls = $startoff - $len;
  my $le = $endoff - $len;
  if ($le < 0 ) {
    $ls += $ls;
    $le = 0;
  }
  if ($endoff>0) {
    print "<a href='$url?o=Graph$bigimg-$ls-$le'><span>&gt;&gt;</span></a>\n"; # '>>'
  } else { # at today, '>' plots a zero-tail
    my $newend = $endoff;
    if ($newend > -3) {
      $newend = -7;
    } else {
      $newend = $newend - 7;
    }
    print "<a href='$url?o=Graph$bigimg-$startoff-$newend'><span>&gt;</span></a>\n"; # '>'
  }
  print " &nbsp; <a href='$url?o=Graph$bigimg-14'><span>2w</span></a>\n";
  print " <a href='$url?o=Graph$bigimg'><span>Month</span></a>\n";
  print " <a href='$url?o=Graph$bigimg-90'><span>3m</span></a> \n";
  print " <a href='$url?o=Graph$bigimg-180'><span>6m</span></a> \n";
  print " <a href='$url?o=Graph$bigimg-365'><span>Year</span></a> \n";
  print " <a href='$url?o=Graph$bigimg-730'><span>2y</span></a> \n";
  print " <a href='$url?o=Graph$bigimg-3650'><span>All</span></a> \n";  # The system isn't 10 years old

  my $zs = $startoff + int($len/2);
  my $ze = $endoff - int($len/2);
  if ( $ze < 0 ) {
    $zs -= $ze;
    $ze = 0 ;
  }
  print " &nbsp; <a href='$url?o=Graph$bigimg-$zs-$ze'><span>[ - ]</span></a>\n";
  my $is = $startoff - int($len/4);
  my $ie = $endoff + int($len/4);
  print " &nbsp; <a href='$url?o=Graph$bigimg-$is-$ie'><span>[ + ]</span></a>\n";
  print "<br/>\n";
  print "</div>\n";
  if ( $futable ){
    print "<hr/><table border=1>";
    print "<tr><td colspan=2><b>Projected</b></td>";
    print "<td>Avg</td><td>Week</td></tr>\n";
    print "$futable</table><hr/>\n";
  }



################################################################################
# Beer board (list) for the location.
# Scraped from their website
################################################################################

if ( $op =~ /board(-?\d*)/i ) {
  my $extraboard = $1 || -1;  # show all kind of extra info for this tap
  $locparam = $loc unless ($locparam); # can happen after posting
  $locparam =~ s/^ +//; # Drop the leading space for guessed locations
  print "<hr/>\n"; # Pull-down for choosing the bar
  print "\n<form method='POST' accept-charset='UTF-8' style='display:inline;' class='no-print' >\n";
  print "Beer list \n";
  print "<select onchange='document.location=\"$url?o=board&l=\" + this.value;' style='width:5.5em;'>\n";
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
  print "&nbsp; (<a href='$url?o=$op&l=$locparam&q=PA'><span>PA</span></a>) "
    if ($qry ne "PA" );

  print "<a href=$url?o=board&f=f><i>(Reload)</i></a>\n";
  print "<a href=$url?o=board-2><i>(all)</i></a>\n";

  print "<p>\n";
  if (!$scrapers{$locparam}) {
    print "Sorry, no  beer list for '$locparam' - showing 'Ølbaren' instead<br/>\n";
    $locparam="Ølbaren"; # A good default
  }

  my $script = $scriptdir . $scrapers{$locparam};
  my $cachefile = $datadir . $scrapers{$locparam};
  $cachefile =~ s/\.pl/.cache/;
  my $json = "";
  my $cacheage = (-M $cachefile) * 24 * 60 ; # in minutes
  if ( -f $cachefile && $cacheage < 20 && -s $cachefile > 256 && $qrylim ne "f" ) {
    open CF, $cachefile or error ("Could not open $cachefile for reading");
    while ( <CF> ) {
      $json .= $_ ;
    }
    close CF;
  }
  if ( !$json ){
    $json = `perl $script`;
  }
  if (! $json) {
    print "Sorry, could not get the list from $locparam<br/>\n";
    print "<!-- Error running " . $scrapers{$locparam} . ". \n";
    print "Result: '$json'\n -->\n";
  }else {
    open CF, ">$cachefile" or error( "Could not open $cachefile for writing");
    print CF $json;
    close CF;
    chomp($json);
    #print "<!--\nPage:\n$json\n-->\n";  # for debugging
    my $beerlist = JSON->new->utf8->decode($json);
    my $nbeers = 0;
    if ($qry) {
    print "Filter:<b>$qry</b> " .
      "(<a href='$url?o=$op&l=$locparam'><span>Clear</span></a>) " .
      "<p>\n";
    }
    my $oldbeer = "$mak : $beer";  # Remember current beer for opening
    $oldbeer =~ s/&[a-z]+;//g;  # Drop things like &amp;
    $oldbeer =~ s/[^a-z0-9]//ig; # and all non-ascii characters

    print "<table border=0 style='white-space: nowrap;'>\n";
    my $previd  = 0;
    foreach $e ( @$beerlist )  {
      $nbeers++;
      my $id = $e->{"id"} || 0;
      $mak = $e->{"maker"} || "" ;
      $beer = $e->{"beer"} || "" ;
      $sty = $e->{"type"} || "";
      $loc = $locparam;
      $alc = $e->{"alc"} || "";
      $alc = sprintf("%4.1f",$alc) if ($alc);
      if ( $qry ) {
        next unless ( $sty =~ /$qry/ );
      }

      if ( $id != $previd +1 ) {
        my $missing = $previd +1 ;
        print "<tr><td align=right>$missing</td><td align=right>. . .</td></tr>\n";
      }
      my $thisbeer = "$mak : $beer";  # Remember current beer for opening
      $thisbeer =~ s/&[a-z]+;//g;  # Drop things like &amp;
      $thisbeer =~ s/[^a-z0-9]//gi; # and all non-ascii characters
      if ( $extraboard == -1 && $thisbeer eq $oldbeer ) {
        $extraboard = $id; # Default to expanding the beer currently in the input fields
      }
      my $dispmak = $mak;
      $dispmak =~ s/\b(the|brouwerij|brasserie|van|den|Bräu)\b//ig; #stop words
      $dispmak =~ s/.*(Schneider).*/$1/i;
      $dispmak =~ s/ &amp; /&amp;/;  # Special case for Dry & Bitter (' & ' -> '&')
      $dispmak =~ s/ & /&/;  # Special case for Dry & Bitter (' & ' -> '&')
      $dispmak =~ s/^ +//;
      $dispmak =~ s/^([^ ]{1,4}) /$1&nbsp;/; #Combine initial short word "To Øl"
      $dispmak =~ s/[ -].*$// ; # first word
      if ( $beer =~ /$dispmak/ || !$mak) {
        $dispmak = ""; # Same word in the beer, don't repeat
      } else {
        $dispmak = filt($mak, "i", $dispmak,"board&l=$locparam");
      }
      $beer =~ s/(Warsteiner).*/$1/;  # Shorten some long beer names
      $beer =~ s/.*(Hopfenweisse).*/$1/;
      $beer =~ s/.*(Ungespundet).*/$1/;
      if ( $beer =~ s/Aecht Schlenkerla Rauchbier[ -]*// ) {
        $mak = "Schlenkerla";
        $dispmak = filt($mak, "i", $mak,"board&l=$locparam");
      }
      my $dispbeer .= filt($beer, "b", $beer, "board&l=$loc");

      $mak =~ s/'//g; # Apostrophes break the input form below
      $beer =~ s/'//g; # So just drop them
      $sty =~ s/'//g;
      my $origsty = $sty ;
      $sty = shortbeerstyle($sty);
      print "<!-- sty='$origsty' -> '$sty'\n'$e->{'beer'}' -> '$beer'\n'$e->{'maker'}' -> '$mak' -->\n";
      # Add a comment to show the simplifying process.
      # If there are strange beers, take a 'view source' and look
      my $country = $e->{'country'} || "";
      my $sizes = $e->{"sizePrice"};
      my $hiddenbuttons = "";
        $hiddenbuttons .= "<input type='hidden' name='m' value='$mak' />\n" ;
        $hiddenbuttons .= "<input type='hidden' name='b' value='$beer' />\n" ;
        $hiddenbuttons .= "<input type='hidden' name='s' value='$origsty' />\n" ;
        $hiddenbuttons .= "<input type='hidden' name='a' value='$alc' />\n" ;
        $hiddenbuttons .= "<input type='hidden' name='l' value='$loc' />\n" ;
        $hiddenbuttons .= "<input type='hidden' name='o' value='board' />\n" ;  # come back to the board display
      my $buttons="";
      foreach $sp ( sort( {$a->{"vol"} <=> $b->{"vol"}} @$sizes) ) {
        $vol = $sp->{"vol"};
        $pr = $sp->{"price"};
        my $lbl;
        if ($extraboard == $id || $extraboard == -2) {
          $lbl = "$vol cl: $pr.-";
        } else {
          $lbl = "$pr.-";
          $buttons .= "<td>";
        }
        $buttons .= "<form method='POST' accept-charset='UTF-8' style='display: inline;' class='no-print' >\n";
        $buttons .= $hiddenbuttons;
        $buttons .= "<input type='hidden' name='v' value='$vol' />\n" ;
        $buttons .= "<input type='hidden' name='p' value='$pr' />\n" ;
        $buttons .= "<input type='submit' name='submit' value='$lbl'/> \n";
        $buttons .= "</form>\n";
        $buttons .= "</td>\n" if ($extraboard != $id && $extraboard != -2);
      }
      my $beerstyle = beercolorstyle($origsty, "Board:$e->{'id'}", "[$e->{'type'}] $e->{'maker'} : $e->{'beer'}" );

      if ($extraboard == $id  || $extraboard == -2) { # More detailed view
        $mak .= ":" if ($mak);
        print "<tr><td colspan=5><hr></td></tr>\n";
        print "<tr><td $beerstyle>";
        my $linkid = $id;
        if ($extraboard == $id) {
          $linkid = "-3";  # Force no expansion
        }
        print "<a href='$url?o=board$linkid'><span width=100% $beerstyle>$id</span></a> ";
        print "</td>\n";

        print "<td colspan=4 >";
        print "<span style='white-space:nowrap;overflow:hidden;text-overflow:clip;max-width=100px'>\n";
        print "$mak $dispbeer <span style='font-size: x-small;'>($country)</span></span></td></tr>\n";
        print "<tr><td>&nbsp;</td><td colspan=4> $buttons &nbsp;\n";
        print "<form method='POST' accept-charset='UTF-8' style='display: inline;' class='no-print' >\n";
        print "$hiddenbuttons";
        print "<input type='hidden' name='v' value='T' />\n" ;  # taster
        print "<input type='hidden' name='p' value='X' />\n" ;  # at no cost
        print "<input type='submit' name='submit' value='Taster' /> \n";
        print "</form>\n";
        print "</td></tr>\n";
        print "<tr><td>&nbsp;</td><td colspan=4>$origsty <span style='font-size: x-small;'>$alc%</span></td></tr> \n";
        if ($seen{$beer}) {
          print "<tr><td>&nbsp;</td><td colspan=4> Seen <b>" . ($seen{$beer}). "</b> times. ";
          print "Last: $lastseen{$beer} " if ($lastseen{$beer});
          print "</td></tr>\n";
          if ($ratecount{$beer}) {
            my $avgrate = sprintf("%3.1f", $ratesum{$beer}/$ratecount{$beer});
            print "<tr><td>&nbsp;</td><td colspan=4>";
            my $rating = "rating";
            $rating .= "s" if ($ratecount{$beer} > 1 );
            print "$ratecount{$beer} $rating <b>$avgrate</b>: ";
            print $ratings[$avgrate];
          print "</td></tr>\n";
          }
        }
        print "<tr><td colspan=5><hr></td></tr>\n" if ($extraboard != -2) ;
      } else { # Plain view
        print "<tr><td align=right $beerstyle>";
        print "<a href='$url?o=board$id'><span width=100% $beerstyle>$id</span></a> ";
        print "</td>\n";
        print "$buttons\n";
        print "<td style='font-size: x-small;' align=right>$alc</td>\n";
        print "<td>$dispbeer $dispmak ($country) $sty</td>\n";
        print "</tr>\n";
      }
      $previd = $id;
    } # beer loop
    print "</table>\n";
    if (! $nbeers ) {
      print "Sorry, got no beers from $locparam\n";
      print "<!-- Error running " . $scrapers{$locparam} . ". \n";
      print "Result: '$json'\n -->\n";
    }
  }
  # Keep $qry, so we filter the big list too
  $qry = "" if ($qry =~ /PA/i );   # But not 'PA', it is only for the board
} # Board


################################################################################
# short list, aka daily statistics
################################################################################

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
  print "<hr/>Other stats: \n";
  print "<a href='$url?o=short'><b>Days</b></a>&nbsp;\n";
  print "<a href='$url?o=Months'><span>Months</span></a>&nbsp;\n";
  print "<a href='$url?o=Years'><span>Years</span></a>&nbsp;\n";
  print "<hr/>\n";
  my $filts = splitfilter($qry);
  print "<hr/>Filter: <b>$yrlim $filts</b> (<a href='$url?o=short'><span>Clear</span></a>)" .
    "&nbsp;(<a href='$url?q=$qry'><span>Full</span></a>)<br/>" if ($qry||$yrlim);
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
          $places .= " " . filt($loc, "", $loc, "short");
          $locseen{$loc} = 1;
        }
      }
    }
    if ( $lastdate ne $effdate ) {
      if ( $entry ) {
        my $daydrinks = sprintf("%3.1f", $daysum / $onedrink) ;
        $entry .= " " . unit($daydrinks,"d") . " " . unit($daymsum,"kr");
        $entry .= " " . unit(sprintf("%0.2f",$bloodalc{$lastdate}), "‰")
          if ( ( $bloodalc{$lastdate} || 0 ) > 0.01 );
        print "<span style='white-space: nowrap'>$entry";
        print "$places</span><br/>\n";
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
          print ". . . <br/>\n";
        } elsif ( $ndays > 1) {
          print ". . . ($ndays days) . . .<br/>\n";
        }
      }
      my $thismonth = substr($effdate,0,7); #yyyy-mm
      my $bold = "";
      if ( $thismonth ne $month ) {
        $bold = "b";
        $month = $thismonth;
      }
      $wday = "<b>$wday</b>" if ($wday =~ /Fri|Sat|Sun/);  # mark wkends
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
      $loc =~ s/ place$//i;  # Dorthes Place => Dorthes
      $loc =~ s/ /&nbsp;/gi;   # Prevent names breaking in the middle
      if ( $places !~ /$loc/ ) {
        $places .= " " . filt($full, "", $loc, "short");
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
        print "<a href='$url?o=short&y=$y&q=".uri_escape_utf8($qry)."'><span>$y</span></a> ($years{$y})<br/>\n" ;
        $ysum += $years{$y};
      }
    }
    print "<a href='$url?maxl=-1&" . $q->query_string(). "'>" .
      "All</a> ($ysum)<p>\n";
  } else {
    print "<br/>That was the whole list<p>\n" unless ($yrlim);
  }
  exit(); # All done
} # Short list

################################################################################
# Annual summary
################################################################################

elsif ( $op =~ /Years(d?)/i ) {
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
  print "<hr/>Other stats: \n";
  print "<a href='$url?o=short'><span>Days</span></a>&nbsp;\n";
  print "<a href='$url?o=Months'><span>Months</span></a>&nbsp;\n";
  print "<a href='$url?o=Years'><b>Years</b></a>&nbsp;\n";
  print "<hr/>\n";
  my $nlines = param("maxl") || 10;
  if ($sortdr) {
    print "Sorting by drinks (<a href='$url?o=Years&q=" . uri_escape_utf8($qry) .
       "' class='no-print'><span>Sort by money</span></a>)\n";
  } else {
    print "Sorting by money (<a href='$url?o=YearsD&q=" . uri_escape_utf8($qry) .
       "' class='no-print'><span>Sort by drinks</span></a>)\n";
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
          $yrlink = "<a href='$url?o=$op&q=$thisyear&maxl=20'><span>$thisyear</span></a>";
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
    print  "&nbsp; <a href='$url?o=$op&q=" . uri_escape($qry) . "&maxl=$top'><span>Top-$top</span></a>\n";
  }
  if ($qry) {
    my $prev = "<a href=$url?o=Years&q=" . ($qry - 1) . "&maxl=" . param('maxl') ."><span>Prev</span></a> \n";
    my $all = "<a href=$url?o=Years&&maxl=" . param('maxl') ."><span>All</span></a> \n";
    my $next = "<a href=$url?o=Years&q=" . ($qry + 1) . "&maxl=" . param('maxl') ."><span>Next</span></a> \n";
    print "<br/> $prev &nbsp; $all &nbsp; $next \n";
  }
  print  "<hr/>\n";

  exit();
} # Annual stats

################################################################################
# Monthly statistics
# from %monthdrinks and %monthprices
################################################################################

elsif ( $op =~ /Months([BS])?/ ) {
  my $defbig = $mobile ? "S" : "B";
  my $bigimg = $1 || $defbig;
  $bigimg =~ s/S//i ;
  print "<hr/>Other stats: \n";
  print "<a href='$url?o=short'><span>Days</span></a>&nbsp;\n";
  print "<a href='$url?o=Months'><b>Months</b></a>&nbsp;\n";
  print "<a href='$url?o=Years'><span>Years</span></a>&nbsp;\n";
  print "<hr/>\n";

  if ( $allfirstdate !~ /^(\d\d\d\d)/ ) {
    print "Oops, no year from allfirstdate '$allfirstdate' <br/>\n";
    exit(); # Never mind missing footers
  }
  my $firsty=$1;
  my $pngfile = $plotfile;
  $pngfile =~ s/\.plot/-stat.png/;
  my $lasty = datestr("%Y",0);
  my $lastm = datestr("%m",0);
  my $lastym = "$lasty-$lastm";
  my $dayofmonth = datestr("%d");

  open F, ">$plotfile"
      or error ("Could not open $plotfile for writing");
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
  # If in January, extend to Feb, so we see the beginning of the line
#  if ( datestr("%m",0) eq "01" ) {
#    my $nextm = "$lasty-02";
#    if ( ! $monthdrinks{$nextm} ) {
#      $monthdrinks{$nextm} = $monthdrinks{$lastym} / $dayofmonth * 30;
#      $monthprices{$nextm} = 0;
#    }
#  }
  foreach $m ( 1 .. 12 ) {
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
      $dw = unit(int($dw*7+0.5), "/w");
      $t .= "<td align=right>". unit($mdrinks,"/d") .
        "<br/>$dw" .
        "<br/>&nbsp;$mprice</td>\n";
   }
    $t .= "</tr>";
    $plotline .=  "\n";
    push (@plotlines, $plotline);
  }
  print F sort(@plotlines);
  # Projections
  my $cur = datestr("%m",0);
  $curmonth = datestr("%Y-%m",0);
  $d = ($monthdrinks{$curmonth}||0) / $onedrink ;
  my $min = sprintf("%3.1f", $d / 30);  # for whole month
  my $avg = $d / $dayofmonth;
  my $max = 2 * $avg - $min;
  $max = sprintf("%3.1f", $max);
  print F "\n";
  print F "2001-$cur $min\n";
  print F "2001-$cur $max\n";
  close(F);
  $t .= "<tr><td>Avg</td>\n";
  my $granddr = 0;
  my $granddays = 0;
  my $grandprice = 0;
  foreach $y ( reverse($firsty .. $lasty) ) {
    my $d = "";
    my $dw = "";
    if ( $ydays[$y] ) { # have data for the year
      $granddr += $ydrinks[$y];
      $granddays += $ydays[$y];
      $d = sprintf("%3.1f", $ydrinks[$y] / $ydays[$y] / $onedrink) ;
      $dw = $1 if ($d=~/([0-9.]+)/);
      $dw = unit(int($dw*7+0.5), "/w");
      $d = unit($d, "/d");
      $p = int(30*$yprice[$y]/$ydays[$y]+0.5);
      $grandprice += $yprice[$y];
    }
    $t .= "<td align=right>$d<br/>$dw<br/>$p</td>\n";
  }
  my $d = sprintf("%3.1f", $granddr / $granddays / $onedrink) ;
  my $dw = $1 if ($d=~/([0-9.]+)/);
  $dw = unit(int($dw*7+0.5), "/w");
  $d = unit($d, "/d");
  $p = int (30 * $grandprice / $granddays + 0.5);
  $t .= "<td align=right>$d<br/>$dw<br>$p</td>\n";
  $t .= "</tr>\n";

  $t .= "<tr><td>Sum</td>\n";
  my $grandtot = 0;
  foreach $y ( reverse($firsty .. $lasty) ) {
    my $pr  = "";
    if ( $ydays[$y] ) { # have data for the year
      $pr = unit(sprintf("%5.0f", ($yprice[$y]+500)/1000), "kkr") ;
      $grandtot += $yprice[$y];
    }
    $t .= "<td align=right>$pr";
    if ( $y eq $lasty && $yprice[$lasty] ) {
      $pr = $yprice[$lasty] / $ydays[$lasty] * 365;
      $pr = unit(sprintf("%5.0f", ($pr+500)/1000), "kkr") ;
      $pr =~ s/^ *//;  # Remove leading space
      $t .= "<br/>~$pr";
    }
    $t .= "</td>\n";
  }
  $grandtot = unit(sprintf("%5.0f",($grandtot+500)/1000), "kkr");
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
          "behind fc \"#003000\" fillstyle solid border \n".  # green bkg
       "set border linecolor \"white\" \n" .
       "set arrow from \"2000-$firstm\", 5 to \"2001-$lastm\", 5 nohead linewidth 0.1 linecolor \"white\" \n" .
       "set arrow from \"2000-$firstm\", 10 to \"2001-$lastm\", 10 nohead linewidth 0.1 linecolor \"white\" \n" .
       "set arrow from \"2001-01\", 0 to \"2001-01\", 10 nohead linewidth 0.1 linecolor \"white\" \n" .
       "plot ";
  my $lw = 2;
  my $yy = $firsty;
  for ( my $i = 2*($lasty - $firsty) +3; $i > 2; $i -= 2) { # i is the column in plot file
    $lw++ if ( $yy == $lasty );
    my $col = "$yearcolors[$yy]";
    $cmd .= "\"$plotfile\" " .
            "using 1:$i with line lc \"$col\" lw $lw notitle , " ;
    my $j = $i +1;
    $cmd .= "\"$plotfile\" " .
            "using 1:$j with line lc \"$col\" lw $lw notitle , " ;
    $lw+= 0.25;
    $yy++;
  }
  # Finish by plotting low/high projections for current month
  $cmd .= "\"$plotfile\" " .
            "using 1:2 with points pt 6 lc \"$yearcolors[$lasty]\" lw 2 notitle," ;
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
} # Monthly stats

################################################################################
# About page
################################################################################

elsif ( $op eq "About" ) {

  print "<hr/><h2>Beertracker</h2>\n";
  print "Copyright 2016-2024 Heikki Levanto. <br/>";
  print "Beertracker is my little script to help me remember all the beers I meet.\n";
  print "It is Open Source.\n";
  print "<hr/>";

  print "Beertracker on GitHub: <ul>";
  print aboutlink("GitHub","https://github.com/heikkilevanto/beertracker");
  print aboutlink("Bugtracker", "https://github.com/heikkilevanto/beertracker/issues");
  print aboutlink("User manual", "https://github.com/heikkilevanto/beertracker/blob/master/manual.md" );
  print "</ul><p>\n";
  print "Some of my favourite bars and breweries<ul>";
  for my $k ( sort keys(%links) ) {
    print aboutlink($k, $links{$k});
  }
  print "</ul><p>\n";
  print "Other useful links: <ul>";
  print aboutlink("Ratebeer", "https://www.ratebeer.com");
  print aboutlink("Untappd", "https://untappd.com");
  print "</ul><p>\n";

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

  print "<p><hr>\n";
  print "This site uses no cookies, and collects on personally identifiable information<p>\n";


  print "<p><hr/>\n";
  print "<b>Debug info </b><br/>\n";
  print "&nbsp; <a href='$url?o=Datafile&maxl=30' target='_blank' ><span>Tail of the data file</span></a><br/>\n";
  print "&nbsp; <a href='$url?o=Datafile'  target='_blank' ><span>Download the whole data file</span></a><br/>\n";
  print "&nbsp; <a href='$url?o=geo'><span>Geolocation summary</span></a><br/>\n";
  exit();
} # About


################################################################################
# Geolocation debug
################################################################################

elsif ( $op eq "geo" ) {
  if (!$qry || $qry =~ /^ *[0-9 .]+ *$/ ) {  # numerical query
    print "<hr><b>Geolocations</b><p>\n";
    if ($qry) {
      my ($guess, $gdist) = guessloc($qry);
      if ($gdist < 2 ) {
        print "Geo $qry seems to be $guess <br/>\n";
      } else {
        print "Geo $qry looks like $guess at $gdist m<br/>\n";
      }
    }

    print "<table>\n";
    print "<tr><td>Latitude</td><td>Longitude</td>";
    print "<td>dist</td>" if ($qry);
    print "<td>Location</td></tr>\n";
    my %geodist;
    foreach my $k (keys(%geolocations)) {
      if ($qry) {
        my $d = geodist($qry, $geolocations{$k});
        $d = sprintf("%09d",$d);
        $geodist{$k} = "$d $k";
      } else {
        $geodist{$k} = $k;
      }
    }

    foreach my $k (sort { $geodist{$a} cmp $geodist{$b}} (keys(%geolocations))) {
      print "<tr>\n";
      my ($la,$lo, $g) = geo( $geolocations{$k} );
      my $u = "m";
      my ($dist) = $geodist{$k} =~ /^[ 0]*(\d+)/;
      if ( !$dist ) {
        $u ="";
      } elsif ( $dist > 9999 ) {
        $dist = int($dist / 1000) ;
        $u = "km";
      }
      print "<td><a href=$url?o=geo&q=$la+$lo><span>$la</span></a></td>\n";
      print "<td>$lo</td>\n";
      print "<td>" . unit($dist,$u). "</td>\n" if ($qry);
      print "<td><a href='$url?o=geo&q=$k' ><span>$k</span></a></td>\n";
      print "</tr>\n";
    }
    print "</table>\n";

  } else { # loc given, list all occurrences of that location
    my $i = scalar( @lines );
    print "<hr/>Geolocation for <b>$qry</b> &nbsp;";
    print "<a href='$url?o=geo'><span>Back</span></a>";
    print "<p>\n";
    my (undef,undef,$defloc) = geo($geolocations{$qry});
    print "$qry is at: $defloc <p>\n" if ($defloc);
    print "<table>\n";
    print "<tr><td>Latitude</td><td>Longitude</td><td>Dist</td></tr>\n";
    while ( $i-- > 0 ){
      ( $stamp, $wday, $effdate, $loc, $mak, $beer, $vol, $sty, $alc, $pr,
        $rate, $com, $geo ) =  split( / *; */, $lines[$i] );
      next unless $geo;
      next unless ($loc eq $qry);
      my ($la, $lo, $g) = geo($geo);
      next unless ($lo);
      my $dist = geodist($defloc,$g);
      my $ddist = unit($dist,"m");
      my $gdist;
      my $guess = "";
      if ($dist > 15.0) {
        $ddist = "<b>$ddist</b>";
        ($guess, $gdist) = guessloc($g, $qry);
        $gdist = unit($gdist,"m");
      }
      print "<tr>\n";
      print "<td>$la &nbsp; </td><td>$lo &nbsp; </td>";
      print "<td align='right'>$ddist</td>";
      print "<td><a href='$url?o=$op&q=$qry&e=$stamp' ><span>$stamp</span></a> ";
      if ($guess) {
        print "<br>(<b>$guess $gdist ?)</b>\n" ;
        print STDERR "Suspicious Geo: '$loc' looks like '$guess'  for '$g' at '$stamp' \n";
      }
      print "</td>\n";
      print "</tr>\n";
    }
    print "</table>\n";
  }
}  # Geo debug

elsif ( $op eq "full" ) {
  # Ignore for now, we print the full list later.
}

################################################################################
# various lists (beer, location, etc)
################################################################################

elsif ( $op ) {
  print "<hr/><a href='$url'><span><b>$op</b> list</span></a>\n";
  print "<div class='no-print'>\n";
  if ( !$sortlist) {
    print "(<a href='$url?o=$op&sort=1' ><span>sort</span></a>) <br/>\n";
  } else {
    print "(<a href='$url?o=$op'><span>Recent</span></a>) <br/>\n";
  }
  my $filts = splitfilter($qry);
  print "Filter: $filts " .
     "(<a href='$url?o=$op'><span>clear</span></a>) <br/>" if $qry;
  print "Filter: <a href='$url?y=$yrlim'><span>$yrlim</span></a> " .
     "(<a href='$url?o=$op'><span>clear</span></a>) <br/>" if $yrlim;
  print searchform();
  print "Other lists: " ;
  my @ops = ( "Location", "Brewery", "Beer",
      "Wine", "Booze", "Restaurant", "Style");
  for my $l ( @ops ) {
    print "<a href='$url?o=$l'><span>$l</span></a> &nbsp;\n";
  }
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
        "&nbsp; " . loclink($loc, "Www") . "\n  " . glink($loc, "G") . "</span>" .
        "</td>\n" .
        "<td>$wday $effdate ($seen{$loc}) <br class='no-wide'/>" .
        lst("Location",$mak,"i") . ": \n" . lst($op,$beer) . "</td>";

    } elsif ( $op eq "Brewery" ) {
      next if ( $mak =~ /^wine/i );
      next if ( $mak =~ /^booze/i );
      next if ( $mak =~ /^restaurant/i );
      $fld = $mak;
      $mak =~ s"/"/<br/>"; # Split collab brews on two lines
      my $seentimes = "";
      $seentimes = "($seen{$fld})" if ($seen{$fld} );
      $line = "<td>" . filt($mak,"b","","full") . "\n<br/ class='no-wide'>&nbsp;&nbsp;" . glink($mak) . "</td>\n" .
      "<td>$wday $effdate " . lst($op,$loc) . "\n $seentimes " .
            "<br class='no-wide'/> " . lst($op,$sty,"","[$sty]") . " \n " . lst("full",$beer,"b")  ."</td>";

    } elsif ( $op eq "Beer" ) {
      next if ( $mak =~ /^wine/i );
      next if ( $mak =~ /^booze/i );
      next if ( $mak =~ /^restaurant/i );
      $fld = $beer;
      my $seentimes = "";
      $seentimes = "($seen{$beer})" if ($seen{$beer} );
      $line = "<td>" . filt($beer,"b","","full") . "&nbsp; $seentimes &nbsp;\n" . glink($mak,"G") ."</td>" .
            "<td>$wday $effdate ".
            lst($op,$loc) .  "\n <br class='no-wide'/> " .
            lst($op,$sty,"","[$sty]"). "\n " . unit($alc,'%') .
            lst($op,$mak,"i") . "&nbsp;</td>";

    } elsif ( $op eq "Wine" ) {
      next unless ( $mak =~ /^wine, *(.*)$/i );
      $fld = $beer;
      my $stylename = $1;
      my $seentimes = "";
      $seentimes = "($seen{$beer})" if ($seen{$beer} );
      $line = "<td>" . filt($beer,"b","","full")  . "&nbsp; $stylename &nbsp;\n" . glink($beer, "G") . "</td>\n" .
            "<td>$wday $effdate ".
            lst($op,$loc) . "\n $seentimes \n" .
            "<br class='no-wide'/> " . lst($op,$sty,"","[$sty]"). "</td>";

    } elsif ( $op eq "Booze" ) {
      next unless ( $mak =~ /^booze, *(.*)$/i );
      $fld = $beer;
      my $seentimes = "";
      $seentimes = "($seen{$beer})" if ($seen{$beer} );
      my $stylename = $1;
      $line = "<td>" .filt($beer,"b","","full") . "\n&nbsp;" . glink($beer, "G") ."</td>\n" .
            "<td>$wday $effdate ".
            lst($op,$loc) ."\n $seentimes " .
            "<br class='no-wide'/> " . lst($op,$sty,"","[$sty]"). " " . unit($alc,'%') . "\n" .
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
      $line = "<td>" . filt($loc,"b","","full") . "&nbsp; ($seen{$restname}) <br class='no-wide'/> \n ".
              "$rstyle  &nbsp;\n" . glink("Restaurant $loc") . "</td>\n" .
              "<td><i>$beer</i>". " $rpr <br class='no-wide'/> " .
              "$wday $effdate $ratestr</td>";

    } elsif ( $op eq "Style" ) {
      next if ( $mak =~ /^wine/i );
      next if ( $mak =~ /^booze/i );
      next if ( $mak =~ /^restaurant/i );
      next if ( $sty =~ /^misc/i );
      $fld = $sty;
      my $seentimes = "";
      $seentimes = "($seen{$sty})" if ($seen{$sty} );
      $line = "<td>" . filt("[$sty]","b","","full") . " $seentimes" . "</td><td>$wday $effdate \n" .
            lst("Beer",$loc,"i") .
            "\n <br class='no-wide'/> " . lst($op,$mak,"i") . ": \n" . lst("full",$beer,"b") . "</td>";
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
      print "<tr>\n$lineseen{$k}</tr>\n";
    }
  } else {
    foreach my $dl (@displines) {
      print "<tr>\n$dl</tr>\n";
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
      print "<a href='$url?o=$op&y=$y&q=" . uri_escape($qry) . "'><span>$y</span></a><br/>\n" ;
      $ysum += $years{$y};
    }
  }
  print "<a href='$url?maxl=-1&" . $q->query_string() . "'>" .
    "All</a> ($ysum)<br/>\n" if($ysum);

  exit();
}  # Lists


################################################################################
# Regular list, on its own, or after graph and/or beer board
################################################################################

if ( !$op || $op eq "full" ||  $op =~ /Graph(\d*)/i || $op =~ /board/i) {
  my @ratecounts = ( 0,0,0,0,0,0,0,0,0,0,0);
  print "\n<!-- Full list -->\n ";
  my $filts = splitfilter($qry);
  print "<hr/>Filter: \n";
  print " -$qrylim " if ($qrylim);
  print "(<a href='$url'><span>Clear</span></a>) <b>$yrlim $filts</b>" if ($qry || $qrylim || $yrlim);
  print " &nbsp; \n";
  print "<br/>" . searchform() . "<br/>" .
    glink($qry) . " " . rblink($qry) . " " . utlink($qry) . "\n"
    if ($qry||$qrylim);

  print "<span class='no-print'>\n";
  print "<a href='$url?o=$op&q=" . uri_escape_utf8($qry) . "&y=" . uri_escape_utf8($yrlim) .
      "&f=r' ><span>Ratings</span></a>\n";
  print "<a href='$url?o=$op&q=" . uri_escape_utf8($qry) ."&y=" . uri_escape_utf8($yrlim) .
      "&f=c' ><span>Comments</span></a>\n";
  print " &nbsp; Show: ";
  print "<a href='$url?o=$op&q=" . uri_escape_utf8($qry) ."&y=" . uri_escape_utf8($yrlim) .
      "&f=x' ><span>Extra info<span></a><br/>\n";
  if ($qrylim) {
    for ( my $i = 0; $i < 11; $i++) {
      print "<a href='$url?o=$op&q=" . uri_escape_utf8($qry) . "&f=r$i' ><span>$i</span></a> &nbsp;";
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
          print " (a=" . unit($averages{$lastdate},"d"). " )\n";
          if ($bloodalc{$lastdate}) {
            print " ". unit(sprintf("%0.2f",$bloodalc{$lastdate}), "‰");
          }
          print "<br/>\n";
        } # fl avg on loc line, if not going to print a day summary line
        # Restaurant copy button
        print "<form method='POST' style='display: inline;' class='no-print'>\n";
        print "<input type='hidden' name='l' value='$lastloc2' />\n";
        my $rtype = $restaurants{$lastloc2} || "Restaurant, unspecified";
        print "<input type='hidden' name='m' value='$rtype' />\n";
        $rtype =~ s/Restaurant, //;
        print "<input type='hidden' name='b' value='Food and Drink' />\n";
        print "<input type='hidden' name='v' value='x' />\n";
        print "<input type='hidden' name='s' value='$rtype' />\n";
        print "<input type='hidden' name='a' value='x' />\n";
        print "<input type='hidden' name='p' value='$locmsum kr' />\n";
        print "<input type='hidden' name='g' value='' />\n";
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
          if ($bloodalc{$lastdate}) {
            print " ". unit(sprintf("%0.2f",$bloodalc{$lastdate}), "‰");
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
      print "<br/><b>$wday $effdate </b>" . filt($loc,"b") . newmark($loc) . loclink($loc);
      print "<br/>\n" ;
      if ( $qrylim eq "x") {
        my ( undef, undef, $gg) = geo($geolocations{$loc});
        my $tdist = geodist($geo, $gg);
        if ( $tdist && $tdist > 1 ) {
          $tdist = "<b>".unit($tdist,"m"). "</b>";
        } else {
          $tdist = "";
        }
        my ($guess, $gdist) = guessloc($gg,$loc);
        $gdist = unit($gdist,"m");
        $guess = " <b>($guess $gdist?)</b> " if ($guess);
        print "Geo: $gg $tdist $guess<br/>\n" if ($gg || $guess || $tdist);
      }
    }
    # The beer entry itself ##############
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
    print "\n<a id='$anchor'></a>\n";
    print "<br class='no-print'/><span style='white-space: nowrap'> " .
           "$time " . filt($mak,"i") . newmark($mak) .
            " : " . filt($beer,"b") . newmark($beer, $mak) .
      "</span> <br class='no-wide'/>\n";
    my $origsty = $sty || "???";
    if ( $sty || $pr || $vol || $alc || $rate || $com ) {
      if ($sty) {
        my $beerstyle = beercolorstyle("$sty $mak", "$date", "[$sty $mak] : $beer" );
        my $tag="span $beerstyle";
        $sty = shortbeerstyle($sty) if ( $qrylim ne "x" );
        print filt("$sty",$tag) . newmark($sty) . " "   ;
        print "<br>\n" if ( $qrylim eq "x" );
      }
      if ($sty || $pr || $alc) {
        if ( $qrylim ne "x" ) {
          print units($pr, $vol, $alc);
        } else {
          print units($pr, $vol, $alc, $bloodalc{$stamp});
        }
      }
      print "<br/>\n" ;
      if ($rate || $com) {
        print "<span class='only-wide'>&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;</span>\n";
        print " <b>'$rate'-$ratings[$rate]</b>" if ($rate);
        print ": " if ($rate && $com);
        print "<i>$com</i>" if ($com);
        print "<br/>\n";
      }
      $ratecounts[$rate] ++ if ($rate);
      if ( $qrylim eq "x" ) {
        print "Seen " . ($seen{$beer}). " times. " if ($seen{$beer});
        #print "last $lastseen{$beer}. " if ($lastseen{$beer});
        if ($ratecount{$beer}) {
          my $avgrate = sprintf("%3.1f", $ratesum{$beer}/$ratecount{$beer});
          if ($ratecount{$beer} == 1 )  {
            print " One rating: <b>$avgrate</b> ";
          } else {
            print " Avg of <b>$ratecount{$beer}</b> ratings: <b>$avgrate</b>";
          }
        }
        print "<br>\n";
        if ( $geo ) {
          my (undef, undef, $gg) = geo($geo);
          print "Geo: $gg ";
          my $dist = "";
          $dist = geodist( $geolocations{$loc}, $geo);
          my ($guess,$gdist) = guessloc($gg);
          if ( $guess eq $loc ) {
            print " $guess ";
          } else {
            print " <b>$guess ??? </b>  ";
          }
          #if ( $gdist > 0 ) {
            print " (" . unit($gdist,"m"). ")";
          #}
          print "<br>\n";
        }
      }

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
    print "<a href='$url?o=$op&q=$qry&e=" . uri_escape_utf8($stamp) ."' ><span>Edit</span></a> \n";

    # Copy values
    print "<input type='hidden' name='m' value='$mak' />\n";
    print "<input type='hidden' name='b' value='$beer' />\n";
    print "<input type='hidden' name='v' value='' />\n";
    print "<input type='hidden' name='s' value='$origsty' />\n";
    print "<input type='hidden' name='a' value='$alc' />\n";
    print "<input type='hidden' name='l' value='$loc' />\n" if ( $copylocation);
    print "<input type='hidden' name='g' id='geo' value='' />\n";
    print "<input type='hidden' name='o' value='$op' />\n";  # Stay on page
    print "<input type='hidden' name='q' value='$qry' />\n";

    foreach my $volx (sort {no warnings; $a <=> $b || $a cmp $b} keys(%vols) ){
      # The sort order defaults to numerical, but if that fails, takes
      # alphabetical ('R' for restaurant). Note the "no warnings".
      print "<input type='submit' name='submit' value='Copy $volx'
                  style='display: inline; font-size: small' />\n";
    }
    if ( $qrylim eq "x" ) {
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
            "'><span>$y</span></a> ($years{$y})<br/>\n" ;  # TODO - Skips some ??!!
        $ysum += $years{$y};
      }
    }
    $anchor = "#".$anchor if ($anchor);
    $ysum = $ysum || "";
    print "<a href='$url?maxl=-1$anchor' ><span>All</span></a> ($ysum)<p>\n";
  } else {
    print "<br/>That was the whole list<p>\n" unless ($yrlim);
  }
  my $rsum = 0;
  my $rcnt = 0;
  print "<p>Ratings:<br/>\n";
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
} # Full list

# HTML footer
print "</body></html>\n";

exit();


################################################################################
# Various small helpers
################################################################################

# Helper to trim leading and trailing spaces
sub trim {
  $val = shift;
  $val =~ s/^ +//; # Trim leading spaces
  $val =~ s/ +$//; # and trailing
  $val =~ s/\s+/ /g; # and repeated spaces in the middle
  return $val;
}

# Helper to sanitize input data
sub param {
  my $tag = shift;
  my $keepspaces = shift || 1;
  my $val = $q->param($tag) || "";
  $val =~ s/[^a-zA-ZñÑåÅæÆøØÅöÖäÄéÉáÁāĀ\/ 0-9.,&:\(\)\[\]?%-]/_/g;
  $val = trim($val) unless ( $keepspaces );
  return $val;
}


# Helper to make a filter link
sub filt {
  my $f = shift; # filter term
  my $tag = shift || "span";
  my $dsp = shift || $f;
  my $op = shift || $op || "";
  $op = "o=$op&" if ($op);
  my $param = $f;
  $param =~ s"[\[\]]""g; # remove the [] around styles etc
  my $endtag = $tag;
  $endtag =~ s/ .*//; # skip attributes
  my $style = "";
  if ( $tag =~ /background-color:([^;]+);/ ) { #make the link underline disappear
    $style = "style='color:$1'";
  }
  my $link = "<a href='$url?$op"."q=".uri_escape_utf8($param) ."' $style>" .
    "<$tag>$dsp</$endtag></a>";
  return $link;
}

# Helper to split the filter string into individual words, each of which is
# a new filter link. Useful with long beer names etc
sub splitfilter {
  my $f = shift || "";  # current filter term
  my $ret = "";
  for my $w ( split ( /\W+/, $f) ) {
    $ret .= "<a href='$url?o=$op&q=".uri_escape_utf8($w)."'><span>$w</span></a> ";
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
  return "" if ( $v =~ /mixed|misc/i );  # We don't collect those in seen
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
    $lnk .= " &nbsp; <i><a href='$url?o=board&l=$loc'><span>$scrape</span></a></i>" ;
  }
  if (defined($links{$loc}) && $www ne " ") {
    $lnk .= " &nbsp; <i><a href='" . $links{$loc} . "' target='_blank' ><span>$www</span></a></i>" ;
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
    uri_escape($qry) . "' target='_blank' class='no-print'><span>$txt</span></a>)</i>\n";
  return $lnk;
}

# Helper to make a Ratebeer search link
sub rblink {
  my $qry = shift;
  my $txt = shift || "Ratebeer";
  return "" unless $qry;
  $qry = uri_escape_utf8($qry);
  my $lnk = "<i>(<a href='https://www.ratebeer.com/search?q=" . uri_escape($qry) .
    "' target='_blank' class='no-print'><span>$txt<span></a>)</i>\n";
  return $lnk;
}
# Helper to make a Untappd search link
sub utlink {
  my $qry = shift;
  my $txt = shift || "Untappd";
  return "" unless $qry;
  $qry = uri_escape_utf8($qry);
  my $lnk = "<i>(<a href='https://untappd.com/search?q=" . uri_escape($qry) .
    "' target='_blank' class='no-print'><span>$txt<span></a>)</i>\n";
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
  my $bloodalc = shift;
  my $s = unit($pr,"kr") .
    unit($vol, "cl").
    unit($alc,'%');
  if ( $alc && $vol && $pr >= 0) {
    my $dr = sprintf("%1.2f", ($alc * $vol) / $onedrink );
    $s .= unit($dr, "d");
  }
  if ( $pr && $vol && $bloodalc ) {  # bloodalc indicates we have the extended list
    my $lpr = int($pr / $vol * 100);
    $s .= unit($lpr, "kr/l");
  }
  if ($bloodalc) {
    $s .= unit( sprintf("%0.2f",$bloodalc), "‰");
  }
  return $s;
}


# Helper to make an error message
sub error {
  my $msg = shift;
  print $q->header("Content-type: text/plain\n\n");
  print "ERROR\n";
  print $msg;
  exit();
}

# Helper to validate and split a geolocation string
# Takes one string, in either new or old format
# returns ( lat, long, string ), or all "" if not valid coord
sub geo {
  my $g = shift || "";
  return ("","","") unless ($g =~ /^ *\[?\d+/ );
  $g =~ s/\[([-0-9.]+)\/([-0-9.]+)\]/$1 $2/ ;  # Old format geo string
  my ($la,$lo) = $g =~ /([0-9.-]+) ([0-9.-]+)/;
  return ($la,$lo,$g) if ($lo);
  return ("","","");
}

# Helper to return distance between 2 geolocations
sub geodist {
  my $g1 = shift;
  my $g2 = shift;
  return "" unless ($g1 && $g2);
  my ($la1, $lo1, undef) = geo($g1);
  my ($la2, $lo2, undef) = geo($g2);
  return "" unless ($la1 && $la2 && $lo1 && $lo2);
  my $pi = 3.141592653589793238462643383279502884197;
  my $earthR = 6371e3; # meters
  my $latcorr = cos($la1 * $pi/180 );
  my $dla = ($la2 - $la1) * $pi / 180 * $latcorr;
  my $dlo = ($lo2 - $lo1) * $pi / 180;
  my $dist = sqrt( ($dla*$dla) + ($dlo*$dlo)) * $earthR;
  return sprintf("%3.0f", $dist);
}

# Helper to guess the closest location
sub guessloc {
  my $g = shift;
  my $def = shift || ""; # def value, not good as a guess
  $def =~ s/ *$//;
  $def =~ s/^ *//;
  return ("",0) unless $g;
  my $dist = 200;
  my $guess = "";
  foreach my $k ( sort(keys(%geolocations)) ) {
    my $d = geodist( $g, $geolocations{$k} );
    if ( $d && $d < $dist ) {
      $dist = $d;
      $guess = $k;
      $guess =~ s/ *$//;
      $guess =~ s/^ *//;
    }
  }
  if ($def eq $guess ){
    $guess = "";
    $dist = 0;
  }
  return ($guess,$dist);
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

# Helper to assign a color for a beer
sub beercolor {
  my $type = shift;
  my $prefix = shift || "0x";
  my $date = shift; # for error logging
  my $line = shift;

  my @drinkcolors = (   # color, pattern. First match counts, so order matters
      "003000", "restaurant", # regular bg color, no highlight
      "eac4a6", "wine[, ]+white",
      "801414", "wine[, ]+red",
      "4f1717", "wine[, ]+port",
      "aa7e7e", "wine",
      "f2f21f", "Pils|Lager|Keller|Bock|Helles|IPL",
      "e5bc27", "Classic|dunkel|shcwarz|vienna",
      "adaa9d", "smoke|rauch|sc?h?lenkerla",
      "350f07", "stout|port",  # imp comes later
      "1a8d8d", "sour|kriek|lambie?c?k?|gueuze|gueze|geuze|berliner",
      "8cf2ed", "booze|sc?h?nap+s|whisky",
      "e07e1d", "cider",
      "eaeac7", "weiss|wit|wheat|weizen",
      "66592c", "Black IPA|BIPA",
      "9ec91e", "NEIPA|New England",
      "c9d613", "IPA|NE|WC",  # pretty late, NE matches pilsNEr
      "d8d80f", "Pale Ale|PA",
      "b7930e", "Old|Brown|Red|Dark|Ale|Belgian||Tripel|Dubbel|IDA",   # Any kind of ales (after Pale Ale)
      "350f07", "Imp",
      "dbb83b", "misc|mix|random",
      );
      for ( my $i = 0; $i < scalar(@drinkcolors); $i+=2) {
        my $pat = $drinkcolors[$i+1];
        if ( $type =~ /$pat/i ) {
          return $prefix.$drinkcolors[$i] ;
        }
      }
      print STDERR "No color (on $date) for  '$line' \n";
      return $prefix."9400d3" ;   # dark-violet, aggressive pink
}

sub beercolorstyle {
  my $type = shift;
  my $date = shift; # for error logging
  my $line = shift;
  my $bkg= beercolor($type,"#",$date,$line);
  my $col = $bgcolor;
  my $lum = ( hex($1) + hex($2) + hex($3) ) /3  if ($bkg =~ /^#?(..)(..)(..)/i );
  if ($lum < 64) {  # If a fairly dark color
    $col = "#ffffff"; # put white text on it
  }
  return "style='background-color:$bkg;color:$col;'";
}

# Helper to shorten a beer style
sub shortbeerstyle{
  my $sty = shift;
  $sty =~ s/\b(Beer|Style)\b//i; # Stop words
  $sty =~ s/\W+/ /g;  # non-word chars, typically dashes
  $sty =~ s/\s+/ /g;  # multiple spaces etc
  if ( $sty =~ /(\WPA|Pale Ale)/i ) {
    return "APA"   if ( $sty =~ /America|US/i );
    return "BelPA" if ( $sty =~ /Belg/i );
    return "NEPA"  if ( $sty =~ /Hazy|Haze|New England|NE/i);
    return "PA";
  }
  if ( $sty =~ /(IPA|India)/i ) {
    return "SIPA" if ( $sty =~ /Session/i);
    return "BIPA" if ( $sty =~ /Black/i);
    return "DNE"  if ( $sty =~ /(Double|Triple).*(New England|NE)/i);
    return "DIPA" if ( $sty =~ /Double|Dipa/i);
    return "WIPA" if ( $sty =~ /Wheat/i);
    return "NEIPA" if ( $sty =~ /New England|NE|Hazy/i);
    return "NZIPA" if ( $sty =~ /New Zealand|NZ/i);
    return "WC"   if ( $sty =~ /West Coast|WC/i);
    return "AIPA" if ( $sty =~ /America|US/i);
    return "IPA";
  }
  return "IL"   if ( $sty =~ /India Lager/i);
  return "Lag"  if ( $sty =~ /Pale Lager/i);
  return "Kel"  if ( $sty =~ /^Keller.*/i);
  return "Pils" if ( $sty =~ /.*(Pils).*/i);
  return "Hefe" if ( $sty =~ /.*Hefe.*/i);
  return "Wit"  if ( $sty =~ /.*Wit.*/i);
  return "Dunk" if ( $sty =~ /.*Dunkel.*/i);
  return "Wbock" if ( $sty =~ /.*Weizenbock.*/i);
  return "Dbock" if ( $sty =~ /.*Doppelbock.*/i);
  return "Bock" if ( $sty =~ /.*[^DW]Bock.*/i);
  return "Smoke" if ( $sty =~ /.*(Smoke|Rauch).*/i);
  return "Berl" if ( $sty =~ /.*Berliner.*/i);
  return "Imp"  if ( $sty =~ /.*(Imperial).*/i);
  return "Stout" if ( $sty =~ /.*(Stout).*/i);
  return "Port"  if ( $sty =~ /.*(Porter).*/i);
  return "Farm" if ( $sty =~ /.*Farm.*/i);
  return "Saison" if ( $sty =~ /.*Saison.*/i);
  return "Dubl" if ( $sty =~ /.*(Double|Dubbel).*/i);
  return "Trip" if ( $sty =~ /.*(Triple|Tripel|Tripple).*/i);
  return "Quad" if ( $sty =~ /.*(Quadruple|Quadrupel).*/i);
  return "Blond" if ( $sty =~ /Blond/i);
  return "Brown" if ( $sty =~ /Brown/i);
  return "Strong" if ( $sty =~ /Strong/i);
  return "Belg" if ( $sty =~ /.*Belg.*/i);
  return "BW"   if ( $sty =~ /.*Barley.*Wine.*/i);
  $sty =~ s/.*(Lambic|Sour) *(\w+).*/$1/i;   # Lambic Fruit - Fruit
  $sty =~ s/.*\b(\d+)\b.*/$1/i; # Abt 12 -> 12 etc
  $sty =~ s/^ *([^ ]{1,6}).*/$1/; # Only six chars, in case we didn't get it above
  return $sty;
}
