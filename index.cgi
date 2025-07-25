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
# All actual code should be in the modules
require "./persons.pm";   # List of people, their details, editing, helpers
require "./locations.pm"; # Locations stuff
require "./brews.pm";  # Lists of various brews, etc
require "./glasses.pm"; # Main input for and the full list
require "./comments.pm"; # Stuff for comments, ratings, and photos
require "./util.pm"; # Various helper functions
require "./graph.pm"; # The daily graph
require "./stats.pm"; # Various statistics
require "./monthstat.pm"; # Monthly statistics
require "./yearstat.pm"; # annual stats
require "./mainlist.pm"; # The main "full" list
require "./beerboard.pm"; # The beer board for the current bar
require "./inputs.pm"; # Helper routines for input forms
require "./listrecords.pm"; # A way to produce a nice list from db records
require "./aboutpage.pm"; # The About page
require "./VERSION.pm"; # auto-generated version info
require "./copyproddata.pm"; # Copy production database into the dev version
require "./db.pm"; # Various database helpers



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
#                  RrGgBb
my $bgcolor =    "#003000";
my $altbgcolor = "#004810";
if (  $devversion ) {
  $bgcolor = "#003050" ;
  $altbgcolor = "#004850";
}
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
  'cgi'      => $q,
  'onedrink' => $onedrink,
  'bgcolor'  => $bgcolor,
  'altbgcolor'  => $altbgcolor,
  'devversion' => $devversion,
  'mobile'   => $mobile,
};
# Input Parameters. Need to have a $c to get them.
$c->{edit}= util::param($c,"e");  # Record to edit
$c->{qry} = util::param($c,"q");  # filter query, greps the list
$c->{op}  = util::param($c,"o");  # operation, to list breweries, locations, etc
$c->{sort} = util::param($c,"s");  # Sort key
$c->{href} = "$c->{url}?o=$c->{op}";



################################################################################
# Main program
################################################################################


if ($devversion) { # Print a line in error.log, to see what errors come from this invocation
  my $now = localtime;
  print STDERR  "\n" . $now->ymd . " " . $now->hms . " " .
     $q->request_method . " " . $ENV{'QUERY_STRING'}. " \n";
}

if ( $devversion && $c->{op} eq "copyproddata" ) {
  print STDERR "Copying prod data to dev \n";
  copyproddata::copyproddata($c);
  exit;
}


# # Default new users to the about page, we have nothing else to show
# TODO - Make a better check, and force  the about page to show an input form
# if ( !$c->{op}) {
#   if ( !@lines) {
#     $c->{op} = "About";
#   } else {
#     $c->{op} = "Graph";  # Default to showing the graph
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

  if ( $c->{op} =~ /Person/i ) {
    persons::postperson($c);
  } elsif ( $c->{op} =~ /Location/i ) {
    locations::postlocation($c);
  } elsif ( $c->{op} =~ /Beer|Brew/i ) {
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

if ( $c->{op} =~ /Board/i ) {
  glasses::inputform($c);
  graph::graph($c);
  beerboard::beerboard($c);
  mainlist::mainlist($c);
} elsif ( $c->{op} =~ /Years(d?)/i ) {
  yearstat::yearsummary($c,$1); # $1 indicates sort order
} elsif ( $c->{op} =~ /short/i ) {
  stats::dailystats($c);
} elsif ( $c->{op} =~ /Months([BS])?/ ) {
  monthstat::monthstat($c,$1);
} elsif ( $c->{op} =~ /DataStats/i ) {
  stats::datastats($c);
} elsif ( $c->{op} eq "About" ) {
  aboutpage::about($c);
} elsif ( $c->{op} =~ /Brew/i ) {
  brews::listbrews($c);
} elsif ( $c->{op} =~ /Person/i ) {
  persons::listpersons($c);
} elsif ( $c->{op} =~ /Comment/i ) {
  comments::listallcomments($c);
} elsif ( $c->{op} =~ /Location/i ) {
  locations::listlocations($c);
} elsif ( $c->{op} =~ /Full/i ) {
  glasses::inputform($c);
  mainlist::mainlist($c);
} else { # Default to the graph
  $c->{op} = "Graph" unless $c->{op};
  graph::graph($c);
  glasses::inputform($c);
  mainlist::mainlist($c);
}

$dbh->disconnect;
htmlfooter();
exit();  # The rest should be subs only

# End of main


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
  print "  body { background-color: $bgcolor; color: #FFFFFF; }\n";
  print "  input, select, textarea, button, select option { background-color: $altbgcolor; color: #FFFFFF; }\n";
  print "  * { font-size: small; }\n";
  print "  a { color: #666666; }\n";  # Almost invisible grey. Applies only to the
            # underline, if the content is in a span of its own.
  print "  a span, a b, a i { color: #FFFFFF; }\n";  # Link text in white, if inside a span
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


