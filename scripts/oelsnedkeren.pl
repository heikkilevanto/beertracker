#!/usr/bin/perl -w
use XML::LibXML;
use URI::URL;
use JSON;
use LWP::UserAgent;
use utf8;

my $base_url = "https://www.olsnedkeren.dk";

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
my $xpath = '//*[@class="beer-entry"]';
my $count = 1;
foreach my $design ($dom->findnodes($xpath)) {

  my @beer;
  my $index = 0;
  foreach my $tdNodes ($design->findnodes('./div/div')) {
    push @beer, $tdNodes->toString;
    $index++;
  }
  # 0 <div class="beer-name">Slambert</div>
  # 1 <div class="beer-facts"><div class="beer-style">IPA - Imperial / Double New England</div></div>
  # 2 <div class="beer-facts"><div class="beer-abv">7.5% ABV</div><div class="beer-ibu">0.0 IBU</div></div>
  # 3 <div class="beer-facts"><div class="brewery-name">
  #    Ølsnedkeren</div><div class="brewery-area"> Copenhagen, Region Hovedstaden</div></div>
  # 4 <div class="beer-facts"><div class="beer-description"> Double IPA with Citra and Mosaic. </div></div>
  my ($number) = $count; # $beer[0] =~ m/\<td.*?\>(.*?)\<\/td\>/g;

  my ($model) = $beer[0] =~ m/beer-name">(.*?)</g;
  my ($maker) = $beer[3] =~ m/brewery-name">(.*?)</g;
  $maker =~ s/\s*Ølsnedkeren\s*//; # They only serve their own beer, no need to repeat
  my ($type)  = $beer[1] =~ m/beer-style">(.*?)</g;
  my ($abv)   = $beer[2] =~ m/beer-abv">(.*?)%/g;
  my ($desc)  = $beer[4] =~ m/beer-description">[ ]*(.*?)[ ]*</g;
  #    print "RESULT:", $model, $maker, $type, $abv;

  # The prices are not listed with the beers, but separately:
  # <td>30cl <big>65</big><br/>20cl <big>45</big></td>
  # <td>30cl <big>55</big></td>
  # and one bad?
  # <td> <br>30cl <big>60</big></td>
  my @sizePrices = ();
  push @sizePrices, { vol => 30, price => 40};
  push @sizePrices, { vol => 50, price => 55};
  my $tapItem = {
    id     => $number,
    maker  => $maker,
    beer  => $model,
    type   => $type,
    alc    => $abv,
    desc   => $desc,
    sizePrice => [ @sizePrices ]
    };

  if ($model) {
    push @taps, $tapItem;
  };
  $count++;
}

print JSON->new
  ->pretty(1)   # Pretty-print the json
  ->ascii(1)    # Encode anything non-ascii
  ->canonical(1) # Always order tags, produces same json
  ->encode(\@taps);
