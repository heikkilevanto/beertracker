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

use Time::Piece;

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


################################################################################
# Input Parameters
################################################################################
# These are used is so many places that it is OK to have them as globals
# TODO - Check if all are used, after refactoring
my $edit= param("e");  # Record to edit
my $type = param("type"); # Switch record type
our $qry = param("q");  # filter query, greps the list
my $qrylim = param("f"); # query limit, "x" for extra info, "f" for forcing refresh of board
my $yrlim = param("y"); # Filter by year
our $op  = param("o");  # operation, to list breweries, locations, etc
our $url = $q->url;
my $sort = param("s");  # Sort key
# the POST routine reads its own input parameters

################################################################################
# Global variables
# Mostly from reading the file, used in various places
################################################################################
# TODO - Remove most of these
my %ratesum; # sum of ratings for every beer
my %ratecount; # count of ratings for every beer, for averaging

# Collect all 'global' variables here in one context that gets passed around
# a lot.
my $c = {
  'username' => $username,
  'datadir'  => $datadir,
  'databasefile' => $databasefile,
  'plotfile' => $plotfile,
  'cmdfile'  => $cmdfile,
  'photodir' => $photodir,
  'dbh'      => $dbh,
  'url'      => $url,
  'href'     => "$url?o=$op",
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
require "./mainlist.pm"; # The main "full" list
require "./VERSION.pm"; # auto-generated version info

################################################################################
# Main program
################################################################################


if ($devversion) { # Print a line in error.log, to see what errors come from this invocation
  my $now = localtime;
  print STDERR  "\n" . $now->ymd . " " . $now->hms . " " .
     $q->request_method . " " . $ENV{'QUERY_STRING'}. " \n";
}

if ( $devversion && $op eq "copyproddata" ) {
  print STDERR "Copying prod data to dev \n";
  copyproddata();
  exit;
}


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
      print STDERR "   p: $param = '$value'\n" if ($value);
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


htmlhead(); # Ok, now we can commit to making a HTML page

print util::topline($c);

if ( $op =~ /Board/i ) {
  glasses::inputform($c);
  graph::graph($c);
  beerboard();
  mainlist::mainlist($c);
} elsif ( $op =~ /Years(d?)/i ) {
  stats::yearsummary($c,$1); # $1 indicates sort order
} elsif ( $op =~ /short/i ) {
  stats::dailystats($c);
} elsif ( $op =~ /Months([BS])?/ ) {
  stats::monthstat($c,$1);
} elsif ( $op =~ /DataStats/i ) {
  stats::datastats($c);
} elsif ( $op eq "About" ) {
  about();
} elsif ( $op =~ /Brew/i ) {
  brews::listbrews($c);
} elsif ( $op =~ /Person/i ) {
  persons::listpersons($c);
} elsif ( $op =~ /Location/i ) {
  locations::listlocations($c);
} elsif ( $op =~ /Full/i ) {
  glasses::inputform($c);
  mainlist::mainlist($c);
} else { # Default to the graph
  $op = "Graph" unless $op;
  graph::graph($c);
  glasses::inputform($c);
  mainlist::mainlist($c);
}

$dbh->disconnect;
htmlfooter();
exit();  # The rest should be subs only

# End of main


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



###############################################
# TODO - Move the photo handling into its own module.
# At the moment not used at all, kept here as an example

#
# # Get image file name. Width can be in pixels, or special values like
# # "orig" for the original image, "" for the plain name to be saved in the record,
# # or "thumb", "mob", "pc" for default sizes
# sub XXXimagefilename {
#   my $fn = shift; # The raw file name
#   my $width = shift; # How wide we want it, or "orig" or ""
#   $fn =~ s/(\.?\+?orig)?\.jpe?g$//i; # drop extension if any
#   return $fn if (!$width); # empty width for saving the clean filename in $rec
#   $fn = "$photodir/$fn"; # a real filename
#   if ( $width =~ /\.?orig/ ) {
#     $fn .= "+orig.jpg";
#     return $fn;
#   }
#   $width = $imagesizes{$width} || "";
#   return "" unless $width;
#   $width .= "w"; # for easier deleting *w.jpg
#   $fn .= "+$width.jpg";
#   return $fn;
# }
#
# # Produce the image tag
# sub XXXimage {
#   my $rec = shift;
#   my $width = shift; # One of the keys in %imagesizes
#   return "" unless ( $rec->{photo} && $rec->{photo} =~ /^2/);
#   my $orig = imagefilename($rec->{photo}, "orig");
#   if ( ! -r $orig ) {
#     print STDERR "Photo file '$orig' not found for record $rec->{stamp} \n";
#     return "";
#   }
#   my $fn = imagefilename($rec->{photo}, $width);
#   return "" unless $fn;
#   if ( ! -r $fn ) { # Need to resize it
#     my $size = $imagesizes{$width};
#     $size = $size . "x". $size .">";
#     system ("convert $orig -resize '$size' $fn");
#     print STDERR "convert $orig -resize '$size' $fn \n";
#   }
#   my $w = $imagesizes{$width};
#   my $itag = "<img src='$fn' width='$w' />";
#   my $tag = "<a href='$orig'>$itag</a>";
#   return $tag;
#
# }
# # - Make a routine to scale to any given width. Check if already there.
# # - Use that when displaying
# # - When clearing the cache, delete scaled images over a month old, but not .orig
# sub XXXsavefile {
#   my $rec = shift;
#   my $fn = $rec->{stamp};
#   $fn =~ s/ /+/; # Remove spaces
#   $fn .= ".jpg";
#   if ( ! -d $photodir ) {
#     print STDERR "Creating photo dir $photodir - FIX PERMISSIONS \n";
#     print STDERR "chgrp heikki $photodir; chmod g+sw $photodir \n";
#     mkdir($photodir);
#   }
#   my $savefile = "$photodir/$fn";
#   my ( $base, $sec ) = $fn =~ /^(.*):(\d\d)/;
#   $sec--;
#   do {
#     $sec++;
#     $fn = sprintf("%s:%02d", $base,$sec);
#     $savefile = imagefilename($fn,"orig");
#   }  while ( -e $savefile ) ;
#   $rec->{photo} = imagefilename($fn,"");
#
#   my $filehandle = $q->upload('newphoto');
#   my $tmpfilename = $q->tmpFileName( $filehandle );
#   my $conv = `/usr/bin/convert $tmpfilename -auto-orient -strip $savefile`;
#     # -auto-orient turns them upside up. -strip removes the orientation, so
#     # they don't get turned again when displaying.
#   print STDERR "Conv returned '$conv' \n" if ($conv); # Can this happen
#   my $fsz = -s $savefile;
#   print STDERR "Uploaded $fsz bytes into '$savefile' \n";
# }
#
# ########################


################################################################################
# HTML head
################################################################################

sub htmlhead {
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
} # htmlhead


# HTML footer
sub htmlfooter {
  print "</body></html>\n";
}




################################################################################
# Beer board (list) for the location.
# Scraped from their website
################################################################################

sub beerboard {
  my $extraboard = -1; # Which of the entries to open, or -1 current, -2 for all, -3 for none
  if ( $op =~ /board(-?\d+)/i ) {
    $extraboard = $1;
  }
  my $sql = "select * from glassrec " .
            "where username = ? " .
            "order by stamp desc ".
            "limit 1";
  my $sth = $c->{dbh}->prepare($sql);
  $sth->execute( $c->{username} );
  my $foundrec = $sth->fetchrow_hashref;
  $sth->finish;

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
      my $locrec = util::findrecord($c,"LOCATIONS","Name",$locparam, "collate nocase");
      my $locid = $locrec->{Id};
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
      $hiddenbuttons .= "<input type='hidden' name='Location' value='$locid' />\n" ;
      $hiddenbuttons .= "<input type='hidden' name='tap' value='$id#' />\n" ; # Signalss this comes from a beer board
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
# Various small helpers
################################################################################

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

# TODO - These link functions should live in util
# For now they are not used at all. Kept here for future reference
# # Helper to make a google link
#sub glink {
#   my $qry = shift;
#   my $txt = shift || "Google";
#   return "" unless $qry;
#   $qry = uri_escape_utf8($qry);
#   my $lnk = "&nbsp;<i>(<a href='https://www.google.com/search?q=$qry'" .
#     " target='_blank' class='no-print'><span>$txt</span></a>)</i>\n";
#   return $lnk;
# }

# # Helper to make a Ratebeer search link
#sub XXrblink {
#   my $qry = shift;
#   my $txt = shift || "Ratebeer";
#   return "" unless $qry;
#   $qry = uri_escape_utf8($qry);
#   my $lnk = "<i>(<a href='https://www.ratebeer.com/search?q=$qry' " .
#     " target='_blank' class='no-print'><span>$txt<span></a>)</i>\n";
#   return $lnk;
# }
#
# # Helper to make a Untappd search link
#sub XXutlink {
#   my $qry = shift;
#   my $txt = shift || "Untappd";
#   return "" unless $qry;
#   $qry = uri_escape_utf8($qry);
#   my $lnk = "<i>(<a href='https://untappd.com/search?q=$qry'" .
#     " target='_blank' class='no-print'><span>$txt<span></a>)</i>\n";
#   return $lnk;
# }

#sub XXmaplink {
#   my $g = shift;
#   my $txt = shift || "Map";
#   return "" unless $g;
#   my ( $la, $lo, undef ) = geo($g);
#   my $lnk = "<a href='https://www.google.com/maps/place/$la,$lo' " .
#   "target='_blank' class='no-print'><span>$txt</span></a>";
#   return $lnk;
# }




# TODO - Geo stuff not (re)implemented in the new code.
# Kept here as an example

# Helper to validate and split a geolocation string
# Takes one string, in either new or old format
# returns ( lat, long, string ), or all "" if not valid coord
# sub geo {
#   my $g = shift || "";
#   return ("","","") unless ($g =~ /^ *\[?\d+/ );
#   $g =~ s/\[([-0-9.]+)\/([-0-9.]+)\]/$1 $2/ ;  # Old format geo string
#   my ($la,$lo) = $g =~ /([0-9.-]+) ([0-9.-]+)/;
#   return ($la,$lo,$g) if ($lo);
#   return ("","","");
# }

# # Helper to return distance between 2 geolocations
# sub geodist {
#   my $g1 = shift;
#   my $g2 = shift;
#   return "" unless ($g1 && $g2);
#   my ($la1, $lo1, undef) = geo($g1);
#   my ($la2, $lo2, undef) = geo($g2);
#   return "" unless ($la1 && $la2 && $lo1 && $lo2);
#   my $pi = 3.141592653589793238462643383279502884197;
#   my $earthR = 6371e3; # meters
#   my $latcorr = cos($la1 * $pi/180 );
#   my $dla = ($la2 - $la1) * $pi / 180 * $latcorr;
#   my $dlo = ($lo2 - $lo1) * $pi / 180;
#   my $dist = sqrt( ($dla*$dla) + ($dlo*$dlo)) * $earthR;
#   return sprintf("%3.0f", $dist);
# }

# # Helper to guess the closest location
#sub guessloc {
#   my $g = shift;
#   my $def = shift || ""; # def value, not good as a guess
#   $def =~ s/ *$//;
#   $def =~ s/^ *//;
#   return ("",0) unless $g;
#   my $dist = 200;
#   my $guess = "";
#   foreach my $k ( sort(keys(%geolocations)) ) {
#     my $d = geodist( $g, $geolocations{$k} );
#     if ( $d && $d < $dist ) {
#       $dist = $d;
#       $guess = $k;
#       $guess =~ s/ *$//;
#       $guess =~ s/^ *//;
#     }
#   }
#   if ($def eq $guess ){
#     $guess = "";
#     $dist = 0;
#   }
#   return ($guess,$dist);
# }


# # Check if the record has problematic geo coords
# # That is, coords and loc don't match
#sub XXcheckgeoerror {
#   my $rec = shift;
#   return unless $rec;
#   return unless ( $rec->{loc} );
#   return unless ( $rec->{geo} );
#   my ( $guess, $dist ) = guessloc($rec->{geo});
#   if ( $guess ne $rec->{loc} ) {
#     $rec->{geoerror} = "$guess [$dist]m";
#     #print STDERR "Possible geo error for $rec->{stamp}: '$rec->{loc}' " .
#     # "is not at $rec->{geo}, '$guess' is at $dist m from it\n";
#   }
# }
#

# ################################################################################
# # Get all geo locations
# # TODO - Don't use this for the javascript, send also the 'last' time
# ################################################################################
# sub XXextractgeo {
# #  Earlier version of the sql, with last seen and sorting
# #     select name, GeoCoordinates, max(timestamp) as last
# #     from Locations, glasses
# #     where  LOCATIONS.id = GLASSES.Location
# #       and GeoCoordinates is not null
# #     group by location
# #     order by last desc
#   my $sql = q(
#     select name, GeoCoordinates
#     from Locations, glasses
#     where  LOCATIONS.id = GLASSES.Location
#       and GeoCoordinates is not null
#     group by location
#   ); # No need to sort here, since put it all in a hash.
#   my $get_sth = $dbh->prepare($sql);
#   $get_sth->execute();
#   while ( my ($name, $geo, $last) = $get_sth->fetchrow_array ) {
#     $geolocations{$name} = $geo;
#   }
# }
#


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









