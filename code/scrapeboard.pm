# Part of my beertracker
# Routines for scraping beer lists and updating brews and producers 


package scrapeboard;
use strict;
use warnings;
use feature 'unicode_strings';
use utf8;  # Source code and string literals are utf-8
use JSON;
use URI::Escape qw(uri_escape_utf8);

# Beerlist scraping scripts
# Each entry is ["script.pl", "arg"] where arg is passed to the script.
our %scrapers;
$scrapers{"Ølbaren"}   = ["oelbaren.pl"];
$scrapers{"Taphouse"}  = ["taphouse.pl"];
$scrapers{"Brus"}      = ["brus.pl"];
$scrapers{"Ølsnedkeren"} = ["untappd.pl", "olsnedkeren/415314"];
$scrapers{"Bootleggers"}  = ["untappd.pl", "bootleggers-craft-beer-bar-frb/10845482"];
# Fermentoren is temporarily closed:
#$scrapers{"Fermentoren"}  = ["untappd.pl", "fermentoren-cph/127076"];
# Old per-venue untappd scrapers, superseded by untappd.pl:
#$scrapers{"Fermentoren"} = "fermentoren.pl";
#$scrapers{"Ølsnedkeren"} = "oelsnedkeren.pl";

################################################################################
# Update board: scrape and ensure brews/producers exist in DB
################################################################################

sub updateboard {
  my $c = shift;

  my $locparam = util::param($c,"loc");
  
  if (!$scrapers{$locparam}) {
    print { $c->{log} } "updateboard: No scraper for '$locparam'\n";
    return;  # No error page
  }

  my ($scriptfile, $arg) = @{ $scrapers{$locparam} };
  my $script = $c->{scriptdir} . $scriptfile;
  $arg //= '';
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

  # Get location ID
  my $loc_rec = db::findrecord($c, "LOCATIONS", "Name", $locparam);
  my $loc_id = $loc_rec->{Id};

  # Fetch current board upfront: tap_num -> { Id, Brew, BrewName, Producer }
  my %current_board;
  my $cur_sth = db::query($c, "SELECT Tap, Brew, Id, BrewName, Producer FROM current_taps WHERE Location = ?", $loc_id);
  while (my $row = $cur_sth->fetchrow_hashref) {
    $current_board{$row->{Tap}} = $row;
  }

  my $inserted_brews = 0;

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

  # Update taps
  taps::update_taps($c, $loc_id, $beerlist, \%current_board);

  # Redirect back to showing the board, for this location
  $c->{redirect_url} = "$c->{url}?o=Board&loc=" . uri_escape_utf8($locparam);
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