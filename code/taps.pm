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

  my $now = util::now();
  my %scraped_taps;

  # Fetch all current active taps for this location upfront
  my %current;
  my $cur_sth = db::query($c, "SELECT Tap, Brew, Id FROM current_taps WHERE Location = ?", $location_id);
  while (my $row = $cur_sth->fetchrow_hashref) {
    $current{$row->{Tap}} = $row;
  }

  foreach my $tap (@$beerlist) {
    next unless $tap->{brew_id};
    my $tap_num = $tap->{id};
    $scraped_taps{$tap_num} = 1;

    my $cur = $current{$tap_num};
    if ($cur && $cur->{Brew} == $tap->{brew_id}) {
      next;  # Brew unchanged - LastSeen updated below
    }

    # Close old tap if brew has changed
    if ($cur) {
      db::execute($c, "UPDATE tap_beers SET Gone = ? WHERE Id = ?", $now, $cur->{Id});
    }

    # Insert tap (new or changed)
    my @sizes = sort { ($a->{vol} || 0) <=> ($b->{vol} || 0) } @{$tap->{sizePrice} || []};
    my ($sizeS, $priceS, $sizeM, $priceM, $sizeL, $priceL);
    if (@sizes >= 1) {
      $sizeS = $sizes[0]->{vol};
      $priceS = $sizes[0]->{price};
    }
    if (@sizes == 2) {
      $sizeL = $sizes[1]->{vol};
      $priceL = $sizes[1]->{price};
    } elsif (@sizes >= 3) {
      $sizeM = $sizes[1]->{vol};
      $priceM = $sizes[1]->{price};
      $sizeL = $sizes[2]->{vol};
      $priceL = $sizes[2]->{price};
    }

    my $insert_sql = "INSERT INTO tap_beers (Location, Tap, Brew, FirstSeen, LastSeen, SizeS, PriceS, SizeM, PriceM, SizeL, PriceL) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)";
    db::execute($c, $insert_sql, $location_id, $tap_num, $tap->{brew_id}, $now, $now, $sizeS, $priceS, $sizeM, $priceM, $sizeL, $priceL);
    my $action = $cur ? "Closed and opened" : "Opened";
    print { $c->{log} } "taps: $action tap $tap_num with brew $tap->{brew_id} at location $location_id\n";
  }

  # Close taps that were not in the scraped list
  foreach my $tap_num (keys %current) {
    next if $scraped_taps{$tap_num};
    db::execute($c, "UPDATE tap_beers SET Gone = ? WHERE Id = ?", $now, $current{$tap_num}{Id});
    print { $c->{log} } "taps: Closed tap $tap_num (not scraped) at location $location_id\n";
  }

  # Update LastSeen for active taps
  my $update_sql = "UPDATE tap_beers SET LastSeen = ? WHERE Location = ? AND Gone IS NULL";
  db::execute($c, $update_sql, $now, $location_id);
  #print { $c->{log} } "taps: Updated LastSeen for active taps at location $location_id\n";

  # Add scrape marker 
  my $marker_sql = "INSERT INTO tap_beers (Location, Tap, Brew, FirstSeen, LastSeen) VALUES (?, NULL, NULL, ?, ?)";
  db::execute($c, $marker_sql, $location_id, $now, $now);
  #print { $c->{log} } "taps: Added scrape marker for location $location_id\n";
} # update_taps

################################################################################
# Report module loaded ok
1;