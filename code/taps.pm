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

  foreach my $tap (@$beerlist) {
    next unless $tap->{brew_id};
    my $tap_num = $tap->{id};
    $scraped_taps{$tap_num} = 1;

    # Prepare size/price data
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

    # Check current active tap
    my $sql = "SELECT * FROM current_taps WHERE Location = ? AND Tap = ?";
    my $sth = db::query($c, $sql, $location_id, $tap_num);
    my $current = $sth->fetchrow_hashref;

    if ($current) {
      if ($current->{Brew} == $tap->{brew_id}) {
        # Brew unchanged; update prices if they changed
        if ( ($current->{SizeS} // 0) != ($sizeS // 0) ||
             ($current->{PriceS} // 0) != ($priceS // 0) ||
             ($current->{SizeM} // 0) != ($sizeM // 0) ||
             ($current->{PriceM} // 0) != ($priceM // 0) ||
             ($current->{SizeL} // 0) != ($sizeL // 0) ||
             ($current->{PriceL} // 0) != ($priceL // 0) ) {
          my $price_sql = "UPDATE tap_beers SET SizeS=?, PriceS=?, SizeM=?, PriceM=?, SizeL=?, PriceL=? WHERE Id=?";
          db::execute($c, $price_sql, $sizeS, $priceS, $sizeM, $priceM, $sizeL, $priceL, $current->{Id});
          print { $c->{log} } "taps: Updated prices for tap $tap_num at location $location_id\n";
        }
      } else {
        # Close old tap
        my $close_sql = "UPDATE tap_beers SET Gone = ? WHERE Id = ?";
        db::execute($c, $close_sql, $now, $current->{Id});
        #print { $c->{log} } "taps: Closed tap $tap_num at location $location_id\n";

        # Insert new tap
        my $insert_sql = "INSERT INTO tap_beers (Location, Tap, Brew, FirstSeen, LastSeen, SizeS, PriceS, SizeM, PriceM, SizeL, PriceL) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)";
        db::execute($c, $insert_sql, $location_id, $tap_num, $tap->{brew_id}, $now, $now, $sizeS, $priceS, $sizeM, $priceM, $sizeL, $priceL);
        print { $c->{log} } "taps: Closed and opened tap $tap_num with brew $tap->{brew_id} at location $location_id\n";
      }
    } else {
      # Insert new tap
      my $insert_sql = "INSERT INTO tap_beers (Location, Tap, Brew, FirstSeen, LastSeen, SizeS, PriceS, SizeM, PriceM, SizeL, PriceL) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)";
      db::execute($c, $insert_sql, $location_id, $tap_num, $tap->{brew_id}, $now, $now, $sizeS, $priceS, $sizeM, $priceM, $sizeL, $priceL);
      print { $c->{log} } "taps: Opened tap $tap_num with brew $tap->{brew_id} at location $location_id\n";
    }
  }

  # Close missing taps
  my $missing_sql = "SELECT Tap, Id FROM current_taps WHERE Location = ?";
  my $missing_sth = db::query($c, $missing_sql, $location_id);
  while (my $row = $missing_sth->fetchrow_hashref) {
    next if $scraped_taps{$row->{Tap}};
    my $close_sql = "UPDATE tap_beers SET Gone = ? WHERE Id = ?";
    db::execute($c, $close_sql, $now, $row->{Id});
    print { $c->{log} } "taps: Closed tap $row->{Tap} (not scraped) at location $location_id\n";
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