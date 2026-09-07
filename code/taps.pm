# Module for updating tap_beers table based on scraper data

package taps;
use strict;
use warnings;

use feature 'unicode_strings';
use utf8;  # Source code and string literals are utf-8
use URI::Escape qw(uri_escape_utf8);

################################################################################
# Update tap_beers table for a location's scraped beer list
################################################################################

sub update_taps {
  my $c = shift;
  my $location_id = shift;
  my $beerlist = shift;
  my $current_ref = shift;  # Pre-fetched current board from scrapeboard.pm
  my %current = %$current_ref; # current taps from the scraper

  my $now = dateutil::now();
  my $taps_changed = 0;
  my %scraped_taps;


  foreach my $tap (@$beerlist) {
    next unless $tap->{brew_id};
    my $tap_num = $tap->{id};
    $scraped_taps{$tap_num} = 1;

    my $cur = $current{$tap_num};
    if ($cur && $cur->{Brew} == $tap->{brew_id}) {
      next;  # Brew unchanged - LastSeen updated below
    }

    # Close ALL old taps with this number (handles duplicates from old scrapes)
    if ($cur) {
      db::execute($c, "UPDATE tap_beers SET Gone = ? WHERE Location = ? AND Tap = ? AND Gone IS NULL", $now, $location_id, $tap_num);
    }

    # Insert tap (new or changed)
    $taps_changed++;
    my ($sizes, $sp) = util::sizeprices($tap->{sizePrice});

    my $insert_sql = "INSERT INTO tap_beers (Location, Tap, Brew, FirstSeen, LastSeen, SizeS, PriceS, SizeM, PriceM, SizeL, PriceL) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)";
    db::execute($c, $insert_sql, $location_id, $tap_num, $tap->{brew_id}, $now, $now,
      $sp->{SizeS}, $sp->{PriceS}, $sp->{SizeM}, $sp->{PriceM}, $sp->{SizeL}, $sp->{PriceL});
    my $action = "Opened";
    $action = "Closed and opened" if ($cur);
    print { $c->{log} } "taps: $action tap $tap_num with brew $tap->{brew_id} at location $location_id\n";

    # First seen on tap: remember the brew's earliest appearance
    db::execute($c, "UPDATE brews SET FirstSeen = COALESCE(FirstSeen, strftime('%Y-%m-%d', ?)) WHERE Id = ?", $now, $tap->{brew_id});

  } # foreach tap

  # Close taps that were not in the scraped list
  foreach my $tap_num (keys %current) {
    next if $scraped_taps{$tap_num};
    db::execute($c, "UPDATE tap_beers SET Gone = ? WHERE Id = ?", $now, $current{$tap_num}{Id});
    print { $c->{log} } "taps: Closed tap $tap_num (not scraped) at location $location_id\n";
  }

  # Update LastSeen for active taps
  my $update_sql = "UPDATE tap_beers SET LastSeen = ? WHERE Location = ? AND Gone IS NULL";
  db::execute($c, $update_sql, $now, $location_id);

  # Add scrape marker (one per location, indicating last scrape time)
  # Manual upsert: update LastSeen if marker exists, insert if not.
  my $rows = db::execute($c, "UPDATE tap_beers SET LastSeen = ? WHERE Location = ? AND Tap IS NULL AND Brew IS NULL AND Gone IS NULL", $now, $location_id);
  if ($rows == 0) {
    db::execute($c, "INSERT INTO tap_beers (Location, Tap, Brew, FirstSeen, LastSeen) VALUES (?, NULL, NULL, ?, ?)", $location_id, $now, $now);
  }

  return $taps_changed;
} # update_taps

################################################################################
# Render the tap action form (shared between beer board and tap history)
# $tap_beers_id: the tap_beers row Id
# $locname: location name (for redirect back)
# $is_gone: if true, the keg is closed — show "reopen" instead of "close & reopen"
################################################################################

sub render_tap_action_form {
  my ($c, $tap_beers_id, $locname, $is_gone, $is_unusual) = @_;

  my $form_id = "tapact_$tap_beers_id";

  # The [manage] link - inline, same line as surrounding text
  print "<span style='font-size: x-small;'> ";
  print "<span style='cursor: pointer; color: #888;' "
      . "onclick=\"var f=document.getElementById('$form_id'); "
      . "f.style.display=(f.style.display==='none'?'block':'none');\">[manage]</span>\n";
  print "</span>\n";

  # The form - hidden div, opens on a new line below
  print "<div id='$form_id' style='display: none; font-size: x-small; margin-top: 2px;'>\n";
  _render_tap_action_form_fields($c, $tap_beers_id, $locname, $is_gone, $is_unusual);
  print "</div>\n";
} # render_tap_action_form

# Render the actual form in a table row (called separately for tap history)
sub render_tap_action_form_row {
  my ($c, $tap_beers_id, $locname, $is_gone, $colspan, $is_unusual) = @_;

  my $form_id = "tapact_$tap_beers_id";

  print "<tr id='$form_id' style='display: none;'>\n";
  print "<td colspan='$colspan' style='border: none; padding: 4px 6px;'>\n";
  _render_tap_action_form_fields($c, $tap_beers_id, $locname, $is_gone, $is_unusual);
  print "</td></tr>\n";
} # render_tap_action_form_row

# Shared: render the actual form fields
sub _render_tap_action_form_fields {
  my ($c, $tap_beers_id, $locname, $is_gone, $is_unusual) = @_;

  print "<form method='POST' accept-charset='UTF-8' class='no-print' "
      . "style='display: inline;'>\n";
  print "<input type='hidden' name='o' value='Taps' />\n";
  print "<input type='hidden' name='tap_beers_id' value='$tap_beers_id' />\n";
  print "<input type='hidden' name='loc' value='" . util::htmlesc($locname) . "' />\n";
  print "<input type='hidden' name='redir_op' value='" . util::htmlesc($c->{op}) . "' />\n";

  # Styled dropdown using our dropdown CSS classes
  my @opts;
  if ($is_gone) {
    push @opts, ["reopen", "Reopen this keg"];
  } else {
    push @opts, ["close", "Close tap"];
    push @opts, ["close_reopen", "Close &amp; reopen same"];
  }

  print "<div class='dropdown' style='max-width: 14em; display: inline-block; vertical-align: middle;'>\n";
  print "  <div class='dropdown-main'>\n";
  print "    <input type='text' class='dropdown-filter' autocomplete='off' "
      . "placeholder='Leave keg open' value='' readonly\n"
      . "    onfocus=\"var dl=this.parentElement.querySelector('.dropdown-list'); "
      . "dl.style.display='block'; this.value='';\"\n"
      . "    onblur=\"var dl=this.parentElement.querySelector('.dropdown-list'); "
      . "var self=this; setTimeout(function(){ dl.style.display='none'; self.value=''; }, 200);\"\n"
      . "    style='font-size: x-small; width: 10em;' />\n";
  print "    <input type='hidden' name='tap_action' value='' />\n";
  print "    <div class='dropdown-list'>\n";
  for my $opt (@opts) {
    print "      <div class='dropdown-item' id='$opt->[0]' "
        . "onmousedown=\"this.closest('form').querySelector('input[name=tap_action]').value='$opt->[0]'; "
        . "this.closest('.dropdown').querySelector('.dropdown-filter').value='$opt->[1]';\">"
        . "$opt->[1]</div>\n";
  }
  print "    </div>\n";
  print "  </div>\n";
  print "</div>\n";

  my $checked = $is_unusual ? " checked" : "";
  print "<br/>\n";
  print "<input type='checkbox' name='mark_unusual' value='1'$checked /> <span>Unusual</span>\n";
  print "<br/>\n";
  print "<input type='submit' value='Update Keg' />\n";
  print "</form>\n";
} # _render_tap_action_form_fields

################################################################################
# POST handler for tap actions (close, close & reopen, reopen, mark unusual)
################################################################################

sub posttapaction {
  my $c = shift;

  my $tap_beers_id = util::param($c, "tap_beers_id");
  my $tap_action = util::param($c, "tap_action") || "";
  my $mark_unusual = util::param($c, "mark_unusual") || 0;
  my $locname = util::param($c, "loc") || "";

  util::error("Missing tap_beers_id") unless $tap_beers_id;

  # Look up the tap_beers row
  my $sth = $c->{dbh}->prepare(
    "SELECT Id, Location, Tap, Brew FROM tap_beers WHERE Id = ?");
  $sth->execute($tap_beers_id);
  my $tap = $sth->fetchrow_hashref;
  $sth->finish;
  util::error("Tap record $tap_beers_id not found") unless $tap;

  my $now = dateutil::now();

  if ($tap_action eq "close") {
    db::execute($c, "UPDATE tap_beers SET Gone = ? WHERE Id = ?", $now, $tap_beers_id);
    print { $c->{log} } "taps: manual close tap $tap->{Tap} (id=$tap_beers_id) at location $tap->{Location}\n";

  } elsif ($tap_action eq "close_reopen") {
    db::execute($c, "UPDATE tap_beers SET Gone = ? WHERE Id = ?", $now, $tap_beers_id);
    db::execute($c,
      "INSERT INTO tap_beers (Location, Tap, Brew, FirstSeen, LastSeen, SizeS, PriceS, SizeM, PriceM, SizeL, PriceL) "
      . "SELECT Location, Tap, Brew, ?, ?, SizeS, PriceS, SizeM, PriceM, SizeL, PriceL "
      . "FROM tap_beers WHERE Id = ?",
      $now, $now, $tap_beers_id);
    print { $c->{log} } "taps: manual close & reopen tap $tap->{Tap} (id=$tap_beers_id) at location $tap->{Location}\n";

  } elsif ($tap_action eq "reopen") {
    # Verify no newer active keg on this tap
    my $check = $c->{dbh}->prepare(
      "SELECT Id FROM tap_beers WHERE Location = ? AND Tap = ? AND Gone IS NULL AND Id != ?");
    $check->execute($tap->{Location}, $tap->{Tap}, $tap_beers_id);
    my $existing = $check->fetchrow_hashref;
    $check->finish;
    if ($existing) {
      util::error("Cannot reopen: tap $tap->{Tap} already has an active keg at this location");
    }
    db::execute($c, "UPDATE tap_beers SET Gone = NULL WHERE Id = ?", $tap_beers_id);
    print { $c->{log} } "taps: manual reopen tap $tap->{Tap} (id=$tap_beers_id) at location $tap->{Location}\n";
  }

  # Handle unusual flag
  if ($tap_action ne "" || $mark_unusual) {
    my $unusual_val = $mark_unusual ? 1 : 0;
    db::execute($c, "UPDATE tap_beers SET Unusual = ? WHERE Id = ?", $unusual_val, $tap_beers_id);
    print { $c->{log} } "taps: set Unusual=$unusual_val for tap $tap->{Tap} (id=$tap_beers_id)\n";
  }

  # Redirect back to the original page (beer board or tap history)
  my $redir_op = util::param($c, "redir_op") || $c->{op};
  my $redir = "$c->{url}?o=" . uri_escape_utf8($redir_op);
  if ($locname) {
    $redir .= "&loc=" . uri_escape_utf8($locname);
  }
  # Preserve extra query params (days, from, tap) from the original page
  my $qs = $ENV{'QUERY_STRING'} || "";
  foreach my $pair (split(/&/, $qs)) {
    my ($k, $v) = split(/=/, $pair, 2);
    next if !$k || $k eq 'o' || $k eq 'loc' || $k eq 'tap_beers_id' || $k eq 'tap_action' || $k eq 'mark_unusual';
    $redir .= "&$k=" . uri_escape_utf8($v) if defined $v;
  }
  $c->{redirect_url} = $redir;
} # posttapaction

################################################################################
# Report module loaded ok
1;
