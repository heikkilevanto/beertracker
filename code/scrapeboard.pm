# Part of my beertracker
# Routines for scraping beer lists and updating brews and producers


package scrapeboard;
use strict;
use warnings;
use feature 'unicode_strings';
use utf8;  # Source code and string literals are utf-8
use JSON;
use URI::Escape qw(uri_escape_utf8);

################################################################################
# get_scraper_locations($c, $days)
# Returns a list of location names that have a scraper configured,
# sorted by most recently used (via glasses) first.
# If $days is set, only locations with glasses within that many days are returned.
################################################################################

sub get_scraper_locations {
  my $c = shift;
  my $days = shift;
  my $sql = q{
    SELECT l.Name
    FROM locations l
    LEFT JOIN glasses g ON g.Location = l.Id
    WHERE l.Scraper IS NOT NULL
    GROUP BY l.Id
  };
  my @params;
  if (defined $days) {
    $sql .= " HAVING MAX(g.Timestamp) > datetime('now', ?)";
    push @params, "-$days days";
  }
  $sql .= " ORDER BY MAX(g.Timestamp) DESC, l.Name";
  my $sth = db::query($c, $sql, @params);
  my @locs;
  while (my $row = $sth->fetchrow_hashref) {
    push @locs, $row->{Name};
  }
  return @locs;
} # get_scraper_locations

################################################################################
# Update board: scrape and ensure brews/producers exist in DB
################################################################################

sub updateboard {
  my $c = shift;

  my $locparam = shift;
  $locparam = util::param($c,"loc") unless defined $locparam;

  $c->{scrape_status} = undef;

  my $loc_rec = db::findrecord($c, "LOCATIONS", "Name", $locparam, "collate nocase");
  my $scraper_str = $loc_rec ? $loc_rec->{Scraper} : undef;

  if (!$scraper_str) {
    print { $c->{log} } "updateboard: No scraper for '$locparam'\n";
    return;  # No error page
  }

  my ($scriptfile, $arg) = split(' ', $scraper_str, 2);
  my $script = $c->{scriptdir} . $scriptfile;
  $arg = '' unless defined $arg;
  my $json = `timeout 5s perl $script $arg`;
  if ($!) {
    print { $c->{log} } "updateboard: Timeout running $script: $!\n";
    return;
  }
  chomp($json);
  if (!$json) {
    print { $c->{log} } "updateboard: No output from scraper for $locparam\n";
    return;
  }

  my $beerlist = eval { JSON->new->utf8->decode($json) };
  if ($@) {
    print { $c->{log} } "updateboard: JSON decode failed for $locparam: $@\n";
    return;
  }

  print { $c->{log} } "updateboard: Scraped " . scalar(@$beerlist) . " beers for $locparam\n";

  # Get location ID (reuse $loc_rec fetched earlier for scraper lookup)
  my $loc_id = $loc_rec->{Id};

  # Fetch current board upfront: tap_num -> { Id, Brew, BrewName, Producer, prices, DefPrice }
  my %current_board;
  my $cur_sth = db::query($c, "
    SELECT ct.Tap, ct.Brew, ct.Id, ct.BrewName, ct.Producer,
           tb.SizeS, tb.PriceS, tb.SizeM, tb.PriceM, tb.SizeL, tb.PriceL,
           b.DefPrice
    FROM current_taps ct
    JOIN tap_beers tb ON tb.Id = ct.Id
    JOIN brews b ON b.Id = ct.Brew
    WHERE ct.Location = ?
  ", $loc_id);
  while (my $row = $cur_sth->fetchrow_hashref) {
    $current_board{$row->{Tap}} = $row;
  }

  my $inserted_brews = 0;
  my $inserted_producers = 0;

  foreach my $e (@$beerlist) {
    my $maker = $e->{maker} || "";
    my $beer = $e->{beer} || "";
    my $style = $e->{type} || "";
    my $alc = $e->{alc} || "";
    my $tap_num = $e->{id};

    next unless $maker && $beer;  # Skip incomplete entries

    # Check if this tap is unchanged - reuse brew_id without any DB lookups
    my $cur = $current_board{$tap_num};
    if ($cur && ($cur->{BrewName} // '') eq $beer && ($cur->{Producer} // '') eq $maker) {
      $e->{brew_id} = $cur->{Brew};

      # If DB has no prices but scraper does, update prices directly
      my @sizes = sort { ($a->{vol} || 0) <=> ($b->{vol} || 0) } @{$e->{sizePrice} || []};
      if (@sizes) {
        my $db_has_prices = $cur->{PriceS} || $cur->{PriceM} || $cur->{PriceL};
        unless ($db_has_prices) {
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
          db::execute($c,
            "UPDATE tap_beers SET SizeS=?, PriceS=?, SizeM=?, PriceM=?, SizeL=?, PriceL=? WHERE Id=?",
            $sizeS, $priceS, $sizeM, $priceM, $sizeL, $priceL, $cur->{Id});
          print { $c->{log} } "updateboard: Added prices to tap $tap_num ($beer) at location $locparam\n";

          # Also update brew's DefPrice/DefVol if not already set
          if (!$cur->{DefPrice}) {
            my $largest = $sizes[-1];
            db::execute($c, "UPDATE BREWS SET DefPrice = ?, DefVol = ? WHERE Id = ?",
              $largest->{price}, $largest->{vol}, $cur->{Brew});
            print { $c->{log} } "updateboard: Set brew $cur->{Brew} DefPrice=$largest->{price} DefVol=$largest->{vol}\n";
          }
        }
      }

      next;
    }

    # Tap is new or changed - ensure producer exists
    my $prod_rec = db::findrecord($c, "LOCATIONS", "Name", $maker, "collate nocase");
    my $prod_id;
    if ($prod_rec) {
      $prod_id = $prod_rec->{Id};
    } else {
      # Insert new producer
      my $sql = "INSERT INTO LOCATIONS (Name, LocType, LocSubType) VALUES (?, 'Producer', 'Beer')";
      db::execute($c, $sql, $maker);
      $prod_id = $c->{dbh}->last_insert_id(undef, undef, "LOCATIONS", undef);
      $inserted_producers++;
      print { $c->{log} } "updateboard: Inserted producer '$maker' (id $prod_id)\n";
    }

    # Ensure brew exists
    my $sql_check = "SELECT Id FROM BREWS WHERE Name = ? AND ProducerLocation = ?";
    my ($brew_id) = db::queryarray($c, $sql_check, $beer, $prod_id);

    if (!$brew_id) {
      # Insert new brew
      my $short_style = styles::shortbeerstyle($style);
      # Extract year from beer name if present
      my $year = undef;
      if ($beer =~ /(20[23][0-9])/) {
        $year = $1;
      }
      my $sql = "INSERT INTO BREWS " .
        "(Name, BrewType, SubType, BrewStyle, Alc, ProducerLocation, Year) " .
        "VALUES (?, 'Beer', ?, ?, ?, ?, ?)";
      db::execute($c, $sql, $beer, $short_style, $style, $alc, $prod_id, $year);
      $brew_id = $c->{dbh}->last_insert_id(undef, undef, "BREWS", undef);
      $inserted_brews++;
      print { $c->{log} } "updateboard: Inserted brew '$beer' by '$maker' (id $brew_id)\n";
    }
    $e->{brew_id} = $brew_id;
  }

  print { $c->{log} } "updateboard: $inserted_brews new brews inserted\n" if $inserted_brews;

  # Log if any tap numbers were renumbered (have fractional part)
  my @renumbered;
  my %seen_tap;
  foreach my $e (@$beerlist) {
    my $tap = $e->{id} // 0;
    my $intpart = int($tap);
    my $frac = $tap - $intpart;
    if ($frac > 0 && !$seen_tap{$intpart}) {
      push @renumbered, $tap;
      $seen_tap{$intpart} = 1;
    }
  }
  if (@renumbered) {
    print { $c->{log} } "updateboard: Duplicate or missing tap numbers renumbered: " . join(", ", sort { $a <=> $b } @renumbered) . "\n";
  }

  # Update taps
  my $taps_changed = taps::update_taps($c, $loc_id, $beerlist, \%current_board);

  $c->{scrape_status} = "${inserted_brews} new brews, ${inserted_producers} new producers, ${taps_changed} taps changed";

  # Redirect back to showing the board, for this location (web context only)
  $c->{redirect_url} = "$c->{url}?o=Board&loc=" . uri_escape_utf8($locparam)
    if $c->{url};
}

# Helper to create a POST form for triggering an operation
sub post_form {
  my ($c, $op, $loc, $label) = @_;
  my $form_id = "form_" . $op . "_" . ($loc || 'none');
  $form_id =~ s/\W/_/g;  # sanitize
  my $form = "<form id='$form_id' method='POST' accept-charset='UTF-8' action='$c->{url}' style='display:inline;'>";
  $form .= "<input type='hidden' name='o' value='$op'>";
  $form .= "<input type='hidden' name='loc' value='$loc'>" if $loc;
  $form .= "</form>";
  $form .= "<a href='#' onclick='document.getElementById(\"$form_id\").submit(); return false;'><i>$label</i></a>\n";
  return $form;
}


################################################################################
# Tell Perl the module loaded fine
1;
