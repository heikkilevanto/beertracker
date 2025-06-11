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
my $q = CGI->new;
$q->charset( "UTF-8" );


# Database setup
use DBI;
my $databasefile = "beerdata/beertracker.db";
die ("Database '$databasefile' not writable" ) unless ( -w $databasefile );

my $dbh = DBI->connect("dbi:SQLite:dbname=$databasefile", "", "", { RaiseError => 1, AutoCommit => 1 })
    or util::error($DBI::errstr);
$dbh->{sqlite_unicode} = 1;  # Yes, we use unicode in the database, and want unicode in the results!
$dbh->do('PRAGMA journal_mode = WAL'); # Avoid locking problems with SqLiteBrowser
# But watch out for file permissions on the -wal and -sha files
#$dbh->trace(1);  # Lots of SQL logging in error.log

################################################################################
# Program modules
################################################################################
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
require "./beerboard.pm"; # The beer board for the current bar
require "./inputs.pm"; # Helper routines for input forms
require "./VERSION.pm"; # auto-generated version info


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
my $username = ($q->remote_user()||"");

# Sudo mode, normally commented out
#$username = "dennis" if ( $username eq "heikki" );  # Fake user to see one with less data

if ( ($q->remote_user()||"") =~ /^[a-zA-Z0-9]+$/ ) {
  $plotfile = $datadir . $username . ".plot";
  $cmdfile = $datadir . $username . ".cmd";
  $photodir = $datadir . $username. ".photo";
} else {
  util::error ("Bad username\n");
}

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
my $qry = param("q");  # filter query, greps the list
my $qrylim = param("f"); # query limit, "x" for extra info, "f" for forcing refresh of board
my $yrlim = param("y"); # Filter by year
my $op  = param("o");  # operation, to list breweries, locations, etc
my $url = $q->url;
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
  'scriptdir'    => $scriptdir,
  'plotfile' => $plotfile,
  'cmdfile'  => $cmdfile,
  'photodir' => $photodir,
  'dbh'      => $dbh,
  'url'      => $q->url,
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

  # Redirect back to the op, but not editing
  print $c->{cgi}->redirect( "$c->{url}?o=$c->{op}" );
  $dbh->disconnect;
  exit;
}


htmlhead(); # Ok, now we can commit to making a HTML page

print util::topline($c);

if ( $op =~ /Board/i ) {
  glasses::inputform($c);
  graph::graph($c);
  beerboard::beerboard($c);
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
} elsif ( $op =~ /Comment/i ) {
  comments::listallcomments($c);
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
  #print "Some of my favourite bars and breweries<ul>";
  #for my $k ( sort keys(%links) ) {  # TODO - Get these from the database somehow. Or skip
  #  print aboutlink($k, $links{$k});
  #}
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
# TODO - These should be in util.pm, or dropped altogether

# Helper to sanitize input data
sub param {
  my $tag = shift;
  my $val = $q->param($tag) || "";
  $val =~ s/[^a-zA-ZñÑåÅæÆøØÅöÖäÄéÉáÁāĀ\/ 0-9.,&:\(\)\[\]?%-]/_/g;
  return $val;
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

