#!/usr/bin/perl -w
use XML::LibXML;
use URI::URL;
use JSON;
use LWP::UserAgent;
use utf8;

my $base_url = "https://oelbaren.dk/oel/";

binmode STDOUT, ":encoding(UTF-8)";
my $ua = LWP::UserAgent->new;
$res = $ua->get($base_url);
die "Failed to fetch $base_url", $res->status_line unless $res->is_success;

my $dom = XML::LibXML->load_html(
    string        => $res->content,
    recover         => 1,
    suppress_errors => 1,
);

my @taps;
my $xpath = '//*[@id="beerTable"]/tbody/tr';
foreach my $design ($dom->findnodes($xpath)) {
    my @beer;
    my $index = 0;
    foreach my $tdNodes ($design->findnodes('./td')) {
      push @beer, $tdNodes->toString;
      # print($index . " " . $tdNodes->toString . "\n");
      $index++;
    }
    my ($number) = $beer[0] =~ m/\>(.*?)\</g;

    my ($maker, $model) = $beer[1] =~ m/\<td\>\<big\>(.*?) *\<b\>(.*?)\<\/b\>.*?\<br\/\>/g;
    # Skip empty taps
    if ($model) {
      # <br/>DK - NEIPA - 7.5% </td>
      # <br/>DK - NEIPA - 7.5% - <a href...
      # <br/>DK - NEIPA - SUBTYPE - 7.5% [- <a... >]</td>

      my ($country, $type, $abv) = $beer[1] =~ m/\<br\/\>(.*?) - (.*?) - ([0-9.]+)% [-<]/g;

      # <td>30cl <big>65</big><br/>20cl <big>45</big></td>
      # <td>30cl <big>55</big></td>
      # <td><br/>20cl <big>45</big></td>
      my ($size, $price) = $beer[2]   =~ m/>([0-9]*?)cl.*?\<big\>([0-9\.,]*)\<\/big\>/g;
      my ($size2, $price2) = $beer[2] =~ m/\<br\/\>(.*?)cl.*?\<big\>(.*?)\<\/big\>/g;
      if ($size2 && $size == $size2) {
          undef $size2;
          undef $price2;
      }
      #    my($url) = $design->findnodes('./a/@href')->to_literal_list;
      my @sizePrices = ();

      if ($size) {
        push @sizePrices, { vol => 1.0 * $size, price => 1.0 * $price };
      }
      if ($size2) {
        push @sizePrices, { vol => 1.0 * $size2, price => 1.0 * $price2 };
      }
      # Reference to hash
      my $tapItem = {
        id => 0 + $number,
        country => $country,
        maker  => $maker,
        beer  => $model,
        type   => $type,
        alc    => 1.0 * $abv,
        sizePrice => [ @sizePrices ]
      };

      if ($model) {
        push @taps, $tapItem;
      }
    }
} # foreach

print JSON->new
  ->pretty(1)   # Pretty-print the json
  ->ascii(1)    # Encode anything non-ascii
  ->canonical(1) # Always order tags, produces same json
  ->encode(\@taps);
