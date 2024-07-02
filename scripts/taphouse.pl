#!/usr/bin/perl -w
use JSON;
use LWP::UserAgent;
use utf8;

# Version 2, using their API

my $base_url = "https://taphouse.dk/api/taplist/index.php";


binmode STDOUT, ":encoding(UTF-8)";
my $ua = LWP::UserAgent->new;
#$ua->ssl_opts(verify_hostname => 0);
$res = $ua->get($base_url);

die "Failed to fetch $base_url", $res->status_line unless $res->is_success;

my $j = JSON->new();
my $beers = $j->decode($res->content);

my @taps;
foreach my $k ( sort {$a <=> $b} keys(%$beers) ) { # For each beer
  my $b = $beers->{$k};
  #print "Beer $k: " . $j->pretty(1)->encode($b) . "\n";

  if ( $b->{beverage} ) {
    my @sizePrices = (
      { vol => $b->{volumeOutSmall}, price => $b->{priceOutSmall} },
      { vol => $b->{volumeOutLarge}, price => $b->{priceOutLarge} }
      );

    my $tapItem = {
      id     => 0 + $k,
      maker  => $b->{company},
      beer   => $b->{beverage},
      type   => $b->{beverageType},
      alc    => 0.0 + $b->{abv},
      country=> $b->{country},
      sizePrice => [ @sizePrices ]
    };
    #print "Result: " . $j->encode($tapItem);
    push @taps, $tapItem;
  }

}

print $j
  ->pretty(1)   # Pretty-print the json
  ->ascii(1)    # Encode anything non-ascii
  ->canonical(1) # Always order tags, produces same json
  ->encode(\@taps);
