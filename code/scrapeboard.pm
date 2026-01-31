# Part of my beertracker
# Routines for scraping beer lists and updating brews and producers 


package scrapeboard;
use strict;
use warnings;
use feature 'unicode_strings';
use utf8;  # Source code and string literals are utf-8
use JSON;

# Beerlist scraping scripts
our %scrapers;
$scrapers{"Ølbaren"} = "oelbaren.pl";
$scrapers{"Taphouse"} = "taphouse.pl";
$scrapers{"Fermentoren"} = "fermentoren.pl";
$scrapers{"Brus"} = "brus.pl";
#$scrapers{"Ølsnedkeren"} = "oelsnedkeren.pl";
# Ølsnedkerens web site is broken, does not show a beer list at all
# See #368

################################################################################
# Update board: scrape and ensure brews/producers exist in DB
################################################################################

sub updateboard {
  my $c = shift;

  my ($locparam, undef) = beerboard::get_location_param($c);
  
  if (!$scrapers{$locparam}) {
    print STDERR "updateboard: No scraper for '$locparam'\n";
    return;  # No error page
  }

  my $script = $c->{scriptdir} . $scrapers{$locparam};
  my $json = `timeout 5s perl $script`;
  if ($!) {
    print STDERR "updateboard: Timeout running $script: $!\n";
    return;
  }
  chomp($json);
  if (!$json) {
    print STDERR "updateboard: No output from scraper for $locparam\n";
    return;
  }

  my $beerlist = eval { JSON->new->utf8->decode($json) };
  if ($@) {
    print STDERR "updateboard: JSON decode failed for $locparam: $@\n";
    return;
  }

  print STDERR "updateboard: Scraped " . scalar(@$beerlist) . " beers for $locparam\n";

  my $existing_brews = 0;
  my $inserted_brews = 0;

  foreach my $e (@$beerlist) {
    my $maker = $e->{maker} || "";
    my $beer = $e->{beer} || "";
    my $style = $e->{type} || "";
    my $alc = $e->{alc} || "";

    next unless $maker && $beer;  # Skip incomplete entries

    # Ensure producer exists
    my $prod_rec = db::findrecord($c, "LOCATIONS", "Name", $maker, "collate nocase");
    my $prod_id;
    if ($prod_rec) {
      $prod_id = $prod_rec->{Id};
    } else {
      # Insert new producer
      my $sql = "INSERT INTO LOCATIONS (Name, LocType, LocSubType) VALUES (?, 'Producer', 'Beer')";
      my $sth = $c->{dbh}->prepare($sql);
      $sth->execute($maker);
      $prod_id = $c->{dbh}->last_insert_id(undef, undef, "LOCATIONS", undef);
      print STDERR "updateboard: Inserted producer '$maker' (id $prod_id)\n";
    }

    # Ensure brew exists
    my $sql_check = "SELECT Id, DefPrice, DefVol FROM BREWS WHERE Name = ? AND ProducerLocation = ?";
    my $sth_check = $c->{dbh}->prepare($sql_check);
    $sth_check->execute($beer, $prod_id);
    my ($brew_id, $current_defprice, $current_defvol) = $sth_check->fetchrow_array;

    # Compute defprice and defvol from scraped data
    my $defprice;
    my $defvol;
    if ($e->{sizePrice} && ref($e->{sizePrice}) eq 'ARRAY') {
      my @sizes = sort { $a->{vol} <=> $b->{vol} } @{$e->{sizePrice}};
      my $count = scalar @sizes;
      if ($count >= 1) {
        my $def_index = ($count == 1) ? 0 : 1;
        $defvol = $sizes[$def_index]->{vol};
        $defprice = $sizes[$def_index]->{price};
      }
    }

    if ($brew_id) {
      $existing_brews++;
      # Update DefPrice/DefVol if different
      if ( ($current_defprice // '') ne ($defprice // '') ||
           ($current_defvol // '') ne ($defvol // '') ) {
        my $sql_update = "UPDATE BREWS SET DefPrice = ?, DefVol = ? WHERE Id = ?";
        my $sth_update = $c->{dbh}->prepare($sql_update);
        $sth_update->execute($defprice, $defvol, $brew_id);
        print STDERR "updateboard: Updated brew '$brew_id' DefPrice to '$defprice', DefVol to '$defvol'\n";
      }
    } else {
      # Insert new brew
      my $short_style = styles::shortbeerstyle($style);
      # Extract year from beer name if present (pattern: 20[23][0-9])
      my $year = undef;
      if ($beer =~ /(20[23][0-9])/) {
        $year = $1;
      }
      my $sql = "INSERT INTO BREWS ".
        "(Name, BrewType, SubType, BrewStyle, Alc, ProducerLocation, DefPrice, DefVol, Year) " .
        "VALUES (?, 'Beer', ?, ?, ?, ?, ?, ?, ?)";
      my $sth = $c->{dbh}->prepare($sql);
      $sth->execute($beer, $short_style, $style, $alc, $prod_id, $defprice, $defvol, $year);
      $brew_id = $c->{dbh}->last_insert_id(undef, undef, "BREWS", undef);
      $inserted_brews++;
      print STDERR "updateboard: Inserted brew '$beer' by '$maker' (id $brew_id)\n";
    }
  }

  print STDERR "updateboard: $existing_brews brews already existed, $inserted_brews inserted\n";

  # Get location ID
  my $loc_rec = db::findrecord($c, "LOCATIONS", "Name", $locparam);
  my $loc_id = $loc_rec->{Id};

  # Add brew_id to each beer and save updated JSON
  my $cachefile = $c->{datadir} . $scrapers{$locparam};
  $cachefile =~ s/\.pl/.cache/;
  foreach my $e (@$beerlist) {
    my $maker = $e->{maker} || "";
    my $beer = $e->{beer} || "";
    if ($maker && $beer) {
      my $prod_rec = db::findrecord($c, "LOCATIONS", "Name", $maker, "collate nocase");
      if ($prod_rec) {
        my $sql = "SELECT Id FROM BREWS WHERE Name = ? AND ProducerLocation = ?";
        my $sth = $c->{dbh}->prepare($sql);
        $sth->execute($beer, $prod_rec->{Id});
        my ($brew_id) = $sth->fetchrow_array;
        $e->{brew_id} = $brew_id;
      }
    }
  }

  # Update taps
  taps::update_taps($c, $loc_id, $beerlist);

  # Redirect back to showing the board, for this location
  $c->{redirect_url} = "$c->{url}?o=Board&loc=$locparam";
}

# Helper to create a POST form for triggering an operation
sub post_form {
  my ($c, $op, $loc, $label) = @_;
  my $form_id = "form_" . $op . "_" . ($loc || 'none');
  $form_id =~ s/\W/_/g;  # sanitize
  my $form = "<form id='$form_id' method='POST' action='$c->{url}' style='display:inline;'>";
  $form .= "<input type='hidden' name='o' value='$op'>";
  $form .= "<input type='hidden' name='loc' value='$loc'>" if $loc;
  $form .= "</form>";
  $form .= "<a href='#' onclick='document.getElementById(\"$form_id\").submit(); return false;'><i>$label</i></a>\n";
  return $form;
}


################################################################################
# Tell Perl the module loaded fine
1;