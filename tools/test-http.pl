#!/usr/bin/perl
# Standalone HTTP test script for the beertracker dev site.
# Run from the repo root: perl tools/test-http.pl
# GET smoke + content tests for all core ops, with selector support.
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
  # After a git pull the fcgi script reloads itself: the first request gets a
  # 302 with an empty body (index.fcgi), then exec's a fresh process. Absorb
  # that one-time bounce for GETs; POST Location headers are still returned
  # verbatim so round-trip tests can assert them.
  if ( $res->code == 302 && $res->header('Location') && $res->content eq '' && $method eq 'GET' ) {
    print STDERR "note: server reloaded itself, retrying $url\n";
    $res = $ua->get($url);
  }
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

# True if the body shows no signs of a Perl error buried in the page.
# Note: the bare word "ERROR" is deliberately NOT a marker here: real user data
# (e.g. a comment "Coding Error") legitimately contains it. The real error
# signal is now the HTTP 500 status from index.fcgi, asserted separately.
sub no_errors_in {
  my $body = shift;
  my @markers = ( "DB ERROR", "Stack Trace", "Undefined subroutine",
                  "Can't locate", "Use of uninitialized" );
  foreach my $marker (@markers) {
    return 0 if $body =~ /\Q$marker\E/i;
  }
  return 1;
} # no_errors_in

# Assert the common GET smoke checks for a page: status, doctype, menu markup,
# content marker, footer diagnostic, and error markers
sub assert_page_ok {
  my ($status, $body, $op, $marker) = @_;
  # scalar() keeps a regex match from flattening away in list context
  my $ok_status = $status == 200;
  my $ok_doctype = scalar($body =~ /<!DOCTYPE html>/i);
  my $ok_menu = scalar($body =~ /id='menu-toggle'/);
  my $ok_marker = scalar($body =~ /\Q$marker\E/i);
  my $ok_diag = scalar($body =~ /beertracker-test .+queries=\d+/);
  assert($ok_status, "$op page returns HTTP 200 (got $status)");
  assert($ok_doctype, "$op page has a DOCTYPE");
  assert($ok_menu, "$op page has the menu markup");
  assert($ok_marker, "$op page has content marker '$marker'");
  assert($ok_diag, "$op page carries the dev footer diagnostic line");
  assert(no_errors_in($body), "$op page body is free of error markers");
} # assert_page_ok

################################################################################
# Tests
################################################################################

# Generic GET smoke test for a single op: fetch and assert the common checks
sub test_op_page {
  my ($op, $marker) = @_;
  my ($status, $headers, $body) = req("GET", "$BASE_URL?o=$op");
  assert_page_ok($status, $body, $op, $marker);
} # test_op_page

sub test_about {
  test_op_page("About", "Beertracker");
} # test_about

sub test_debug {
  my ($status, $headers, $body) = req("GET", "$BASE_URL?o=Debug");
  # The page embeds a raw log tail; strip only the log lines so the footer
  # diagnostic and error-scan checks stay meaningful
  my $page = $body;
  $page =~ s{<pre style='font-size:0\.8em;'>.*?</pre>}{}s;
  assert_page_ok($status, $page, "Debug", "Grand total");
} # test_debug

sub test_graph { test_op_page("Graph", "id='mainform'"); } # test_graph

sub test_board { test_op_page("Board", "id='mainform'"); } # test_board

sub test_full {
  my ($status, $headers, $body) = req("GET", "$BASE_URL?o=Full");
  assert_page_ok($status, $body, "Full", "id='mainform'");
  assert(scalar($body =~ /Older records/), "Full page has the 'Older records' link");
} # test_full

sub test_default {
  # No 'o' parameter at all must fall through to the default graph rendering
  my ($status, $headers, $body) = req("GET", "$BASE_URL");
  assert_page_ok($status, $body, "default", "id='mainform'");
} # test_default

sub test_bogus {
  # A bogus op must fall through to the default graph rendering
  my ($status, $headers, $body) = req("GET", "$BASE_URL?o=Bogus");
  assert_page_ok($status, $body, "Bogus", "id='mainform'");
} # test_bogus

sub test_years    { test_op_page("Years", "Year <b>"); } # test_years
sub test_months {
  # Default page is drinks mode: the toggle offers "Show money spent"
  my ($status, $headers, $body) = req("GET", "$BASE_URL?o=Months");
  assert_page_ok($status, $body, "Months", "Show money spent");
  # Money mode (s=money) instead offers "Show drinks"
  ($status, $headers, $body) = req("GET", "$BASE_URL?o=Months&s=money");
  assert($status == 200, "Months money mode returns HTTP 200 (got $status)");
  assert(scalar($body =~ /Show drinks/), "Months page (money mode) has the 'Show drinks' link");
} # test_months
sub test_short    { test_op_page("short", "Daily stats"); } # test_short
sub test_datastats { test_op_page("DataStats", "Data file stats"); } # test_datastats
sub test_ratings  { test_op_page("Ratings", "Ratings statistics"); } # test_ratings
sub test_export   { test_op_page("Export", "Export data"); } # test_export
sub test_comment  { test_op_page("Comment", "Comments by"); } # test_comment
sub test_location { test_op_page("Location", "Locations"); } # test_location
sub test_person   { test_op_page("Person", "Persons"); } # test_person
sub test_brew     { test_op_page("Brew", "Brews"); } # test_brew
sub test_photos   { test_op_page("Photos", "Photos for"); } # test_photos

# name => sets, test => sub. sets holds selector tags: module/op names,
# abstract group tags, and the special 'quick' tag (included in the default run).
my @TESTS = (
  { name => "graph",     sets => [qw(quick graph glasses mainlist)],                 test => \&test_graph },
  { name => "board",     sets => [qw(quick board graph beerboard glasses mainlist)], test => \&test_board },
  { name => "full",      sets => [qw(quick full glasses mainlist)],                  test => \&test_full },
  { name => "default",   sets => [qw(quick default)],                                test => \&test_default },
  { name => "bogus",     sets => [qw(quick bogus)],                                  test => \&test_bogus },
  { name => "years",     sets => [qw(quick years stats yearstat)],                   test => \&test_years },
  { name => "months",    sets => [qw(quick months stats monthstat)],                 test => \&test_months },
  { name => "short",     sets => [qw(quick short stats)],                            test => \&test_short },
  { name => "datastats", sets => [qw(quick datastats stats)],                        test => \&test_datastats },
  { name => "ratings",   sets => [qw(quick ratings stats ratestats)],                test => \&test_ratings },
  { name => "about",     sets => [qw(quick about)],                                  test => \&test_about },
  { name => "debug",     sets => [qw(quick debug)],                                  test => \&test_debug },
  { name => "export",    sets => [qw(quick export)],                                 test => \&test_export },
  { name => "comment",   sets => [qw(quick comment comments lists)],                 test => \&test_comment },
  { name => "location",  sets => [qw(quick location locations lists)],               test => \&test_location },
  { name => "person",    sets => [qw(quick person persons lists)],                   test => \&test_person },
  { name => "brew",      sets => [qw(quick brew brews lists)],                       test => \&test_brew },
  { name => "photos",    sets => [qw(quick photo photos lists)],                     test => \&test_photos },
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
