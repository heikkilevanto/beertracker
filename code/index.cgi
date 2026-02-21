#!/usr/bin/perl -w

# Heikki's beer tracker
#
# Keeps track of the beers I drink, and what I think about them
#
# This is a (not so) simple CGI script
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

# Text::LevenshteinXS - for calculating string similarity (edit distance)
# Alternative: use Text::Levenshtein qw(distance); # pure Perl version
use Text::LevenshteinXS qw(distance);

use URI::Escape;
use CGI qw( -utf8 );
my $q = CGI->new;
$q->charset( "UTF-8" );

################################################################################
# Fix the current directory
################################################################################
# This is necessary after we moved index.cgi into the code dir
if ( cwd() =~ /\/code$/ ) {
  chdir("..")
    or util::error("Can not chdir to .. from code/: $!" );
}

################################################################################
# Program modules
################################################################################
# All actual code should be in the modules
require "./code/persons.pm";   # List of people, their details, editing, helpers
require "./code/locations.pm"; # Locations stuff
require "./code/brews.pm";  # Lists of various brews, etc
require "./code/styles.pm"; # Beer style utilities: colors, display, shortening
require "./code/glasses.pm"; # Main input for and the full list
require "./code/postglass.pm"; # POST handling for glass records
require "./code/comments.pm"; # Stuff for comments, ratings, and photos
require "./code/util.pm"; # Various helper functions
require "./code/graph.pm"; # The daily graph
require "./code/stats.pm"; # Various statistics
require "./code/monthstat.pm"; # Monthly statistics
require "./code/yearstat.pm"; # annual stats
require "./code/mainlist.pm"; # The main "full" list
require "./code/beerboard.pm"; # The beer board for the current bar
require "./code/scrapeboard.pm"; # Scraping and updating beer boards
require "./code/taps.pm"; # Updating tap_beers table
require "./code/inputs.pm"; # Helper routines for input forms
require "./code/listrecords.pm"; # A way to produce a nice list from db records
require "./code/aboutpage.pm"; # The About page
require "./code/VERSION.pm"; # auto-generated version info
require "./code/superuser.pm"; # Superuser functions: Copåy prod data, git pull
require "./code/db.pm"; # Various database helpers
require "./code/geo.pm"; # Geo coordinate stuff
require "./code/ratestats.pm"; # Histogram of the ratings
require "./code/export.pm"; # Export the users own data
require "./code/photos.pm"; # Helpers for managing photo files
require "./code/migrate.pm"; # DB migration system




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
  'scriptdir'    => $scriptdir,
  'plotfile' => $plotfile,
  'cmdfile'  => $cmdfile,
  'photodir' => $photodir,
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
$c->{duplicate} = util::param($c,"duplicate");  # ID of brew to duplicate
$c->{href} = "$c->{url}?o=$c->{op}";



################################################################################
# Main program
################################################################################


if ($devversion) { # Print a line in error.log, to see what errors come from this invocation
  my $now = localtime;
  print STDERR  "\n\n" . $now->ymd . " " . $now->hms . " " .
     $q->request_method . " " . $ENV{'QUERY_STRING'}. " \n";
}

# Needs to be done early, before we send HTTP headers
if ( $devversion && $c->{op} =~ /copyproddata/i ) {
  print STDERR "Copying prod data to dev \n";
  superuser::copyproddata($c);
  exit;
}


if ( !$c->{op}) {
  $c->{op} = "Graph";  # Default to showing the graph
}

if ( $q->request_method eq "POST" ) {

  my $debugparams = "";
  eval { # Catch all database errors (and a few others)
    db::open_db($c, "rw");  # POST requests modify data by default

    if ( $c->{devversion} ) {
      foreach my $param ($c->{cgi}->param) { # Debug dump params while developing
        my $value = $c->{cgi}->param($param);
        $debugparams .= "p: $param = '$value'\n";
        print STDERR "   p: $param = '$value'\n" ; #if ($value);  # log also zeroes
      }
    }

    $c->{dbh}->do("BEGIN TRANSACTION");

    if ( $c->{op} =~ /migrate/i ) {
      migrate::run_migrations($c);
    } elsif ( $c->{op} =~ /Person/i ) {
      persons::postperson($c);
    } elsif ( $c->{op} =~ /Location/i ) {
      locations::postlocation($c);
    } elsif ( $c->{op} =~ /Beer|Brew/i ) {
      brews::postbrew($c);
    } elsif ( $c->{op} =~ /Photo/i ) {
      photos::post_photo($c);
    } elsif ( util::param($c, "commentedit") ) {
      comments::postcomment($c);
    } elsif ( $c->{op} =~ /updateboard/i ) {
      scrapeboard::updateboard($c);
    } else { # Default to posting a glass
      postglass::postglass($c);
    }

    $c->{dbh}->do("COMMIT");
    $c->{dbh}->disconnect;
  };
  if ( $@ ) {
    #db::dberror($c,"$@\n$debugparams");
    util::error("$@\n$debugparams");
    $c->{dbh}->rollback;
  }

  # Redirect back to the op, but not editing
  print $c->{cgi}->redirect( $c->{redirect_url} || "$c->{url}?o=$c->{op}" );
  exit;
}

db::open_db($c, "ro");  # GET requests are read-only by default

migrate::startup_check($c);  # Redirect to migration form if DB is behind code version

# Datafile export needs to be done before HTML head, as we output text/plain
if ( $c->{op} =~ /DoExport/i ) {
  export::do_export($c);
  exit;
}

htmlhead(); # Ok, now we can commit to making a HTML page

print util::topline($c);
print "<div class='content-wrapper'>\n";

if ( $c->{op} =~ /Board/i ) {
  graph::graph($c);
  glasses::inputform($c);
  beerboard::beerboard($c);
  mainlist::mainlist($c);
} elsif ( $c->{op} =~ /Years/i ) {
  yearstat::yearsummary($c);
} elsif ( $c->{op} =~ /short/i ) {
  stats::dailystats($c);
} elsif ( $c->{op} =~ /Months/ ) {
  monthstat::monthstat($c);
} elsif ( $c->{op} =~ /DataStats/i ) {
  stats::datastats($c);
} elsif ( $c->{op} =~ /Ratings/i ) {
  ratestats::ratings_histogram($c);
} elsif ( $c->{op} =~ /About/i ) {
  aboutpage::about($c);
} elsif ( $c->{op} =~ /Brew/i ) {
  brews::listbrews($c);
} elsif ( $c->{op} =~ /Person/i ) {
  persons::listpersons($c);
} elsif ( $c->{op} =~ /Photo/i ) {
  photos::listphotos($c);
} elsif ( $c->{op} =~ /Comment/i ) {
  comments::listallcomments($c);
} elsif ( $c->{op} =~ /Location/i ) {
  locations::listlocations($c);
} elsif ( $c->{op} =~ /migrate/i ) {
  migrate::migrate_form($c);
} elsif ( $c->{op} =~ /Export/i ) {
  export::exportform($c);
} elsif ( $c->{op} =~ /GitStatus/i ) {
  superuser::gitstatus($c);
} elsif ( $c->{op} =~ /GitPull/i ) {
  superuser::gitpull($c);
} elsif ( $c->{op} =~ /Full/i ) {
  glasses::inputform($c);
  mainlist::mainlist($c);
} else { # Default to the graph
  # Log it, I have seen menus with no section selected! Must be a bad $op
  # but I don't know where it comes from.
  print STDERR "Index.cgi: Default op '$c->{op}' \n"
    unless ( $c->{op} eq "Graph" );
  $c->{op} = "Graph" unless $c->{op};
  graph::graph($c);
  glasses::inputform($c);
  mainlist::mainlist($c);
}

$c->{dbh}->disconnect;
htmlfooter();
exit();  # The rest should be subs only

# End of main

# Helper to make a link to a CSS file for the headers
# Adds a parameter with the file mod time, so the browsers
# can not use an older version from cache
sub csslink {
  my $module = shift;
  my $fn = "static/$module.css";
  my $mtime = (stat($fn))[9] || time;
  return "<link rel='stylesheet' href='$fn?m=$mtime'>\n";
}
# Helper to make a link to a JS file for the headers
sub jslink {
  my $module = shift;
  my $fn = "static/$module.js";
  my $mtime = (stat($fn))[9] || time;
  return "<script src='$fn?m=$mtime'></script>\n";
}

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
    print "<link rel='shortcut icon' href='static/beer-dev.png'/>\n";
  } else {
    print "<title>Beer</title>\n";
    print "<link rel='shortcut icon' href='static/beer.png'/>\n";
  }
  print "<meta http-equiv='Content-Type' content='text/html;charset=UTF-8'>\n";
  my ($r, $g, $b) = $bgcolor =~ /#(..)(..)(..)/;   # Make menu on semitransparent bg
  $r = hex($r); $g = hex($g); $b = hex($b);
  print <<"END_STYLE";
    <meta name='viewport' content='width=device-width, initial-scale=1.0'>
    <style>:root {
      --bgcolor: $bgcolor;
      --altbgcolor: $altbgcolor;
      --menu-bg: rgba($r,$g,$b,0.9);
      --menu-current: #FFD700;
    }</style>
END_STYLE
  # CSS files
  print csslink("base");
  print csslink("layout");
  print csslink("menu");
  print csslink("inputs");
  # JS files
  print jslink("menu");
  print jslink("geo");
  print jslink("inputs");
  print jslink("listrecords");
  print jslink("beerboard");
  print jslink("quagga.min");
  print jslink("barcode");
  print "</head><body>\n";
  print "\n";
} # htmlhead


# HTML footer
sub htmlfooter {
  print "</div>\n"; # Close content-wrapper
  print "</body></html>\n";
}


