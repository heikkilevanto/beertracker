#!/usr/bin/perl
# Standalone HTTP test script for the beertracker dev site.
# Run from the repo root: perl tools/test-http.pl
# GET smoke tests for the About and Debug pages, with selector support.
#
# Options:
#   -h   this help text
#   -l   list the tests
#   -s   list the test sets (sets keywords) with a count of tests each
#   -v   verbose: show each PASS/FAIL line and a header per test
#   -q   quiet: no per-test summary lines
# Optional selector arguments (one or more) select what to run; the tests
# matching any of them are run:
#   (no argument)  tests tagged 'quick' (the default, safe run)
#   all            every test
#   testname       run exactly that test
#   selector       anything matching a sets entry (module/op name or group tag)

use strict;
use warnings;
use utf8;
use Getopt::Long;
use LWP::UserAgent;
use HTTP::Cookies;

################################################################################
# Config
################################################################################
my $BASE_URL = "http://127.0.0.1/beertracker-dev/code/index.fcgi";

my $help = 0;
my $list = 0;
my $sets = 0;
my $verbose = 0;
my $quiet = 0;
GetOptions( "h|help" => \$help, "l|list" => \$list, "s|sets" => \$sets,
            "v|verbose" => \$verbose, "q|quiet" => \$quiet, )
  or die usage();

sub usage {
  return "Usage: $0 [options] [selector]\n" .
         "  -h   this help text\n" .
         "  -l   list the tests\n" .
         "  -s   list the test sets (sets keywords) with a count of tests\n" .
         "  -v   verbose: show each PASS/FAIL line and a header per test\n" .
         "  -q   quiet: no per-test summary lines\n" .
         "Selector (one or more, default: the 'quick' tests):\n" .
         "  all       every test\n" .
         "  testname  run exactly that test\n" .
         "  keyword   any sets entry (module/op name or group tag)\n";
} # usage

################################################################################
# HTTP helper
################################################################################
my $ua = LWP::UserAgent->new(timeout => 30);
$ua->cookie_jar(HTTP::Cookies->new);      # Keep cookies for future POST tests
$ua->max_redirect(0);                     # So Location headers can be asserted later

sub req {
  my ($method, $url) = @_;
  my $res = $ua->get($url);
  return ($res->code, $res->headers, $res->decoded_content);
} # req

################################################################################
# Assertion helpers
################################################################################
my $pass = 0;
my $fail = 0;
my $tpass = 0;  # Per-test counts, reset before each test
my $tfail = 0;

sub assert {
  my ($cond, $msg) = @_;
  if ($cond) {
    $pass++;
    $tpass++;
    print "PASS: $msg\n" if $verbose;
  } else {
    $fail++;
    $tfail++;
    print "FAIL: $msg\n";  # Always shown, even in quiet mode
  }
} # assert

# True if the body shows no signs of a Perl error buried in the page
sub no_errors_in {
  my $body = shift;
  my @markers = ( "ERROR", "DB ERROR", "Stack Trace", "Undefined subroutine",
                  "Can't locate", "Use of uninitialized" );
  foreach my $marker (@markers) {
    return 0 if $body =~ /\Q$marker\E/i;
  }
  return 1;
} # no_errors_in

# Assert the common GET smoke checks for a page: status, doctype, footer diagnostic
sub assert_page_ok {
  my ($status, $body, $op, $marker) = @_;
  # scalar() keeps a regex match from flattening away in list context
  my $ok_status = $status == 200;
  my $ok_doctype = scalar($body =~ /<!DOCTYPE html>/i);
  my $ok_marker = scalar($body =~ /\Q$marker\E/i);
  my $ok_diag = scalar($body =~ /beertracker-test .+queries=\d+/);
  assert($ok_status, "$op page returns HTTP 200 (got $status)");
  assert($ok_doctype, "$op page has a DOCTYPE");
  assert($ok_marker, "$op page has content marker '$marker'");
  assert($ok_diag, "$op page carries the dev footer diagnostic line");
  assert(no_errors_in($body), "$op page body is free of error markers");
} # assert_page_ok

################################################################################
# Tests
################################################################################
sub test_about {
  my ($status, $headers, $body) = req("GET", "$BASE_URL?o=About");
  assert_page_ok($status, $body, "About", "Beertracker");
} # test_about

sub test_debug {
  my ($status, $headers, $body) = req("GET", "$BASE_URL?o=Debug");
  # The page embeds a raw log tail; strip only the log lines so the footer
  # diagnostic and error-scan checks stay meaningful
  my $page = $body;
  $page =~ s{<pre style='font-size:0\.8em;'>.*?</pre>}{}s;
  assert_page_ok($status, $page, "Debug", "Grand total");
} # test_debug

# name => sets, test => sub. sets holds selector tags: module/op names,
# abstract group tags, and the special 'quick' tag (included in the default run).
my @TESTS = (
  { name => "about", sets => [qw(quick about)], test => \&test_about },
  { name => "debug", sets => [qw(quick debug)], test => \&test_debug },
);

################################################################################
# Test selection
################################################################################
# Select the tests to run. Any number of selectors may be given; the result
# is the union of the tests each one matches. Any unknown selector is reported
# (with the bad name) and the empty list is returned.
sub select_tests {
  my @selectors = @_;

  if ( !@selectors ) {
    return grep { my $s = $_->{sets};
                  grep { $_ eq "quick" } @$s } @TESTS;
  }

  my @run;
  my %seen;
  my @unknown;
  foreach my $sel (@selectors) {
    if ( $sel =~ /^all$/i ) {
      return @TESTS;  # 'all' covers everything
    }
    my $lower = lc $sel;
    my $matched = 0;
    foreach my $t (@TESTS) {
      my $match = ( lc $t->{name} eq $lower ) ? 1 : 0;
      if ( !$match ) {
        foreach my $c (@{ $t->{sets} }) {
          if ( index(lc $c, $lower) != -1 ) { $match = 1; last; }
        }
      }
      if ( $match ) {
        $matched = 1;
        push @run, $t unless $seen{$t->{name}}++;
      }
    }
    push @unknown, $sel unless $matched;
  }
  if ( @unknown ) {
    list_selectors( join(", ", @unknown) );
    return ();
  }
  return @run;
} # select_tests

sub list_tests {
  foreach my $t (@TESTS) {
    print $t->{name} . " (" . join(", ", @{ $t->{sets} }) . ")\n";
  }
} # list_tests

sub list_sets {
  my %count;
  foreach my $t (@TESTS) {
    foreach my $c (@{ $t->{sets} }) {
      $count{$c}++;
    }
  }
  foreach my $kw (sort keys %count) {
    print "$kw: $count{$kw}\n";
  }
} # list_sets

sub list_selectors {
  my $bad = shift;
  print "Unknown selector" . ( defined $bad ? ": $bad" : "" ) . ".\n";
  print "Available selectors: all, quick, or\n";
  list_tests();
} # list_selectors

################################################################################
# Main
################################################################################
if ( $help ) {
  print usage();
  exit 0;
}
if ( $list ) {
  list_tests();
  exit 0;
}
if ( $sets ) {
  list_sets();
  exit 0;
}

my @run = select_tests(@ARGV);
if ( !@run ) {
  list_selectors() unless @ARGV;  # Unknown selectors already reported
  exit 1;
}

foreach my $t (@run) {
  print "\n" . $t->{name} . ":\n" if $verbose;
  $tpass = 0;
  $tfail = 0;
  $t->{test}->();
  print $t->{name} . ": $tpass PASS" . ( $tfail ? ", $tfail FAIL" : "" ) . "\n"
    unless $quiet;
}

# Grand summary: distinct sets (ignoring the 'quick' tag), tests run, and totals
my %seen;
foreach my $t (@run) {
  foreach my $c (@{ $t->{sets} }) {
    next if $c eq "quick";
    $seen{$c} = 1;
  }
}
my $nsets = scalar keys %seen;
my $ntests = $pass + $fail;  # Every assertion counts as a test
if ( $fail == 0 ) {
  print "all: $nsets sets, $ntests tests, all PASS\n";
} else {
  print "all: $nsets sets, $ntests tests, $pass PASS, $fail FAIL\n";
}
exit($fail ? 1 : 0);
