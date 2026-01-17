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

    # Check current active tap
    my $sql = "SELECT * FROM current_taps WHERE Location = ? AND Tap = ?";
    my $sth = $c->{dbh}->prepare($sql);
    $sth->execute($location_id, $tap_num);
    my $current = $sth->fetchrow_hashref;

    if ($current) {
      if ($current->{Brew} == $tap->{brew_id}) {
        print STDERR "taps: Tap $tap_num beer unchanged\n";
      } else {
        # Close old tap
        my $close_sql = "UPDATE tap_beers SET Gone = ? WHERE Id = ?";
        my $close_sth = $c->{dbh}->prepare($close_sql);
        $close_sth->execute($now, $current->{Id});
        print STDERR "taps: Closed tap $tap_num at location $location_id\n";

        # Insert new tap
        my $insert_sql = "INSERT INTO tap_beers (Location, Tap, Brew, FirstSeen, LastSeen) VALUES (?, ?, ?, ?, ?)";
        my $insert_sth = $c->{dbh}->prepare($insert_sql);
        $insert_sth->execute($location_id, $tap_num, $tap->{brew_id}, $now, $now);
        print STDERR "taps: Opened tap $tap_num with brew $tap->{brew_id} at location $location_id\n";
      }
    } else {
      # Insert new tap
      my $insert_sql = "INSERT INTO tap_beers (Location, Tap, Brew, FirstSeen, LastSeen) VALUES (?, ?, ?, ?, ?)";
      my $insert_sth = $c->{dbh}->prepare($insert_sql);
      $insert_sth->execute($location_id, $tap_num, $tap->{brew_id}, $now, $now);
      print STDERR "taps: Opened tap $tap_num with brew $tap->{brew_id} at location $location_id\n";
    }
  }

  # Close missing taps
  my $missing_sql = "SELECT Tap, Id FROM current_taps WHERE Location = ?";
  my $missing_sth = $c->{dbh}->prepare($missing_sql);
  $missing_sth->execute($location_id);
  while (my $row = $missing_sth->fetchrow_hashref) {
    next if $scraped_taps{$row->{Tap}};
    my $close_sql = "UPDATE tap_beers SET Gone = ? WHERE Id = ?";
    my $close_sth = $c->{dbh}->prepare($close_sql);
    $close_sth->execute($now, $row->{Id});
    print STDERR "taps: Closed tap $row->{Tap} (not scraped) at location $location_id\n";
  }

  # Update LastSeen for active taps
  my $update_sql = "UPDATE tap_beers SET LastSeen = ? WHERE Location = ? AND Gone IS NULL";
  my $update_sth = $c->{dbh}->prepare($update_sql);
  $update_sth->execute($now, $location_id);
  print STDERR "taps: Updated LastSeen for active taps at location $location_id\n";

  # TODO: Add scrape marker (future enhancement)
  # my $marker_sql = "INSERT INTO tap_beers (Location, Tap, Brew, FirstSeen, LastSeen) VALUES (?, NULL, NULL, ?, ?)";
  # my $marker_sth = $c->{dbh}->prepare($marker_sql);
  # $marker_sth->execute($location_id, $now, $now);
  # print STDERR "taps: Added scrape marker for location $location_id\n";
} # update_taps

################################################################################
# Report module loaded ok
1;