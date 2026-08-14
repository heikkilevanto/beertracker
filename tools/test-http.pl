#!/usr/bin/perl
# Standalone HTTP test script for the beertracker dev site.
# Run from the repo root: perl tools/test-http.pl
# GET smoke + content tests for all core ops, plus harvested-id edit-page
# variants, q= filters, and static assets, with selector support.
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
use Cwd;
use File::Basename;
use Getopt::Long;
use LWP::UserAgent;
use HTTP::Cookies;

################################################################################
# Config
################################################################################
# The path component of the base URL comes from the basename of the checkout
# directory, so a copy of the code under another name (beertracker, a debug
# checkout like beertracker-x, ...) can be tested without editing this file.
my $reldir = basename(getcwd());
if ( $reldir !~ /beertracker/i ) {
  die "Cannot use the current directory '$reldir' for testing: its name does " .
      "not contain 'beertracker'. Run this script from a beertracker checkout.\n";
}
my $BASE_URL = "http://127.0.0.1/$reldir/code/index.fcgi";

# Static assets are served next to the fcgi script under /static/
my $STATIC_URL = $BASE_URL;
$STATIC_URL =~ s{/code/index\.fcgi$}{/static};

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
my $skipped = 0;  # Tests skipped, e.g. a list page that yielded no ids
my $tpass = 0;  # Per-test counts, reset before each test
my $tfail = 0;
my $tskip = 0;

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

# Skip a test cleanly (not a failure): the prerequisite data is missing,
# e.g. an empty dev database gives a list page with nothing to harvest.
sub skipmsg {
  my ($msg) = @_;
  $skipped++;
  $tskip++;
  print "SKIP: $msg\n";
} # skipmsg

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
# Test table
################################################################################
# name => sets, test => sub. sets holds selector tags: module/op names,
# abstract group tags, and the special 'quick' tag (included in the default run).
# The heavy list/main-list pages and the variants that refetch them are
# deliberately NOT 'quick': the default run stays fast, while 'all' (or any of
# their named selectors) still covers them. The main list is exercised in the
# quick run by the default/bogus tests, which render the same graph view.
my @TESTS = (
  { name => "about",         sets => [qw(quick about)],                               test => \&test_about },
  { name => "default",       sets => [qw(quick default)],                             test => \&test_default },
  { name => "bogus",         sets => [qw(quick bogus)],                               test => \&test_bogus },
  { name => "years",         sets => [qw(quick years stats yearstat)],                test => \&test_years },
  { name => "months",        sets => [qw(quick months stats monthstat)],              test => \&test_months },
  { name => "short",         sets => [qw(quick short stats)],                         test => \&test_short },
  { name => "datastats",     sets => [qw(quick datastats stats)],                     test => \&test_datastats },
  { name => "ratings",       sets => [qw(quick ratings stats ratestats)],             test => \&test_ratings },
  { name => "debug",         sets => [qw(quick debug)],                               test => \&test_debug },
  { name => "export",        sets => [qw(quick export)],                              test => \&test_export },
  { name => "location",      sets => [qw(quick location locations lists)],            test => \&test_location },
  { name => "person",        sets => [qw(quick person persons lists)],                test => \&test_person },
  { name => "photos",        sets => [qw(quick photo photos lists)],                  test => \&test_photos },
  { name => "location_edit", sets => [qw(quick location locations lists edits)],      test => \&test_location_edit },
  { name => "person_edit",   sets => [qw(quick person persons lists edits)],          test => \&test_person_edit },
  { name => "brew_new",      sets => [qw(quick brew brews lists newrecords)],         test => \&test_brew_new },
  { name => "location_new",  sets => [qw(quick location locations lists newrecords)], test => \&test_location_new },
  { name => "person_new",    sets => [qw(quick person persons lists newrecords)],     test => \&test_person_new },
  { name => "filter_years",  sets => [qw(quick years stats yearstat filters)],        test => \&test_filter_years },
  { name => "static_assets", sets => [qw(quick static)],                              test => \&test_static_assets },
  # Heavy pages / tests that refetch the main list — not in 'quick'
  { name => "graph",         sets => [qw(graph glasses mainlist)],                    test => \&test_graph },
  { name => "board",         sets => [qw(board graph beerboard glasses mainlist)],    test => \&test_board },
  { name => "full",          sets => [qw(full glasses mainlist)],                     test => \&test_full },
  { name => "brew",          sets => [qw(brew brews lists)],                          test => \&test_brew },
  { name => "comment",       sets => [qw(comment comments lists)],                    test => \&test_comment },
  { name => "brew_edit",     sets => [qw(brew brews lists edits)],                    test => \&test_brew_edit },
  { name => "comment_edit",  sets => [qw(comment comments lists edits)],              test => \&test_comment_edit },
  { name => "glass_edit",    sets => [qw(full graph glasses mainlist edits)],         test => \&test_glass_edit },
  { name => "graph_edit",    sets => [qw(graph glasses mainlist edits)],              test => \&test_graph_edit },
  { name => "comment_new",   sets => [qw(comment comments glasses newrecords)],       test => \&test_comment_new },
  { name => "filter_board",  sets => [qw(board graph beerboard filters)],             test => \&test_filter_board },
  { name => "filter_full",   sets => [qw(full graph glasses mainlist filters)],       test => \&test_filter_full },
);

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

################################################################################
# Id harvesting from rendered list pages (no DB access)
################################################################################
# The list pages render the edit links themselves, and those carry the record
# ids. The regexes are small and kept here, next to the tests that use them,
# so a link-format change is easy to spot and fix.
my %OP_ID_RE = (
  "Brew"     => qr{o=Brew&e=(\d+)},
  "Location" => qr{o=Location&e=(\d+)},
  "Person"   => qr{o=Person&e=(\d+)},
  "Comment"  => qr{o=Comment&e=(\d+)},
  "Full"     => qr{o=Full&e=(\d+)},   # glass ids, on the main list
  "Graph"    => qr{o=Graph&e=(\d+)},  # glass ids, on the Graph page
);

# All distinct ids for $op in page order. Returns () when the regex is unknown.
sub harvest_ids {
  my ($body, $op) = @_;
  my $re = $OP_ID_RE{$op} or return ();
  my %seen;
  my @ids;
  while ( $body =~ /$re/g ) {
    push @ids, $1 unless $seen{$1}++;
  }
  return @ids;
} # harvest_ids

# The first id for $op (undef if the list has none, e.g. an empty dev DB)
sub first_id {
  my ($body, $op) = @_;
  my @ids = harvest_ids($body, $op);
  return @ids ? $ids[0] : undef;
} # first_id

################################################################################
# Edit-page variants, filters, static assets (all GET-only, DB-free)
################################################################################

sub test_brew_edit {
  my ($status, $headers, $body) = req("GET", "$BASE_URL?o=Brew");
  my $id = first_id($body, "Brew");
  if ( !defined $id ) { skipmsg("Brew list has no ids to edit"); return; }
  ($status, $headers, $body) = req("GET", "$BASE_URL?o=Brew&e=$id");
  assert_page_ok($status, $body, "Brew edit", "Editing Brew");
} # test_brew_edit

sub test_location_edit {
  my ($status, $headers, $body) = req("GET", "$BASE_URL?o=Location");
  my $id = first_id($body, "Location");
  if ( !defined $id ) { skipmsg("Location list has no ids to edit"); return; }
  ($status, $headers, $body) = req("GET", "$BASE_URL?o=Location&e=$id");
  assert_page_ok($status, $body, "Location edit", "Editing Location");
} # test_location_edit

sub test_person_edit {
  my ($status, $headers, $body) = req("GET", "$BASE_URL?o=Person");
  my $id = first_id($body, "Person");
  if ( !defined $id ) { skipmsg("Person list has no ids to edit"); return; }
  ($status, $headers, $body) = req("GET", "$BASE_URL?o=Person&e=$id");
  assert_page_ok($status, $body, "Person edit", "Editing Person");
} # test_person_edit

sub test_comment_edit {
  my ($status, $headers, $body) = req("GET", "$BASE_URL?o=Comment");
  my $id = first_id($body, "Comment");
  if ( !defined $id ) { skipmsg("Comment list has no ids to edit"); return; }
  ($status, $headers, $body) = req("GET", "$BASE_URL?o=Comment&e=$id");
  assert_page_ok($status, $body, "Comment edit", "Edit comment");
} # test_comment_edit

sub test_glass_edit {
  # The edit-glass page: input form + comments + photos (o=Full&e=<glassid>)
  my ($status, $headers, $body) = req("GET", "$BASE_URL?o=Full");
  my $id = first_id($body, "Full");
  if ( !defined $id ) { skipmsg("Full list has no glass ids to edit"); return; }
  ($status, $headers, $body) = req("GET", "$BASE_URL?o=Full&e=$id");
  assert_page_ok($status, $body, "Full glass edit", "id='mainform'");
  assert(scalar($body =~ /name='submit' value='Save'/), "glass edit form has the Save button");
  assert(scalar($body =~ /name='submit' value='Del'/),   "glass edit form has the Del button");
  assert(scalar($body =~ /\(Photo\)/),                   "glass edit page has the photo form");
  assert(scalar($body =~ /\(New comment\)/),             "glass edit page has the new-comment link");
} # test_glass_edit

sub test_graph_edit {
  # Editing a glass via the Graph page
  my ($status, $headers, $body) = req("GET", "$BASE_URL?o=Graph");
  my $id = first_id($body, "Graph");
  if ( !defined $id ) { skipmsg("Graph list has no glass ids to edit"); return; }
  ($status, $headers, $body) = req("GET", "$BASE_URL?o=Graph&e=$id");
  assert_page_ok($status, $body, "Graph glass edit", "id='mainform'");
  assert(scalar($body =~ /name='submit' value='Save'/), "Graph glass edit form has the Save button");
} # test_graph_edit

# New-record forms
sub test_brew_new {
  my ($status, $headers, $body) = req("GET", "$BASE_URL?o=Brew&e=new");
  assert_page_ok($status, $body, "Brew new", "Insert Brew");
} # test_brew_new

sub test_location_new {
  my ($status, $headers, $body) = req("GET", "$BASE_URL?o=Location&e=new");
  assert_page_ok($status, $body, "Location new", "Insert Location");
} # test_location_new

sub test_person_new {
  my ($status, $headers, $body) = req("GET", "$BASE_URL?o=Person&e=new");
  assert_page_ok($status, $body, "Person new", "New Person");
} # test_person_new

sub test_comment_new {
  # New-comment form prefilled from a glass
  my ($status, $headers, $body) = req("GET", "$BASE_URL?o=Full");
  my $id = first_id($body, "Full");
  if ( !defined $id ) { skipmsg("Full list has no glass ids for comment prefill"); return; }
  ($status, $headers, $body) = req("GET", "$BASE_URL?o=Comment&e=new&glass=$id");
  assert_page_ok($status, $body, "Comment new", "New comment");
  assert(scalar($body =~ /o=Full&e=$id/), "new-comment page links back to its glass");
} # test_comment_new

# q= filter variants
sub test_filter_board {
  my ($status, $headers, $body) = req("GET", "$BASE_URL?o=Board&q=IPA");
  assert_page_ok($status, $body, "Board q=IPA", "id='mainform'");
  assert(scalar($body =~ /Filter:<b>IPA<\/b>/), "Board filter line shows 'Filter: IPA'");
} # test_filter_board

sub test_filter_full {
  # NOTE: mainlist.pm does not actually filter on q (no "Filter:" line on the
  # Full page), so this only asserts the q= variant is accepted without errors.
  my ($status, $headers, $body) = req("GET", "$BASE_URL?o=Full&q=IPA");
  assert_page_ok($status, $body, "Full q=IPA", "id='mainform'");
} # test_filter_full

sub test_filter_years {
  # Pick a year from the Years page's "Year <b>" links, then filter to it
  my ($status, $headers, $body) = req("GET", "$BASE_URL?o=Years");
  my ($year) = $body =~ /q=(\d{4})&maxl=20/;
  if ( !defined $year ) { skipmsg("Years page has no year links to filter by"); return; }
  ($status, $headers, $body) = req("GET", "$BASE_URL?o=Years&q=$year");
  assert_page_ok($status, $body, "Years q=$year", "Year <b>");
  assert(scalar($body =~ /q=$year&maxl=20/), "filtered Years page still links the $year row");
} # test_filter_years

# Static assets: served directly, not through the fcgi script
sub test_static_assets {
  foreach my $asset (qw(base.css menu.js beer-dev.png)) {
    my ($status, $headers, $body) = req("GET", "$STATIC_URL/$asset");
    assert($status == 200, "static/$asset returns HTTP 200 (got $status)");
  }
} # test_static_assets

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
  $tskip = 0;
  $t->{test}->();
  my $tline = "$t->{name}: $tpass PASS";
  $tline .= ", $tskip SKIP" if $tskip;
  $tline .= ", $tfail FAIL" if $tfail;
  print "$tline\n" unless $quiet;
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
my $ntests = $pass + $fail;  # Every assertion counts as a test; skips are extra
if ( $fail == 0 ) {
  print "all: $nsets sets, $ntests tests, all PASS";
  print " ($skipped skipped)" if $skipped;
  print "\n";
} else {
  print "all: $nsets sets, $ntests tests, $pass PASS, $fail FAIL";
  print ", $skipped skipped" if $skipped;
  print "\n";
}
exit($fail ? 1 : 0);
