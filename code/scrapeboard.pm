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
#$scrapers{"Ølsnedkeren"} = "oelsnedkeren.pl";
# Ølsnedkerens web site is broken, does not show a beer list at all
# See #368

# Links to beer lists at the most common locations and breweries
our %links; # TODO - Kill this, get them from the database
$links{"Ølbaren"} = "http://oelbaren.dk/oel/";
$links{"Ølsnedkeren"} = "https://www.olsnedkeren.dk/";
$links{"Fermentoren"} = "http://fermentoren.com/index";
$links{"Dry and Bitter"} = "https://www.dryandbitter.com/collections/beer/";
#$links{"Dudes"} = "http://www.dudes.bar"; # R.I.P Dec 2018
$links{"Taphouse"} = "http://www.taphouse.dk/";
$links{"Slowburn"} = "https://slowburn.coop/";
$links{"Brewpub"} = "https://brewpub.dk/vores-l";
$links{"Penyllan"} = "https://penyllan.com/";

################################################################################
# Update board: scrape and ensure brews/producers exist in DB
################################################################################

sub updateboard {
  my $c = shift;

  my ($locparam, undef) = beerboard::get_location_param($c);
  
  if (!$scrapers{$locparam}) {
    print STDERR "updateboard: No scraper for '$locparam'\n";
    util::error("No scraper for '$locparam'");
  }

  my $script = $c->{scriptdir} . $scrapers{$locparam};
  my $json = `timeout 5s perl $script`;
  if ($!) {
    print STDERR "updateboard: Timeout running $script: $!\n";
    util::error("Timeout running scraper for $locparam");
  }
  chomp($json);
  if (!$json) {
    print STDERR "updateboard: No output from scraper for $locparam\n";
    util::error("No data from scraper for $locparam");
  }

  my $beerlist = JSON->new->utf8->decode($json)
    or util::error("JSON decode failed for $locparam");

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
    my $sql_check = "SELECT Id FROM BREWS WHERE Name = ? AND ProducerLocation = ?";
    my $sth_check = $c->{dbh}->prepare($sql_check);
    $sth_check->execute($beer, $prod_id);
    my ($brew_id) = $sth_check->fetchrow_array;
    if ($brew_id) {
      $existing_brews++;
    } else {
      # Insert new brew
      my $sql = "INSERT INTO BREWS (Name, BrewType, SubType, Alc, ProducerLocation) VALUES (?, 'Beer', ?, ?, ?)";
      my $sth = $c->{dbh}->prepare($sql);
      $sth->execute($beer, $style, $alc, $prod_id);
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

  # Set redirect
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

# Helper to make a link to a bar of brewery web page and/or scraped beer menu
sub loclink {
  my $c = shift;
  my $loc = shift;
  my $www = shift || "www";
  my $scrape = shift || "List";
  my $lnk = "";
  if (defined($scrapers{$loc}) && $scrape ne " ") {
    $lnk .= " &nbsp; <i><a href='$c->{url}?o=Board&loc=$loc'><span>$scrape</span></a></i>" ;
  }
  if (defined($links{$loc}) && $www ne " ") {
    $lnk .= " &nbsp; <i><a href='" . $links{$loc} . "' target='_blank' ><span>$www</span></a></i>" ;
  }
  return $lnk
}

# Helper functions for beerboard refactoring - but wait, these are for beerboard, but since loclink is here

# Actually, loclink is used in beerboard, so perhaps keep it in scrapeboard since links are here.

# But to minimize changes, perhaps move loclink too.

# For now, include loclink in scrapeboard.

# Also, get_location_param is used in updateboard, so move it.

################################################################################
# Tell Perl the module loaded fine
1;