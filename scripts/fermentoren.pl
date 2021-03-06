#!/usr/bin/perl -w
use XML::LibXML;
use URI::URL;
use JSON qw(to_json);
use LWP::UserAgent;
use utf8;

### Script to scrape from Untapped.
# Unfortunately, it would require clicking on the "show more beers" button
# and wait for the ajax code to load the rest of the list.
# Also, prices seem not to be available.

#<div class="beer-details">
# <h5>
# <a class="track-click" data-track="menu" data-href=":beer"
# href="/b/fermentoren-yippie-ipa/1161868"
# >1. Yippie IPA</a> <em>IPA - American</em></h5>
# <h6>
# <span>6.3% ABV • 75 IBU •
# <a class="track-click" data-track="menu" data-href=":brewery"
# href="/w/fermentoren/78485">Fermentoren</a>
# </span>

my $base_url = "https://untappd.com/v/fermentoren/127076";
my $xpath        = '//div[@class="beer-details"]';
my $xpath_number = './/a[@data-href=":beer"]/text()';
my $regex_number = '^([0-9]*?)\.';
my $xpath_model  = './/a[@data-href=":beer"]/text()';
my $regex_model  = '.*?\. (.*)$';
my $xpath_type   = './/em/text()';
my $regex_type   = '.*';
my $xpath_maker  = './/a[@data-href=":brewery"]/text()';
my $regex_maker  = '.*';
my $xpath_abv    = './/span/text()';
my $regex_abv    = '^([0-9\.,]*)%';



binmode STDOUT, ":encoding(UTF-8)";
my $ua = LWP::UserAgent->new;
#$ua->ssl_opts(verify_hostname => 0);
$res = $ua->get($base_url);

die "Failed to fetch $base_url", $res->status_line unless $res->is_success;

my $dom = XML::LibXML->load_html(
  string        => $res->content,
  recover         => 1,
  suppress_errors => 1,
);

my @taps;
my $count = 1;
foreach my $design ($dom->findnodes($xpath)) {
  my @beer;
  my $index = 0;

  #    print $count, $design->toString;
  my ($number,$model,$maker,$type,$abv, $other);
  foreach my $node ($design->findnodes($xpath_number)) {
    ($number) = $node->toString =~ m/$regex_number/g;
    $number = $count if not $number;
    $index++;
  }

  foreach my $node ($design->findnodes($xpath_model)) {
    ($model) = $node->toString =~ m/$regex_model/g;
    $index++;
  }
  foreach my $node ($design->findnodes($xpath_maker)) {
    ($maker) = $node->toString =~ m/$regex_maker/g;
    $index++;
  }
  foreach my $node ($design->findnodes($xpath_type)) {
    ($type) = $node->toString =~ m/$regex_type/g;
    $index++;
  }

  $node = ($design->findnodes($xpath_abv))[0];
  ($abv) = $node->toString =~ m/$regex_abv/g;

  my ($size, $price,$size2, $price2) = (20, 30, 40, 50);  # ???
  my @sizePrices = ();

  if ($size) {
    push @sizePrices, { size => $size, price => $price};
  }
  if ($size2) {
    push @sizePrices, { size => $size2, price => $price2};
  }
  my $tapItem = {
    number => $number,
    maker  => $maker,
    model  => $model,
    type   => $type,
    abv    => $abv,
#    desc   => $desc,
    sizePrice => [ @sizePrices ]
  };

  # why doesn't this work?
  $tapItem->{'subtype'} = $subtype if $subtype;

  if ($model) {
    push @taps, $tapItem;
  };
  # [ { size => $size, price => $price}, { size => $size2, price => $price2}]
  $count++;
}

print(to_json(\@taps, {pretty => 1}));
