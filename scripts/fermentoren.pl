#!/usr/bin/perl -w
use XML::LibXML;
use URI::URL;
use JSON qw(to_json);
use LWP::UserAgent;
use utf8;

### Script to scrape from Untapped.

# TODO - Get the whole list from
#        https://business.untappd.com/locations/2098/themes/4868/js
# and parse the html out of the js

# The rest is OUTDATED!

# Unfortunately, it would require clicking on the "show more beers" button
# and wait for the ajax code to load the rest of the list.
# Also, prices seem not to be available.


my $base_url = "https://business.untappd.com/locations/2098/themes/4868/js";
my $xpath        = '//div[@class="item"]';
my $xpath_number = './/span[@class="tap-number-hideable"]/text()';
my $xpath_model  = './/p[@class="item-name"]/a';
#my $xpath_model  = './/p[@class="beer-name"]/a';
my $xpath_maker  = './/span[@class="brewery"]/a';

my $xpath_type   = './/p[@class="item-style beer-style-hideable item-title-color"]/span';
my $regex_type   = '.*';
my $regex_maker  = '.*';
my $xpath_abv    = './/span[@class="abv"]';
my $regex_abv    = '^([0-9\.,]*)%';



binmode STDOUT, ":encoding(UTF-8)";
my $ua = LWP::UserAgent->new;
#$ua->ssl_opts(verify_hostname => 0);
$res = $ua->get($base_url);

die "Failed to fetch $base_url", $res->status_line unless $res->is_success;

my $xml = $res->content;
#if ( $xml =~ /container.innerHTML = "(.*)\n";/mi ) {
if ( $xml =~ /container.innerHTML = "(.*)/mi ) {
  $xml = $1;
  $xml =~ s/\\n/\n/g;  # Replace \n newlines
  $xml =~ s/\\//g; # unquote
} else {
  die "Failed to extract html from " . substr($xml,0, 512). " \n";
}

my $dom = XML::LibXML->load_html(
  string        => $xml,
  recover         => 1,
  suppress_errors => 1,
);

#print STDERR $dom->toString() . "\n";
my @taps;
my $count = 1;
foreach my $design ($dom->findnodes($xpath)) {
  my @beer;
  # print STDERR "=========$count: " . $design->toString() . "\n";

  my ($number,$model,$maker,$type,$abv, $other);

  foreach my $node ($design->findnodes($xpath_model)) {
    ($number,$model) = $node->textContent =~ m/([0-9]+)[ \.]*(.*)/g;
    $model =~ s/ *$//;
  }
  foreach my $node ($design->findnodes($xpath_type)) {
    ($type) = $node->textContent =~ m/$regex_type/g;
  }

  foreach my $node ($design->findnodes($xpath_maker)) {
    $maker = $node->textContent;
  }

  $node = ($design->findnodes($xpath_abv))[0];
  ($abv) = $node->textContent =~ m/$regex_abv/g;

  # The list has no prices, so we make a decent guess.
  my ($size, $price,$size2, $price2) = (20, 30, 40, 50);
  my @sizePrices = ();

  if ($size) {
    push @sizePrices, { vol => $size, price => $price};
  }
  if ($size2) {
    push @sizePrices, { vol => $size2, price => $price2};
  }
  my $tapItem = {
    id => 0 + $number,
    maker  => $maker,
    beer  => $model,
    type   => $type,
    alc    => 1.0 * $abv,
#    desc   => $desc,
    sizePrice => [ @sizePrices ]
  };


  if ($model) {
    push @taps, $tapItem;
    #print STDERR "=== $count: " . to_json($tapItem, {pretty=>1}). "\n";
  };
  $count++;

}
print STDERR "Found $count beers for Fermentoren\n"; ###
print(to_json(\@taps, {pretty => 1}));
