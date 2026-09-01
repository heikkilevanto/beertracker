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
use POSIX qw(strftime);  # date/time for the glass round-trip POSTs

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

my $on_dev = $reldir =~ /-dev/i;   # True if the checkout dir name ends in -dev

my $help = 0;
my $list = 0;
my $sets = 0;
my $verbose = 0;
my $quiet = 0;
my $no_post = 0;
GetOptions( "h|help" => \$help, "l|list" => \$list, "s|sets" => \$sets,
            "v|verbose" => \$verbose, "q|quiet" => \$quiet,
            "no-post" => \$no_post, )
  or die usage();

sub usage {
  return "Usage: $0 [options] [selector]\n" .
         "  -h   this help text\n" .
         "  -l   list the tests\n" .
         "  -s   list the test sets (sets keywords) with a count of tests\n" .
         "  -v   verbose: show each PASS/FAIL line and a header per test\n" .
         "  -q   quiet: no per-test summary lines\n" .
         "  -P   --no-post: force GET-only, drop any POST round-trip tests\n" .
         "Selector (one or more, default: the 'quick' tests):\n" .
         "  all       every test (includes POST round-trips, dev-guarded)\n" .
         "  testname  run exactly that test\n" .
         "  keyword   any sets entry (module/op name or group tag)\n";
} # usage

################################################################################
# HTTP helper
################################################################################
my $ua = LWP::UserAgent->new(timeout => 30);
$ua->cookie_jar(HTTP::Cookies->new);      # Keep cookies for future POST tests
$ua->max_redirect(0);                     # So Location headers can be asserted later

my $post_count = 0;  # POST requests made this run; drives the final CopyProdData sync

sub req {
  my ($method, $url, $form) = @_;
  $form ||= {};
  my $res;
  if ( $method eq 'POST' ) {
    $post_count++;
    $res = $ua->post($url, $form);
  } else {
    $res = $ua->get($url);
  }
  # After a git pull the fcgi script reloads itself: the first request gets a
  # 302 with an empty body (index.fcgi), then exec's a fresh process. Absorb
  # that one-time bounce for GETs, but only when the Location still points at a
  # page with a query string (the reload redirects to "?o=..."). A real
  # redirect without a query (e.g. CopyProdData's 302 to the bare base URL) is
  # a genuine response and must be returned verbatim; POST Location headers are
  # always returned verbatim so round-trip tests can assert them.
  if ( $method eq 'GET' && $res->code == 302 &&
       $res->header('Location') && $res->content eq '' &&
       $res->header('Location') =~ /\?/ ) {
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

# Assert the standard POST response (index.fcgi:347): a 302 with a Location
# header. Returns the Location value, or undef when the POST did not succeed so
# the round-trip test cannot continue.
sub assert_post_redirect {
  my ($status, $headers, $what) = @_;
  assert($status == 302, "$what returns a 302 redirect (got $status)");
  my $loc = $headers->header('Location') || "";
  assert($loc ne '', "$what redirect has a Location header");
  return $status == 302 && $loc ne '' ? $loc : undef;
} # assert_post_redirect

# Assert the common GET smoke checks for a page: status, doctype, menu markup,
# content marker, footer diagnostic, and error markers
sub assert_page_ok {
  my ($status, $body, $op, $marker) = @_;
  # scalar() keeps a regex match from flattening away in list context
  my $ok_status = $status == 200;
  my $ok_doctype = scalar($body =~ /<!DOCTYPE html>/i);
  my $ok_menu = scalar($body =~ /id='menu-toggle'/);
  my $ok_marker = scalar($body =~ /\Q$marker\E/i);
  assert($ok_status, "$op page returns HTTP 200 (got $status)");
  assert($ok_doctype, "$op page has a DOCTYPE");
  assert($ok_menu, "$op page has the menu markup");
  assert($ok_marker, "$op page has content marker '$marker'");
  if ($on_dev) {
    my $ok_diag = scalar($body =~ /beertracker-test .+queries=\d+/);
    assert($ok_diag, "$op page carries the dev footer diagnostic line");
  }
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
  # Tap Timeline (o=Taps): GET-only smoke + content; no DB writes, so safe in 'quick'
  { name => "taps",          sets => [qw(quick taps taphistory)],                    test => \&test_taps },
  { name => "taps_single",   sets => [qw(quick taps taphistory)],                    test => \&test_taps_single },
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
  # POST round-trips — dev-guarded, never in 'quick'
  { name => "person_roundtrip", sets => [qw(posts roundtrip person persons)],         test => \&test_person_roundtrip },
  { name => "brew_roundtrip",     sets => [qw(posts roundtrip brew brews)],             test => \&test_brew_roundtrip },
  { name => "location_roundtrip", sets => [qw(posts roundtrip location locations)],       test => \&test_location_roundtrip },
  { name => "glass_roundtrip",    sets => [qw(posts roundtrip postglass glasses)],        test => \&test_glass_roundtrip },
  { name => "comment_roundtrip",  sets => [qw(posts roundtrip comment comments)],          test => \&test_comment_roundtrip },
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

# test_op_page, but also remember the first id on the page for the edit tests
sub test_op_page_remember {
  my ($op, $marker) = @_;
  my ($status, $headers, $body) = req("GET", "$BASE_URL?o=$op");
  assert_page_ok($status, $body, $op, $marker);
  remember_first_id($body, $op);
} # test_op_page_remember

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

sub test_graph { test_op_page_remember("Graph", "id='mainform'"); } # test_graph

sub test_board { test_op_page("Board", "id='mainform'"); } # test_board

sub test_full {
  my ($status, $headers, $body) = req("GET", "$BASE_URL?o=Full");
  assert_page_ok($status, $body, "Full", "id='mainform'");
  assert(scalar($body =~ /Older records/), "Full page has the 'Older records' link");
  remember_first_id($body, "Full");
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
sub test_comment  { test_op_page_remember("Comment", "Comments by"); } # test_comment
sub test_location { test_op_page_remember("Location", "Locations"); } # test_location
sub test_person   { test_op_page_remember("Person", "Persons"); } # test_person
sub test_brew     { test_op_page_remember("Brew", "Brews"); } # test_brew
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

# First id harvested from each list page this run, so the edit-page tests can
# reuse it instead of refetching the list. The list tests run before their edit
# counterparts in @TESTS, so the cache is normally already filled.
my %LIST_IDS;

# Remember the first id seen on $op's list page, if the page has one. Returns
# the id (undef if the list had none).
sub remember_first_id {
  my ($body, $op) = @_;
  my $id = first_id($body, $op);
  $LIST_IDS{$op} = $id if defined $id;
  return $id;
} # remember_first_id

# First id for $op: the one cached by the list test if any, else fetch the list
# page now (e.g. when only an edit test was selected).
sub get_first_id {
  my ($op) = @_;
  return $LIST_IDS{$op} if defined $LIST_IDS{$op};
  my ($status, $headers, $body) = req("GET", "$BASE_URL?o=$op");
  return remember_first_id($body, $op);
} # get_first_id

# The id of the row whose cell text $text appears on, harvested from a rendered
# list page. The id column (a link like o=$op&e=<id>) precedes the text column,
# so the link before the text is the row's own id. The text can also occur in a
# non-row context — e.g. the main input form's data-note attribute on the Full
# page mirrors the latest glass's note before the main list renders — so we
# examine each occurrence and take the first one that has a preceding id link.
# Returns undef when no occurrence has one.
sub id_before_text {
  my ($body, $op, $text) = @_;
  my $re = qr{o=$op&e=(\d+)};
  my $pos = 0;
  while ( (my $found = index($body, $text, $pos)) >= 0 ) {
    my $before = substr($body, 0, $found);
    my $id;
    while ( $before =~ /$re/g ) {
      $id = $1;
    }
    return $id if defined $id;
    $pos = $found + length($text);
  }
  return undef;
} # id_before_text

################################################################################
# Edit-page variants, filters, static assets (all GET-only, DB-free)
################################################################################

sub test_brew_edit {
  my $id = get_first_id("Brew");
  if ( !defined $id ) { skipmsg("Brew list has no ids to edit"); return; }
  my ($status, $headers, $body) = req("GET", "$BASE_URL?o=Brew&e=$id");
  assert_page_ok($status, $body, "Brew edit", "Editing Brew");
} # test_brew_edit

sub test_location_edit {
  my $id = get_first_id("Location");
  if ( !defined $id ) { skipmsg("Location list has no ids to edit"); return; }
  my ($status, $headers, $body) = req("GET", "$BASE_URL?o=Location&e=$id");
  assert_page_ok($status, $body, "Location edit", "Editing Location");
} # test_location_edit

sub test_person_edit {
  my $id = get_first_id("Person");
  if ( !defined $id ) { skipmsg("Person list has no ids to edit"); return; }
  my ($status, $headers, $body) = req("GET", "$BASE_URL?o=Person&e=$id");
  assert_page_ok($status, $body, "Person edit", "Editing Person");
} # test_person_edit

sub test_comment_edit {
  my $id = get_first_id("Comment");
  if ( !defined $id ) { skipmsg("Comment list has no ids to edit"); return; }
  my ($status, $headers, $body) = req("GET", "$BASE_URL?o=Comment&e=$id");
  assert_page_ok($status, $body, "Comment edit", "Edit comment");
} # test_comment_edit

sub test_glass_edit {
  # The edit-glass page: input form + comments + photos (o=Full&e=<glassid>)
  my $id = get_first_id("Full");
  if ( !defined $id ) { skipmsg("Full list has no glass ids to edit"); return; }
  my ($status, $headers, $body) = req("GET", "$BASE_URL?o=Full&e=$id");
  assert_page_ok($status, $body, "Full glass edit", "id='mainform'");
  assert(scalar($body =~ /name='submit' value='Save'/), "glass edit form has the Save button");
  assert(scalar($body =~ /name='submit' value='Del'/),   "glass edit form has the Del button");
  assert(scalar($body =~ /\(Photo\)/),                   "glass edit page has the photo form");
  assert(scalar($body =~ /\(New comment\)/),             "glass edit page has the new-comment link");
} # test_glass_edit

sub test_graph_edit {
  # Editing a glass via the Graph page
  my $id = get_first_id("Graph");
  if ( !defined $id ) { skipmsg("Graph list has no glass ids to edit"); return; }
  my ($status, $headers, $body) = req("GET", "$BASE_URL?o=Graph&e=$id");
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
  my $id = get_first_id("Full");
  if ( !defined $id ) { skipmsg("Full list has no glass ids for comment prefill"); return; }
  my ($status, $headers, $body) = req("GET", "$BASE_URL?o=Comment&e=new&glass=$id");
  assert_page_ok($status, $body, "Comment new", "New comment");
  assert(scalar($body =~ /o=Full&e=$id/), "new-comment page links back to its glass");
} # test_comment_new

# q= filter variants
sub test_filter_board {
  # Beer Board filtering is client-side JS only (beerboard.pm never reads q
  # server-side), so a GET cannot verify filtering. Assert the client-side
  # filter control is present and that q= is accepted without error.
  my ($status, $headers, $body) = req("GET", "$BASE_URL?o=Board&q=IPA");
  assert_page_ok($status, $body, "Board q=IPA", "id='mainform'");
  assert(scalar($body =~ /id='board-filter'/), "Board has the client-side filter control");
} # test_filter_board

sub test_filter_full {
  # mainlist.pm server-side grep filtering on q: the Filter: form input must
  # carry the query, and a no-match query must report "No matches".
  my ($status, $headers, $body) = req("GET", "$BASE_URL?o=Full&q=IPA");
  assert_page_ok($status, $body, "Full q=IPA", "id='mainform'");
  assert(scalar($body =~ /name="q" value="IPA"/), "Full filter form preserves the q query");

  # Deterministic no-match: a unique token can never match, so filtered_list
  # must render "No matches for '<token>'".
  my $tok = "TST" . time();
  ($status, $headers, $body) = req("GET", "$BASE_URL?o=Full&q=$tok");
  assert_page_ok($status, $body, "Full q=$tok", "id='mainform'");
  assert(scalar($body =~ /No matches for '\Q$tok\E'/), "Full reports no matches for an unknown query");

  # Date-range filtering (server-side, via the Filter form's date/ndays inputs)
  my $d = "2026-01-01";
  ($status, $headers, $body) = req("GET", "$BASE_URL?o=Full&date=$d&ndays=3");
  assert_page_ok($status, $body, "Full date/ndays", "id='mainform'");
  assert(scalar($body =~ /name="date" value="$d"/), "Full filter form preserves the date");
  assert(scalar($body =~ /name="ndays" value="3"/), "Full filter form preserves ndalys=3");
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
# Tap Timeline (o=Taps): GET-only smoke + content for the timeline and the
# single-tap detail view. No DB writes, so these stay in the 'quick' set.
################################################################################

# The tap-id links in the timeline's tap column look like
#   o=Taps&loc=...&amp;days=...&amp;from=...&amp;tap=<N>
my $TAP_ID_RE = qr{o=Taps[^"]*?tap=(\d+)};

sub test_taps {
  # Default timeline: the controls (Taps: label, From: input) plus the table
  my ($status, $headers, $body) = req("GET", "$BASE_URL?o=Taps");
  assert_page_ok($status, $body, "Taps", "Taps:");
  assert(scalar($body =~ /<table class='timeline'/), "Taps timeline table is rendered");
  assert(scalar($body =~ /From:/), "Taps controls carry the From: input");

  # Period-token, bare-number, and From-anchor variants must still render
  for my $variant (qw(days=3m days=14 from=2026-01-01 from=11)) {
    ($status, $headers, $body) = req("GET", "$BASE_URL?o=Taps&$variant");
    assert_page_ok($status, $body, "Taps $variant", "Taps:");
    assert(scalar($body =~ /<table class='timeline'/), "Taps timeline renders for $variant");
  }
} # test_taps

sub test_taps_single {
  # Harvest a tap id from the default timeline, then drill into its detail view
  my ($status, $headers, $body) = req("GET", "$BASE_URL?o=Taps");
  if ( $body !~ /$TAP_ID_RE/ ) {
    skipmsg("Taps timeline has no tap links to drill into");
    return;
  }
  my $tap = $1;
  ($status, $headers, $body) = req("GET", "$BASE_URL?o=Taps&tap=$tap");
  assert_page_ok($status, $body, "Taps tap=$tap", "Tap #");
  assert(scalar($body =~ /<table class='tap-detail'/), "single-tap detail table is rendered");
  assert(scalar($body =~ /On &ndash; Off/), "single-tap detail shows the On &ndash; Off header");
  assert(scalar($body =~ /Back to timeline/), "single-tap detail links back to the timeline");
} # test_taps_single

################################################################################
# POST round-trips (dev-guarded, not in 'quick')
################################################################################
# Each test creates a record through the web and verifies it on the rendered
# list page — all through HTTP, no DB access. Markers are TST<epoch> tokens so
# the records are greppable in pages. POST tests are not in the 'quick' set and
# are only allowed on a -dev checkout; the post-run CopyProdData sync (Task 5)
# wipes any residue. The o/e params are sent in the POST body, the way the
# app's own forms do it.

sub test_person_roundtrip {
  # Plan Task 6: create a Person through the web, verify it on the Person list
  # page. Cleanup is left to the post-run CopyProdData sync (the plan's "same
  # cleanup note" as Brew/Location). The o/e params go in the POST body, as the
  # app's forms do: CGI::Fast only reads the query string into params on GET.
  #
  # A warm-up GET first: right after a git pull / VERSION.pm touch the fcgi
  # reloads on the first request, replying 302 and eating it. req absorbs that
  # one-time bounce for GETs, so the insert POST below lands in a fresh process
  # instead of being silently dropped (a reload 302 is indistinguishable from
  # a success redirect on a POST). Only fetch if the list was not already
  # fetched this run (a stored first Person id means it was); get_first_id
  # does both, and caches the id for the edit tests.
  my $name = "TST" . time();
  get_first_id("Person");

  my ($status, $headers, $body) = req("POST", "$BASE_URL",
      { o => "Person", e => "new", Name => $name, submit => "Insert Person" });
  my $loc = assert_post_redirect($status, $headers, "Person insert");
  return unless defined $loc;
  ($status, $headers, $body) = req("GET", $loc);
  assert_page_ok($status, $body, "Person list after insert", "Persons");
  assert(scalar($body =~ /\Q$name\E/), "Person list shows the new record '$name'");
  my $id = id_before_text($body, "Person", $name);
  assert(defined $id, "harvested the new Person id from the list");
  if ( defined $id ) {
    assert(scalar($body =~ /\Qo=Person&e=$id\E/), "the harvested id links to the Person edit page");
  }

  # Update the person: change the name, submit, verify the old name is gone
  # and the new one appears on the list page.
  return unless defined $id;
  my $name2 = "upd" . time();
  ($status, $headers, $body) = req("POST", "$BASE_URL",
      { o => "Person", e => $id, id => $id, Name => $name2, submit => "Update Person" });
  $loc = assert_post_redirect($status, $headers, "Person update");
  return unless defined $loc;
  ($status, $headers, $body) = req("GET", $loc);
  assert_page_ok($status, $body, "Person list after update", "Persons");
  assert(scalar($body !~ /\Q$name\E/), "Person list no longer shows the old name '$name'");
  assert(scalar($body =~ /\Q$name2\E/), "Person list shows the updated name '$name2'");

  # Delete the person: POST with submit=Delete Person. Persons have a web
  # delete button, so this test cleans up after itself.
  ($status, $headers, $body) = req("POST", "$BASE_URL",
      { o => "Person", e => $id, id => $id, submit => "Delete Person" });
  $loc = assert_post_redirect($status, $headers, "Person delete");
  return unless defined $loc;
  ($status, $headers, $body) = req("GET", $loc);
  assert_page_ok($status, $body, "Person list after delete", "Persons");
   assert(scalar($body !~ /\Q$name2\E/), "Person list no longer shows the deleted record '$name2'");
} # test_person_roundtrip

sub test_brew_roundtrip {
  # Plan Task 6: create a Brew through the web, verify it on the Brew list,
  # update it, and delete it — all through HTTP, no DB access.
  # postbrew() has a Delete branch (brews.pm:783), so the delete step works.
  my $name = "TST" . time();
  get_first_id("Brew");

  my ($status, $headers, $body) = req("POST", "$BASE_URL",
      { o => "Brew", e => "new", Name => $name, BrewType => "Beer", submit => "Insert Brew" });
  my $loc = assert_post_redirect($status, $headers, "Brew insert");
  return unless defined $loc;
  ($status, $headers, $body) = req("GET", $loc);
  assert_page_ok($status, $body, "Brew list after insert", "Brews");
  assert(scalar($body =~ /\Q$name\E/), "Brew list shows the new record '$name'");
  my $id = id_before_text($body, "Brew", $name);
  assert(defined $id, "harvested the new Brew id from the list");
  if ( defined $id ) {
    assert(scalar($body =~ /\Qo=Brew&e=$id\E/), "the harvested id links to the Brew edit page");
  }

  # Update the brew: change the name, submit, verify the old name is gone
  # and the new one appears on the list page.
  return unless defined $id;
  my $name2 = "upd" . time();
  ($status, $headers, $body) = req("POST", "$BASE_URL",
      { o => "Brew", e => $id, id => $id, Name => $name2, BrewType => "Beer", submit => "Update Brew" });
  $loc = assert_post_redirect($status, $headers, "Brew update");
  return unless defined $loc;
  ($status, $headers, $body) = req("GET", $loc);
  assert_page_ok($status, $body, "Brew list after update", "Brews");
  assert(scalar($body !~ /\Q$name\E/), "Brew list no longer shows the old name '$name'");
  assert(scalar($body =~ /\Q$name2\E/), "Brew list shows the updated name '$name2'");

  # Delete the brew: POST with submit=Delete Brew, handled by postbrew()
  # (brews.pm:783). Deleting an existing brew with no child glasses should
  # succeed.
  ($status, $headers, $body) = req("POST", "$BASE_URL",
      { o => "Brew", e => $id, id => $id, Name => $name2, BrewType => "Beer", submit => "Delete Brew" });
  $loc = assert_post_redirect($status, $headers, "Brew delete");
  return unless defined $loc;
  ($status, $headers, $body) = req("GET", $loc);
  assert_page_ok($status, $body, "Brew list after delete", "Brews");
  assert(scalar($body !~ /\Q$name2\E/), "Brew list no longer shows the deleted record '$name2'");
} # test_brew_roundtrip

sub test_location_roundtrip {
  # Plan Task 6: create a Location through the web, verify it on the Location
  # list, update it, and delete it — all through HTTP, no DB access.
  # postlocation() has a Delete branch (locations.pm:497), so the delete step
  # works.
  my $name = "TST" . time();
  get_first_id("Location");

  my ($status, $headers, $body) = req("POST", "$BASE_URL",
      { o => "Location", e => "new", Name => $name, LocType => "Bar", submit => "Insert Location" });
  my $loc = assert_post_redirect($status, $headers, "Location insert");
  return unless defined $loc;
  ($status, $headers, $body) = req("GET", $loc);
  assert_page_ok($status, $body, "Location list after insert", "Locations");
  assert(scalar($body =~ /\Q$name\E/), "Location list shows the new record '$name'");
  my $id = id_before_text($body, "Location", $name);
  assert(defined $id, "harvested the new Location id from the list");
  if ( defined $id ) {
    assert(scalar($body =~ /\Qo=Location&e=$id\E/), "the harvested id links to the Location edit page");
  }

  # Update the location: change the name, submit, verify the old name is gone
  # and the new one appears on the list page.
  return unless defined $id;
  my $name2 = "upd" . time();
  ($status, $headers, $body) = req("POST", "$BASE_URL",
      { o => "Location", e => $id, id => $id, Name => $name2, LocType => "Bar", submit => "Update Location" });
  $loc = assert_post_redirect($status, $headers, "Location update");
  return unless defined $loc;
  ($status, $headers, $body) = req("GET", $loc);
  assert_page_ok($status, $body, "Location list after update", "Locations");
  assert(scalar($body !~ /\Q$name\E/), "Location list no longer shows the old name '$name'");
  assert(scalar($body =~ /\Q$name2\E/), "Location list shows the updated name '$name2'");

  # Delete the location: POST with submit=Delete Location, handled by
  # postlocation() (locations.pm:497). Deleting an existing location with no
  # child glasses should succeed.
  ($status, $headers, $body) = req("POST", "$BASE_URL",
      { o => "Location", e => $id, id => $id, Name => $name2, LocType => "Bar", submit => "Delete Location" });
  $loc = assert_post_redirect($status, $headers, "Location delete");
  return unless defined $loc;
  ($status, $headers, $body) = req("GET", $loc);
  assert_page_ok($status, $body, "Location list after delete", "Locations");
  assert(scalar($body !~ /\Q$name2\E/), "Location list no longer shows the deleted record '$name2'");
} # test_location_roundtrip

# The id and BrewType of the first brew in the main input form's dropdown that
# already has a DefPrice, else (). A brew with a DefPrice means the
# DefPrice/DefVol auto-update in postglass is a no-op, so the glass POST cannot
# write to the brews table. Each dropdown item carries defprice='…' and
# brewtype='…' attributes (brews.pm:708); the id='actions' item does not match
# \d+. The regex lives right next to the test, per the "regexes stay visible"
# convention.
sub brew_with_defprice {
  my $body = shift;
  while ( $body =~ m{<div class='dropdown-item' id='(\d+)'[^>]*?defprice='([^']+)'[^>]*?brewtype='([^']*)'}g ) {
    return ($1, $3);
  }
  return ();
} # brew_with_defprice

sub test_glass_roundtrip {
  # Plan Task 6a: create a glass through the web (POST submit=Record), verify it
  # on the main list, update it (submit=Save), and delete it (submit=Del) — all
  # through HTTP, no DB access. The note is TST<epoch> so it is greppable in
  # pages, and the volume is an unlikely 11 cl so it never collides with real
  # drinking data in stats or price guessing. Only brews with an existing
  # DefPrice are used, so the brews table is never written.
  my $locid = get_first_id("Location");
  if ( !defined $locid ) { skipmsg("Location list has no ids for a glass"); return; }
  # Warm-up GET (get_first_id) absorbs the one-time fcgi reload bounce before
  # the first POST, so the insert is not silently dropped by a reload 302.
  get_first_id("Full");

  my ($status, $headers, $body) = req("GET", "$BASE_URL?o=Full");
  my ($brewid, $brewtype) = brew_with_defprice($body);
  if ( !defined $brewid ) { skipmsg("no brew with a DefPrice in the dev data"); return; }

  my $note = "TST" . time();
  my $date = strftime("%Y-%m-%d", localtime());
  my $time = strftime("%H:%M", localtime());

  # Insert: record the glass
  ($status, $headers, $body) = req("POST", "$BASE_URL",
      { o => "Full", Location => $locid, Brew => $brewid, selbrewtype => $brewtype,
        date => $date, time => $time, vol => "11", alc => "4.6", pr => "50",
        note => $note, submit => "Record" });
  my $loc = assert_post_redirect($status, $headers, "Glass insert");
  return unless defined $loc;
  ($status, $headers, $body) = req("GET", $loc);
  assert_page_ok($status, $body, "Full after glass insert", "id='mainform'");
  assert(scalar($body =~ /\Q$note\E/), "Full page shows the new note '$note'");
  my $id = id_before_text($body, "Full", $note);
  assert(defined $id, "harvested the new glass id from the main list");
  if ( defined $id ) {
    assert(scalar($body =~ /\Qo=Full&e=$id\E/), "the harvested id links to the glass edit page");
  }
  return unless defined $id;

  # Verify the volume landed: the edit form shows value='11c', and the note is
  # in the form
  ($status, $headers, $body) = req("GET", "$BASE_URL?o=Full&e=$id");
  assert_page_ok($status, $body, "glass edit form", "id='mainform'");
  assert(scalar($body =~ /name='vol'[^>]*value='11c'/), "glass edit form shows vol value='11c'");
  assert(scalar($body =~ /name='note'[^>]*value="\Q$note\E"/), "glass edit form shows the note '$note'");

  # Update: change the note. Must resend Location/Brew/vol — postglass
  # overwrites the glass with the posted params, and a missing vol would
  # default to 40 cl. $note2 must not contain $note as a substring, or the
  # "old note gone" assertion below would fail.
  my $note2 = "TST" . (time()+1) . "upd";
  ($status, $headers, $body) = req("POST", "$BASE_URL",
      { o => "Full", e => $id, Location => $locid, Brew => $brewid,
        selbrewtype => $brewtype, date => $date, time => $time, vol => "11",
        alc => "4.6", pr => "50", note => $note2, submit => "Save" });
  $loc = assert_post_redirect($status, $headers, "Glass update");
  return unless defined $loc;
  ($status, $headers, $body) = req("GET", $loc);
  assert_page_ok($status, $body, "Full after glass update", "id='mainform'");
  assert(scalar($body !~ /\Q$note\E/), "Full page no longer shows the old note '$note'");
  assert(scalar($body =~ /\Q$note2\E/), "Full page shows the updated note '$note2'");

  # Delete: POST with submit=Del, then verify the note is gone
  ($status, $headers, $body) = req("POST", "$BASE_URL",
      { o => "Full", e => $id, submit => "Del" });
  $loc = assert_post_redirect($status, $headers, "Glass delete");
  return unless defined $loc;
  ($status, $headers, $body) = req("GET", $loc);
  assert_page_ok($status, $body, "Full after glass delete", "id='mainform'");
  assert(scalar($body !~ /\Q$note2\E/), "Full page no longer shows the deleted record '$note2'");
} # test_glass_roundtrip

sub test_comment_roundtrip {
  # Plan Task 6b: attach a comment to an existing glass through the web (POST
  # commentedit=1), verify it, update it, and delete it — all through HTTP, no
  # DB access. The comment text is TST<epoch> so it is greppable in pages, and
  # the rating is a midrange 7. The comment sits on an existing glass, so no
  # glass cleanup is needed; the comment delete cleans up after itself.
  my $glassid = get_first_id("Full");
  if ( !defined $glassid ) { skipmsg("Full list has no glass ids for a comment"); return; }

  my $note = "TST" . time();

  # Insert: add the comment to the glass. Dispatch runs on the commentedit=1
  # param (index.fcgi:322), so o/e just follow the app's own form fields.
  my ($status, $headers, $body) = req("POST", "$BASE_URL",
      { commentedit => "1", o => "Comment", e => "new", glass => $glassid,
        rating => "7", comment => $note, commenttype => "brew", submit => "Add" });
  my $loc = assert_post_redirect($status, $headers, "Comment insert");
  return unless defined $loc;
  # The redirect lands back on the glass's page (o=Full&date=...&ndays=1)
  ($status, $headers, $body) = req("GET", $loc);
  assert_page_ok($status, $body, "Full after comment insert", "id='mainform'");
  assert(scalar($body =~ /\Q$note\E/), "glass page shows the new comment '$note'");
  my $id = id_before_text($body, "Comment", $note);
  assert(defined $id, "harvested the new comment id from the glass page");
  if ( defined $id ) {
    assert(scalar($body =~ /\Qo=Comment&e=$id\E/), "the harvested id links to the comment edit page");
  }
  return unless defined $id;

  # Verify the comment landed: the edit page shows the heading, the note in
  # the textarea, and the rating/type dropdowns preselected
  ($status, $headers, $body) = req("GET", "$BASE_URL?o=Comment&e=$id");
  assert_page_ok($status, $body, "Comment edit form", "Edit comment");
  assert(scalar($body =~ /name='comment'[^>]*>\s*\Q$note\E/), "comment edit form shows the note '$note'");
  assert(scalar($body =~ /id="rating"\s+name="rating"\s+value="7"/), "comment edit form shows rating value='7'");
  assert(scalar($body =~ /id="commenttype"\s+name="commenttype"\s+value="brew"/), "comment edit form shows type 'brew'");

  # Update: change the rating and the note. Must resend glass — postcomment's
  # UPDATE is gated on Glass IS NOT DISTINCT FROM ? (comments.pm:673). $note2
  # must not contain $note as a substring, or the "old note gone" assertion
  # below would fail.
  my $note2 = "TST" . (time()+1) . "upd";
  ($status, $headers, $body) = req("POST", "$BASE_URL",
      { commentedit => "1", o => "Comment", e => $id, glass => $glassid,
        comment_id => $id, rating => "8", comment => $note2,
        commenttype => "brew", submit => "Upd" });
  $loc = assert_post_redirect($status, $headers, "Comment update");
  return unless defined $loc;
  ($status, $headers, $body) = req("GET", $loc);
  assert_page_ok($status, $body, "Full after comment update", "id='mainform'");
  assert(scalar($body !~ /\Q$note\E/), "glass page no longer shows the old comment '$note'");
  assert(scalar($body =~ /\Q$note2\E/), "glass page shows the updated comment '$note2'");

  # Delete: POST with submit=Del and comment_id. Must resend glass so the
  # redirect lands back on the glass page for verification.
  ($status, $headers, $body) = req("POST", "$BASE_URL",
      { commentedit => "1", o => "Comment", e => $id, glass => $glassid,
        comment_id => $id, submit => "Del" });
  $loc = assert_post_redirect($status, $headers, "Comment delete");
  return unless defined $loc;
  ($status, $headers, $body) = req("GET", $loc);
  assert_page_ok($status, $body, "Full after comment delete", "id='mainform'");
  assert(scalar($body !~ /\Q$note2\E/), "glass page no longer shows the deleted comment '$note2'");
} # test_comment_roundtrip

################################################################################
# Post-run: CopyProdData sync + debug.log scan
################################################################################
# Debug log lives in the repo's beerdata directory (index.fcgi opens
# $datadir . "debug.log", and $datadir is "./beerdata/" from the repo root).
my $LOGFILE = "./beerdata/debug.log";

# Record debug.log size before the run; scan only the appended portion after.
sub log_size {
  return -s $LOGFILE || 0;
} # log_size

# The one CopyProdData after the run, only when the run made POST requests.
# GET-only runs never touch the database, so no sync is needed. If dev code is
# ahead of prod (new migrations), the first GET after CopyProdData lands on the
# migrate form; detect that and report instead of failing confusingly.
sub sync_proddata {
  my ($status, $headers, $body) = req("GET", "$BASE_URL?o=CopyProdData");
  assert($status == 302, "CopyProdData redirects (got $status)");
  return unless $status == 302;
  my $loc = $headers->header('Location') || "$BASE_URL";
  # Follow the redirect; if dev code is ahead of prod, this renders the migrate
  # form (startup_check in index.fcgi switches op to 'migrate').
  ($status, $headers, $body) = req("GET", $loc);
  if ( $status == 302 && ($headers->header('Location') || "") =~ /o=migrate/i ) {
    print "note: run migrations first (dev DB is behind the code)\n";
    return;
  }
  if ( $status == 200 && $body =~ /Database Migration Required/i ) {
    print "note: run migrations first (dev DB is behind the code)\n";
    return;
  }
  assert($status == 200, "page after CopyProdData loads (got $status)");
  assert(no_errors_in($body), "page after CopyProdData is free of error markers");
} # sync_proddata

# Scan the appended portion of debug.log for new error lines. The bare word
# "ERROR" IS a marker here, unlike in no_errors_in(): this is the server log,
# not rendered user data, so a line containing ERROR means an error occurred.
sub scan_log_appended {
  my ($log_before) = @_;
  return unless -f $LOGFILE;
  open my $fh, "<:utf8", $LOGFILE or do {
    assert(0, "cannot open $LOGFILE: $!");
    return;
  };
  seek $fh, $log_before, 0;
  my $appended = do { local $/; <$fh> };
  close $fh;
  my @bad;
  while ( $appended =~ /^(.*(?:DB ERROR|ERROR|Use of uninitialized).*)$/gim ) {
    push @bad, $1;
  }
  assert(!@bad, "no new DB ERROR/ERROR/Use of uninitialized lines in debug.log");
  foreach my $line (@bad) {
    print "  log: $line\n";
  }
} # scan_log_appended

# Post-run: the conditional CopyProdData sync (only when POSTs happened) and the
# debug.log scan, once around the whole run rather than per test. Runs even when
# a mid-run failure aborted the tests.
sub post_run {
  my ($log_before) = @_;
  if ( $post_count > 0 ) {
    if ( $fail > 0 ) {
      print "post-run: $fail test(s) failed, skipping CopyProdData sync " .
          "so the database can be inspected\n";
    } else {
      sync_proddata();
    }
  } elsif ( !$quiet ) {
    print "post-run: no POST requests, skipping CopyProdData sync\n";
  }
  scan_log_appended($log_before);
} # post_run

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

# POST round-trips are dev-guarded: they write to the dev DB, so they may only
# run against a -dev checkout/URL. --no-post drops them from the run.
my @post_run = grep { my $p = 0;
                      foreach my $c (@{ $_->{sets} }) { $p = 1 if $c eq 'posts'; }
                      $p } @run;
if ( @post_run ) {
  if ( $no_post ) {
    @run = grep { my $p = 0;
                  foreach my $c (@{ $_->{sets} }) { $p = 1 if $c eq 'posts'; }
                  !$p } @run;
    print "note: --no-post given, skipping " . scalar(@post_run) . " POST test(s)\n";
    if ( !@run ) {
      print "note: nothing left to run\n";
      exit 0;
    }
  } elsif ( $reldir !~ /-dev/i ) {
    print "aborting: POST tests require a '-dev' checkout (this directory is '$reldir')\n";
    exit 1;
  }
}

# Record debug.log size before the run; the post-run scan only looks at the
# appended portion, so pre-existing log errors are not re-flagged.
my $log_before = log_size();

# Wrap the run so a mid-run failure (e.g. a POST killing the worker) still
# triggers the post-run CopyProdData sync (when POSTs happened) and the
# debug.log scan, then re-raises the error for the exit code.
my $run_error;
eval {
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
  1;
} or do {
  $run_error = $@ || "unknown run failure";
  print "run aborted: $run_error\n";
};

# Post-run: conditional CopyProdData sync + debug.log scan, once around the run
post_run($log_before);

# Re-raise a mid-run failure so it counts as a failure for the exit code
if ( $run_error ) {
  $fail++;
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
# Label the run with the set(s) we were asked to run, or 'quick' on the default
my $label = @ARGV ? join(", ", @ARGV) : "quick";
if ( $fail == 0 ) {
  print "$label done: $nsets sets, $ntests tests, all PASS";
  print " ($skipped skipped)" if $skipped;
  print "\n";
} else {
  print "$label done: $nsets sets, $ntests tests, $pass PASS, $fail FAIL";
  print ", $skipped skipped" if $skipped;
  print "\n";
}
exit($fail ? 1 : 0);
