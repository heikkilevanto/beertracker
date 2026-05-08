#!/usr/bin/perl
# scrapeall.pl — standalone cron scraper for all beertracker venues
#
# Replaces cronjob.sh.  Runs outside FastCGI: no HTTP, no Apache, no login.
# Iterates all venues in %scrapeboard::scrapers, calls updateboard() for each,
# with a configurable delay between untappd-backed scrapers.
#
# Usage:
#   perl scripts/scrapeall.pl [--delay N] [--loc NAME]
#
#   --delay N   seconds to sleep between untappd scrapers (default 5)
#   --loc NAME  scrape only this one location (for manual testing)
#
# Redirect output to a log file in crontab:
#   perl /path/to/beertracker/scripts/scrapeall.pl >> /path/to/beertracker/beerdata/scrapeall.log 2>&1

use strict;
use warnings;
use feature 'unicode_strings';
use utf8;
use open ':encoding(UTF-8)';
use Cwd qw(cwd abs_path);
use File::Basename qw(dirname);
use Time::Piece;
use Getopt::Long;

my $scriptdir = dirname(abs_path(__FILE__));
my $projectroot = dirname($scriptdir);
chdir($projectroot) or die "Cannot chdir to $projectroot: $!\n";

# Load only the modules we need
require "./code/db.pm";
require "./code/util.pm";
require "./code/styles.pm";
require "./code/taps.pm";
require "./code/scrapeboard.pm";

################################################################################
# Command-line options
################################################################################
my $delay   = 5;
my $loc_arg = undef;

GetOptions(
  "delay=i" => \$delay,
  "loc=s"   => \$loc_arg,
) or die "Usage: $0 [--delay N] [--loc NAME]\n";

################################################################################
# Build minimal $c context
################################################################################
my $datadir = "$projectroot/beerdata/";
$scriptdir = "$projectroot/scripts/";

my $logfile = $datadir . "scrapeall.log";
open( my $log, ">", $logfile )
  or die "Cannot open log file $logfile: $!\n";
binmode $log,   ":utf8";
binmode STDOUT, ":utf8";

my $workdir    = cwd();
my $devversion = 0;
$devversion = 1 if $workdir =~ /-dev|-old/;

my $c = {
  username   => 'cron',
  datadir    => $datadir,
  scriptdir  => $scriptdir,
  devversion => $devversion,
  log        => $log,
  cache      => {},
};

db::open_db($c, "rw");

my $starttime = localtime->strftime('%Y-%m-%d %H:%M:%S');
print "scrapeall starting at $starttime\n";

################################################################################
# Determine which locations to scrape
################################################################################
my @locations;
if ($loc_arg) {
  @locations = ($loc_arg);
} else {
  @locations = scrapeboard::get_scraper_locations($c);
}

################################################################################
# Main loop
################################################################################
my $now = localtime;
print { $log } "\n" . $now->ymd . " " . $now->hms . " scrapeall start (delay=${delay}s)\n";

my $total_ok   = 0;
my $total_err  = 0;
my $total_skip = 0;

for my $loc (@locations) {
  my $t0 = localtime;

  eval {
    $c->{dbh}->do("BEGIN TRANSACTION");
    scrapeboard::updateboard($c, $loc);
    $c->{dbh}->do("COMMIT");
  };
  if ($@) {
    my $err = $@;
    eval { $c->{dbh}->do("ROLLBACK") };
    my $t1 = localtime;
    print { $log } $t1->hms . " ERROR $loc: $err\n";
    print          $t1->hms . " ERROR $loc: $err\n";
    $total_err++;
    $log->flush;
    next;
  }

  my $t1 = localtime;
  my $status = $c->{scrape_status} || "";
  $status = " ($status)" if $status;
  print { $log } $t1->hms . " OK    $loc$status\n";
  print          $t1->hms . " OK    $loc$status\n";
  $total_ok++;
  $log->flush;

  # Sleep between untappd scrapers to avoid rate-limiting
  my $loc_rec = db::findrecord($c, "LOCATIONS", "Name", $loc, "collate nocase");
  my $scraper_str = $loc_rec && $loc_rec->{Scraper} ? $loc_rec->{Scraper} : "";
  my ($script) = split /\s+/, $scraper_str;
  if ( $script && $script eq "untappd.pl" && $loc ne $locations[-1] ) {
    sleep($delay);
  }
}

my $done = localtime;
print { $log } $done->hms . " $total_ok sites scraped, $total_err errors, $total_skip skipped\n";
print          $done->hms . " $total_ok sites scraped, $total_err errors, $total_skip skipped\n";

$c->{dbh}->disconnect;
close $log;
