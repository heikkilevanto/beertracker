#!/usr/bin/perl -w

# Heikki's beer tracker
#
# Keeps beer drinking history in a flat text file.
#
# This is a simple CGI script
# See https://github.com/heikkilevanto/beertracker/
#


################################################################################
# Overview
################################################################################
#
# The code consists of one very long main function that produces whatever
# output we need, and a small number of helpers. (Ought to be refactored
# in version 2). Sections are delimited by comment blocks like above.
#

# Sections of the main function:
# - Init and setup
#   - Modules and UTF-8 stuff
#   - Constants and setup
#
# - Early processing
#   - Dump of the data file
#   - Read the data file
#   - POST data into the file
#   - HTML head
#   - Javascript trickery for the browser-side stuff
#
# - Various sections of the output page. Mostly conditional on $op
#   - Main input form, always there
#   - Graph. There for some selected $ops: graph, board
#   - Beer board (list) for the location.
#   - Short list, aka daily statistics
#   - Annual summary
#   - Monthly statistics
#   - About page
#   - Geolocation debug
#   - various lists (beer, wine, booze, location, resturant, etc)
#   - Regular full list. Shown by itself, or after graph, board

# Helper functions. These can be grouped into
# - String manipulation (trim)
# - Input parameter normalizing
# - Stuff for the main list filters
# - Making a NEW marker for things not seen before
# - Making various links
# - Prices. Normalizing, currency conversions
# - Displaying units
# - Error handling
# - Geo coordinate stuff
# - Formatting dates
# - Producing the "last seen" line
# - Color coding and shortening beer styles




################################################################################
# Modules and UTF-8 stuff
################################################################################
use strict;
use POSIX qw(strftime localtime locale_h);
use JSON;
use Cwd qw(cwd);
use File::Copy;

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
my $photodir = "";
my $username = ($q->remote_user()||"");

# Sudo mode, normally commented out
#$username = "dennis" if ( $username eq "heikki" );  # Fake user to see one with less data

if ( ($q->remote_user()||"") =~ /^[a-zA-Z0-9]+$/ ) {
  $datafile = $datadir . $username . ".data";
  $plotfile = $datadir . $username . ".plot";
  $cmdfile = $datadir . $username . ".cmd";
  $photodir = $datadir . $username. ".photo";
} else {
  error ("Bad username\n");
}
if ( ! -w $datafile ) {
  error ("Bad username: $datafile not writable\n");
}
my @ratings = ( "Zero", "Undrinkable", "Unpleasant", "Could be better",  # zero should not be used!
"Ok", "Goes down well", "Nice", "Pretty good", "Excellent", "Perfect");  # 9 is the top

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

# Links to beer lists at the most common locations and breweries
my %links;
$links{"Ølbaren"} = "http://oelbaren.dk/oel/";
$links{"Ølsnedkeren"} = "https://www.olsnedkeren.dk/";
$links{"Fermentoren"} = "http://fermentoren.com/index";
$links{"Dry and Bitter"} = "https://www.dryandbitter.com/collections/beer/";
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
#$scrapers{"Ølsnedkeren"} = "oelsnedkeren.pl";
# Ølsnedkerens web site is broken, does not show a beer list at all
# See #368

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
my $burnrate = .10; # g of alc pr kg of weight (.10 to .15)
  # Assume .10 as a pessimistic value. Would need an alc meter to calibrate

# Default image sizes (width in pixels)
my %imagesizes;
$imagesizes{"thumb"} = 90;
$imagesizes{"mob"} = 240;  # 320 is full width on my phone
$imagesizes{"pc"} = 640;


# Geolocations. Set up when reading the file, passed to the javascript
my %geolocations; # Latest known geoloc for each location name
$geolocations{"Home "} =   "[55.6588/12.0825]";  # Special case for FF.
$geolocations{"Home  "} =  "[55.6531712/12.5042688]";  # Chrome
$geolocations{"Home   "} = "[55.6717389/12.5563058]";  # Chrome on my phone
  # My desktop machine gets the coordinates wrong. FF says Somewhere in Roskilde
  # Fjord, Chrome says in Valby...
  # Note also the trailing space(s), to distinguish from the ordinary 'Home'
  # That gets filtered away before saving.
  # (This could be saved in each users config, if we had such)

# Data line types - These define the field names on the data line for that type
# as well as which input fields will be visible.
my %datalinetypes;
# Pseudo-type "None" indicates a line not worth saving, f.ex. no beer on it

# The old style lines with no type.
$datalinetypes{"Old"} = [
  "stamp",  # Time stamp, as in "yyyy-mm-dd hh:mm:ss"
  "wday",   # Weekday, "Mon" to "Sun"
  "effdate",# Effective date "yyyy-mm-dd". Beers after midnight count as the night before. Changes at 08.
  "loc",    # Location
  "mak",    # Maker, or brewer
  "beer",   # Name of the beer
  "vol",    # Volume, in cl
  "sty",    # Style of the beer
  "alc",    # Alcohol percentage, with one decimal
  "pr",     # Price in default currency, in my case DKK
  "rate",   # Rating
  "com",    # Comment
  "geo"];   # Geo coordinates

# A dedicated beer entry. Almost like above. But with a type and subtype
$datalinetypes{"Beer"} = [
  "stamp", "type", "wday", "effdate", "loc",
  "maker",  # Brewery
  "name",   # Name of the beer
  "vol", "style", "alc", "pr", "rate", "com", "geo",
  "subtype", # Taste of the beer, could be fruits, special hops, or type of barrel
  "photo" ]; # Image file name

# Wine
$datalinetypes{"Wine"} = [ "stamp", "type", "wday", "effdate", "loc",
  "subtype", # Red, White, Bubbly, etc
  "maker", # brand or house
  "name", # What it says on the label
  "style", # Can be grape (chardonnay) or country/region (rioja)
  "vol", "alc", "pr", "rate", "com", "geo", "photo"];

# Booze. Also used for coctails
$datalinetypes{"Booze"} = [ "stamp", "type", "wday", "effdate", "loc",
  "subtype",   # whisky, snaps
  "maker", # brand or house
  "name",  # What it says on the label
  "style", # can be coctail, country/(region, or flavor
  "vol", "alc",  # These are for the alcohol itself
  "pr", "rate", "com", "geo", "photo"];


# A comment on a night out.
$datalinetypes{"Night"} = [ "stamp", "type", "wday", "effdate", "loc",
  "subtype",# bar discussion, concert, lunch party, etc
  "com",    # Any comments on the night
  "people", # Who else was here
  "geo", "photo" ];

# Restaurants and bars
$datalinetypes{"Restaurant"} = [ "stamp", "type", "wday", "effdate", "loc",
  "subtype",  # Type of restaurant, "Thai"
  "rate", "pr", # price for the night, per person
  "food",   # Food and drink
  "people",
  "com", "geo",
  "photo"];

# To add a new record type, define it here

# To add new input fields, add them to the end of the field list, so they
# will default to empty in old records that don't have them.
# You probably want to add special code in the input form, record POST, and
# to the various lists.

################################################################################
# Input Parameters
################################################################################
# These are used is so many places that it is OK to have them as globals
# TODO - Check if all are used, after refactoring
my $edit= param("e");  # Record to edit
my $type = param("type"); # Switch record type
my $qry = param("q");  # filter query, greps the list
my $qryfield = param("qf") || "rawline"; # Which field to match $qry to
my $qrylim = param("f"); # query limit, "x" for extra info, "f" for forcing refresh of board
my $yrlim = param("y"); # Filter by year
my $op  = param("o");  # operation, to list breweries, locations, etc
my $maxlines = param("maxl") || "$yrlim$yrlim" || "45";  # negative = unlimited
   # Defaults to 25, unless we have a year limit, in which case defaults to something huge.
my $sortlist = param("sort") || 0; # default to unsorted, chronological lists
my $notbef = param("notbef") || ""; # Skip parsing records older than this
my $url = $q->url;
# the POST routine reads its own input parameters

################################################################################
# Global variables
# Mostly from reading the file, used in various places
################################################################################
# TODO - Check these
my $foundrec;  # The record we found, either the last one or one defined by edit param
my @records; # All data records, parsed
my @lines; # All data lines, unparsed
my %seen; # Count how many times various names seen before (for NEW marks)
my $todaydrinks = "";  # For a hint in the comment box
my %ratesum; # sum of ratings for every beer
my %ratecount; # count of ratings for every beer, for averaging
my %restaurants; # maps location name to restaurant records, mostly for the type
my %bloodalc; # max blood alc for each day
my %lastseen; # Last time I have seen a given beer
my %monthdrinks; # total drinks for each calendar month
my %monthprices; # total money spent. Indexed with "yyyy-mm"
my %averages; # floating average by effdate. Calculated in graph, used in extended full list
my $starttime = "";  # For the datestr helper
my %lastdateindex; # index of last record for each effdate
my $commentlines = 0; # Number of comment lines in the data file
my $commentedrecords = 0; # Number of commented-out data lines
my $efftoday = datestr( "%F", -0.3, 1); #  today's date

################################################################################
# Main program
################################################################################


if ($devversion) { # Print a line in error.log, to see what errors come from this invocation
  print STDERR datestr() . " " . $q->request_method . " " .  $ENV{'QUERY_STRING'} . " \n";
}

if ( $op eq "Datafile" ) {  # Must be done before sending HTML headers
  dumpdatafile();
  exit;
}
if ( $devversion && $op eq "copyproddata" ) {
  copyproddata();
  exit;
}

my $datafilecomment = readdatafile();

# Default new users to the about page, we have nothing else to show
if ( !$op) {
  if ( !@lines) {
    $op = "About";
  } else {
    $op = "Graph";  # Default to showing the graph
  }
}

if ( $q->request_method eq "POST" ) {
  postdata(); # forwards back to the script to display the data
  exit;
}


htmlhead($datafilecomment); # Ok, now we can commit to making a HTML page

findrec(); # Find the default record for display and geo
extractgeo(); # Extract geo coords

javascript(); # with some javascript trickery in it


# The input form is at the top of every page
inputform();


# We display a graph for some pages, but only if we have data
if ( $op =~ /^Graph/i || $op =~ /Board/i) {
  graph();
}
if ( $op =~ /Board/i ) {
  beerboard();
}
if ( $op =~ /Years(d?)/i ) {
  yearsummary($1); # $1 indicates sort order
}
if ( $op =~ /short/i ) {
  shortlist();
}
if ( $op =~ /Months([BS])?/ ) {
  monthstat($1);
}
if ( $op =~ /DataStats/i ) {
  datastats();
}
if ( $op eq "About" ) {
  about();
}
if ( $op eq "geo" ) {
  geodebug();
}
if ( $op =~ /Location|Brewery|Beer|Wine|Booze|Restaurant|Style/i ) {
  lists();
}
if ( !$op || $op eq "full" ||  $op =~ /Graph(\d*)/i || $op =~ /board/i) {
  fulllist();
}

htmlfooter();
exit();  # The rest should be subs only

# End of main

################################################################################
# Dump of the data file
# Needs to be done before the HTML head, since we output text/plain
# Dump directly from the data file, so we get comments too
################################################################################
sub dumpdatafile {
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
  print "# Date Time; [LineType;] Weekday; Effective-date; Location; Brewery; Beer; Vol; " .
    "Style; Alc; Price; Rating; Comment; GeoCoords\n";
  # TODO - Print a header for each line type
  while (<F>) {
    chomp();
    print "$_ \n" unless ($skip-- >0);
  }
  close(F);
} # Dump of data file

################################################################################
# Copy production data to dev file
# Needs to be before the HTML head, as it forwards back to the page
################################################################################
# Nice to see up to date data when developing
sub copyproddata {
  if (!$devversion) {
    error ("Not allowed");
  }
  my $bakfile = $datafile . ".bak";
  my $prodfile = "../beertracker/$datafile";
  error("$prodfile not readable") if ( ! -r $prodfile);
  system("cat $datafile > $bakfile");
  system("cat $prodfile > $datafile");
  clearcachefiles();
  system("cp ../beertracker/$photodir/* $photodir");
  print $q->redirect( "$url" );
  exit();
} # copyproddata


################################################################################
# Read the file
# Readsa all the (non-comment) lines into @lines
################################################################################

sub readdatafile {

  my $nlines = 0;
  open F, "<$datafile"
    or error("Could not open $datafile for reading: $!".
      "<br/>Probably the user hasn't been set up yet" );

  while (<F>) {
    chomp();
    next unless $_; # skip empty lines
    $nlines++;
    if ( /^[^0-9a-z]*#(20)?/i ) { # skip comment lines
      # The set expression is to allow the BOM on the first line which usually is a comment
      if ($1) {
        $commentedrecords++;
      } else {
        $commentlines++;
      }
      next;
    }
    push (@lines, $_ ); #
  }
  close(F);
  my $ndatalines = scalar(@lines);
  my $ncom = $commentedrecords + $commentlines;
  return "<!-- Read $nlines lines from $datafile: $ndatalines real reocrds, $ncom comments -->\n";
}

################################################################################
# Extract geo locations
# Does not parse every line, only those that seem to contain a geo
################################################################################
sub extractgeo {
  for ( my $i = scalar(@lines)-1; $i>0; $i-- ) {
    next unless ( $lines[$i] =~ /\d\d\.\d\d\d\d\d/ ); # seems to contain a geo
    my $rec = getrecord($i);
    if ($rec->{loc} && $rec->{geo} && !$geolocations{$rec->{loc}} ) {
      my $geocoord;
      (undef, undef, $geocoord) = geo($rec->{geo});
      $geolocations{$rec->{loc}} = $geocoord if ($geocoord); # Save the last seen location
    }
  }
}

################################################################################
# Helper to find the record we should prefill in the input form
# Sets $foundrec to it, as it may be used elsewhere
# Does not parse all the redcords
################################################################################
sub findrec {
  my $i = scalar( @lines ) -1;
  if ( ! $edit ) { # Usually the last one
    $foundrec = getrecord($i);
  }
  while ( ! $foundrec && $i > 0) { # Or the one we are editing
    if ( $lines[$i] =~ /^$edit/ ) {
      $foundrec = getrecord($i);
    }
    $i--;
  }
}

################################################################################
# A helper to preload the last few years of records, to get seen marks in
# %seen and %lastseen
################################################################################
sub getseen{
  my $limit = shift || datestr( "%F", -2*365 ) ; # When to stop scannig
  my $i = scalar( @lines )-1;
  while ($i > 0) { # normall we exit when we hit the limit
    my $rec = getrecord($i);
    last if ( ! $rec);
    $seen{$rec->{maker}}++;
    $seen{$rec->{name}}++;
    $seen{$rec->{style}}++;
    $seen{$rec->{loc}}++;
    $seen{$rec->{seenkey}}++;
    $lastseen{$rec->{seenkey}} .= "$rec->{effdate} ";
    last if ( $rec->{stamp} lt $limit );
    $i--;
  }
}

################################################################################
# A helper to calculate blood alcohol
# Sets the bloodalc to all records at the date of the given index
# and $bloodalc{$effdate} to max bloodalc for the effdate
# If asking for the index of the last record, calculates and returns also
# the blood alc at current time, and time when all alc is burned off
#
################################################################################
sub bloodalcohol {
  my $i = shift || scalar(@lines)-1;  # Index to any line on the interesting date
  my $atend = 0;
  $atend = 1 if ( $i == scalar(@lines)-1 );
  if ( !$bodyweight ) {
    print STDERR "Can not calculate alc for $username, don't know body weight \n";
    return; # TODO - What to return
  }
  my $rec = getrecord($i);
  my $eff = $rec->{effdate};
  return if ( $bloodalc{$eff} ); # already done

  # Scan back to the beginning of the day
  while ( $eff eq $rec->{effdate} && $i>0 ) {
    $i--;
    $rec = getrecord($i);
  }
  $i++; # now at the first record of the date
  my $alcinbody = 0;
  my $balctime = 0;
  my $maxba = 0;
  while ( $i < scalar(@lines) ) { # Forward until end of day
    $rec = getrecord($i);
    last if ( ! $rec || $rec->{effdate} ne $eff );
    if ( $rec->{alcvol} ) {
      my $drtime = $1 + $2/60 if ($rec->{stamp} =~/ (\d?\d):(\d\d)/ ); # frac hrs
      $drtime += 24 if ( $drtime < $balctime ); # past midnight
      my $timediff = $drtime - $balctime;
      $balctime = $drtime;
      $alcinbody -= $burnrate * $bodyweight * $timediff;
      $alcinbody = 0 if ( $alcinbody < 0);
      #my $lower = $alcinbody;
      $alcinbody += $rec->{alcvol} / $onedrink * 12 ; # grams of alc in body
      my $ba = $alcinbody / ( $bodyweight * .68 ); # non-fat weight
      $maxba = $ba if ( $ba > $maxba );
      $rec->{bloodalc} = $ba;
      #print STDERR "Bloodalc $i $eff $rec->{stamp}: down to $lower in $timediff, up to $alcinbody, makes $ba \n";
    }
    $i++;
  }
  $bloodalc{$eff} = $maxba;  # Remember it for the date

  my $curba = "";
  my $allgone = "";
  if ( $atend && $eff eq datestr("%F", -0.3, 1) ) {  # We want the current bloodalc and time when down to zero
  #if ( $atend ) {  # We want the current bloodalc and time when down to zero
    my $now = datestr( "%H:%M", 0, 1);
    my $drtime = $1 + $2/60 if ($now =~/^(\d\d):(\d\d)/ ); # frac hrs
    $drtime += 24 if ( $drtime < $balctime ); # past midnight
    my $timediff = $drtime - $balctime;
    $alcinbody -= $burnrate * $bodyweight * $timediff;
    $alcinbody = 0 if ( $alcinbody < 0);
    $curba = $alcinbody / ( $bodyweight * .68 ); # non-fat weight
    my $lasts = $alcinbody / ( $burnrate * $bodyweight );
    my $gone = $drtime + $lasts;
    $gone -= 24 if ( $gone > 24 );
    $allgone = sprintf( "%02d:%02d", int($gone), ( $gone - int($gone) ) * 60 );
    #print STDERR "balc: e='$eff' n='$now' dr='$drtime' b='$balctime' d=$timediff a=$alcinbody ba=$curba l=$lasts ag=$allgone\n";
  }
  return ( $curba, $allgone );
}

################################################################################
# POST data into the file
# Try to guess missing values from last entries
################################################################################

# Helper to convert input parameters into a rough estimation of a record
# Just takes all named parameters into rec. There will be some extras, and
# likely important things missing
sub inputrecord {
  my $rec = {};
  my @pnames = $q->param;
  foreach my $p ( @pnames ) {
    my $pv = $q->param($p);
    #print STDERR "param: '$p' : '$pv'\n";
    $rec->{$p} = "$pv";
  }
  return $rec;
}

# Helper to fix the time, date, effdate, and wkday in the record
# Several special cases
#  - Date "L" for one after the Last entry, 5 min later, same loc
#  - Date "Y" for yesterday
#  - Time as in 4pm, 16, 1630, 16:30, 16:30:45
sub fixtimes {
  my $rec = shift;
  my $lastrec = shift; # the all last record in the file
  my $sub = shift;
  $rec->{time} = "" unless ( defined($rec->{time}) );
  $rec->{date} = "" unless ( defined($rec->{date}) );
  if ( $sub eq "Save" ) { # Keep the datetime from the form
    $rec->{date} = trim($rec->{date});
    $rec->{time} = trim($rec->{time});
  } else { # Kill the datetime, unless explicitly entered
    $rec->{date} = "" if ($rec->{date} && $rec->{date} =~ /^ / );
    $rec->{time} = "" if ($rec->{time} && $rec->{time} =~ /^ / );
  }

  if ($rec->{date} && $rec->{date} =~ /^L$/i ) { # 'L' for last date
    $rec->{date} = $lastrec->{date} || datestr();
    if (! $rec->{time} && $lastrec->{time} =~ /^ *(\d\d):(\d\d)/ ){ # Guess a time
      my $hr = $1;
      my $min = $2;
      $min += 5;  # 5 min past the previous looks right
      if ($min > 59 ) {
        $min -= 60;
        $hr++;
        $hr -= 24 if ($hr >= 24);
        # TODO - Increment date as well
      }
      $rec->{time} = sprintf("%02d:%02d", $hr,$min);
      $rec->{loc} = $foundrec->{loc}; # Assume same location
    }
  } # date 'L'
  if ( $rec->{date} && $rec->{date} =~ /^Y$/i ) { # 'Y' for yesterday
    $rec->{date} = datestr( "%F", -1, 1);
  }
  $rec->{time} = "" if ("$rec->{time}" !~ /^\d/); # Remove real bad times, default to now
  $rec->{time} =~ s/^([0-9:]*p?).*/$1/i; # Remove AM markers (but not the p in pm)
  $rec->{time} =~ s/^(\d\d?)(\d\d)(p?)/$1:$2$3/i; # expand 0130 to 01:30, keeping the p
  if ( $rec->{time} =~ /^(\d\d?) *(p?)$/i ) { # default to full hrs
    $rec->{time} = "$1:00$2";
  }
  if ( $rec->{time} =~ /^(\d+):(\d+)(:\d+)? *(p)/i ) { # Convert 'P' or 'PM' to 24h
    $rec->{time} = sprintf( "%02d:%02d%s", $1+12, $2, $3);
  }
  if ( $rec->{time} =~ /^(\d+:\d+)$/i ) { # Add seconds if not there
    $rec->{time} = "$1:" . datestr("%S", 0,1); # Get seconds from current time
  }   # That keeps timestamps somewhat different, even if adding several entries in the same minute

  # Default to current date and time
  $rec->{date} = $rec->{date} || datestr( "%F", 0, 1);
  $rec->{time} = $rec->{time} || datestr( "%T", 0, 1);
  $rec->{stamp} = "$rec->{date} $rec->{time}";
  my $effdatestr = `date "+%F;%a" -d "$rec->{date} $rec->{time} 8 hours ago"`;
  if ( $effdatestr =~ /([0-9-]+) *;(\w+)/ ) {
    $rec->{effdate} = $1;
    $rec->{wday} = $2;
  }
  my $lasttimestamp = $lastrec->{stamp};
  if (  $rec->{stamp} =~ /^$lasttimestamp/ && $sub eq "Record" ) { # trying to create a duplicate
    if ( $rec->{stamp} =~ /^(.*:)(\d\d)(;.*)$/ ) {
      my $sec = $2;
      $sec++;  # increment the seconds, even past 59.
      $rec->{stamp} = "$1$sec$3";
    }
    print STDERR "Oops, almost inserted a duplicate timestamp '$lasttimestamp'. ".
      "Adjusted it to '$rec->{stamp}' \n";
  }
  #print STDERR "fixed s='$rec->{stamp}' d='$rec->{date}' t='$rec->{time}' e='$rec->{effdate}' w='$rec->{wday}' \n";
} # fixtimes

# Fix volume trickery
sub fixvol {
  my $rec = shift;
  my $sub = shift;
  return unless hasfield($rec->{type},"vol"); # no vol to work with
  if ( $sub =~ /Copy (\d+)/ ) {  # copy different volumes
    $rec->{vol} = $1;
  }
  $rec->{vol} = "" unless ($rec->{vol});
  my $half;  # Volumes can be prefixed with 'h' for half measures.
  if ( $rec->{vol} =~ s/^(H)(.+)$/$2/i ) {
    $half = $1;
  }
  my $volunit = uc(substr($rec->{vol},0,1)); # S or L or such
  if ( $volumes{$volunit} && $volumes{$volunit} =~ /^ *(\d+)/ ) {
    my $actvol = $1;
    $rec->{vol} =~s/$volunit/$actvol/i;
  }
  if ($half) {
    $rec->{vol} = int($rec->{vol} / 2) ;
  }
  if ( $rec->{vol} =~ /([0-9]+) *oz/i ) {  # Convert (us) fluid ounces
    $rec->{vol} = $1 * 3;   # Actually, 2.95735 cl, no need to mess with decimals
  }
} # fixvol


# Helper to see if a field is missing
sub missing {
  my $rec = shift;
  my $fld = shift;
  return  (defined($rec->{$fld}) && $rec->{$fld} eq "" );
}

# Helper to guess missing values from previous lines
sub guessvalues {
  my $rec = shift;
  my $priceguess = "";
  my $defaultvol = 40;
  my $i = scalar( @lines )-1;
  $rec->{name} = trim($rec->{name});  # Remove leading spaces if any
  while ( $i > 0 && $rec->{name}
    && ( missing($rec,"maker") || missing($rec,"vol") || missing($rec,"style") ||
         missing($rec,"alc") || missing($rec,"pr") )) {
    my $irec = parseline($lines[$i]);
    if ( !$priceguess &&    # Guess a price
         $irec->{loc} && $rec->{loc} &&
         uc($irec->{loc}) eq uc($rec->{loc}) &&   # if same location and volume
         $irec->{vol} eq $rec->{vol} ) { # even if different beer, good fallback
      $priceguess = $irec->{pr};
    }
    if ( uc($rec->{name}) eq uc($irec->{name}) ) { # Same beer, copy values over if not set
      $rec->{name} = $irec->{name}; # with proper case letters
      $rec->{maker} = $irec->{maker} unless $rec->{maker};
      $rec->{style} = $irec->{style} unless $rec->{style};
      $rec->{alc} = $irec->{alc} unless $rec->{alc};
      if ( $rec->{vol} eq $irec->{vol} && $irec->{pr} =~/^ *[0-9.]+ *$/) {
        # take price only from same volume, and only if numerical
        $rec->{pr}  = $irec->{pr} if $rec->{pr} eq "";
      }
      $rec->{vol} = $irec->{vol} unless $rec->{vol};
    }
    $i--;
  }
  if (hasfield($rec->{type},"vol")) {
    if ( uc($rec->{vol}) eq "X" ) {  # 'X' is an explicit way to indicate a null value
      $rec->{vol} = "";
    } else {
      $rec->{vol} = number($rec->{vol});
      if ($rec->{vol}<=0) {
        $rec->{vol} = $defaultvol;
      }
    }
  }
  if (hasfield($rec->{type},"pr")) {
    $rec->{pr} = $priceguess if $rec->{pr} eq "";
    my $curpr = curprice($rec->{pr});
    if ($curpr) {
      $rec->{com} =~ s/ *\[\d+\w+\] *$//i; # Remove old currency price comment "[12eur]"
      $rec->{com} .= " [$rec->{pr}]";
      $rec->{pr} = $curpr;
    } else {
      $rec->{pr} = price($rec->{pr});
    }
  }
  if (!$rec->{vol} || $rec->{vol} < 0 ) {
    $rec->{alc} = "";  # Clear alc if no vol
    $rec->{vol} = "";  # But keep the price for restaurants etc
  }
  $rec->{alc} = number($rec->{alc});

  if ( $rec->{type} eq "Beer" && ! $rec->{subtype} ) {
    $rec->{subtype} = "DK"; # A good default
  }
} # guessvalues


# Get image file name. Width can be in pixels, or special values like
# "orig" for the original image, "" for the plain name to be saved in the record,
# or "thumb", "mob", "pc" for default sizes
sub imagefilename {
  my $fn = shift; # The raw file name
  my $width = shift; # How wide we want it, or "orig" or ""
  $fn =~ s/(\.?\+?orig)?\.jpe?g$//i; # drop extension if any
  return $fn if (!$width); # empty width for saving the clean filename in $rec
  $fn = "$photodir/$fn"; # a real filename
  if ( $width =~ /\.?orig/ ) {
    $fn .= "+orig.jpg";
    return $fn;
  }
  $width = $imagesizes{$width} || "";
  return "" unless $width;
  $width .= "w"; # for easier deleting *w.jpg
  $fn .= "+$width.jpg";
  return $fn;
}

# Produce the image tag
sub image {
  my $rec = shift;
  my $width = shift; # One of the keys in %imagesizes
  return "" unless ( $rec->{photo} );
  my $orig = imagefilename($rec->{photo}, "orig");
  if ( ! -r $orig ) {
    print STDERR "Photo file $orig not found for record $rec->{rawline} \n";
    return "";
  }
  my $fn = imagefilename($rec->{photo}, $width);
  return "" unless $fn;
  if ( ! -r $fn ) { # Need to resize it
    my $size = $imagesizes{$width};
    $size = $size . "x". $size .">";
    system ("convert $orig -resize '$size' $fn");
    print STDERR "convert $orig -resize '$size' $fn \n";
  }
  my $w = $imagesizes{$width};
  my $itag = "<img src='$fn' width='$w' />";
  my $tag = "<a href='$orig'>$itag</a>";
  return $tag;

}
# TODO
# - Make a routine to scale to any given width. Check if already there.
# - Use that when displaying
# - When clearing the cache, delete scaled images over a month old, but not .orig
sub savefile {
  my $rec = shift;
  my $fn = $rec->{stamp};
  $fn =~ s/ /+/; # Remove spaces
  $fn .= ".jpg";
  if ( ! -d $photodir ) {
    print STDERR "Creating photo dir $photodir - FIX PERMISSIONS \n";
    print STDERR "chgrp heikki $photodir; chmod g+sw $photodir \n";
    mkdir($photodir);
  }
  my $savefile = "$photodir/$fn";
  my ( $base, $sec ) = $fn =~ /^(.*):(\d\d)/;
  $sec--;
  do {
    $sec++;
    $fn = sprintf("%s:%02d", $base,$sec);
    $savefile = imagefilename($fn,"orig");
  }  while ( -e $savefile ) ;
  $rec->{photo} = imagefilename($fn,"");

  my $filehandle = $q->upload('newphoto');
  my $tmpfilename = $q->tmpFileName( $filehandle );
  my $conv = `/usr/bin/convert $tmpfilename -auto-orient -strip $savefile`;
    # -auto-orient turns them upside up. -strip removes the orientation, so
    # they don't get turned again when displaying.
  print STDERR "Conv returned '$conv' \n" if ($conv); # Can this happen
  my $fsz = -s $savefile;
  print STDERR "Uploaded $fsz bytes into '$savefile' \n";
}

########################
# POST itself
sub postdata {
  error("Can not see $datafile") if ( ! -w $datafile ) ;


  my $sub = $q->param("submit") || "";

  # Input parameters, only used here in POST
  my $rec = inputrecord();  # Get an approximation of a record from the params

  $edit = $rec->{edit}; # Tell findrec what we are editing
  findrec(); # Get some defaults in $foundrec

  # Fix record type.
  $rec->{type} = "None" unless $rec->{type};
  if ( !$datalinetypes{$rec->{type} }) {
    error("Trying to POST a record of unknown type: '$rec->{type}'");
  }

  nullfields($rec);  # set all undefined fields to "", to avoid warnings
  my $lastrec = getrecord(scalar(@lines)-1);
  # dumprec($rec, "raw");

  fixtimes($rec, $lastrec, $sub);
  fixvol($rec, $sub);
  guessvalues($rec);
  if ( $rec->{newphoto} ) { # Uploaded a new photo
    savefile($rec);
  }

  my $lasttimestamp = $lastrec->{stamp};

  # Keep geo and loc unless explicitly changed
  # ( the js trickery can change these from under us)
  if ( $sub eq "Save" ) {
    if ( $rec->{loc} =~ /^ / && $foundrec->{loc} ){
      $rec->{loc} = $foundrec->{loc};
    }
    if ( $rec->{geo} =~ /^ / && $foundrec->{geo} ){
      $rec->{geo} = $foundrec->{geo};
    }
  }
  # Clean the location
  if ($rec->{loc}) {
    $rec->{loc} =~ s/ *\[.*$//; # Drop the distance from geolocation
  } else {
    $rec->{loc} = $foundrec->{loc}; # default to previous loc
  }


  # Manually entered date/time indicate we are filling the data after the fact
  # so do not trust the current geo coordinates
  if ( $sub eq "Record"  &&
      ($rec->{date} =~ /^\d/ || $rec->{time} =~ /^\d/ )
      && ( $rec->{geo} =~ /^ / )) {  # And geo is autofilled
    $rec->{geo} = "";   # Do not remember the suspicious location
  }

  # Sanity check, do not accept conflicting locations
  # Happens typically when entering data at home
  # TODO - Check also if we have a geo for the given location, and the guess is
  # too far from it, don't save a conflicting geo
  if ( $rec->{geo} =~ / *\d+/) { # Have a (guessed?) geo location
    if ( $rec->{loc} && $geolocations{$rec->{loc}} ) {
      my $dist = geodist( $rec->{geo}, $geolocations{$rec->{loc}} );
      if ( $dist && $dist > 50 ) {
        print STDERR "Refusing to store geo '$rec->{geo}' for '$rec->{loc}', " .
          "it is $dist m from its known location $geolocations{$rec->{loc}} '\n";
        $rec->{geo} = "";  # Ignore the suspect geo coords
      }
    }
    my  ($guess, $dist) = guessloc($rec->{geo});
    if ( $rec->{loc} && $guess  # We have location name, and geo guess
        && $dist < 20  # and the guess is good enough
        && $rec->{loc} !~ /$guess/i ) { # And they differ
      print STDERR "Refusing to store geo '$rec->{geo}' for '$rec->{loc}', " .
        "it is closer to '$guess' at $dist m\n";
      $rec->{geo} = "";  # Ignore the suspect geo coords
    }
  }

  # TODO - TZ


  (undef, undef, $rec->{geo})  = geo($rec->{geo});  # Skip bad ones, format right

  # Fix record type
  if ( $rec->{type} eq "Beer" && !$rec->{name} ) { # Not a real line
    print STDERR "Not POSTing record. t='$rec->{type}' n='$rec->{name}' \n";
    $rec->{type} = "None";
  }
  if ($rec->{subtype}) { # Convert subtypes like "Wine, Red" into rectype "Wine", subtype "Red"
    for  my $rt ( sort(keys(%datalinetypes)) ) {
      if ($rec->{subtype} =~ /^($rt) *, *(.*)$/ ) {
        $rec->{type} = $1;
        $rec->{subtype} = $2;
      }
    }
  }

  $rec->{edit} = "" unless defined($rec->{edit});
  $rec->{oldstamp} = $rec->{stamp}; # Remember the stamp for the edit link

  #dumprec($rec, "final");
  my $line = makeline($rec);
  #print STDERR "Saving $line \n";

  if ( $sub eq "Record" ) {  # Want to create a new record
    $rec->{edit} = ""; # so don't edit the current one
  }
  if ( $lasttimestamp gt $rec->{stamp} && $sub ne "Del" ) {
    $sub = "Save"; # force this to be an updating save, so the record goes into its right place
  }

  # Finally, save the line in the file
  if ( $sub ne "Save" && $sub ne "Del" ) { # Regular append
    if ( $line =~ /^[0-9]/ ) { # has at leas something on it
        open F, ">>$datafile"
          or error ("Could not open $datafile for appending");
        print F "$line\n"
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
      my ( $stp ) = $_ =~ /^([^;]*)/ ; # Just take the timestamp (or comment, or whatever)
      if ( $rec->{stamp} && $stp && $stp =~ /^\d+/ &&  # real line
           $sub eq "Save" && # Not deleting it
           "x$rec->{stamp}" lt "x$stp") {  # Right Place to insert the line
           # Note the "x" trick, to force pure string comparision
        print F "$line\n";
        $rec->{stamp} = ""; # do not write it again
      }
      if ( !$stp || $stp ne $rec->{edit} ) {
        print F $_; # just copy the line
      } else { # found the line
        print F "#" . $_ ;  # comment the original line out
        $edit = "XXX"; # Do not delete another line, even if same timestamp
      }
    }
    if ($rec->{stamp} && $sub eq "Save") {  # have not saved it yet
      print F "$line \n";  # (happens when editing latest entry)
    }
    close F
      or error("Error closing $datafile: $!");
    close BF
      or error("Error closing $bakfile: $!");
  }

  # Clear the cached files from the data dir.
  # All graphs for this user can now be out of date
  clearcachefiles();

  # if POSTing a restaurant, return to editing the record, so we can add
  # more relevant stuff like foods, people etc.
  my $editit = "";
  if ( $rec->{type} =~ /Restaurant|Night/i && $sub ne "Del" && $rec->{oldstamp}) {
    $editit = $rec->{oldstamp};
  }
  # Redirect to the same script, without the POST, so we see the results
  # But keep $op and $qry (maybe also filters?)
  print $q->redirect( "$url?o=$op&e=$editit&q=$qry#here" );

} # POST data

# Helper to clear the cached files from the data dir.
sub clearcachefiles {
  foreach my $pf ( glob($datadir."*") ) {
    next if ( $pf =~ /\.data$/ ); # .data files are the only really important ones
    next if ( -d $pf ); # Skip subdirs, if we have such
    if ( $pf =~ /\/$username.*png/ ||   # All png files for this user
         -M $pf > 7 ) {  # And any file older than a week
      unlink ($pf)
        or error ("Could not unlink $pf $!");
      }
  }
} # clearcachefiles


################################################################################
# HTML head
################################################################################

sub htmlhead {
  my $datafilecomment = shift || "";
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
  print "\n";
  print $datafilecomment;
} # htmlhead


# HTML footer
sub htmlfooter {
  print "</body></html>\n";
}




################################################################################
# Javascript trickery. Most of the logic is on the server side, but a few
# things have to be done in the browser.
################################################################################
sub javascript {
  my $script = "";

  # Debug div to see debug output on my phone
  $script .= <<'SCRIPTEND';
    function db(msg) {
      var d = document.getElementById("debug");
      if (d) {
        d.hidden = false;
        d.innerHTML += msg + "<br/>";
      }
    };
SCRIPTEND

  $script .= <<'SCRIPTEND';
    function clearinputs() {  // Clear all inputs, used by the 'clear' button
      var inputs = document.getElementsByTagName('input');  // all regular input fields
      for (var i = 0; i < inputs.length; i++ ) {
        if ( inputs[i].type == "text" )
          inputs[i].value = "";
      }
      const ids = [ "rate", "com" ];
      for ( var i = 0; i < ids.length; i++) {
        var r = document.getElementById(ids[i]);
        if (r)
          r.value = "";
      };

      // Hide the 'save' button, we are about to create a new entry
      var save = document.getElementById("save");
      save.hidden = true;  //

    };
SCRIPTEND

  # Simple script to show the normally hidden lines for entering date, time,
  # and geolocation
  $script .= <<'SCRIPTEND';
    function showrows() {
      var rows = [ "td1", "td2", "td3"];
      for (i=0; i<rows.length; i++) {
        var r = document.getElementById(rows[i]);
        //console.log("Unhiding " + i + ":" + rows[i], r);
        if (r) {
          r.hidden = ! r.hidden;
        }
      }
    };
SCRIPTEND

  # A simple two-liner to redirect to a new page from the 'Show' menu when
  # that changes
  $script .= <<'SCRIPTEND';
    var changeop = function(to) {
      document.location = to;
    };
SCRIPTEND

  # Show the fields for the current record type, and hide the rest
  # TODO - Kill this
  $script .= <<'SCRIPTEND';
    var showrecordtype= function(current) {
      if (current == "Old" ) { current = "" }; // show all sections
      var target = "type-" + current ;
      var rows = document.getElementById("inputformtable").rows;
      for ( var i = 0; i < rows.length-1; i++ ){
        var row = rows[i];
        var id = row.id;
        if ( id.startsWith("type-") ) {
          if (id && id.startsWith(target) ) {
            row.hidden = false;
          } else {
            row.hidden = true;
          }
        }
      } // i loop
    };
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

  $script .= "var origloc=\" $foundrec->{loc}\"; \n";

  $script .= <<'SCRIPTEND';
    var geoloc = "";

    function savelocation (myposition) {
      geoloc = " " + myposition.coords.latitude + " " + myposition.coords.longitude;
      var gf = document.getElementById("geo");
      if (! gf) {
        return;
      }
      console.log ("Geo field: '" + gf.value + "'" );
      if ( ! gf.value ||  gf.value.match( /^ / )) { // empty, or starts with a space
        var el = document.getElementsByName("geo");
        if (el) {
          for ( i=0; i<el.length; i++) {
            el[i].value=geoloc;
          }
        }
        console.log("Saved the location '" + geoloc + "' in " + el.length + " inputs");
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
          if ( origloc.trim() != bestloc.trim() ) {
            var of = document.getElementById("oldloc");
            of.hidden = false;  // display the original location
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

  # Take a photo
  $script .= <<'SCRIPTEND';
  function takephoto() {
    var inp = document.getElementsByName("newphoto");
    inp[0].click();
  }
SCRIPTEND

  print "<script>\n$script</script>\n";
}

################################################################################
# Main input form
################################################################################


# Helper to make an input field
#  print "<td><input name='flavor' value='$foundrec->{flavor}' $sz1 placeholder='Flavor' /></td>\n";
# Checks if this field should exist in $type kind of records. If not, returns ""
sub inputfield {
  my $fld = shift; # The field name
  my $size = shift; # Size of the field, maybe other attributes to add to it
  my $placeholder = shift || ucfirst($fld);
  $placeholder = "placeholder='$placeholder'" if ($placeholder);
  my $tag = shift || "td";
  my $value = shift || $foundrec->{$fld};
  my $colspan = shift || "";
  my $s = "";
  if (hasfield($type,$fld)) {
    $s .= "<$tag $colspan>" if ($tag);
    $s .= "<input name='$fld' value='$value' $size $placeholder />";
    $s .= "</$tag>" if ($tag);
    $s .= "\n";
  }
  return $s;
}

# Compute a summary we can show instead of a comment. We have 4 lines of
# plain text:
#  Today, or last day we have data. drinks, money, blood alc
#  Week, the last 7 days, including today: drinks dr/day, money, zero days
#  Last 30 days: drinks dr/day, money, zero days
#    The 30 days is not the same as the one in the graph, as that is a floating
#    average, but this is a linear average.
# TODO - Loop by days to get this right! See #369. Refactor the avg calculations
# from the graph code, and use the same here.
#
sub summarycomment {
  my $i = scalar(@lines)-1;
  my $last = getrecord($i);
  my $daylimit = $last->{effdate};
  my $weeklimit = datestr("%F", -7);
  my $monthlimit = datestr("%F", -30);
  my $daydr = 0;
  my $daysum = 0;
  my $weekdr = 0;
  my $weeksum = 0;
  my $monthdr = 0;
  my $monthsum = 0;
  my $curba = "";
  my $allgone = "";
  my $cureff = "";
  while ( $i >= 0 ) {
    my $going = 0;
    my $rec = getrecord($i);
    my ( $cba,$agne ) = bloodalcohol($i);
    if ( $cba ) {
      $curba = $cba;
      $allgone = $agne;
    }
    if ( $rec->{effdate} eq $daylimit ) {
      $daydr += $rec->{drinks};
      $daysum += $rec->{pr} if ($rec->{pr} > 0 );
    }
    if ( $rec->{effdate} gt $weeklimit ) {
       $weekdr += $rec->{drinks};
       $weeksum += $rec->{pr} if ($rec->{pr} > 0 );
       $going = 1;
    }
    if ( $rec->{effdate} gt $monthlimit ) {
       $monthdr += $rec->{drinks};
       $monthsum += $rec->{pr} if ($rec->{pr} > 0 );
       $going = 1;
    }
    #if ( $cureff ne $rec->{effdate} ) {
    #   $cureff = $rec->{effdate};
    #   print STDERR "sum: $i: $cureff ".
    #       sprintf( "%5d,- %6.2fd  / %5d,- %6.2fd \n",
    #          $weeksum, $weekdr,$monthsum,$monthdr);
    #}
    $i--;
    last unless $going;
  }
  my $balc = "";
  $balc = sprintf( "%4.2f‰", $bloodalc{$daylimit});
  my $dayline = sprintf("%3.1fd %d-  %s", $daydr, $daysum, $balc);
  if ( $daylimit eq $efftoday ){
    $dayline = "$last->{wday}: $dayline";
    if ( $curba ) {
      $dayline .= sprintf (" -> %4.2f‰ -> %s", $curba, $allgone );
    }
  } else {
    $dayline = "($last->{wday}: $dayline)"
  }
  my $weekline = sprintf("Week: %dd  (%3.1f/d) %d-", $weekdr, $weekdr/7, $weeksum);
  my $monthline = sprintf("30d: %dd  (%3.1f/d) %d-", $monthdr, $monthdr/30, $monthsum);
  return "$dayline\n".
         "$weekline\n".
         "$monthline";
}

sub inputform {
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
    print "<a href='$url?o=copyproddata'><span>Get production data</span></a></li> \n";

    print "<hr>\n";
  }


  # Make sure all fields are defined, for all possible record types
  # so we can show them in input forms without worrying about undef
  nullallfields($foundrec);  # TODO - Just nullfields($type) ?

  # Make sure we always have $type
  # and that it matched the record, if editing it
  if ( !$type || $edit ) {
    if ( $foundrec && $foundrec->{type} )  {
      $type = $foundrec->{type};
    } else {
      $type = "Old"; # Should not happen
    }
  }

  print "\n<form method='POST' accept-charset='UTF-8' class='no-print' " .
        "enctype='multipart/form-data'>\n";
  my $clr = "Onfocus='value=value.trim();select();' autocapitalize='words'";
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
  my $sz4n = "size='20'";
  my $sz4 = "$sz4n $clr";
  my $hidden = "";
  print "<table style='width:100%; max-width:500px' id='inputformtable'>";
  # Preprocess some fields
  # Note that $foundrec can be undef if we have no data at all (or edit url messed with)
  # That produces some warnings, but does not harm much
  my $geo = $foundrec->{geo};  # These fields may need adjustment before use
  my $loc = $foundrec->{loc};
  my $date = " $foundrec->{date}"; # Leading space marks as uncertain
  my $time = " $foundrec->{time}";
  my $prc = "$foundrec->{pr}.-";
  if ($edit) {
    print "<tr><td $c2><b>Record '$edit'</b></td></tr>\n";
    ($date,$time) = $edit =~ /^([0-9-]+) ([0-9]+:[0-9]+:[0-9]+)/ ;
    if (!$geo) {
      $geo = "x";  # Prevent autofilling current geo
    }
  } else {
    $geo = " $geo"; # Allow more recent geolocations
    $hidden = "hidden"; # Hide the geo and date fields for normal use
    $loc = " $loc"; # Mark it as uncertain
  }
  # Taking a photo. Usually hidden
  if (hasfield($type,"photo") ) {
    print "<tr id='td1' $hidden >\n";
    print "<td $c6>\n";
    print "<input type='button' onclick='takephoto()' value='Photo' />\n";
    print "$foundrec->{photo}  ";
    print "<input type='hidden' name='photo' value='$foundrec->{photo}' />\n";
    print "<input type='file' name='newphoto' accept='image/*' capture='camera' hidden /> \n";
    # No broweser accepts a value for the file browser, considered unsafe. Fix in POST
    print "</td>\n";
    print "</tr>\n";
  }

  # Date and time, usually hidden
  print "<tr id='td2' $hidden ><td>\n";
  print "<input name='edit' type='hidden' value='$foundrec->{stamp}' id='editrec' />\n";
  print "<input name='o' type='hidden' value='$op' id='editrec' />\n";
  print "<input name='q' type='hidden' value='$qry' id='editrec' />\n";
  print "<input name='date' value='$date' $sz1 placeholder='" . datestr ("%F") . "' /></td>\n";
  print "<td><input name='time' value='$time' $sz3 placeholder='" .  datestr ("%H:%M",0,1) . "' /></td>\n";
  print "</tr>\n";

  # Geolocation
  print "<tr id='td3' $hidden ><td $c2>\n";
  print inputfield("geo", $sz4, "Geo", "nop", $geo );
  my $chg = "onchange='document.location=\"$url?type=\"+this.value+\"&o=$op&q=$qry\"' ";
  # Disabling the field here is no good, when re-enabled, will not get transmitted !!??
  $chg = "" if ($edit); # Don't move around while editing
  print "&nbsp;<select name='type' $chg style='width:4.5em;' id='type'>\n";
  foreach my $t ( sort(keys(%datalinetypes)) ) {
    next if ($t eq "Old");
    my $sel = "";
    $sel = "selected='selected'" if ( $type eq $t );
    print "<option value='$t' $sel>$t</option>\n";
  }
  print "</select>\n";
  print "</td></tr>\n";

  # Actual location and record type, normally hidden
  print "<tr id='td4' $hidden >";
  print "<td>($foundrec->{type})</td>\n" if ($foundrec->{type} ne $type);
  print "</tr>\n";

  # Location
  print "<tr>\n";
  print inputfield("loc","$sz1 id='loc'","Location", "", $loc);
  print "<td>";
  print "<span id='oldloc' hidden>($foundrec->{loc})</span>\n"; # without geo overwriting it.
  print "&nbsp; &nbsp; <span onclick='showrows();'  align=right>&nbsp; ^</span>";
  print "</td></tr>\n";

  # Type, subtype, and style (flavor, coctail, country/region, etc)
  print "<tr><td>$type\n";
  #print inputfield("subtype", $sz3, "", "nop");
  print inputfield("subtype", "size=10 $clr", "", "nop");
  print "</td>";
  print inputfield("style", $sz1, "Style");
  print "</tr>\n";

  # Maker and name, for most drinks
  print "<tr>\n";
  print inputfield("maker", $sz1);
  print inputfield("name", $sz1);
  print "</tr>\n";


  # General stuff again: Vol, Alc and Price, as well as rating
  # Also restaurant type (instead of Alc and Vol)
  print "<tr><td>";
  print inputfield("vol", $sz2, "Vol", "nop", "$foundrec->{vol} cl" );
  print inputfield("alc", $sz2, "Alc", "nop", "$foundrec->{alc} %" );
  print inputfield("pr",  $sz2, "Price", "nop", "$prc" );

  print "<td>";
  if (hasfield($type,'rate')) {
    print "<select name='rate' id='rate' value='$foundrec->{rate}' placeholder='Rating' style='width:4.5em;'>\n";
    print "<option value=''>Rate</option>\n";
    for my $ro (1 .. scalar(@ratings)-1) {
      print "<option value='$ro'" ;
      print " selected='selected'" if ( $ro eq $foundrec->{rate} );
      print  ">$ro $ratings[$ro]</option>\n";
    }
    print "</select>\n";
  }
  print "</td></tr>\n";

  # For type Restaurant: Food
  if (hasfield($type,'food')) {
    print "<tr>";
    print inputfield("food", $sz4, "Food and Drink", "", "", $c2 );
    print "</tr>\n";
  }

  # For types Night and Restaurant: people
  if (hasfield($type,'people')) {
    print "<tr>";
    print inputfield("people", $sz4, "People", "", "", $c2 );
    print "</tr>\n";
  }

  # Comments
  if (hasfield($type,'com')) {
    my $placeholder = summarycomment();
    print "<tr>";
    print " <td $c6><textarea name='com' cols='45' rows='3' id='com'
      placeholder='$placeholder' autocapitalize='sentences'>$foundrec->{com}</textarea></td>\n";
    print "</tr>\n";
  }

  print "<tr><td>\n";  # Buttons
  if ($edit) {
    print " <input type='submit' name='submit' value='Save' id='save' />\n";
    print " <input type='submit' name='submit' value='Del'/>\n";
    print "<a href='$url?o=$op' ><span>cancel</span></a>";
    print "</td><td>\n";
  } else {
    print "<input type='submit' name='submit' value='Record'/>\n";
    print " <input type='submit' name='submit' value='Save' id='save' />\n";
    print "</td><td>\n";
    print " <input type='button' value='Clr' onclick='getlocation();clearinputs()'/>\n";
  }
  print " <select  style='width:4.5em;' " .
              "onchange='document.location=\"$url?\"+this.value;' >";
  print "<option value='' >Show</option>\n";
  print "<option value='o=full&q=$qry' >Full List</option>\n";
  print "<option value='o=Graph&q=$qry' >Graph</option>\n";
  print "<option value='o=board&q=$qry' >Beer Board</option>\n";
  print "<option value='o=Months&q=$qry' >Stats</option>\n";
    # All the stats pages link to each other
  print "<option value='o=Beer&q=$qry' >Beers</option>\n";
    # The Beer list has links to locations, wines, and other such lists
  print "<option value='o=About' >About</option>\n";
  print "</select>\n";
  print  " &nbsp; &nbsp; &nbsp;";
  if ( $op && $op !~ /graph/i ) {
    print "<a href='$url'><b>G</b></a>\n";
  } else {
    print "<a href='$url?o=board'><b>B</b></a>\n";
  }
  print "</td>";
  print "</tr>\n";

  print "</table>\n";
  print "</form>\n";

  print "<div id='debug' hidden ><hr/>Debug<br/></div>\n"; # for javascript debugging
} # inputform

################################################################################
# Graph
################################################################################

sub graph {
  if ( @records && # Have data
       ($op =~ /Graph([BSX]?)-?(\d+)?-?(-?\d+)?/i || $op =~ /Board/i)) {
    my $defbig = $mobile ? "S" : "B";
    my $bigimg = $1 || $defbig;
    my $startoff = $2 || 30; # days ago
    my $endoff = $3 || -1;  # days ago, -1 defaults to tomorrow
    my $imgsz="320,250";
    my $reload = "";
    if ( $bigimg eq "X" ) {
      $reload = 1;
      $bigimg = $defbig;
    }
    if ( $bigimg eq "B" ) {  # Big image
      $imgsz = "640,480";
    }
    my $startdate = datestr ("%F", -$startoff );
    my $enddate = datestr( "%F", -$endoff);
    my $prestartdate = datestr( "%F", -$startoff-40);
    my $havedata = 0;
    my $futable = ""; # Table to display the 'future' values

    # Normalize limits to where we have data
    getrecord(0);
    while ( $startdate lt $records[0]->{date}) {
      $startoff --;
      $startdate = datestr ("%F", -$startoff );
      if ($endoff >= 0 ) {
        $endoff --;
        $enddate = datestr( "%F", -$endoff);
      }
    }

    my $pngfile = $plotfile;
    $pngfile =~ s/.plot$/-$startdate-$enddate-$bigimg.png/;

    if (  -r $pngfile && !$reload ) { # Have a cached file
      print "\n<!-- Cached graph op='$op' $pngfile -->\n";
    } else { # Have to plot a new one

      my %sums; # drink sums by (eff) date # TODO - Don't calculate the whole history
      my %lastdateindex;
      for ( my $i = scalar(@records)-1; $i >= 0; $i-- ) { # calculate sums
        my $rec = getrecord($i);
        #nullallfields($rec);
        next if ( $rec && $rec->{type} =~ /^Restaurant/i ); # TODO Fails on a tz? line
        next unless ($rec->{alcvol});
        $sums{$rec->{effdate}} += $rec->{alcvol};
        $lastdateindex{$rec->{effdate}} = $i unless ( $lastdateindex{$rec->{effdate}} );
        last if ( $rec->{effdate} lt $prestartdate );
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
      my $maxd = 0;
      while ( $ndays > $endoff) {
        $ndays--;
        my $rawdate = datestr("%F:%u", -$ndays);
        ($date,$wkday) = split(':',$rawdate);
        my $tot = ( $sums{$date} || 0 ) / $onedrink ;
        $maxd = $tot if ( $tot > $maxd && $date ge $startdate);
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

        # Collect drink types into $drinkline ready for plotting
        my $drinkline = "";
        my $totdrinks = $tot;
        my $ndrinks = 0;
        if ( $lastdateindex{$date} ) {
          my $i = $lastdateindex{$date};
          my $lastrec = getrecord($i);
          my $lastloc = $lastrec->{loc};
          my $lasteff = $lastrec->{effdate};
          while ( $records[$i]->{effdate} eq $date ) {
            my $drec = $records[$i];
            if ( $drec->{alcvol} ) {
              my $color = beercolor($drec,"0x");
              my $drinks = $drec->{alcvol} / $onedrink;
              if ( $lastloc ne $drec->{loc}  &&  $startoff - $endoff < 100 ) {
                my $lw = $totdrinks + 0.2; # White line for location change
                $lw += 0.1 unless ($bigimg eq "B");
                $drinkline .= "$lw 0xffffff ";
                $lastloc = $drec->{loc};
                $ndrinks++;
              }
              $drinkline .= "$totdrinks $color ";
              $ndrinks ++;
              $totdrinks -= $drinks;
              last if ($totdrinks <= 0 ); #defensive coding, have seen it happen once
            }
            $i--;
          }

        }
        print STDERR "Many ($ndrinks) drink entries on $date \n"
          if ( $ndrinks >= 20 ) ;
        while ( $ndrinks++ < 20 ) {
          $drinkline .= "0 0x0 ";
        }

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
        if ( $bigimg eq "B" ) {  # Big image
          $maxd = $maxd *7 + 4; # Make room at the top of the graph for the legend
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
          $maxd = $maxd *7 + 8; # Make room at the top of the graph for the legend
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
            "set yrange [ -.5 : $maxd ] \n" .
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
              "behind fc \"#003000\" fillstyle solid border \n";  # green bkg
        for (my $m=20; $m<$maxd-7; $m+= 21) {
          $cmd .= "set arrow from \"$startdate\", $m to \"$enddate\", $m nohead linewidth 1 linecolor \"#00dd10\" \n"
            if ( $maxd > $m + 7 );
        }
        $cmd .=
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
    my ( $imw,$imh ) = $imgsz =~ /(\d+),(\d+)/;
    my $htsize = "width=$imw height=$imh" if ($imh) ;
    if ($bigimg eq "B") {
      print "<a href='$url?o=GraphS-$startoff-$endoff'><img src=\"$pngfile\" $htsize/></a><br/>\n";
    } else {
      print "<a href='$url?o=GraphB-$startoff-$endoff'><img src=\"$pngfile\" $htsize/></a><br/>\n";
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
  } # have data
} # graph


################################################################################
# Beer board (list) for the location.
# Scraped from their website
################################################################################

sub beerboard {
  my $extraboard = -1; # Which of the entries to open, or -1 current, -2 for all, -3 for none
  if ( $op =~ /board(-?\d+)/i ) {
    $extraboard = $1;
  }
  my $locparam = param("loc") || $foundrec->{loc} || "";

  # Set up %seen and %lastseen, for the past 2 years
  getseen(datestr( "%F", -3*365 )) unless ( $extraboard < -1 );

  $locparam =~ s/^ +//; # Drop the leading space for guessed locations
  print "<hr/>\n"; # Pull-down for choosing the bar
  print "\n<form method='POST' accept-charset='UTF-8' style='display:inline;' class='no-print' >\n";
  print "Beer list \n";
  print "<select onchange='document.location=\"$url?o=board&loc=\" + this.value;' style='width:5.5em;'>\n";
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
  print "&nbsp; (<a href='$url?o=$op&loc=$locparam&q=PA'><span>PA</span></a>) "
    if ($qry ne "PA" );

  print "<a href=$url?o=board&loc=$locparam&f=f><i>(Reload)</i></a>\n";
  print "<a href=$url?o=board-2&loc=$locparam><i>(all)</i></a>\n";

  print "<p>\n";
  if (!$scrapers{$locparam}) {
    print "Sorry, no  beer list for '$locparam' - showing 'Ølbaren' instead<br/>\n";
    $locparam="Ølbaren"; # A good default
  }

  my $script = $scriptdir . $scrapers{$locparam};
  my $cachefile = $datadir . $scrapers{$locparam};
  $cachefile =~ s/\.pl/.cache/;
  my $json = "";
  my $loaded = 0;
  if ( -f $cachefile
       && (-M $cachefile) * 24 * 60 < 20    # age in minutes
       && -s $cachefile > 256    # looks like a real file
       && $qrylim ne "f" ) {
    open CF, $cachefile or error ("Could not open $cachefile for reading");
    while ( <CF> ) {
      $json .= $_ ;
    }
    close CF;
  }
  if ( !$json ){
    $json = `perl $script`;
    $loaded = 1;
  }
  if (! $json) {
    print "Sorry, could not get the list from $locparam<br/>\n";
    print "<!-- Error running " . $scrapers{$locparam} . ". \n";
    print "Result: '$json'\n -->\n";
  }else {
    if ($loaded) {
      open CF, ">$cachefile" or error( "Could not open $cachefile for writing");
      print CF $json;
      close CF;
    }
    chomp($json);
    #print "<!--\nPage:\n$json\n-->\n";  # for debugging
    my $beerlist = JSON->new->utf8->decode($json)
      or error("Json decode failed for $scrapers{$locparam} <pre>$json</pre>");
    my $nbeers = 0;
    if ($qry) {
    print "Filter:<b>$qry</b> " .
      "(<a href='$url?o=$op&loc=$locparam'><span>Clear</span></a>) " .
      "<p>\n";
    }
    my $oldbeer = "$foundrec->{maker} : $foundrec->{name}";  # Remember current beer for opening
    $oldbeer =~ s/&[a-z]+;//g;  # Drop things like &amp;
    $oldbeer =~ s/[^a-z0-9]//ig; # and all non-ascii characters

    print "<table border=0 style='white-space: nowrap;'>\n";
    my $previd  = 0;
    foreach my $e ( sort {$a->{"id"} <=> $b->{"id"} } @$beerlist )  {
      $nbeers++;
      my $id = $e->{"id"} || 0;
      my $mak = $e->{"maker"} || "" ;
      my $beer = $e->{"beer"} || "" ;
      my $sty = $e->{"type"} || "";
      my $loc = $locparam;
      my $alc = $e->{"alc"} || "";
      $alc = sprintf("%4.1f",$alc) if ($alc);
      my $seenkey = seenkey($mak,$beer);
      if ( $qry ) {
        next unless ( "$sty $mak $beer" =~ /$qry/i );
      }

      if ( $id != $previd +1 ) {
        print "<tr><td align=right>&nbsp;</td><td align=right>. . .</td></tr>\n";
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
        $dispmak = filt($mak, "i", $dispmak,"board&loc=$locparam","maker");
      }
      $beer =~ s/(Warsteiner).*/$1/;  # Shorten some long beer names
      $beer =~ s/.*(Hopfenweisse).*/$1/;
      $beer =~ s/.*(Ungespundet).*/$1/;
      if ( $beer =~ s/Aecht Schlenkerla Rauchbier[ -]*// ) {
        $mak = "Schlenkerla";
        $dispmak = filt($mak, "i", $mak,"board&loc=$locparam");
      }
      my $dispbeer .= filt($beer, "b", $beer, "board&loc=$loc");

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
        $hiddenbuttons .= "<input type='hidden' name='type' value='Beer' />\n" ;  # always?
        $hiddenbuttons .= "<input type='hidden' name='subtype' value='$country' />\n" ;  # always?
        $hiddenbuttons .= "<input type='hidden' name='maker' value='$mak' />\n" ;
        $hiddenbuttons .= "<input type='hidden' name='name' value='$beer' />\n" ;
        $hiddenbuttons .= "<input type='hidden' name='style' value='$origsty' />\n" ;
        $hiddenbuttons .= "<input type='hidden' name='alc' value='$alc' />\n" ;
        $hiddenbuttons .= "<input type='hidden' name='loc' value='$loc' />\n" ;
        $hiddenbuttons .= "<input type='hidden' name='o' value='board' />\n" ;  # come back to the board display
      my $buttons="";
      foreach my $sp ( sort( {$a->{"vol"} <=> $b->{"vol"}} @$sizes) ) {
        my $vol = $sp->{"vol"};
        my $pr = $sp->{"price"};
        my $lbl;
        if ($extraboard == $id || $extraboard == -2) {
          $lbl = "$vol cl: $pr.- \n";
          $lbl .= sprintf( "%d/l ", $pr * 100 / $vol );
          $lbl .= sprintf( "%3.1fd", $vol * $alc / $onedrink);
        } else {
          $lbl = "$pr.-";
          $buttons .= "<td>";
        }
        $buttons .= "<form method='POST' accept-charset='UTF-8' style='display: inline;' class='no-print' >\n";
        $buttons .= $hiddenbuttons;
        $buttons .= "<input type='hidden' name='vol' value='$vol' />\n" ;
        $buttons .= "<input type='hidden' name='pr' value='$pr' />\n" ;
        $buttons .= "<input type='submit' name='submit' value='$lbl'/> \n";
        $buttons .= "</form>\n";
        $buttons .= "</td>\n" if ($extraboard != $id && $extraboard != -2);
      }
      my $beerstyle = beercolorstyle($origsty, "Board:$e->{'id'}", "[$e->{'type'}] $e->{'maker'} : $e->{'beer'}" );

      if ($extraboard == $id  || $extraboard == -2) { # More detailed view
        print "<tr><td colspan=5><hr></td></tr>\n";
        print "<tr><td $beerstyle>";
        my $linkid = $id;
        if ($extraboard == $id) {
          $linkid = "-3";  # Force no expansion
        }
        print "<a href='$url?o=board$linkid&loc=$locparam'><span width=100% $beerstyle id='here'>$id</span></a> ";
        print "</td>\n";

        print "<td colspan=4 >";
        print "<span style='white-space:nowrap;overflow:hidden;text-overflow:clip;max-width=100px'>\n";
        print "$mak: $dispbeer <span style='font-size: x-small;'>($country)</span></span></td></tr>\n";
        print "<tr><td>&nbsp;</td><td colspan=4> $buttons &nbsp;\n";
        print "<form method='POST' accept-charset='UTF-8' style='display: inline;' class='no-print' >\n";
        print "$hiddenbuttons";
        print "<input type='hidden' name='vol' value='T' />\n" ;  # taster
        print "<input type='hidden' name='pr' value='X' />\n" ;  # at no cost
        print "<input type='submit' name='submit' value='Taster\n ' /> \n";
        print "</form>\n";
        print "</td></tr>\n";
        print "<tr><td>&nbsp;</td><td colspan=4>$origsty <span style='font-size: x-small;'>$alc%</span></td></tr> \n";
        my $seenline = seenline ($mak, $beer);
        if ($seenline) {
          print "<tr><td>&nbsp;</td><td colspan=4> $seenline";
          print "</td></tr>\n";
        }
        if ($ratecount{$seenkey}) {
          my $avgrate = sprintf("%3.1f", $ratesum{$seenkey}/$ratecount{$seenkey});
          print "<tr><td>&nbsp;</td><td colspan=4>";
          my $rating = "rating";
          $rating .= "s" if ($ratecount{$seenkey} > 1 );
          print "$ratecount{$seenkey} $rating <b>$avgrate</b>: ";
          print $ratings[$avgrate];
        print "</td></tr>\n";
        }
        print "<tr><td colspan=5><hr></td></tr>\n" if ($extraboard != -2) ;
      } else { # Plain view
        print "<tr><td align=right $beerstyle>";
        print "<a href='$url?o=board$id&loc=$locparam#here'><span width=100% $beerstyle>$id</span></a> ";
        print "</td>\n";
        print "$buttons\n";
        print "<td style='font-size: x-small;' align=right>$alc</td>\n";
        print "<td>$dispbeer $dispmak ";
        print "<span style='font-size: x-small;'>($country)</span> $sty</td>\n";
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
} # beerboard

################################################################################
# Short list, aka daily statistics
################################################################################

sub shortlist{
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
  print "<a href='$url?o=DataStats'><span>Datafile</span></a>&nbsp;\n";
  print "<hr/>\n";
  print "<a href='$url?o=$op'><span>(Recent)</span></a>&nbsp;\n";
  for ( my $y = datestr("%Y"); $y >= 2016; $y-- ) {
    my $tag = "span";
    $tag = "b" if ( $yrlim eq $y );
    print "<a href='$url?o=$op&y=$y'><$tag>$y</$tag></a>&nbsp;\n";
  }
  print "<a href='$url?o=$op&maxl=-1'><span>(all)</span></a>&nbsp;\n";
  print "<hr/>\n";
  my $filts = splitfilter($qry);
  print "Filter: <b>$yrlim $filts</b> (<a href='$url?o=short'><span>Clear</span></a>)" .
    "&nbsp;(<a href='$url?q=$qry'><span>Full</span></a>)<hr/>" if ($qry||$yrlim);
  print searchform(). "<hr/>" if $qry;
  my $i = scalar( @lines );
  while ( $i > 0 ) {
    $i--;
    if ( $yrlim ) {  # Quick filter on the year, without parsing
      next if ( $lines[$i] !~ /^$yrlim/ );
    }
    my $rec = getrecord($i);
    next if filtered ( $rec ); # TODO - Does this make any sense
    if ( $i == 0 ) {
      $lastdate = "";
      if (!$entry) { # make sure to count the last entry too
        $entry = filt($rec->{effdate}, "") . " " . $rec->{wday} ;
        $daysum += $rec->{alcvol};
        $daymsum += $rec->{pr} if ( $rec->{pr} > 0 );
        if ( $places !~ /$rec->{loc}/ ) {
          $places .= " " . filt($rec->{loc}, "", $rec->{loc}, "short");
          $locseen{$rec->{loc}} = 1;
        }
      }
    }
    if ( $lastdate ne $rec->{effdate} ) {
      if ( $entry ) {
        my $daydrinks = sprintf("%3.1f", $daysum / $onedrink) ;
        $entry .= " " . unit($daydrinks,"d") . " " . unit($daymsum,".-");
        $entry .= " " . unit(sprintf("%0.2f",$bloodalc{$lastdate}), "‰")
          if ( ( $bloodalc{$lastdate} || 0 ) > 0.01 );
        print "<span style='white-space: nowrap'>$entry";
        print "$places</span><br/>\n";
        $maxlines--;
        last if ($maxlines == 0); # if negative, will go for ever
        last if ( $lines[$i] lt $yrlim );  # Past the selected year
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
            $zerodate = $rec->{effdate}; # force the loop to end
          }
        } while ( $zerodate gt $rec->{effdate} && $i > 1);
        $ndays-=3;
        if ( $ndays == 1 ) {
          print ". . . <br/>\n";
        } elsif ( $ndays > 1) {
          print ". . . ($ndays days) . . .<br/>\n";
        }
      }
      my $thismonth = substr($rec->{effdate},0,7); #yyyy-mm
      my $bold = "";
      if ( $thismonth ne $month ) {
        $bold = "b";
        $month = $thismonth;
      }
      my $wday = $rec->{wday};
      $wday = "<b>$wday</b>" if ($wday =~ /Fri|Sat|Sun/);  # mark wkends
      $entry = filt($rec->{effdate}, $bold) . " " . $wday ;
      $places = "";
      $lastdate = $rec->{effdate};
      $lastloc = "";
      $daysum = 0.0;
      $daymsum = 0.0;
    }
    next if ($rec->{type} eq "Restaurant" );
    if ( $lastloc ne $rec->{loc} ) {
      # Abbreviate some location names
      my $sloc=$rec->{loc};
      for my $k ( keys(%shortnames) ) {  # TODO - no need to scan
        my $s = $shortnames{$k};
        $sloc =~ s/$k/$s/i;
      }
      $sloc =~ s/ place$//i;  # Dorthes Place => Dorthes
      $sloc =~ s/ /&nbsp;/gi;   # Prevent names breaking in the middle
      if ( $places !~ /$sloc/ ) {
        $places .= "," if ($places);
        $places .= " " . filt($rec->{loc}, "", $sloc, "short", "loc");
        $locseen{$rec->{loc}} = 1;
        }
      $lastloc = $sloc;
    }
    $daysum += $rec->{'alcvol'};
    $daymsum += $rec->{pr} if ( $rec->{pr} > 0 );
  }
} # Short list

################################################################################
# Annual summary
################################################################################

sub yearsummary {
  my $sortdr = shift;
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
  print "<a href='$url?o=DataStats'><span>Datafile</span></a>&nbsp;\n";
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
} # yearsummary

################################################################################
# Monthly statistics
# from %monthdrinks and %monthprices
################################################################################

sub monthstat {
  my $defbig = $mobile ? "S" : "B";
  my $bigimg = shift || $defbig;
  $bigimg =~ s/S//i ;
  print "<hr/>Other stats: \n";
  print "<a href='$url?o=short'><span>Days</span></a>&nbsp;\n";
  print "<a href='$url?o=Months'><b>Months</b></a>&nbsp;\n";
  print "<a href='$url?o=Years'><span>Years</span></a>&nbsp;\n";
  print "<a href='$url?o=DataStats'><span>Datafile</span></a>&nbsp;\n";
  print "<hr/>\n";

  if ( getrecord(0)->{date} !~ /^(\d\d\d\d)/ ) { # Should not happen
    print "Oops, no start year found <br/>\n";
    return;
  }

  # Collect stats
  my %monthdrinks;
  my %monthprices;
  my $lastmonthday;  # last day of the last month
  for ( my $i = 0 ; $i < scalar(@lines); $i++ ) {
    my $rec = getrecord($i);
    next unless ($rec);
    if ( $rec->{effdate} =~ /(^\d\d\d\d-\d\d)-(\d\d)/ )  { # collect stats for each month
      my $calmon = $1;
      $monthdrinks{$calmon} += $rec->{alcvol};
      $monthprices{$calmon} += abs($rec->{pr}); # negative prices for buying box wines
      $lastmonthday = $2;  # Remember the last day
    }
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
        $d = ($monthdrinks{$calm}||0) / $onedrink;
        $dd = sprintf("%3.1f", $d / 30); # scale to dr/day, approx
        if ( $calm eq $lastym ) { # current month
          $dd = sprintf("%3.1f", $d / $dayofmonth); # scale to dr/day
          $d = "~" . unit($dd,"/d");
          $ydays[$y] += $dayofmonth - 30;
        } else {
          $dd = sprintf("%3.1f", $d / 30); # scale to dr/day, approx
          if ( $dd < 10 ) {
            $d = unit($dd,"/d"); #  "9.3/d"
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
  my $curmonth = datestr("%Y-%m",0);
  my $d = ($monthdrinks{$curmonth}||0) / $onedrink ;
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
      $d = sprintf("%3.1f", $ydrinks[$y] / $ydays[$y] / $onedrink) ;
      $dw = $1 if ($d=~/([0-9.]+)/);
      $dw = unit(int($dw*7+0.5), "/w");
      $d = unit($d, "/d");
      $p = int(30*$yprice[$y]/$ydays[$y]+0.5);
      $grandprice += $yprice[$y];
    }
    $t .= "<td align=right>$d<br/>$dw<br/>$p</td>\n";
  }
  $d = sprintf("%3.1f", $granddr / $granddays / $onedrink) ;
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
      $pr = unit(sprintf("%5.0f", ($yprice[$y]+500)/1000), " k") ;
      $grandtot += $yprice[$y];
    }
    $t .= "<td align=right>$pr";
    if ( $y eq $lasty && $yprice[$lasty] ) {
      $pr = $yprice[$lasty] / $ydays[$lasty] * 365;
      $pr = unit(sprintf("%5.0f", ($pr+500)/1000), " k") ;
      $pr =~ s/^ *//;  # Remove leading space
      $t .= "<br/>~$pr";
    }
    $t .= "</td>\n";
  }
  $grandtot = unit(sprintf("%5.0f",($grandtot+500)/1000), " k");
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
# Statistics of the data file
################################################################################
sub datastats {
  print "<hr/>Other stats: \n";
  print "<a href='$url?o=short'><span>Days</span></a>&nbsp;\n";
  print "<a href='$url?o=Months'><span>Months</span></a>&nbsp;\n";
  print "<a href='$url?o=Years'><span>Years</span></a>&nbsp;\n";
  print "<a href='$url?o=DataStats'><b>Datafile</b></a>&nbsp;\n";
  print "<hr/>\n";

  print "<table>\n";
  print "<tr><td></td><td><b>Data file</b></td></tr>\n";
  print "<tr><td></td><td> $datafile </td></tr>\n";
  my $dfsize = -s $datafile;
  $dfsize = int($dfsize / 1024);
  print "<tr><td align='right'>$dfsize</td><td>kb</td></tr>\n";
  my $datarecords = scalar(@records);
  my $totallines = $datarecords + $commentlines + $commentedrecords;
  print "<tr><td align='right'>$totallines</td><td> lines</td></tr>\n";
  print "<tr><td align='right'>$commentlines</td><td> lines of comments</td></tr>\n";
  print "<tr><td align='right'>$commentedrecords</td><td> record lines commented out</td></tr>\n";
  print "<tr><td align='right'>$datarecords</td><td> real data records</td></tr>\n";

  my %rectypes;
  my %distinct;
  my %seen;
  my $oldrecs = 0;
  my $badrecs = 0;
  my $comments = 0;
  my @rates = ( 0,0,0,0,0,0,0,0,0,0 );
  my $ratesum = 0;
  my $ratecount = 0;

  for ( my $i = 0 ; $i < scalar(@lines); $i++) {
    my $rec = getrecord($i);
    if ( ! $rec ) {
      $badrecs++;
      next;
    }
    my $rt = $rec->{type};
    $rectypes{$rt} ++;
    $oldrecs ++ if ( $rec->{rawline} !~ /; *$rt *;/ );
    $comments++ if ( $rec->{com} );
    if (defined($rec->{rate}) && $rec->{rate} =~ /\d/ ) {
      $rates[ $rec->{rate} ] ++;
      $ratesum += $rec->{rate};
      $ratecount++;
    }
    if ( ! $seen{$rec->{seenkey}} ) {
      $seen{$rec->{seenkey}} = 1;
      $distinct{$rec->{type}}++;
    }
  }
  print "<tr><td align='right'>$oldrecs</td><td> old type lines</td></tr>\n";
  print "<tr><td>&nbsp;</td></tr>\n";
  print "<tr><td>&nbsp;</td><td><b>Record types</b></td></tr>\n";
  foreach my $rt ( sort  { $rectypes{$b} <=> $rectypes{$a} } keys(%rectypes) )  {
    print "<tr><td align='right'>$rectypes{$rt}</td>" .
    "<td> $rt ($distinct{$rt} different)</td></tr>\n";
  }
  if ( $badrecs ) {
    print "<tr><td align='right'>$badrecs</td><td>Bad</td></tr>\n";
  }
  print "<tr><td>&nbsp;</td></tr>\n";
  print "<tr><td>&nbsp;</td><td><b>Ratings</b></td></tr>\n";
  my $i = 1;
  while ( $ratings[$i] ){
    print "<tr><td align='right'>$rates[$i]</td><td>'$ratings[$i]' ($i)</td></tr>\n";
    $i++;
  }
  my $avg = sprintf("%3.1f", $ratesum / $ratecount);
  print "<tr><td align='right'>$ratecount</td><td>Records with ratings</td></tr>\n";
  print "<tr><td align='right'>$avg</td><td>Average rating</td></tr>\n";
  print "<tr><td align='right'>$comments</td><td>Records with comments</td></tr>\n";

  print "</table>\n";
}


################################################################################
# About page
################################################################################

sub about {
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

  print "Shorthand for drink volumes<br/><ul>\n";
  for my $k ( sort { $volumes{$a} cmp $volumes{$b} } keys(%volumes) ) {
    print "<li><b>$k</b> $volumes{$k}</li>\n";
  }
  print "</ul>\n";
  print "You can prefix them with 'h' for half, as in HW = half wine = 37cl<br/>\n";
  print "Of course you can just enter the number of centiliters <br/>\n";
  print "Or even ounces, when traveling: '6oz' = 18 cl<br/>\n";

  print "<p><hr>\n";
  print "This site uses no cookies, and collects no personally identifiable information<p>\n";


  print "<p><hr/>\n";
  print "<b>Debug info </b><br/>\n";
  print "&nbsp; <a href='$url?o=Datafile&maxl=30' target='_blank' ><span>Tail of the data file</span></a><br/>\n";
  print "&nbsp; <a href='$url?o=Datafile'  target='_blank' ><span>Download the whole data file</span></a><br/>\n";
  print "&nbsp; <a href='$url?o=geo'><span>Geolocation debug</span></a><br/>\n";
  exit();
} # About


################################################################################
# Geolocation debug
################################################################################

sub geodebug {
  if (!$qry || $qry =~ /^ *[0-9 .]+ *$/ ) {  # numerical query
    print "<hr><b>Geolocations</b> since $notbef<p>\n";
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
    print "<hr/>\n" ;

  } else { # loc given, list all occurrences of that location
    print "<hr/>Geolocation for <b>$qry</b> &nbsp;";
    print "<a href='$url?o=geo'><span>Back</span></a>";
    print "<p>\n";
    my (undef,undef,$defloc) = geo($geolocations{$qry});
    print "$qry is at: $defloc <p>\n" if ($defloc);
    print "<table>\n";
    print "<tr><td>Latitude</td><td>Longitude</td><td>Dist</td></tr>\n";
    my $i = scalar( @records );
    while ( $i-- > 0 ){
      my $rec = $records[$i];
      next unless $rec->{geo};
      next unless ($rec->{loc} eq $qry);
      my ($la, $lo, $g) = geo($rec->{geo});
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
      print "<td><a href='$url?o=$op&q=$qry&e=$rec->{stamp}' ><span>$rec->{stamp}</span></a> ";
      if ($guess) {
        print "<br>(<b>$guess $gdist ?)</b>\n" ;
        print STDERR "Suspicious Geo: '$rec->{loc}' looks like '$guess'  for '$g' at '$rec->{stamp}' \n";
      }
      print "</td>\n";
      print "</tr>\n";
    }
    print "</table>\n";
  }
}  # Geo debug


################################################################################
# various lists (beer, location, etc)
################################################################################
sub lists {
  print "<hr/><b>$op list</b>\n";
  print "<br/><div class='no-print'>\n";
  my $filts = splitfilter($qry);
  print "Filter: $filts " .
     "(<a href='$url?o=$op'><span>clear</span></a>) <br/>" if $qry;
  print "Filter: <a href='$url?y=$yrlim'><span>$yrlim</span></a> " .
     "(<a href='$url?o=$op'><span>clear</span></a>) <br/>" if $yrlim;
  print searchform();
  print "Other lists: " ;
  my @ops = ( "Beer",  "Brewery", "Wine", "Booze", "Location", "Restaurant", "Style");
  for my $l ( @ops ) {
    my $bold = "nop";
    $bold = "b" if ($l eq $op);
    print "<a href='$url?o=$l'><$bold>$l</$bold></a> &nbsp;\n";
  }
  print "</div><hr/>\n";
  getseen() if ( $qryfield =~ /new/i );
  if ( !$notbef && !$qry ) {
    $notbef = datestr("%F", -180); # Default to last half year
  }
  my $fld;
  my $line;
  my @displines;
  my %lineseen;
  my $anchor="";
  my $maxwidth = "style='max-width:30%;'";
  my $i = scalar( @lines );
  while ( $i > 0 ) {
    $i--;
    my $rec = getrecord($i);
    next unless ($rec); # defensive coding, probably gets that one TZ record
    last if ($lines[$i] lt $notbef && scalar(@displines) >= 30);
    $fld = "";

    if ( $op eq "Location" ) {
      next if filtered ( $rec, "loc" );
      $fld = $rec->{loc};
      $line = "<td>" . filt($fld,"b","","full","loc");
      $line .=  "<span class='no-print'> ".
        "&nbsp; " . loclink($fld, "Www") . "\n  " . glink($fld, "G") . "</span>" .
        "</td>\n";
      $line .=   "<td>$rec->{wday} $rec->{effdate} <br class='no-wide'/>";
      $line .= lst("Location",$rec->{maker},"i","","maker") . ": \n";
      $line .= lst($op,$rec->{name},"","","name") . "</td>";

    } elsif ( $op eq "Brewery" ) {
      next unless ( $rec->{type} eq "Beer" );
      next if filtered ( $rec, "maker" );
      my $mak = $rec->{maker};
      $fld = $mak;
      $mak =~ s"/+"/<br/>&nbsp;"; # Split collab brews on two lines
      my $seentimes = "";
      $seentimes = "($seen{$fld})" if ($seen{$fld} );
      $line = "<td>" . filt($mak,"b","","full","maker") . "\n<br/ class='no-wide'>&nbsp;&nbsp;" . glink($fld) . "</td>\n" .
      "<td>$rec->{wday} $rec->{effdate} " . lst($op,$rec->{loc},"","","loc") . "\n $seentimes " .
            "<br class='no-wide'/> " . lst($op,$rec->{style},"","[$rec->{style}]","style") . " \n " .
            lst("full",$rec->{name},"b","","name")  ."</td>";

    } elsif ( $op eq "Beer" ) {
      next if ( $rec->{type} ne "Beer" );
      next if filtered ( $rec, "name" );
      my $beer = $rec->{name};
      $beer =~ s"(/|%2f|\()+"<br/>&nbsp; $1"gi if (length($beer) > 25); # Split longer lines
      $fld = $beer;
      my $seentimes = "";
      $seentimes = "$seen{$fld}" if ($seen{$fld} );
      my $sterm = "$rec->{maker} $rec->{name}";
      my $col = beercolorstyle($rec);
      my $shortstyle = shortbeerstyle($rec->{style});
      my $dispsty = "<span $col>$shortstyle</span>";
      $line = "<td $maxwidth>" . filt($fld,"b",$beer,"full","name") ;
      $line .= "<br/>&nbsp; " if ( $mobile || length($fld) > 25 );
      $line .= "&nbsp; $seentimes &nbsp;\n" .
            unit($rec->{alc},'%') .
            glink($sterm,"G") . rblink($sterm,"R") . utlink($sterm,"U") . "</td>" .
            "<td>$rec->{wday} $rec->{effdate} ".
            lst($op,$rec->{loc},"","","loc") .  "\n <br class='no-wide'/> " .
            lst($op,$shortstyle,"",$dispsty,"shortstyle"). "\n " .
            lst($op,$rec->{maker},"i","","maker") . "&nbsp;</td>";

    } elsif ( $op eq "Wine" ) {
      next unless ( $rec->{type} eq "Wine" );
      next if filtered ( $rec ); # new marks anywhere
      my $wine = $rec->{name};
      $fld = $wine;
      next if ( $wine =~ /^Misc/i );
      my $seentimes = "";
      $seentimes = "($seen{$wine})" if ($seen{$wine} );
      $line = "<td>" . filt($wine,"b","","full","name")  .
            " [$rec->{subtype}] &nbsp; " . filt($rec->{maker},"i","","Wine","maker" ) .
            "&nbsp;\n" . glink($wine, "G") . "</td>\n" .
            "<td>$rec->{wday} $rec->{effdate} ".
            lst($op,$rec->{loc},"","","loc") . "\n $seentimes \n" .
            "<br class='no-wide'/> ";
      $line .= lst($op,$rec->{style},"","[$rec->{style}]", "style") if ($rec->{style});
      $line .= "</td>";

    } elsif ( $op eq "Booze" ) {
      next unless ( $rec->{type} eq "Booze" );
      next if filtered ( $rec, "name" );
      my $stylename = $rec->{subtype};
      my $beer = $rec->{name};
      $fld = $beer;
      my $seentimes = "";
      $seentimes = "($seen{$beer})" if ($seen{$beer} );
      $line = "<td>" . filt($stylename,"", " [$stylename] ", "Booze", "subtype" ) .
            filt($beer,"b","","full","name") . "\n&nbsp;" . glink($beer, "G") ."</td>\n" .
            "<td>$rec->{wday} $rec->{effdate} ".
            lst($op,$rec->{loc},"","","loc") ."\n $seentimes " .
            "<br class='no-wide'/> " .
            lst($op,$rec->{style},"","[$rec->{style}]","style"). " " . unit($rec->{alc},'%') .
            "</td>\n";

    } elsif ( $op eq "Restaurant" ) {
      next unless ( $rec->{type} eq "Restaurant" );
      next if filtered ( $rec, "loc" );
      my $rstyle= $rec->{subtype};
      $fld = "$rec->{loc}";
      my $ratestr = "";
      $ratestr = "$rec->{rate}: <b>$ratings[$rec->{rate}]</b>" if $rec->{rate};  # TODO - Make a helper for this
      my $restname = "Restaurant,$rec->{loc}";
      my $rpr = "";
      $rpr = "&nbsp; $rec->{pr}.-" if ($rec->{pr} && $rec->{pr} >0) ;
      $line = "<td>" . filt($rec->{loc},"b","","full","loc") . "&nbsp; <br class='no-wide'/> \n ".
              filt("$rec->{subtype}", "", " [$rec->{subtype}] ", "Restaurant", "subtype") .
              " &nbsp;\n" . glink("Restaurant $rec->{loc}") . "</td>\n" .
              "<td>$rec->{wday} $rec->{effdate} <i>$rec->{food}</i>". " $rpr <br class='no-wide'/> " .
              " &nbsp; $ratestr</td>";

    } elsif ( $op eq "Style" ) {
      next unless ( $rec->{type} eq "Beer" );
      next if filtered ( $rec, "style" );
      my $sty = $rec->{style};
      $fld = $sty;
      my $seentimes = "";
      $seentimes = "($seen{$sty})" if ($seen{$sty} );
      $line = "<td>" . filt("[$sty]","b","","full","style") . " $seentimes" . "</td>" .
              "<td>$rec->{wday} $rec->{effdate} \n" .
              lst("Beer",$rec->{loc},"","","loc") .
              "\n <br class='no-wide'/> " .
              lst($op,$rec->{maker},"i","","maker") . ": \n" .
              lst("full",$rec->{name},"b","","name") . "</td>";
    } else {
      print "<!-- unknown shortlist '$op' -->\n";
      last;
    }
    next unless $fld;
    $fld = uc($fld);
    next if $lineseen{$fld};
    $lineseen{$fld} = $line;
    push @displines, "$line";
  }
  print scalar(@displines) . " entries ";
  print "from $notbef" if ($notbef);
  print "<br/>\n" ;
  if ( !$sortlist) {
    print "(<a href='$url?o=$op&sort=1&notbef=$notbef&qf=$qryfield&q=" . uri_escape($qry) . "' ><span>Sort Alphabetically</span></a>) <br/>\n";
  } else {
    print "(<a href='$url?o=$op&notbef=$notbef&qf=$qryfield&q=" . uri_escape($qry) . "'><span>Sort Recent First</span></a>) <br/>\n";
  }


  print "<hr/>\n" ;
  print "&nbsp;<br /><table style='background-color: #00600; max-width: 60em;' >\n";
  if ($sortlist) {
    @displines = ();
    for my $k ( sort { "\U$a" cmp "\U$b" } keys(%lineseen) ) {
      print "<tr>\n$lineseen{$k}</tr>\n";
    }
  } else {
    foreach my $dl (@displines) {
      print "<tr>\n$dl</tr>\n";
    }
  }
  print "</table>\n";

}  # Lists


################################################################################
# Regular list, on its own, or after graph and/or beer board
################################################################################

sub fulllist {
  my @ratecounts = ( 0,0,0,0,0,0,0,0,0,0,0);
  print "\n<!-- Full list -->\n ";
  my $filts = splitfilter($qry);
  print "<hr/>\n";
  print "<a href='$url?o=$op&q=.'><span>Filter</span></a> \n";
  print " -$qrylim " if ($qrylim);
  print "(<a href='$url'><span>Clear</span></a>) <b>$yrlim $filts</b>" if ($qry || $qrylim || $yrlim || $qryfield!~/rawline/i);
  print " &nbsp; \n";
  print "<span class='no-print'>\n";
  print " &nbsp; Show: ";
  print "<a href='$url?o=$op&q=" . uri_escape_utf8($qry) ."&y=" . uri_escape_utf8($yrlim) .
      "&f=x&qf=$qryfield' ><span>Extra info</span></a><br/>\n";
  print "</span>\n";
  if ($qry || $qrylim || $qryfield !~ /rawline/i || $yrlim) {
    $qry = "" if ( $qry eq "." );
    print "<br/>" . searchform() . "<br/>" ;
    print  glink($qry) . " " . rblink($qry) . " " . utlink($qry) . "\n" if ($qry);
  }
  if ( $qrylim eq "x" || $qryfield eq "new" ) {
    getseen(datestr( "%F", -3*365 ))
       unless ( scalar(%seen) > 2 );  # already done in beer board
  }
  my $efftoday = datestr( "%F", -0.3, 1); #  today's date
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
  my $anchor;
  my $i = scalar( @lines );
  $maxlines = $i*10 if ($maxlines <0); # neg means all of them
  my $rec = getrecord($i-1);
  my $lastrec; # TODO - Use this instead of the many last-somethings above
  while ( $i > 0 ) {  # Usually we exit at end-of-day
    $i--;
    $lastrec = $rec;
    $rec = getrecord($i);
    next if filtered ( $rec );
    nullallfields($rec);  # Make sure we don't access undefined values, fills the log with warnings
    $maxlines--;

    $origpr = $rec->{pr};

    my $dateloc = "$rec->{effdate} : $rec->{loc}";
    bloodalcohol($i);

    if ( $dateloc ne $lastloc && ! $qry) { # summary of loc and maybe date
      print "\n";
      my $locdrinks = sprintf("%3.1f", $locdsum / $onedrink) ;
      my $daydrinks = sprintf("%3.1f", $daydsum / $onedrink) ;
      # loc summary: if nonzero, and diff from daysummary
      # or there is a new loc coming,
      if ( $locdrinks > 0.1) {
        print "<br/>$lastwday ";
        print "$lastloc2: " . unit($locdrinks,"d"). unit($locmsum, ".-"). "\n";
        if ($averages{$lastdate} && $locdrinks eq $daydrinks && $lastdate ne $rec->{effdate}) {
          print " (a=" . unit($averages{$lastdate},"d"). " )\n";
          if ($bloodalc{$lastdate}) { #
            print " ". unit(sprintf("%0.2f",$bloodalc{$lastdate}), "‰");
          }
          print "<br/>\n";
        } # fl avg on loc line, if not going to print a day summary line
        # Restaurant copy button
        my $rtype = $restaurants{$lastloc2}->{subtype}|| "";
        $rtype =~ s/Restaurant, //;
        my $rtime = $1 . ":" . sprintf("%02d",$2-1) if ( $lastrec->{time} =~ /^(\d+):(\d+)/ );
        my $hiddeninputs =
          "<input type='hidden' name='loc' value='$lastloc2' />\n" .
          "<input type='hidden' name='pr' value='$locmsum.-' />\n" .
          #"<input type='hidden' name='geo' value='' />\n" .  # no geo, we already have it on a drink, can get wrong
          "<input type='hidden' name='date' value='$lastrec->{date}' />\n" .
          "<input type='hidden' name='time' value='$rtime' />\n" ;
        print "<form method='POST' style='display: inline;' class='no-print'>\n";
        print $hiddeninputs;
        print "<input type='hidden' name='type' value='Restaurant' />\n";
        print "<input type='hidden' name='subtype' value='$rtype' />\n";
        print "<input type='submit' name='submit' value='Rest'
                    style='display: inline; font-size: x-small' />\n";
        print "</form>\n";
        print "<form method='POST' style='display: inline;' class='no-print'>\n";
        print $hiddeninputs;
        print "<input type='hidden' name='type' value='Night' />\n";
        print "<input type='submit' name='submit' value='Night'
                    style='display: inline; font-size: x-small' />\n";
        print "</form>\n";
        print "<br/>\n";
      }
      # day summary
      if ($lastdate ne $rec->{effdate} ) {
        if ( $locdrinks ne $daydrinks) {
          print " <b>$lastwday</b>: ". unit($daydrinks,"d"). unit($daymsum,".-");
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
          $maxlines = 0; # signal that we need a "more" link
          last;
        }
      }
      $locdsum = 0.0;
      $locmsum = 0;
      $loccnt = 0;
    }
    if ( $lastdate ne $rec->{effdate} ) { # New date
      print "<hr/>\n" ;
      $lastloc = "";
    }
    if ( $dateloc ne $lastloc ) { # New location and maybe also new date
      print "<br/><b>$rec->{wday} $rec->{effdate} </b>" . filt($rec->{loc},"b","","","loc") . newmark($rec->{loc}) . loclink($rec->{loc});
      print "<br/>\n" ;
      if ( $qrylim eq "x") {
        my ( undef, undef, $gg) = geo($geolocations{$rec->{loc}});
        my $tdist = geodist($rec->{geo}, $gg);
        if ( $tdist && $tdist > 1 ) {
          $tdist = "<b>".unit($tdist,"m"). "</b>";
        } else {
          $tdist = "";
        }
        my ($guess, $gdist) = guessloc($gg,$rec->{loc});
        $gdist = unit($gdist,"m");
        $guess = " <b>($guess $gdist?)</b> " if ($guess);
        my $map = maplink($gg);
        print "Geo: $gg $tdist $guess $map<br/>\n" if ($gg || $guess || $tdist);
      }
    }
    ###### The (beer) entry itself ##############
    my $time = $rec->{time};
    $time = $1 if ( $qrylim ne "x" && $time =~ /^(\d+:\d+)/ ); # Drop the seconds
    if ( $rec->{date} ne $rec->{effdate} ) {
      $time = "($time)";
    }

    if ( !( $rec->{type}  eq "Restaurant" ) ) { # don't count rest lines
      $daydsum += $rec->{alcvol};
      $daymsum += abs($rec->{pr});
      $locdsum += $rec->{alcvol};
      $locmsum += abs($rec->{pr}) ;
      $loccnt++;
    }
    $anchor = $rec->{stamp} || "";
    $anchor =~ s/[^0-9]//g;
    print "\n<a id='$anchor'></a>\n";
    my $disptype = $rec->{type}; # Show record type
    $disptype .= ", $rec->{subtype}" if ($rec->{subtype});

    print "<br class='no-print'/><span style='white-space: nowrap'> " .
           "$time ";
    print " [$disptype]\n";

    print filt($rec->{maker},"i", "","","maker") . newmark($rec->{maker}). ": " if ($rec->{maker});
    print filt($rec->{name},"b","","","name") . newmark($rec->{name}, $rec->{maker});
    print $rec->{people}; # Not on the same type record as maker/name

    print "</span> <br class='no-wide'/>\n";
    if ( $rec->{style} || $rec->{pr} || $rec->{vol} || $rec->{alc} || $rec->{rate} || $rec->{com} ) {
      if ($rec->{style}) {
        my $beerstyle = beercolorstyle($rec);
        my $tag="span $beerstyle";
        my $ssty = $rec->{style};
        if ( $qrylim ne "x" ) {
          $ssty = shortbeerstyle($rec->{style}) ;
          print filt("$ssty",$tag,"","","shortstyle") . newmark($rec->{style}) . " "   ;
          print "<br>\n";
        } else {
          print filt("$ssty",$tag,"","","style") . " "   ;
          print "<br>\n";
        }
      }
      if ($rec->{style} || $rec->{pr} || $rec->{alc}) {
        if ( $qrylim ne "x" ) {
          print units($rec);
        } else {
          print units($rec, "x");  # indicates extended units
        }
      }
      print "<br/>\n" ;
      if ($rec->{food}) {
        print "<span class='only-wide'>&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;</span>\n";
        print "$rec->{food}";
        print "<br/>\n";
      }
      if ($rec->{rate} || $rec->{com}) {
        print "<span class='only-wide'>&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;</span>\n";
        if ($rec->{rate} && $rec->{rate} =~ /^\d+$/ ) {
          print " <b>'$rec->{rate}' - $ratings[$rec->{rate}]</b>";
          print ": " if ($rec->{com});
        }
        print "<i>$rec->{com}</i>" if ($rec->{com});
        print "<br/>\n";
      }
      $ratecounts[$rec->{rate}] ++ if ($rec->{rate});
      if ( $qrylim eq "x" ) {
        my $seenkey = $rec->{seenkey};
        if ($seenkey && $ratecount{$seenkey}) {
          print "<span class='only-wide'>&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;</span>\n";
          my $avgrate = sprintf("%3.1f", $ratesum{$seenkey}/$ratecount{$seenkey});
          if ($ratecount{$seenkey} == 1 )  {
            print " One rating: <b>$avgrate</b> ";
          } else {
            print " Avg of <b>$ratecount{$seenkey}</b> ratings: <b>$avgrate</b><br>";
          }
        }
        my $seenline = seenline($rec);
        if ($seenline) {
          print "<span style='white-space: nowrap'>";
          print $seenline;
          print "</span><br>\n";
        }
        if ( $rec->{geo} ) {
          my (undef, undef, $gg) = geo($rec->{geo});
          my $map = maplink($gg);
          print "Geo: $gg $map";
          my $dist = "";
          $dist = geodist( $geolocations{$rec->{loc}}, $rec->{geo});
          my ($guess,$gdist) = guessloc($gg);
          if ( $guess eq $rec->{loc} ) {
            print " $guess ";
          } else {
            print " <b>$guess ??? </b>  ";
          }
          print " (" . unit($gdist,"m"). ")";
          print "<br>\n";
        }
      }
    }

    if ( $rec->{photo} ) {
      my $w = "thumb";
      if ( $qrylim eq "x" ) {
        if ( $mobile ) {
          $w = "mob";
        } else {
          $w = "pc";
        }
      }
      print image($rec,$w);
      print "<br/>\n";
    }
    my %vols;     # guess sizes for small/large beers
    $vols{$rec->{vol}} = 1 if ($rec->{vol});
    if ( $rec->{type} =~ /Night|Restaurant/) {
      %vols=(); # nothing to copy
    } elsif ( $rec->{type}  eq "Wine" ) {
      $vols{12} = 1;
      $vols{16} = 1 unless ( $rec->{vol} == 15 );
      $vols{37} = 1;
      $vols{75} = 1;
    } elsif ( $rec->{type}  eq "Booze" ) {
      $vols{2} = 1;
      $vols{4} = 1;
    } else { # Default to beer, usual sizes in craft beer world
      $vols{25} = 1;
      $vols{40} = 1;
    }
    print "<form method='POST' style='display: inline;' class='no-print' >\n";
    print "<a href='$url?o=$op&q=$qry&e=" . uri_escape_utf8($rec->{stamp}) ."' ><span>Edit</span></a> \n";

    # Copy values
    my $fieldnamelistref = $datalinetypes{$rec->{type}};
    my @fieldnamelist = @{$fieldnamelistref};
    foreach my $k ( @fieldnamelist ) {
      next if $k =~ /stamp|wday|effdate|loc|vol|geo|rate|com|people|food/; # not these
      print "<input type='hidden' name='$k' value='$rec->{$k}' />\n";
    }
    print "<input type='hidden' name='geo' id='geo' value='' />\n"; # with the id
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
      print glink("$rec->{maker} $rec->{name}", "Google") . "&nbsp;\n";
      print rblink("$rec->{maker} $rec->{name}", "RateBeer") . "&nbsp;\n";
      print utlink("$rec->{maker} $rec->{name}", "Untappd") . "&nbsp;\n";
    }
    print"<br/>\n";
    print "</form>\n";
    $lastloc = $dateloc;
    $lastloc2 = $rec->{loc};
    $lastdate = $rec->{effdate};
    $lastwday = $rec->{wday};
  } # line loop

  if ( ! $qry) { # final summary
    my $locdrinks = sprintf("%3.1f", $locdsum / $onedrink);
    my $daydrinks = sprintf("%3.1f", $daydsum / $onedrink);
    # loc summary: if nonzero, and diff from daysummary
    # or there is a new loc coming
    if ( $locdrinks > 0.1 ) {
      print "$lastloc2: $locdrinks d, $locmsum.- \n";
      }
      # day summary: if nonzero and diff from daysummary and end of day
    if ( abs ( $daydrinks > 0.1 ) && abs ( $daydrinks - $locdrinks ) > 0.1 &&
         $lastdate ne $efftoday ) {
      print " <b>$lastwday</b>: $daydrinks d, $daymsum.- \n";
      }
      print "<br/>";
    }

  print "<hr/>\n" ;
  my $rsum = 0;
  my $rcnt = 0;
  print "<p>Ratings:<br/>\n"; # TODO - Move these to the datafile stats, for every year
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



################################################################################
# Various small helpers
################################################################################

# Helper to trim leading and trailing spaces
sub trim {
  my $val = shift || "";
  $val =~ s/^ +//; # Trim leading spaces
  $val =~ s/ +$//; # and trailing
  $val =~ s/\s+/ /g; # and repeated spaces in the middle
  return $val;
}

# Helper to sanitize input data
sub param {
  my $tag = shift;
  my $val = $q->param($tag) || "";
  $val =~ s/[^a-zA-ZñÑåÅæÆøØÅöÖäÄéÉáÁāĀ\/ 0-9.,&:\(\)\[\]?%-]/_/g;
  return $val;
}

# Helper to make a filter link
sub filt {
  my $f = shift; # filter term
  my $tag = shift || "span";
  my $dsp = shift || $f;
  my $op = shift || $op || "";
  my $fld = shift || ""; # Field to filter by
  $op = "o=$op" if ($op);
  my $param = $f;
  $param =~ s"[\[\]]""g; # remove the [] around styles etc
  my $endtag = $tag;
  $endtag =~ s/ .*//; # skip attributes
  my $style = "";
  if ( $tag =~ /background-color:([^;]+);/ ) { #make the link underline disappear
    $style = "style='color:$1'";
  }
  $param = "&q=" . uri_escape_utf8($param) if ($param);
  $fld = "&qf=$fld" if ($fld);
  my $link = "<a href='$url?$op$param$fld' $style>" .
    "<$tag>$dsp</$endtag></a>";
  return $link;
}

# Helper to make a link to a list
# TODO - Is this needed, wouldn't filt() above do the same?
sub lst {
  my $op = shift; # The kind of list
  my $qry = shift || ""; # Optional query to filter the list
  my $tag = shift || "nop";
  my $dsp = shift || $qry || "???";
  my $fld = shift || "";
  $fld = "&qf=$fld" if ($fld);
  $qry = "&q=" . uri_escape_utf8($qry) if $qry;
  $op = uri_escape_utf8($op);
  my $link = "<a href='$url?o=$op$qry$fld' ><$tag>$dsp</$tag></a>";
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


# Helper to filter out records
# Checks them against $qry, $qryfield and $yrlim
#    next if filtered ( $rec );
# returns 0 if the record should be displayed
sub filtered {
  my $rec = shift;
  my $newfield = shift; # the field to check for new mark. Defaults to all relevant
  my $skip = 0; # default to displaying it
  return 1 if ( !$rec ); # nothing to show
  if ( $qryfield eq "shortstyle" ) {
    checkshortstyle($rec); # Make sure we have a short style
  } elsif ( $qryfield eq "new" ) {
    checknew($rec, $newfield);
  } elsif ( $qryfield eq "geoerror" ) {
    checkgeoerror($rec);
  }
  if ( $qry ) {
    $rec->{$qryfield} = "" if ( !defined($rec->{$qryfield} ) );
    $skip = 1 if ( $rec->{$qryfield} !~ /\b$qry\b/i ) ;
  } else {
    if (  $qryfield !~ /rawline/i ) {
      if ( ! defined($rec->{$qryfield}) || ! $rec->{$qryfield} ) {
        $skip = 1;
      }
    }
  }
  if ( $yrlim ) {
    $skip = 1 if ( $rec->{rawline} !~ /^$yrlim/ );
  }
  return $skip;
}

# Helper to pring a search form
sub searchform {
  my $rectype = shift || "Beer";
  my $r = "" .
    "<form method=GET accept-charset='UTF-8'> " .
    "<input type=hidden name='o' value=$op />\n" .
    "<input type=text name='q' value='$qry' />  \n " .
    "<select name='qf' style='width:6em;'> \n";
  $r .=  "<option value='rawline'>(any)</option>\n";

  foreach my $fn ( fieldnames(), "shortstyle", "new", "geoerror" ) {
    my $dsp = ucfirst($fn);
    my $sel = "";
    $sel = "selected" if ( $fn eq $qryfield );
    $r .=  "<option value='$fn' $sel>$dsp</option>\n";
  }
  $r .= "</select> \n" ;
  $r .=  "<input type=hidden name=notbef value='$notbef' />\n" if ( $notbef gt "2000" );
  $r .=  "<input type=hidden name=f value='$qrylim' />\n" if ( $qrylim);
  $r .=  "<input type=submit value='Search'/> \n " .
    "</form> \n";
  return $r;
}

# Helper to print "(NEW)" in case we never seen the entry before
sub newmark {
  my $v = shift;
  my $rest = shift || "";
  return "" if ( $rest =~ /^Restaurant/);
  return "" if ($seen{$v} && $seen{$v} != 1);
  return "" if ( $v =~ /mixed|misc/i );  # We don't collect those in seen
  return "" if ( scalar(keys(%seen)) < 2); # No seen marks collected
  return " <i>new</i> ";
}


# Helper to make a link to a bar of brewery web page and/or scraped beer menu
sub loclink {
  my $loc = shift;
  my $www = shift || "www";
  my $scrape = shift || "List";
  my $lnk = "";
  if (defined($scrapers{$loc}) && $scrape ne " ") {
    $lnk .= " &nbsp; <i><a href='$url?o=board&loc=$loc'><span>$scrape</span></a></i>" ;
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
  my $lnk = "&nbsp;<i>(<a href='https://www.google.com/search?q=$qry'" .
    " target='_blank' class='no-print'><span>$txt</span></a>)</i>\n";
  return $lnk;
}

# Helper to make a Ratebeer search link
sub rblink {
  my $qry = shift;
  my $txt = shift || "Ratebeer";
  return "" unless $qry;
  $qry = uri_escape_utf8($qry);
  my $lnk = "<i>(<a href='https://www.ratebeer.com/search?q=$qry' " .
    " target='_blank' class='no-print'><span>$txt<span></a>)</i>\n";
  return $lnk;
}

# Helper to make a Untappd search link
sub utlink {
  my $qry = shift;
  my $txt = shift || "Untappd";
  return "" unless $qry;
  $qry = uri_escape_utf8($qry);
  my $lnk = "<i>(<a href='https://untappd.com/search?q=$qry'" .
    " target='_blank' class='no-print'><span>$txt<span></a>)</i>\n";
  return $lnk;
}

sub maplink {
  my $g = shift;
  my $txt = shift || "Map";
  return "" unless $g;
  my ( $la, $lo, undef ) = geo($g);
  my $lnk = "<a href='https://www.google.com/maps/place/$la,$lo' " .
  "target='_blank' class='no-print'><span>$txt</span></a>";
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
# price (literprice), alc, vol, drinks, (bloodalc)
sub units {
  my $rec = shift;
  my $extended = shift || "";
  my $s = "<b>". unit($rec->{vol}, "cl") . "</b>";
  $s .= unit($rec->{pr},".-");
  if ($extended) {
    if ($rec->{pr} && $rec->{vol}) {
      my $lpr = int($rec->{pr} / $rec->{vol} * 100);
      $s .= "(" . unit($lpr, "/l") . ") ";
    }
  }
  $s .=  unit($rec->{alc},'%');
  if ( $rec->{drinks} && $rec->{pr} >= 0) {
    my $dr = sprintf("%1.2f", $rec->{drinks} );
    $s .= unit($dr, "d") if ($dr > 0.1);
  }
  if ($rec->{bloodalc}) {
    my $tag = "nop";
    $tag = "b" if ( $rec->{bloodalc} > 0.5 );
    $s .= "<$tag>" . unit( sprintf("%0.2f",$rec->{bloodalc}), "/₀₀"). "</$tag>";
    # The promille sign '‰' is hard to read on a phone. Experimenting wiht alternatives:
    # from https://en.wikipedia.org/wiki/List_of_Unicode_characters
    # ⁂ ₀  /₀₀ ◎ ➿ 。🜽
  }
  return $s;
}


# Helper to make an error message
sub error {
  my $msg = shift;
  print "\n\n";  # Works if have sent headers or not
  print "<hr/>\n";
  print "ERROR   <br/>\n";
  print $msg;
  print STDERR "ERROR: $msg\n";
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

# Helper to make a seenkey, an index to %lastseen and %seen
# Normalizes the names a bit, to catch some misspellings etc
sub seenkey {
  my $rec= shift;
  my $maker;
  my $name = shift;
  my $key;
  if (ref($rec)) {
    $maker = $rec->{maker} || "";
    $name = $rec->{name} || "";
    if ($rec->{type} eq "Beer") {
      $key = "$rec->{maker}:$rec->{name}"; # Needs to match m:b in beer board etc
    } elsif ( $rec->{type} =~ /Restaurant|Night/ ) {
      $key = "$rec->{type}:$rec->{loc}";  # We only have loc to match (and subkey?)
    } elsif ( $rec->{name} && $rec->{subkey} ) {  # Wine and booze: Wine:Red:Foo
      $key = "$rec->{type}:$rec->{subkey}:$rec->{name}";
    } elsif ( $rec->{name} ) {  # Wine and booze: Wine::Mywine
      $key = "$rec->{type}::$rec->{name}";
    } else { # TODO - Not getting keys for many records !!!
      #print STDERR "No seenkey for $rec->{rawline} \n";
      return "";  # Nothing to make a good key from
    }
  } else { # Called  the old way, like for beer board
    $maker = $rec;
    $key = "$maker:$name";
    #return "" if ( !$maker && !$name );
  }
  $key = lc($key);
  return "" if ( $key =~ /misc|mixed/ );
  $key =~ s/&amp;/&/g;
  $key =~ s/[^a-zåæø0-9:]//gi;  # Skip all special characters and spaces
  return $key;
}

# Helper to produce a "Seen" line
sub seenline {
  my $maker = shift;
  my $beer = shift;
  my $seenkey;
  if ( ref($maker) ) {
    my $rec = $maker;
    $seenkey = $rec->{seenkey};
  } else {
    $seenkey = seenkey($maker,$beer);
  }
  return "" unless ($seenkey);
  return "" unless ($seenkey =~ /[a-z]/ );  # At least some real text in it
  my $seenline = "";
  $seenline = "Seen <b>" . ($seen{$seenkey}). "</b> times: " if ($seen{$seenkey});
  my $prefix = "";
  my $detail="";
  my $detailpattern = "";
  my $nmonths = 0;
  my $nyears = 0;
  my $lastseenline = $lastseen{$seenkey} || "";
  foreach my $ls ( split(' ', $lastseenline ) )  {
    my $comma = ",";
    if ( ! $prefix || $ls !~ /^$prefix/ ) {
      $comma = ":" ;
      if ( $nmonths++ < 2 ) {
        ($prefix) = $ls =~ /^(\d+-\d+)/ ;  # yyyy-mm
        $detailpattern = "(\\d\\d)\$";
      } elsif ( $nyears++ < 1 ) {
        ($prefix) = $ls =~ /^(\d+)/ ;  # yyyy
        $detailpattern = "(\\d\\d)-\\d\\d\$";
      } else {
        $prefix = "20";
        $detailpattern = "^20(\\d\\d)";
        $comma = "";
      }
      $seenline .= " <b>$prefix</b>";
    }
    my ($det) = $ls =~ /$detailpattern/ ;
    next if ($det eq $detail);
    $detail = $det;
    $seenline .= $comma . "$det";
  }
  return $seenline;
}


# Helper to assign a color for a beer
sub beercolor {
  my $rec = shift; # Can also be type
  my $prefix = shift || "0x";
  my $line = shift;
  my $type;
  if ( ref($rec) ) {
    $type = "$rec->{type},$rec->{subtype}: $rec->{style} $rec->{maker}";  # something we can match
    $line = $rec->{rawline};
  } else {
    $type = $rec;
  }
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
      print STDERR "No color for '$line' \n";
      return $prefix."9400d3" ;   # dark-violet, aggressive pink
}

# Helper to return a style attribute with suitable colors for (beer) style
sub beercolorstyle {
  my $rec = shift;  # Can also be style as text, see below
  my $line = shift; # for error logging
  my $type = "";
  my $bkg;
  if (ref($rec)) {
    $bkg= beercolor($rec,"#");
  } else {
    $type = $rec;
    $bkg= beercolor($type,"#",$line);
  }
  my $col = $bgcolor;
  my $lum = ( hex($1) + hex($2) + hex($3) ) /3  if ($bkg =~ /^#?(..)(..)(..)/i );
  if ($lum < 64) {  # If a fairly dark color
    $col = "#ffffff"; # put white text on it
  }
  return "style='background-color:$bkg;color:$col;'";
}

# Helper to shorten a beer style
sub shortbeerstyle {
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

# Check that the record has a short style
sub checkshortstyle {
  my $rec = shift;
  return unless $rec;
  return unless ( $rec->{style} );
  return if $rec->{shortstyle}; # already have it
  $rec->{shortstyle} = shortbeerstyle($rec->{style});
}

# Check if the record should have a NEW marker
# Only considers fields in the given list
sub checknew {
  my $rec = shift;
  my $field = shift;
  my @fields = ( $field );
  @fields = ( "name", "maker", "style" ) unless ( $field );
  return if defined($rec->{new}) ; # already checked
  $rec->{new} = ""; # default not new
  return if ( scalar(%seen) < 2); # no new marks to check
  for my $f ( @fields ) {
    next unless ( $rec->{$f} );
    my $s = $seen{ $rec->{$f} };
    next if ( $s &&  $s > 1 );
    $rec->{new} = $f;
    last;
  }
}

# Check if the record has problematic geo coords
# That is, coords and loc don't match
sub checkgeoerror {
  my $rec = shift;
  return unless $rec;
  return unless ( $rec->{loc} );
  return unless ( $rec->{geo} );
  my ( $guess, $dist ) = guessloc($rec->{geo});
  if ( $guess ne $rec->{loc} ) {
    $rec->{geoerror} = "$guess [$dist]m";
    #print STDERR "Possible geo error for $rec->{stamp}: '$rec->{loc}' " .
    # "is not at $rec->{geo}, '$guess' is at $dist m from it\n";
  }
}

# Split a data line into a hash. Precalculate some fields
sub splitline {
  my $line = shift;
  my @datafields = split(/ *; */, $line);
  my $linetype = $datafields[1]; # This is either the type, or the weekday for old format lines (or comment)
  my $v = {};
  return $v unless ($linetype); # Can be an empty line, BOM mark, or other funny stuff
  return $v if ( $line =~/^#/ ); # skip comment lines
  $linetype =~ s/(Mon|Tue|Wed|Thu|Fri|Sat|Sun)/Old/i; # If we match a weekday, we have an old-format line with no type
  $v->{type} = $linetype; # Likely to be overwritten below, this is just in case (Old)
  $v->{rawline} = $line; # for filtering
  $v->{name} = ""; # Default, make sure we always have something
  $v->{maker} = "";
  $v->{style} = "";
  my $fieldnamelist = $datalinetypes{$linetype} || "";
  if ( $fieldnamelist ) {
    my @fnames = @{$fieldnamelist};
    for ( my $i = 0; $fieldnamelist->[$i]; $i++ ) {
      $v->{$fieldnamelist->[$i]} = $datafields[$i] || "";
    }
  } else {
    error ("Unknown line type '$linetype' in $line");
  }
  # Normalize some common fields
  $v->{alc} = number( $v->{alc} );
  $v->{vol} = number( $v->{vol} );
  $v->{pr} = price( $v->{pr} );
  # Precalculate some things we often need
  ( $v->{date}, $v->{year}, $v->{time} ) = $v->{stamp} =~ /^(([0-9]+)[0-9-]+) +([0-9:]+)/;
  my $alcvol = $v->{alc} * $v->{vol} || 0 ;
  $alcvol = 0 if ( $v->{pr} < 0  );  # skip box wines
  $v->{alcvol} = $alcvol;
  $v->{drinks} = $alcvol / $onedrink;
  return $v;
}

# Parse a line to a proper $rec
# Converts Old type records to more modern types, etc
sub parseline {
  my $line = shift;
  my $rec = splitline( $line );

  # Make sure we accept missing values for fields
  nullfields($rec);

  # Convert "Old" records to better types if possible
  if ( $rec->{type} eq "Old") {
    if ($rec->{mak} =~ /^Tz,/i){ # Skip Time Zone lines, almost never used
      $rec = {};
      return;
    }
    if ($rec->{mak} !~ /,/ ) {
      $rec->{type} = "Beer";
      $rec->{maker} = $rec->{mak};
      $rec->{name} = $rec->{beer};
      $rec->{style} = $rec->{sty};
    } elsif ( $rec->{mak} =~ /^(Wine|Booze)[ ,]*(.*)/i ) {
      $rec->{type} = ucfirst($1);
      $rec->{subtype} = $2;
      $rec->{name} = $rec->{beer};
    } elsif ( $rec->{mak} =~ /^Drink/i ) {
      $rec->{type} = "Booze";
      $rec->{name} = $rec->{beer};
    } elsif ( $rec->{mak} =~ /^Restaurant *, *(.*)/i ) {
      $rec->{type} = "Restaurant";
      $rec->{subtype} = $1;
      $rec->{food} = $rec->{beer};
      $rec->{sty} = "";
    } else {
      print STDERR "Unconverted 'Old' line: $rec->{rawline} \n";
    }
    $rec->{beer} = "";  # Kill old style fields, no longer used
    $rec->{mak} = "";
    $rec->{sty} = "";
    nullfields($rec); # clear undefined fields again, we may have changed the type
  }
  $rec->{seenkey} = seenkey($rec); # Do after normalizing name and type
  return $rec;
}

# Helper to get the ith record
# Caches the parsing
sub getrecord {
  my $i = shift;
  if ( ! $records[$i] ) {
    $records[$i] = parseline($lines[$i]);
  }
  return $records[$i];
}

# Get all field names for a type, or all
sub fieldnames {
  my $type = shift || "";
  my @fields;
  my @typelist;
  if ( $type ) {
    @typelist = ( $type ) ;
  } else {
    @typelist = sort( keys ( %datalinetypes ) );
  }
  my %seen;
  foreach my $t ( @typelist ) {
    next if ( $t =~ /Old/i );
    my $fieldnamelistref = $datalinetypes{$t};
    my @fieldnamelist = @{$fieldnamelistref};
    foreach my $f ( @fieldnamelist ) {
      push @fields, $f unless ( $seen{$f} );
      $seen{$f} = 1;
    }
  }
  return @fields;
}

# Create a line out of a record
sub makeline {
  my $rec = shift;
  my $linetype = $rec->{type} || "Old";
  my $line = "";
  return "" if ($linetype eq "None"); # Not worth saving
  foreach my $f ( fieldnames($linetype) ) {
    $line .=  $rec->{$f} || "";
    $line .= "; ";
  }
  return trim($line);
}

# Make sure we have all fields defined, even as empty strings
sub nullfields {
  my $rec = shift;
  my $linetype = shift || $rec->{type} || "Old";
  my $fieldnamelistref = $datalinetypes{$linetype};
  my @fieldnamelist = @{$fieldnamelistref};
  foreach my $f ( fieldnames($linetype) ) {
    $rec->{$f} = ""
      unless defined($rec->{$f});
  }
}

# Make sure we have all possible fields defined, for all types
# otherwise the user changing record type would hit us with undefined values
# in the input form
sub nullallfields{
  my $rec = shift;
  for my $k ( keys(%datalinetypes) ) {
    nullfields($rec, $k);
  }
}

# Check if a given record type should have this field
sub hasfield {
  my $linetype = shift;
  if ( ref($linetype) ) {
    $linetype = $linetype->{type};
  }
  my $field = shift;
  print STDERR "hasfield: bad params linetype='$linetype' field='$field' \n"
     if (!$linetype || !$field);
  return grep( /^$field$/, fieldnames($linetype) );
}


# Debug dump of record into STDERR
sub dumprec {
  my $rec = shift;
  my $msg = shift || "";
  print STDERR "$msg -- ";
  for my $k ( sort(keys( %{$rec} ) ) )  {
    print STDERR "$k:'$rec->{$k}'  ";
  }
  print STDERR "\n";
}
