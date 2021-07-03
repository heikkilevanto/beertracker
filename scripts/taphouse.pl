#!/usr/bin/perl -w
use XML::LibXML;
use URI::URL;
use JSON;
use LWP::UserAgent;
use utf8;

# <tr>
# <td><div class="tapNumber mainBeverageType-dark-ale" title="Dark Ale">1</div></td>
# <td data-sort-value="Bad Seed"><span class="glyphicon star onBigList"></span> Bad Seed</td>
# <td data-sort-value="Rust Belt"><span class="glyphicon star onSmallList"></span> Rust Belt
#    <span class="onSmallList"><a href="https://untappd.com/b/a/4329438" class="untappdLink">U</a></span></td>
# <td>Brown Ale</td>
# <td>DK</td>
# <td>4.5%</td>
# <td data-sort-value="58">40cl <big>58</big></td>
# <td data-sort-value="40">25cl <big>40</big></td>
# <td class="iconstring"><a href="https://untappd.com/b/a/4329438" class="untappdLink">U</a></td>
# </tr>

my $base_url = "https://taphouse.dk";
my $xpath        = '//*[@id="beerTable"]/tbody/tr';


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
foreach my $design ($dom->findnodes($xpath)) { # For each beer
  my @beerdata = $design->findnodes('.//td');

  my $number = $beerdata[0]->textContent;
  my $maker = $beerdata[1]->textContent;
  $maker =~ s/^\s*(.*?)\s*$/$1/;  # Trim leading and trailing spaces (note non-greedy .*?)

  my $beer = $beerdata[2]->findnodes('./text()');  # The only node that is pure text
  $beer =~ s/^\s*(.*?)\s*$/$1/;  # Trim leading and trailing spaces
  my $type = $beerdata[3]->textContent;
  my $country = $beerdata[4]->textContent;
  my $alc = $beerdata[5]->textContent;
  $alc =~ s/[^0-9.]//g;
  my @sizePrices = ();
  if ( $beerdata[6]->textContent =~ /(\d+)cl *(\d+)/ ) {
    push @sizePrices, { vol => $1, price => $2};
  }
  if ( $beerdata[7]->textContent =~ /(\d+)cl *(\d+)/ ) {
    push @sizePrices, { vol => $1, price => $2};
  }

  my $tapItem = {
    id     => 0 + $number,
    maker  => $maker,
    beer   => $beer,
    type   => $type,
    alc    => 0.0 + $alc,
    country=> $country,
  #    desc   => $desc,
    sizePrice => [ @sizePrices ]
  };

  if ($beer) {
    push @taps, $tapItem;
  };
}

print JSON->new
  ->pretty(1)   # Pretty-print the json
  ->ascii(1)    # Encode anything non-ascii
  ->canonical(1) # Always order tags, produces same json
  ->encode(\@taps);
