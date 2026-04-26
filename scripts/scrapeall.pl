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
use Cwd qw(cwd);
use Time::Piece;
use Getopt::Long;

# Fix working directory (same as index.fcgi)
if ( cwd() =~ /\/scripts$/ || cwd() =~ /\/code$/ ) {
  chdir("..") or die "Cannot chdir to ..: $!\n";
}

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
my $datadir   = "./beerdata/";
my $scriptdir = "./scripts/";

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

################################################################################
# Determine which locations to scrape
################################################################################
my @locations;
if ($loc_arg) {
  @locations = ($loc_arg);
} else {
  @locations = sort keys %scrapeboard::scrapers;
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

  if ( !$scrapeboard::scrapers{$loc} ) {
    print { $log } $t0->hms . " SKIP $loc (no scraper defined)\n";
    print           $t0->hms . " SKIP $loc (no scraper defined)\n";
    $total_skip++;
    next;
  }

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
    print           $t1->hms . " ERROR $loc: $err\n";
    $total_err++;
    $log->flush;
    next;
  }

  my $t1 = localtime;
  print { $log } $t1->hms . " OK    $loc\n";
  print           $t1->hms . " OK    $loc\n";
  $total_ok++;
  $log->flush;

  # Sleep between untappd scrapers to avoid rate-limiting
  my ($script) = @{ $scrapeboard::scrapers{$loc} };
  if ( $script eq "untappd.pl" && $loc ne $locations[-1] ) {
    sleep($delay);
  }
}

my $done = localtime;
print { $log } $done->hms . " $total_ok sites scraped, $total_err errors, $total_skip skipped\n";
print           $done->hms . " $total_ok sites scraped, $total_err errors, $total_skip skipped\n";

$c->{dbh}->disconnect;
close $log;
