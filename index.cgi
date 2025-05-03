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
# THIS IS OUTDATED - I am in the middle of a complex rewrite that
#  - uses SqLite for the back end
#  - Splits the code into several dedicated modules
#  - Should simplify this script to something pretty small
# At the moment we are somewhere in the middle. Using SqLite all right, but
# faking the old line-based things for many of the lists etc. TODO
#
#
# The code consists of one very long main function that produces whatever
# output we need, and a small number of helpers. (Ought to be refactored
# in version 2). Sections are delimited by comment blocks like above.

# While working on everything at once, I can not maintain github issues for
# everything, so I put TODO markers in the code. The word may be followed by
# SOON for things that should be done in the near future, or LATER for those
# that have to wait a little. Maybe I invite more labeling in time. In the end
# all TODOs should be resolved, or moved into github issues

# TODO - Switch to using
#  - FIXME instead of TODO SOON
#  - NOTE instead TODO LATER

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
#
# End of outdated comment



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

use locale;
setlocale(LC_COLLATE, "da_DK.utf8"); # but dk is the default
setlocale(LC_CTYPE, "da_DK.utf8");

use open ':encoding(UTF-8)';  # Data files are in utf-8
binmode STDOUT, ":utf8"; # Stdout only. Not STDIN, the CGI module handles that
binmode STDERR, ":utf8"; #

use URI::Escape;
use CGI qw( -utf8 );
our $q = CGI->new;
$q->charset( "UTF-8" );


# Database setup
use DBI;
my $databasefile = "beerdata/beertracker.db";
die ("Database '$databasefile' not writable" ) unless ( -w $databasefile );

our $dbh = DBI->connect("dbi:SQLite:dbname=$databasefile", "", "", { RaiseError => 1, AutoCommit => 1 })
    or util::error($DBI::errstr);
$dbh->{sqlite_unicode} = 1;  # Yes, we use unicode in the database, and want unicode in the results!
$dbh->do('PRAGMA journal_mode = WAL'); # Avoid locking problems with SqLiteBrowser
# But watch out for file permissions on the -wal and -sha files
#$dbh->trace(1);  # Lots of SQL logging in error.log

################################################################################
# Constants and setup
################################################################################

my $mobile = ( $ENV{'HTTP_USER_AGENT'} =~ /Android|Mobile|Iphone/i );
my $workdir = cwd();
my $devversion = 0;  # Changes a few display details if on the development version
$devversion = 1 unless ( $ENV{"SCRIPT_NAME"} =~ /index.cgi/ );
$devversion = 1 if ( $workdir =~ /-dev|-old/ );
# Background color. Normally a dark green (matching the "racing green" at Øb),
# but with experimental versions of the script, a dark blue, to indicate that
# I am not running the real thing.
my $bgcolor = "#003000";
$bgcolor = "#003050" if ( $devversion );

# Constants
my $onedrink = 33 * 4.6 ; # A regular danish beer, 33 cl at 4.6%
my $datadir = "./beerdata/";
my $scriptdir = "./scripts/";  # screen scraping scripts
my $plotfile = "";
my $cmdfile = "";
my $photodir = "";
our $username = ($q->remote_user()||"");

# Sudo mode, normally commented out
#$username = "dennis" if ( $username eq "heikki" );  # Fake user to see one with less data

if ( ($q->remote_user()||"") =~ /^[a-zA-Z0-9]+$/ ) {
  $plotfile = $datadir . $username . ".plot";
  $cmdfile = $datadir . $username . ".cmd";
  $photodir = $datadir . $username. ".photo";
} else {
  util::error ("Bad username\n");
}

my @ratings = ( "Zero", "Undrinkable", "Unpleasant", "Could be better",  # zero should not be used!
"Ok", "Goes down well", "Nice", "Pretty good", "Excellent", "Perfect");  # 9 is the top


# Links to beer lists at the most common locations and breweries
my %links; # TODO - Kill this, get them from the database
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
# my %shortnames;
# $shortnames{"Home"} = "H";
# $shortnames{"Fermentoren"} = "F";
# $shortnames{"Ølbaren"} = "Øb";
# $shortnames{"Ølsnedkeren"} = "Øls";
# $shortnames{"Hooked, Vesterbro"} = "Hooked Vbro";
# $shortnames{"Hooked, Nørrebro"} = "Hooked Nbro";
# $shortnames{"Dennis Place"} = "Dennis";
# $shortnames{"Væskebalancen"} = "VB";

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

my %subtypes;

# The old style lines with no type.

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

$subtypes{"Wine"} = [ "Red", "White", "Sweet", "Bubbly" ];

# Spirits, Booze. Also used for coctails
$datalinetypes{"Spirit"} = [ "stamp", "type", "wday", "effdate", "loc",
  "subtype",   # whisky, snaps
  "maker", # brand or house
  "name",  # What it says on the label
  "style", # can be coctail, country/(region, or flavor
  "vol", "alc",  # These are for the alcohol itself
  "pr", "rate", "com", "geo", "photo"];
$datalinetypes{"Booze"} = $datalinetypes{"Spirit"};

$datalinetypes{"Cider"} = [
  "stamp", "type", "wday", "effdate", "loc",
  "maker",  # Brewery
  "name",   # Name of the beer
  "vol", "style", "alc", "pr", "rate", "com", "geo",
  "subtype", # Taste of the beer, could be fruits, special hops, or type of barrel
  "photo" ]; # Image file name


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
our $qry = param("q");  # filter query, greps the list
my $qryfield = param("qf") || "rawline"; # Which field to match $qry to
my $qrylim = param("f"); # query limit, "x" for extra info, "f" for forcing refresh of board
my $yrlim = param("y"); # Filter by year
our $op  = param("o");  # operation, to list breweries, locations, etc
my $maxlines = param("maxl") || "$yrlim$yrlim" || "45";  # negative = unlimited
   # Defaults to 25, unless we have a year limit, in which case defaults to something huge.
my $sortlist = param("sort") || 0; # default to unsorted, chronological lists
my $notbef = param("notbef") || ""; # Skip parsing records older than this
our $url = $q->url;
my $sort = param("s");  # Sort key
# the POST routine reads its own input parameters

################################################################################
# Global variables
# Mostly from reading the file, used in various places
################################################################################
# TODO - Remove most of these
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

# Collect all 'global' variables here in one context
my $c = {
  'username' => $username,
  'datadir'  => $datadir,
  'databasefile' => $databasefile,
  'plotfile' => $plotfile,
  'cmdfile'  => $cmdfile,
  'photodir' => $photodir,
  'dbh'      => $dbh,
  'url'      => $url,
  'cgi'      => $q,
  'edit'     => $edit,
  'qry'      => $qry,
  'op'       => $op,
  'sort'     => $sort,
  'onedrink' => $onedrink,
  'bgcolor'  => $bgcolor,
  'devversion' => $devversion,
  'mobile'   => $mobile,

};

################################################################################
# Program modules
################################################################################
# After declaring 'our' variables, before calling any functions
# TODO - More modules, more stuff away from the main script
require "./persons.pm";   # List of people, their details, editing, helpers
require "./locations.pm"; # Locations stuff
require "./brews.pm";  # Lists of various brews, etc
require "./glasses.pm"; # Main input for and the full list
require "./comments.pm"; # Stuff for comments, ratings, and photos
require "./util.pm"; # Various helper functions
require "./graph.pm"; # The daily graph
require "./stats.pm"; # Various statistics
require "./VERSION.pm"; # auto-generated version info

################################################################################
# Main program
################################################################################


if ($devversion) { # Print a line in error.log, to see what errors come from this invocation
  print STDERR datestr() . " " . $q->request_method . " " .  $ENV{'QUERY_STRING'} . " \n";
}

if ( $devversion && $op eq "copyproddata" ) {
  print STDERR "Copying prod data to dev \n";
  copyproddata();
  exit;
}

my $datafilecomment = "";

# # Default new users to the about page, we have nothing else to show
# TODO - Make a better check, and force  the about page to show an input form
# if ( !$op) {
#   if ( !@lines) {
#     $op = "About";
#   } else {
#     $op = "Graph";  # Default to showing the graph
#   }
# }

if ( $q->request_method eq "POST" ) {

  if ( 1 ) { # TODO LATER Remove this debug dumping of all CGI params
    foreach my $param ($c->{cgi}->param) { # Debug dump params while developing
      my $value = $c->{cgi}->param($param);
      print STDERR "p: $param = '$value'\n" if ($value);
    }
  }

  $dbh->do("BEGIN TRANSACTION");

  if ( $op =~ /Person/i ) {
    persons::postperson($c);
  } elsif ( $op =~ /Location/i ) {
    locations::postlocation($c);
  } elsif ( $op =~ /Beer|Brew/i ) {
    brews::postbrew($c);
  } elsif ( util::param($c, "commentedit") ) {
    comments::postcomment($c);
  } else { # Default to posting a glass
    glasses::postglass($c);
  }

  $dbh->do("COMMIT");

  # Redirect back to the edit page. Clear Set up $c as needed
  print $c->{cgi}->redirect( "$c->{url}?o=$c->{op}&e=$c->{edit}" );
  $dbh->disconnect;
  exit;
}


htmlhead($datafilecomment); # Ok, now we can commit to making a HTML page

print util::topline($c);

if ( $op =~ /Board/i ) {
  glasses::inputform($c);
  oldstuff();
  graph();
  beerboard();
  fulllist();
} elsif ( $op =~ /Years(d?)/i ) {
  stats::yearsummary($c,$1); # $1 indicates sort order
} elsif ( $op =~ /short/i ) {
  stats::dailystats($c);
} elsif ( $op =~ /Months([BS])?/ ) {
  stats::monthstat($c,$1);
} elsif ( $op =~ /DataStats/i ) {
  stats::datastats($c);
} elsif ( $op eq "About" ) {
  # The about page went from 500ms to under 100 when dropping the oldstuff
  about();
} elsif ( $op =~ /Brew/i ) {
  brews::listbrews($c);
} elsif ( $op =~ /Person/i ) {
  persons::listpersons($c);
} elsif ( $op =~ /Location/i ) {
  locations::listlocations($c);
} elsif ( $op =~ /Full/i ) {
  glasses::inputform($c);
  oldstuff();
  fulllist();
} else { # Default to the graph
  $op = "Graph" unless $op;
  oldstuff();
  graph();
  glasses::inputform($c);
  fulllist();
}

$dbh->disconnect;
htmlfooter();
exit();  # The rest should be subs only

# End of main

# Helper to do all the 'global' stuff needed by old form pages
# Used to be called in the beginning, but separated for different pages
# above, so we can skip it for modern things
sub oldstuff {
  readdatalines();
  extractgeo(); # Extract geo coords
  javascript(); # with some javascript trickery in it
}

################################################################################
# Copy production data to dev file
# Needs to be before the HTML head, as it forwards back to the page
################################################################################
# Nice to see up to date data when developing
# NOTE Had some problems with file permissions and the -wal and -shm files. Now I
# delete those first, and copy over if they exist. Seems to work. But I leave
# noted to STDERR so I can look in the log if I run into problems later.
sub copyproddata {
  if (!$devversion) {
    util::error ("Not allowed");
  }
  $dbh->disconnect;
  print STDERR "Before: \n" . `ls -l $databasefile* ` . `ls -l ../beertracker/$databasefile*`;
  system("rm $databasefile-*");  # Remove old -shm and -wal files
  print STDERR "rm $databasefile-* \n";
  system("cp ../beertracker/$databasefile* $datadir"); # And copy all such files over
  print STDERR "cp ../beertracker/$databasefile* $datadir \n";
  graph::clearcachefiles( $c );
  system("cp ../beertracker/$photodir/* $photodir");
  print STDERR "After: \n" . `ls -l $databasefile* ` . ` ls -l ../beertracker/$databasefile*`;
  print $q->redirect( "$url" ); # without the o=, so we don't copy again and again
  exit();
} # copyproddata


################################################################################
# Read the records
# Reads all the records into @lines, to simulate the old way of reading the
# whole file. Puts the whole records in @records
# This costs some 400ms for every page, but speeds up the really slow ones, like
# full list filtering from 30 seconds to 3.
################################################################################
# TODO - At some point we won't need this at all, when each function reads its
# own things from the database.

sub readdatalines {
  my $nlines = 0;
  $lines[0] = "";
  my $sql = "select * from glassrec where username = ? order by stamp";
  my $get_sth = $dbh->prepare($sql);
  $get_sth->execute($username);
  my $rn = 1;

 while ( my $rec = $get_sth->fetchrow_hashref ) {
    $lines[$rn] = $rec->{stamp};
    fixrecord($rec, $rn);
    $records[$rn] = $rec;
    $rn++;
  }
  my $ndatalines = scalar(@lines)-1;
  return "<!-- Read $ndatalines records from the database to the lines array-->\n";
}

################################################################################
# Get all geo locations
# TODO - Don't use this for the javascript, send also the 'last' time
################################################################################
sub extractgeo {
#  Earlier version of the sql, with last seen and sorting
#     select name, GeoCoordinates, max(timestamp) as last
#     from Locations, glasses
#     where  LOCATIONS.id = GLASSES.Location
#       and GeoCoordinates is not null
#     group by location
#     order by last desc
  my $sql = q(
    select name, GeoCoordinates
    from Locations, glasses
    where  LOCATIONS.id = GLASSES.Location
      and GeoCoordinates is not null
    group by location
  ); # No need to sort here, since put it all in a hash.
  my $get_sth = $dbh->prepare($sql);
  $get_sth->execute();
  while ( my ($name, $geo, $last) = $get_sth->fetchrow_array ) {
    $geolocations{$name} = $geo;
  }

}



################################################################################
# A helper to calculate blood alcohol for a given effdate
# Returns a hash with bloodalcs for each timestamp for the effdate
#  $bloodalc{"max"} = max ba for the date
#  $bloodacl{"date"} = the effdate we calculated for
#  $bloodalc{$timestamp} = ba after ingesting that glass
################################################################################
# TODO: Change this to return a list of values: ( date, max, hashref ). Add time when gone

sub bloodalcohol {
  my $effdate = shift; # effdate we are interested in
  if ( !$bodyweight ) {
    print STDERR "Can not calculate alc for $username, don't know body weight \n";
    return undef;
  }
  #print STDERR "Bloodalc for '$effdate' \n";
  my $bloodalc = {};
  $bloodalc->{"date"} = $effdate;
  my $sql = q(
    select
      timestamp,
      strftime ('%Y-%m-%d', timestamp,'-06:00') as effdate,
      alc * volume as alcvol
    from glasses
    where effdate = ?
      and alc > 0
      and volume > 0
    order by timestamp
  ); # No need to sort here, since put it all in a hash.
  my $get_sth = $dbh->prepare($sql);
  $get_sth->execute($effdate);
  my $alcinbody = 0;
  my $balctime = 0;
  my $maxba = 0;
  while ( my ($stamp, $eff, $alcvol) = $get_sth->fetchrow_array ) {
    next unless $alcvol;
    my $drtime = $1 + $2/60 if ($stamp =~/ (\d?\d):(\d\d)/ ); # frac hrs
    $drtime += 24 if ( $drtime < $balctime ); # past midnight
    my $timediff = $drtime - $balctime;
    $balctime = $drtime;
    $alcinbody -= $burnrate * $bodyweight * $timediff;
    $alcinbody = 0 if ( $alcinbody < 0);
    $alcinbody += $alcvol / $onedrink * 12 ; # grams of alc in std drink
    my $ba = $alcinbody / ( $bodyweight * .68 ); # non-fat weight
    $maxba = $ba if ( $ba > $maxba );
    $bloodalc->{$stamp} = $ba;
    #print STDERR "  $stamp : $ba \n";
  }
  $bloodalc->{"max"} = $maxba ;
  #print STDERR "  max : $maxba \n";
  return $bloodalc;

}

#     # Get allgone  TODO
#     my $now = datestr( "%H:%M", 0, 1);
#     my $drtime = $1 + $2/60 if ($now =~/^(\d\d):(\d\d)/ ); # frac hrs
#     $drtime += 24 if ( $drtime < $balctime ); # past midnight
#     my $timediff = $drtime - $balctime;
#     $alcinbody -= $burnrate * $bodyweight * $timediff;
#     $alcinbody = 0 if ( $alcinbody < 0);
#     $curba = $alcinbody / ( $bodyweight * .68 ); # non-fat weight
#     my $lasts = $alcinbody / ( $burnrate * $bodyweight );
#     my $gone = $drtime + $lasts;
#     $gone -= 24 if ( $gone > 24 );
#     $allgone = sprintf( "%02d:%02d", int($gone), ( $gone - int($gone) ) * 60 );


# Helper to see if a field is missing
sub missing {
  my $rec = shift;
  my $fld = shift;
  return  (defined($rec->{$fld}) && $rec->{$fld} eq "" );
}


###############################################
# TODO - Move the photo handling into its own module.
# At the moment not used at all, kept here as an example


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
  return "" unless ( $rec->{photo} && $rec->{photo} =~ /^2/);
  my $orig = imagefilename($rec->{photo}, "orig");
  if ( ! -r $orig ) {
    print STDERR "Photo file '$orig' not found for record $rec->{stamp} \n";
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
  print "  input:valid { border: 1px solid white; } \n";
  print "  input:invalid { border: 1px solid red; } \n";
  print "  select { border: 1px solid white; } \n";
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

  $script .= "var origloc=\" $foundrec->{loc}\"; \n"
    if ( $foundrec );

  $script .= <<'SCRIPTEND';
    var geoloc = "";

    function savelocation (myposition) {
    }

    function OLDsavelocation (myposition) {  // TODO - Geo disabled for now
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
        if (! loc)
          return;
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
    getrecord(1);
    while ( $startdate lt $records[1]->{date}) {
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

      my %sums; # drink sums by (eff) date
      my %lastdateindex;
      my $bloodalc;
      my $maxba = {};
      for ( my $i = scalar(@lines)-1; $i >= 0; $i-- ) { # calculate sums
        my $rec = getrecord($i);
        #nullallfields($rec);
        next if ( $rec && $rec->{type} =~ /^Restaurant/i ); # TODO Fails on a tz? line
        next unless ($rec->{alcvol});
        $sums{$rec->{effdate}} += $rec->{alcvol};
        $lastdateindex{$rec->{effdate}} = $i unless ( $lastdateindex{$rec->{effdate}} );
        if ( !$bloodalc || !$bloodalc->{"date"} || $bloodalc->{"date"} ne $rec->{effdate} ) {
          $bloodalc = bloodalcohol($rec->{effdate});
          $maxba->{$rec->{effdate}} = $bloodalc->{"max"};
        }
        last if ( $rec->{effdate} lt $prestartdate );
      }
      my $ndays = $startoff+35; # to get enough material for the running average
      my $date;
      open F, ">$plotfile"
          or util::error ("Could not open $plotfile for writing");
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
            $lastavg = sprintf("30d (%2.1f/d %0.0f/w)", $sum30, $sum30*7) if ($sum30 > 0);
            $lastwk = sprintf("wk (%2.1f/d %0.0f/w)", $sumweek, $sumweek*7) if ($sumweek > 0);
          } else {
            $lastavg = sprintf("m %2.1f", $sum30) if ($sum30 > 0);
            $lastwk = sprintf("w %0.0f", $sumweek*7) if ($sumweek > 0);
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
          my $wkendcolor = $bgcolor;
          $wkendcolor =~ s/003/005/;
          $weekends .= "set object $wkendtag rect at \"$date\",50 " .
            "size $threedays,200 behind  fc rgbcolor \"$wkendcolor\"  fillstyle solid noborder \n";
          $wkendtag++;
        }

        # Collect drink types into $drinkline ready for plotting
        my $drinkline = "";
        my $totdrinks = $tot;
        my $ndrinks = 0;
        my $ba = -1 ; # invisible
        $ba = $maxba->{$date} * 10 if ( $maxba->{$date} );

        if ( $lastdateindex{$date} ) {
          my $i = $lastdateindex{$date};
          my $lastrec = getrecord($i);
          my $lastloc = $lastrec->{loc};
          my $lasttime = $1 + $2/60 if ( $lastrec->{time} =~ /^(\d+):(\d\d)/ );
          my $lasteff = $lastrec->{effdate};
          while ( $records[$i]->{effdate} eq $date ) {
            my $drec = $records[$i];
            my $dtime = $1 + $2/60 if ( $drec->{time} =~ /^(\d+):(\d\d)/ );
            my $timediff = $lasttime - $dtime ;
            $timediff +=24 if ( $timediff < 0);
            if ( $startoff - $endoff < 100  ) {
              if ( $lastloc ne $drec->{loc} || $timediff > 3 ) {
                my $lw = $totdrinks + 0.2; # White line for location change
                $lw += 0.1 unless ($bigimg eq "B");
                $drinkline .= "$lw 0xffffff ";
                $lastloc = $drec->{loc};
                $ndrinks++;
              }
            }
            if ( $drec->{alcvol} ) {
              my $color = beercolor($drec,"0x");
              my $drinks = $drec->{alcvol} / $onedrink;
              $drinkline .= "$totdrinks $color ";
              $ndrinks ++;
              $totdrinks -= $drinks;
              last if ($totdrinks <= 0 ); #defensive coding, have seen it happen once
            }
            $lasttime = $dtime;
            $i--;
          }

        }
        print STDERR "Many ($ndrinks) drink entries on $date \n"
          if ( $ndrinks >= 20 ) ;
        while ( $ndrinks++ < 20 ) {
          $drinkline .= "0 0x0 ";
        }

        if ($zerodays >= 0) {
          print F "$date  $tot $sum30 $sumweek  $zero $fut $ba  $drinkline \n" ;
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
        my $batitle = "notitle" ;
        $batitle =  "title \"ba\" " if ( $bigimg eq "B" );
        my $plotweekline =
          "\"$plotfile\" using 1:4 with linespoints lc \"#00dd10\" pointtype 7 axes x1y2 title \"$lastwk\", " .
          "\"$plotfile\" using 1:7 with points lc \"red\" pointtype 1 pointsize 0.2 axes x1y2 $batitle, ";
        my $xtic = 1;
        my @xyear = ( $oneyear, "\"%y\"" );   # xtics value and xformat
        my @xquart = ( $oneyear / 4, "\"%b\\n%y\"" );  # Jan 24
        my @xmonth = ( $onemonth, "\"%b\\n%y\"" ); # Jan 24
        my @xweek = ( $oneweek, "\"%d\\n%b\"" ); # 15 Jan
        my $pointsize = "";
        my $fillstyle = "fill solid noborder";  # no gaps between drinks or days
        my $fillstyleborder = "fill solid border linecolor \"$bgcolor\""; # Small gap around each drink
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
              "behind fc \"$bgcolor\" fillstyle solid border \n";  # green bkg
        for (my $m=6; $m<$maxd-7; $m+= 21) {
          $cmd .= "set arrow from \"$startdate\", $m to \"$enddate\", $m nohead linewidth 1 linecolor \"#00dd10\" \n"
            if ( $maxd > $m + 7 );
        }
        $cmd .=
            $weekends .
            "plot " .
                  # note the order of plotting, later ones get on top
                  # so we plot weekdays, avg line, zeroes

              "\"$plotfile\" using 1:8:9 with boxes lc rgbcolor variable axes x1y2 notitle, " .
              "\"$plotfile\" using 1:10:11 with boxes lc rgbcolor variable axes x1y2 notitle, " .
              "\"$plotfile\" using 1:12:13 with boxes lc rgbcolor variable axes x1y2 notitle, " .
              "\"$plotfile\" using 1:14:15 with boxes lc rgbcolor variable axes x1y2 notitle, " .
              "\"$plotfile\" using 1:16:17 with boxes lc rgbcolor variable axes x1y2 notitle, " .
              "\"$plotfile\" using 1:18:19 with boxes lc rgbcolor variable axes x1y2 notitle, " .
              "\"$plotfile\" using 1:20:21 with boxes lc rgbcolor variable axes x1y2 notitle, " .
              "\"$plotfile\" using 1:22:23 with boxes lc rgbcolor variable axes x1y2 notitle, " .
              "\"$plotfile\" using 1:24:25 with boxes lc rgbcolor variable axes x1y2 notitle, " .
              "\"$plotfile\" using 1:26:27 with boxes lc rgbcolor variable axes x1y2 notitle, " .
              "\"$plotfile\" using 1:28:29 with boxes lc rgbcolor variable axes x1y2 notitle, " .
              "\"$plotfile\" using 1:30:31 with boxes lc rgbcolor variable axes x1y2 notitle, " .
              "\"$plotfile\" using 1:32:33 with boxes lc rgbcolor variable axes x1y2 notitle, " .
              "\"$plotfile\" using 1:34:35 with boxes lc rgbcolor variable axes x1y2 notitle, " .
              "\"$plotfile\" using 1:36:37 with boxes lc rgbcolor variable axes x1y2 notitle, " .
              "\"$plotfile\" using 1:38:39 with boxes lc rgbcolor variable axes x1y2 notitle, " .
              "\"$plotfile\" using 1:40:41 with boxes lc rgbcolor variable axes x1y2 notitle, " .
              "\"$plotfile\" using 1:42:43 with boxes lc rgbcolor variable axes x1y2 notitle, " .
              "\"$plotfile\" using 1:44:45 with boxes lc rgbcolor variable axes x1y2 notitle, " .
              "\"$plotfile\" using 1:46:47 with boxes lc rgbcolor variable axes x1y2 notitle, " .

              "$weekline " .
              "\"$plotfile\" " .
                  "using 1:3 with line lc \"#FfFfFf\" lw 3 axes x1y2 title \"$lastavg\", " .  # avg30
                    # smooth csplines
              "\"$plotfile\" " .
                  "using 1:6 with points pointtype 7 lc \"#E0E0E0\" axes x1y2 notitle, " .  # future tail
              "\"$plotfile\" " .
                  "using 1:5 with points lc \"#00dd10\" pointtype 11 axes x1y2 notitle \n" .  # zeroes (greenish)
              "";
        open C, ">$cmdfile"
            or util::error ("Could not open $plotfile for writing");
        print C $cmd;
        close(C);
        system ("gnuplot $cmdfile ");
      } # havedata
    } # Have to plot

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
    print "<hr/>\n";

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
  if ( ! $foundrec ) {
    my $sql = "select * from glassrec " .
              "where username = ? " .
              "order by stamp desc ".
              "limit 1";
    my $sth = $c->{dbh}->prepare($sql);
    $sth->execute( $c->{username} );
    $foundrec = $sth->fetchrow_hashref;
    $sth->finish;
  }

  my $locparam = param("loc") || $foundrec->{loc} || "";
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

  print "<a href='$url?o=board&loc=$locparam&f=f'><i>(Reload)</i></a>\n";
  print "<a href='$url?o=board-2&loc=$locparam'><i>(all)</i></a>\n";

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
    open CF, $cachefile or util::error ("Could not open $cachefile for reading");
    while ( <CF> ) {
      $json .= $_ ;
    }
    close CF;
    print "<!-- Loaded cached board from '$cachefile' -->\n";
  }
  if ( !$json ){
    $json = `perl $script`;
    $loaded = 1;
    print "<!-- run scraper script '$script' -->\n";
  }
  if (! $json) {
    print "Sorry, could not get the list from $locparam<br/>\n";
    print "<!-- Error running " . $scrapers{$locparam} . ". \n";
    print "Result: '$json'\n -->\n";
  }else {
    if ($loaded) {
      open CF, ">$cachefile" or util::error( "Could not open $cachefile for writing");
      print CF $json;
      close CF;
    }
    chomp($json);
    #print "<!--\nPage:\n$json\n-->\n";  # for debugging
    my $beerlist = JSON->new->utf8->decode($json)
      or util::error("Json decode failed for $scrapers{$locparam} <pre>$json</pre>");
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
        if ( $sty =~ /Cider/i ) {
          $hiddenbuttons .= "<input type='hidden' name='type' value='Cider' />\n" ;
        } else {
          $hiddenbuttons .= "<input type='hidden' name='type' value='Beer' />\n" ;
        }
        $hiddenbuttons .= "<input type='hidden' name='country' value='$country' />\n"
          if ($country) ;
        $hiddenbuttons .= "<input type='hidden' name='maker' value='$mak' />\n" ;
        $hiddenbuttons .= "<input type='hidden' name='name' value='$beer' />\n" ;
        $hiddenbuttons .= "<input type='hidden' name='style' value='$origsty' />\n" ;
        $hiddenbuttons .= "<input type='hidden' name='subtype' value='$sty' />\n" ;
        $hiddenbuttons .= "<input type='hidden' name='alc' value='$alc' />\n" ;
        $hiddenbuttons .= "<input type='hidden' name='loc' value='$loc' />\n" ;
        $hiddenbuttons .= "<input type='hidden' name='o' value='board' />\n" ;  # come back to the board display
      my $buttons="";
      #foreach my $sp ( sort( {($a->{"vol"} <=> $b->{"vol"}) || ($a->{"vol"} cmp $b->{"vol"}) } @$sizes) ) {
      while ( scalar(@$sizes) < 2 ) {
        push @$sizes, { "vol" => "", "price" => "" };
      }
      foreach my $sp ( @$sizes ) {
        my $vol = $sp->{"vol"} || "";
        my $pr = $sp->{"price"} || "";
        my $lbl;
        if ($extraboard == $id || $extraboard == -2) {
          my $dispvol = $vol;
          $dispvol = $1 if ( $glasses::volumes{$vol} && $glasses::volumes{$vol} =~ /(^\d+)/);   # Translate S and L
          $lbl = "$dispvol cl  ";
          $lbl .= sprintf( "%3.1fd", $dispvol * $alc / $onedrink);
          $lbl .= "\n$pr.- " . sprintf( "%d/l ", $pr * 100 / $vol ) if ($pr);
        } else {
          if ( $pr ) {
            $lbl = "$pr.-";
          } elsif ( $vol =~ /\d/ ) {
            $lbl = "$vol cl";
          } elsif ( $vol ) {
            $lbl = "&nbsp; $vol &nbsp;";
          } else {
            $lbl = " ";
          }
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

      my $dispid = $id;
      $dispid = "&nbsp;&nbsp;$id"  if ( length($dispid) < 2);
      if ($extraboard == $id  || $extraboard == -2) { # More detailed view
        print "<tr><td colspan=5><hr></td></tr>\n";
        print "<tr><td align=right $beerstyle>";
        my $linkid = $id;
        if ($extraboard == $id) {
          $linkid = "-3";  # Force no expansion
        }
        print "<a href='$url?o=board$linkid&loc=$locparam'><span width=100% $beerstyle id='here'>$dispid</span></a> ";
        print "</td>\n";

        print "<td colspan=4 >";
        print "<span style='white-space:nowrap;overflow:hidden;text-overflow:clip;max-width=100px'>\n";
        print "$mak: $dispbeer ";
        print "<span style='font-size: x-small;'>($country)</span>" if ($country);
        print "</span></td></tr>\n";
        print "<tr><td>&nbsp;</td><td colspan=4> $buttons &nbsp;\n";
        print "<form method='POST' accept-charset='UTF-8' style='display: inline;' class='no-print' >\n";
        print "$hiddenbuttons";
        print "<input type='hidden' name='vol' value='T' />\n" ;  # taster
        print "<input type='hidden' name='pr' value='X' />\n" ;  # at no cost
        print "<input type='submit' name='submit' value='Taster ' /> \n";
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
        print "<a href='$url?o=board$id&loc=$locparam#here'><span width=100% $beerstyle>$dispid</span></a> ";
        print "</td>\n";
        print "$buttons\n";
        print "<td style='font-size: x-small;' align=right>$alc</td>\n";
        print "<td>$dispbeer $dispmak ";
        print "<span style='font-size: x-small;'>($country)</span> " if ($country);
        print "$sty</td>\n";
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
# About page
################################################################################

sub about {


  print "<hr/><h2>Beertracker</h2>\n";
  print "Copyright 2016-2025 Heikki Levanto. <br/>";
  print "Beertracker is my little script to help me remember all the beers I meet.\n";
  print "It is Open Source (GPL v2)\n";
  print "<hr/>";

  my $v = Version::version_info();
  print "This is ";
  print "DEVELOPMENT " if ( $c->{devversion} );
  print "version $v->{tag} ";
  print "plus $v->{commits} commits " if ( $v->{commits} );
  print "<br>\n";
  print "commit $v->{commit} from $v->{date} ";
  print "on '$v->{branch}' " if ( $v->{branch} ne "master" );
  print "<br/><br/>\n";
  if ( $c->{devversion} ) {
    print "The production version is ";
    $v = util::getversioninfo("../beertracker");
  } else {
    print "The development version is ";
    $v = util::getversioninfo("../beertracker-dev");
  }
  print "$v->{tag} ";
  print "plus $v->{commits} commits " if ( $v->{commits} );
  print "<br>\n";
  print "commit $v->{commit} from $v->{date} ";
  print "on '$v->{branch}' " if ( $v->{branch} ne "master" );
  print "<hr/>\n";

  print "Beertracker on GitHub: <ul>";
  print aboutlink("GitHub","https://github.com/heikkilevanto/beertracker");
  print aboutlink("Bugtracker", "https://github.com/heikkilevanto/beertracker/issues" .
      "?q=is%3Aissue+is%3Aopen+sort%3Aupdated-desc+-label%3ANextVersion");
  print aboutlink("User manual", "https://github.com/heikkilevanto/beertracker/blob/master/manual.md" );
  print "</ul><p>\n";
  print "Some of my favourite bars and breweries<ul>";
  for my $k ( sort keys(%links) ) {  # TODO - Get these from the database somehow. Or skip
    print aboutlink($k, $links{$k});
  }
  print "</ul><p>\n";
  print "Other useful links: <ul>";
  print aboutlink("Events", "https://www.beercph.dk/");
  print aboutlink("Ratebeer", "https://www.ratebeer.com");
  print aboutlink("Untappd", "https://untappd.com");
  print "</ul><p>\n";
  print "<hr/>";

  print "Shorthand for drink volumes<br/><ul>\n";
  for my $k ( keys(%glasses::volumes) ) {
    print "<li><b>$k</b> $glasses::volumes{$k}</li>\n";
  }
  print "</ul>\n";
  print "You can prefix them with 'h' for half, as in HW = half wine = 37cl<br/>\n";
  print "Of course you can just enter the number of centiliters <br/>\n";
  print "Or even ounces, when traveling: '6oz' = 18 cl<br/>\n";

  print "<p><hr>\n";
  print "This site uses no cookies, and collects no personally identifiable information<p>\n";


  print "<p><hr/>\n";
  #print "<b>Debug info </b><br/>\n";  # TODO - Add new debug helpers here if needed
  #print "&nbsp; <a href='$url?o=Datafile&maxl=30' target='_blank' ><span>Tail of the data file</span></a><br/>\n";
  #print "&nbsp; <a href='$url?o=Datafile'  target='_blank' ><span>Download the whole data file</span></a><br/>\n";
  exit();
} # About


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
  $qrylim = "x" if ( $qryfield =~ /Geoerror/i ) ;
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
  my $rec = getrecord_com($i-1);
  my $lastrec; # TODO - Use this instead of the many last-somethings above
  my $bloodalc;
  while ( $i > 0 ) {  # Usually we exit at end-of-day
    $i--;
    $lastrec = $rec;
    $rec = getrecord_com($i);
    next if filtered ( $rec );
    nullallfields($rec);  # Make sure we don't access undefined values, fills the log with warnings
    $maxlines--;

    $origpr = $rec->{pr};

    my $dateloc = "$rec->{effdate} : $rec->{loc}";
    #bloodalcohol($i); # TODO Pass effdate

    if ( $dateloc ne $lastloc && ! $qry) { # summary of loc and maybe date
      print "\n";
      my $locdrinks = sprintf("%3.1f", $locdsum / $onedrink) ;
      my $daydrinks = sprintf("%3.1f", $daydsum / $onedrink) ;
      # loc summary: if nonzero, and diff from daysummary
      # or there is a new loc coming,
      if ( $locdrinks > 0.1) {
        print "<br/>=== $lastwday ";
        print "$lastloc2: " . unit($locdrinks,"d"). unit($locmsum, ".-"). "\n";
        if ($averages{$lastdate} && $locdrinks eq $daydrinks && $lastdate ne $rec->{effdate}) {
          print " (a=" . unit($averages{$lastdate},"d"). " )\n";
          if ($bloodalc{$lastdate}) { #
            print " ". unit(sprintf("%0.2f",$bloodalc{$lastdate}), "‰");
          }
          print "<br/>\n";
        } # fl avg on loc line, if not going to print a day summary line
        # Restaurant copy button was here
      }
      # day summary
      if ($lastdate ne $rec->{effdate} ) {
        if ( $locdrinks ne $daydrinks) {
          print "<br/> === <b>$lastwday</b>: ". unit($daydrinks,"d"). unit($daymsum,".-");
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
      $bloodalc = bloodalcohol($rec->{effdate});
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
        print utlink($rec->{loc}), rblink($rec->{loc}), glink($rec->{loc}) , "<br>\n";
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
    print filt($rec->{name},"b","","","name") . newmark($rec->{name}, $rec->{maker}) unless ($rec->{type} eq "Restaurant");
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
      if ( ! $rec->{bloodalc} && $bloodalc->{ $rec->{stamp} } ) {
        $rec->{bloodalc} = $bloodalc->{ $rec->{stamp} };
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
        print "<i>$rec->{com}</i>" if ($rec->{com} =~ /\w/);
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
        my $seenline = seenline($rec->{maker}, $rec->{name});
        if ($seenline) {
          print "<span style='white-space: nowrap'>";
          print $seenline;
          print "</span><br>\n";
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
    print "<a href='$url?o=$op&q=$qry&e=" . uri_escape_utf8($rec->{glassid}) ."' ><span>Edit</span></a> \n";

    # Copy values
    my $fieldnamelistref = $datalinetypes{$rec->{type}};
    my @fieldnamelist = @{$fieldnamelistref};
    foreach my $k ( @fieldnamelist ) {
      next if $k =~ /stamp|wday|effdate|loc|vol|geo|rate|com|people|food/; # not these
      print "<input type='hidden' name='$k' value='$rec->{$k}' />\n";
    }
    print "<input type='hidden' name='geo' id='geo' value='' />\n"; # with the id
    { # Input fields to simulate the new input form
      my $brewid = $rec->{brewid} || "";
      my $locid = $rec->{locid} || "";
      #print "<input type='hidden' name='Location'  value='$locid' />\n";
      # TODO - Copied the location too, have to change manually
      print "<input type='hidden' name='Brew'  value='$brewid' />\n";
      print "<input type='hidden' name='selbrewtype'  value='$rec->{type}' />\n";
      # TODO - Geo location ??
    }
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
  if ( $qryfield eq "rawline" && ! $rec->{rawline} ) {
    for my $k ( keys %{$rec} ) {
      $rec->{rawline} .= "; " . ( $rec->{$k} || "" ) ;
    }
    #util::error ( "Made rawline '$rec->{rawline}' ");
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
    $skip = 1 if ( $rec->{stamp} !~ /^$yrlim/ );
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
  $long =~ s/\?.*$//; # Remove parameters
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
  my $s = "[$rec->{glassid}] " .  "<b>". unit($rec->{vol}, "cl") . "</b>";
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
  $seenkey = seenkey($maker,$beer);
  return "" unless ($seenkey);
  return "" unless ($seenkey =~ /[a-z]/ );  # At least some real text in it
  my $countsql = q{
    select brews.id, count(glasses.id)
    from brews, glasses, locations
    where brews.id = glasses.brew
    and locations.id = brews.producerlocation
    and locations.name = ?
    and brews.name = ?
  };
  my $get_sth = $dbh->prepare($countsql);
  $get_sth->execute($maker,$beer);
  my ( $brewid, $count ) = $get_sth->fetchrow_array;
  return "" unless($count);
  my $seenline = "Seen <b>$count</b> times: ";
  my $listsql = q{
    select
      distinct strftime ('%Y-%m-%d', timestamp,'-06:00') as effdate
    from glasses
    where brew = ?
    order by timestamp desc
    limit 7
  };
  my $prefix = "";
  my $detail="";
  my $detailpattern = "";
  my $nmonths = 0;
  my $nyears = 0;
  my $list_sth = $dbh->prepare($listsql);
  $list_sth->execute($brewid);
  while ( my $eff = $list_sth->fetchrow_array ) {
    my $comma = ",";
    if ( ! $prefix || $eff !~ /^$prefix/ ) {
      $comma = ":" ;
      if ( $nmonths++ < 2 ) {
        ($prefix) = $eff =~ /^(\d+-\d+)/ ;  # yyyy-mm
        $detailpattern = "(\\d\\d)\$";
      } elsif ( $nyears++ < 1 ) {
        ($prefix) = $eff =~ /^(\d+)/ ;  # yyyy
        $detailpattern = "(\\d\\d)-\\d\\d\$";
      } else {
        $prefix = "20";
        $detailpattern = "^20(\\d\\d)";
        $comma = "";
      }
      $seenline .= " <b>$prefix</b>";
    }
    my ($det) = $eff =~ /$detailpattern/ ;
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
  my $sty = shift || "";
  return "" unless $sty;
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
    return "SIPA"  if ( $sty =~ /Session/i);
    return "BIPA"  if ( $sty =~ /Black/i);
    return "DNE"   if ( $sty =~ /(Double|Triple).*(New England|NE)/i);
    return "DIPA"  if ( $sty =~ /Double|Dipa|Triple/i);
    return "WIPA"  if ( $sty =~ /Wheat/i);
    return "NEIPA" if ( $sty =~ /New England|NE|Hazy/i);
    return "NZIPA" if ( $sty =~ /New Zealand|NZ/i);
    return "WC"    if ( $sty =~ /West Coast|WC/i);
    return "AIPA"  if ( $sty =~ /America|US/i);
    return "IPA";
  }
  return "Dunk"  if ( $sty =~ /.*Dunkel.*/i);
  return "Bock"  if ( $sty =~ /Bock/i);
  return "Smoke" if ( $sty =~ /(Smoke|Rauch)/i);
  return "Lager" if ( $sty =~ /Lager|Keller|Pils|Zwickl/i);
  return "Berl"  if ( $sty =~ /Berliner/i);
  return "Weiss" if ( $sty =~ /Hefe|Weizen|Hvede|Wit/i);
  return "Stout" if ( $sty =~ /Stout|Porter|Imperial/i);
  return "Farm"  if ( $sty =~ /Farm/i);
  return "Sais"  if ( $sty =~ /Saison/i);
  return "Dubl"  if ( $sty =~ /(Double|Dubbel)/i);
  return "Trip"  if ( $sty =~ /(Triple|Tripel|Tripple)/i);
  return "Quad"  if ( $sty =~ /(Quadruple|Quadrupel)/i);
  return "Trap"  if ( $sty =~ /Trappist/i);
  return "Blond" if ( $sty =~ /Blond/i);
  return "Brown" if ( $sty =~ /Brown/i);
  return "Strng" if ( $sty =~ /Strong/i);
  return "Belg"  if ( $sty =~ /Belg/i);
  return "BW"    if ( $sty =~ /Barley.*Wine/i);
  return "Sour"  if ( $sty =~ /Lambic|Gueuze|Sour|Kriek|Frmaboise/i);
  $sty =~ s/^ *([^ ]{1,5}).*/$1/; # First word, only five chars, in case we didn't get it above
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



# Helper to fix a record after getting it from the database
sub fixrecord {
  my $rec = shift;
  my $recindex = shift || "";
  # Normalize some common fields
  $rec->{alc} = number( $rec->{alc} );
  $rec->{vol} = number( $rec->{vol} );
  $rec->{pr} = price( $rec->{pr} );
  if (! $rec->{stamp} ) {   # Should never happen
    # Only when working with the timestamp code. Make the error visible, but don't crash
    print STDERR "fixrecord: Missing stamp in $recindex: '$rec->{stamp}'  on '$rec->{effdate}' '$rec->{name}' \n";
    print "fixrecord: Missing stamp in $recindex: '$rec->{stamp}'  on '$rec->{effdate}' '$rec->{name}' \n";

  }
  # Precalculate some things we often need
  my @weekdays = ( "Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun" );
  $rec->{wday} = $weekdays[ $rec->{wdaynumber} ] ;
  my $alcvol = $rec->{alc} * $rec->{vol} || 0 ;
  $alcvol = 0 if ( $rec->{pr} < 0  );  # skip box wines
  $rec->{alcvol} = $alcvol;
  $rec->{drinks} = $alcvol / $onedrink;
  nullfields($rec); # Make sure we accept missing values for fields
  $rec->{seenkey} = seenkey($rec);
}


# Helper to get a record from the database by array index
# Does not get comments, that's too slow, and often not needed. But does get
# brew names and locations.
sub getrecord {
  my $i = shift;
  $i++ unless $i; # trick to get around [0]
  if ( ! $records[$i] ) {
    my $ts = $lines[$i];
    util::error ("No timestamp for record '$i' ") unless ($ts);
    my $sql = "select * from glassrec where username=? and stamp = ?";
    my $get_sth = $dbh->prepare($sql);
    $get_sth->execute($username, $ts);
    my $rec = $get_sth->fetchrow_hashref;
    util::error("Got no record $i ($ts) for '$username'") unless ($rec);
    #print STDERR "got rec $i: '$rec' : " ,  JSON->new->encode($rec), "\n";
    fixrecord($rec, $i);
    $records[$i] = $rec;
  }
  return $records[$i];
}


# Helper to get a full record with comments
sub getrecord_com {
  my $i = shift;
  my $rec = getrecord($i);
  if ( ! defined($rec->{com_cnt} ) ) {  # no comments yet, get them
    my $get_sth = $dbh->prepare("select * from compers where id = ?");
    $get_sth->execute($rec->{glassid});
    my $com = $get_sth->fetchrow_hashref;
    if ( ! $com ) {
      $rec->{com_cnt} = 0; # Mark that we have tried
    } else {
      for my $k ( keys(%$com) ) {
        $rec->{$k} = $com->{$k};
      }
    }
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


# Make sure we have all fields defined, even as empty strings
sub nullfields {
  my $rec = shift;
  my $linetype = shift || $rec->{type};
  my $fieldnamelistref = $datalinetypes{$linetype};
  util::error ("Oops, no field list for '$linetype'") unless $fieldnamelistref;
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


