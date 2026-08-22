# Module for updating tap_beers table based on scraper data

package taps;
use strict;
use warnings;

use feature 'unicode_strings';
use utf8;  # Source code and string literals are utf-8

################################################################################
# Update tap_beers table for a location's scraped beer list
################################################################################

sub update_taps {
  my $c = shift;
  my $location_id = shift;
  my $beerlist = shift;
  my $current_ref = shift;  # Pre-fetched current board from scrapeboard.pm
  my %current = %$current_ref; # current taps from the scraper

  my $now = util::now();
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
# Report module loaded ok
1;
