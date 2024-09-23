#!/usr/bin/perl -w
use XML::LibXML;
use URI::URL;
use JSON qw(to_json);
use LWP::UserAgent;
use utf8;

### Script to scrape from Untapped.

my $debug = 0;

my $base_url = "https://business.untappd.com/locations/2098/themes/4868/js";
my $xpath        = '//div[@class="item"]';
my $xpath_number = './/span[@class="tap-number-hideable"]/text()';
my $xpath_model  = './/h4[@class="item-name"]/a';
#my $xpath_model  = './/p[@class="beer-name"]/a';
my $xpath_maker  = './/span[@class="brewery"]/a';

#my $xpath_type   = './/span[@class="item-style beer-style-hideable item-title-color"]';
my $xpath_type   = './/span[@class="item-style item-title-color"]';
my $regex_type   = '.*';
my $regex_maker  = '.*';
my $xpath_abv    = './/span[@class="item-abv"]';
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
my $count = 0;
my $foundcount = 0;
foreach my $design ($dom->findnodes($xpath)) {
  my @beer;
  print STDERR "========= $count: " . $design->toString() . "\n" if $debug;
  print STDERR "========= $count \n" if $debug;

  my ($number,$model,$maker,$type,$abv, $other);

  foreach my $node ($design->findnodes($xpath_model)) {
    print STDERR "Model: '$node' \n" if $debug;
    my $txt = $node->textContent;
    $txt =~ s/\n/ /gs;
    $txt =~ s/ +/ /g;
    print STDERR "Model txt: '$txt' \n" if $debug;
    ($number,$model) = $txt =~ m/([0-9]+)\W+(\w.*\w)/s;
    $model =~ s/ *$//;
    print STDERR "Got number '$number' and model '$model' \n" if $debug;
  }
  foreach my $node ($design->findnodes($xpath_type)) {
    ($type) = $node->textContent;
    print STDERR "Got type '$type' \n" if $debug;
  }

  foreach my $node ($design->findnodes($xpath_maker)) {
    print STDERR "Maker '$node' \n" if $debug;
    $maker = $node->textContent;
    $maker =~ s/\n/ /gs;
    $maker =~ s/ +/ /g;
    $maker =~ s/^ +//;
    $maker =~ s/ +$//;
    print STDERR "Got maker '$maker' \n" if $debug;
  }

  $node = ($design->findnodes($xpath_abv))[0];
  if ($node) {
    ($abv) = $node->textContent =~ m/$regex_abv/g;
    $abv = $abv * 1.0; # force it into a number
  } else {
    $abv = "";
  }
  print STDERR "Got alc '$abv' \n" if $debug;

  # The list has no prices, guess volumes to have something to show
  my ($size, $size2 ) = (20, 40);
  my @sizePrices = ();

  if ($size) {
    push @sizePrices, { vol => $size };
  }
  if ($size2) {
    push @sizePrices, { vol => $size2};
  }
  my $tapItem = {
    id => 0 + $number,
    maker  => $maker,
    beer  => $model,
    type   => $type,
    alc    => $abv,
#    desc   => $desc,
    sizePrice => [ @sizePrices ]
  };


  if ($model) {
    push @taps, $tapItem;
    print STDERR "=== $count: " . to_json($tapItem, {pretty=>1}). "\n" if $debug;
    $foundcount++;
  };
  $count++;
}
print STDERR "Found $foundcount beers for Fermentoren\n";
my $js = JSON->new->utf8(1)->pretty(1)->encode(\@taps);
print $js;
