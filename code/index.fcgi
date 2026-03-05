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
use CGI::Fast qw( -utf8 );

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
require "./code/login.pm";  # Cookie-based authentication
# Login module dependencies (also loaded inside login.pm; listed here for documentation):
#   Digest::SHA qw(hmac_sha256_hex), Authen::Htpasswd, CGI::Cookie, MIME::Base64




################################################################################
# Constants and setup
################################################################################

my $workdir = cwd();
my $devversion = 0;  # Changes a few display details if on the development version
$devversion = 1 if ( $workdir =~ /-dev|-old/ );
# Background color. Normally a dark green (matching the "racing green" at Øb),
# but with experimental versions of the script, a dark blue, to indicate that
# I am not running the real thing.
#                  RrGgBb
my $bgcolor =    "#001800";  # Darker than index.cgi so fcgi vs cgi is visually obvious
my $altbgcolor = "#002408";
if (  $devversion ) {
  $bgcolor = "#001828" ;
  $altbgcolor = "#002438";
}
# Constants
my $onedrink = 33 * 4.6 ; # A regular danish beer, 33 cl at 4.6%
my $datadir = "./beerdata/";
my $scriptdir = "./scripts/";  # screen scraping scripts

# Open log file once per process (rotate if > 1MB, keep 3 generations)
my $logfile = $datadir . "debug.log";
if ( -f $logfile && -s $logfile > 1_000_000 ) {
  for my $n ( reverse 1..2 ) {
    rename "$logfile.$n", "$logfile." . ($n+1) if -f "$logfile.$n";
  }
  rename $logfile, "$logfile.1";
}
open( my $log, ">>", $logfile )
  or die "Cannot open log file $logfile: $!\n";
binmode $log, ":utf8";
$log->autoflush(1);  # Flush after every write so log is live under FastCGI
util::set_log($log);  # Let util.pm (and modules using $util::log) find it

# Record startup mtimes for auto-reload detection
my $mtime0    = (stat($0))[9];
my $mtime_ver = (stat("code/VERSION.pm"))[9];

{ my $now = localtime;
  my $dev_info = $devversion ? " DEV" : " PROD";
  print { $log } "\n" . $now->ymd . " " . $now->hms . " fcgi startup pid=$$" . $dev_info . " workdir=$workdir\n";
}

my $dbh_ro;  # Persistent read-only dbh, reused across requests

################################################################################
# Main FastCGI loop — runs once per request; CGI::Fast falls back to plain CGI
################################################################################
while (my $q = CGI::Fast->new) {
  # Reload if the script or VERSION.pm changed (e.g. after git pull)
  my $reload_reason = $q->param('reload')                       ? "manual reload request"
                    : (stat($0))[9]             != $mtime0      ? "script $0 changed on disk"
                    : (stat("code/VERSION.pm"))[9] != $mtime_ver ? "code/VERSION.pm changed on disk"
                    : "";
  if ( $reload_reason ) {
    my $now = localtime;
    print { $log } $now->ymd . " " . $now->hms . " fcgi reloading pid=$$ ($reload_reason)\n";
    my $op = $q->param('o') || 'Graph';
    print $q->header(-status => '302 Found', -location => $q->url() . "?o=$op");
    exit(0);
  }
  my $mobile = ( $ENV{'HTTP_USER_AGENT'} =~ /Android|Mobile|Iphone/i );
  my $plotfile = "";
  my $cmdfile = "";
  my $photodir = "";
# Build a minimal context so login.pm can use the CGI object.
# authenticate() sets $c_auth->{username}; sends 401 and returns empty username on failure.
my $c_auth = { cgi => $q };
login::authenticate($c_auth);
my $username = $c_auth->{username};
next unless $username;  # 401 already sent by authenticate()

# Sudo mode, normally commented out
#$username = "dennis" if ( $username eq "heikki" );  # Fake user to see one with less data

if ( $username =~ /^[a-zA-Z0-9]+$/ ) {
  $plotfile = $datadir . $username . ".plot";
  $cmdfile  = $datadir . $username . ".cmd";
  $photodir = $datadir . $username . ".photo";
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
  'log'      => $log,
};
# Input Parameters. Need to have a $c to get them.
$c->{edit}= util::param($c,"e");  # Record to edit
$c->{qry} = util::param($c,"q");  # filter query, greps the list
$c->{op}  = util::param($c,"o");  # operation, to list breweries, locations, etc
$c->{sort} = util::param($c,"s");  # Sort key
$c->{duplicate} = util::param($c,"duplicate");  # ID of brew to duplicate
$c->{href} = "$c->{url}?o=$c->{op}";

login::prepare_cookie($c);  # Build fresh auth cookie; htmlhead() will send it.


################################################################################
# Main program
################################################################################


if ($devversion) { # Print a line in the log, to see what errors come from this invocation
  my $now = localtime;
  print $log "\n\n" . $now->ymd . " " . $now->hms . " " .
     $q->request_method . " " . $ENV{'QUERY_STRING'}. " \n";
}

# Needs to be done early, before we send HTTP headers
if ( $devversion && $c->{op} =~ /copyproddata/i ) {
  print $log "Copying prod data to dev \n";
  superuser::copyproddata($c);
  next;
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
        print { $c->{log} } "   p: $param = '$value'\n" ; #if ($value);  # log also zeroes
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
  next;
}

# GET request handling
# Reuse persistent ro dbh if alive, otherwise reconnect
if ( !$dbh_ro || !$dbh_ro->ping ) {
  db::open_db($c, "ro");
  $dbh_ro = $c->{dbh};
} else {
  $c->{dbh} = $dbh_ro;
}

migrate::startup_check($c);  # Redirect to migration form if DB is behind code version

# DoExport sends its own text/plain header; handle before buffer setup
if ( $c->{op} =~ /DoExport/i ) {
  export::do_export($c);
  next;
}

htmlhead($c); # Content-Type + HTML head → directly to FCGI::Stream

# Buffer remaining body through a :utf8 layer (FCGI::Stream ignores binmode :utf8)
my $body = '';
open my $buf, '>:utf8', \$body or die "Cannot open body buffer: $!";
my $old_fh = select $buf;

eval {
print util::topline($c);
print "<div class='content-wrapper'>\n";

if ( $c->{op} =~ /Board/i ) {
  graph::graph($c);
  glasses::maininputform($c);
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
  glasses::maininputform($c);
  mainlist::mainlist($c);
} else { # Default to the graph
  # Log it, I have seen menus with no section selected! Must be a bad $op
  # but I don't know where it comes from.
  print { $c->{log} } "Index.cgi: Default op '$c->{op}' \n"
    unless ( $c->{op} eq "Graph" );
  $c->{op} = "Graph" unless $c->{op};
  graph::graph($c);
  glasses::maininputform($c);
  mainlist::mainlist($c);
}

$c->{dbh} = undef;  # Don't disconnect; keep $dbh_ro alive for next request

}; # end eval GET
if ($@) {
  eval { $dbh_ro->disconnect; $dbh_ro = undef } if $dbh_ro;  # Drop on error, reconnect next request
  print { $c->{log} } "GET error: $@\n";
}

select $old_fh;  # Restore output to FCGI::Stream
print $body;     # Emit UTF-8 encoded body
htmlfooter();

} # end while (FastCGI loop)

{ my $now = localtime; print { $log } $now->ymd . " " . $now->hms . " fcgi exit pid=$$\n"; }

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
  my $c = shift;
  print $c->{cgi}->header(
    -type => "text/html;charset=UTF-8",
    -Cache_Control => "no-cache, no-store, must-revalidate",
    -Pragma => "no-cache",
    -Expires => "0",
    -Secure => 1,
    -cookie => $c->{auth_cookie},
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


