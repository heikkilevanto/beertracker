#!/usr/bin/perl -w
# Scraper for Tapperiet Brus beer list
use XML::LibXML;
use URI::URL;
use JSON;
use LWP::UserAgent;
use utf8;

my $base_url = "https://tapperietbrus.dk/bar/";

binmode STDOUT, ":encoding(UTF-8)";
my $ua = LWP::UserAgent->new ( timeout => 10 );   # sec
$ua->agent('Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/91.0.4472.124 Safari/537.36');
$res = $ua->get($base_url);
die "Failed to fetch $base_url", $res->status_line unless $res->is_success;

my $dom = XML::LibXML->load_html(
    string        => $res->content,
    recover         => 1,
    suppress_errors => 1,
);

my @taps;
my $xpath_dt = '//div[@id="taps"]//dt';
my $xpath_dd = '//div[@id="taps"]//dd';
my @dts = $dom->findnodes($xpath_dt);
my @dds = $dom->findnodes($xpath_dd);
for (my $i = 0; $i < @dts; $i++) {
    my $dt = $dts[$i];
    my $dd = $dds[$i];
    my $tap_number = $dt->textContent;
    $tap_number =~ s/\s+//g;  # Remove whitespace

    my $tap_name = '';
    my $tap_brewery = '';
    my @tap_pricings;

    foreach my $span ($dd->findnodes('./span')) {
        my $class = $span->getAttribute('class') || '';
        if ($class eq 'tap-name') {
            $tap_name = $span->textContent;
        } elsif ($class eq 'tap-brewery') {
            $tap_brewery = $span->textContent;
        } elsif ($class =~ /tap-pricing/) {
            push @tap_pricings, $span->textContent;
        }
    }

    # Parse tap_name: "Beer Name - Type - Subtype ABV%"
    my ($beer, $type, $abv) = $tap_name =~ /^(.+?) - (.+?) (\d+\.\d+)%$/;
    if (!$beer) {
        # Fallback if no subtype
        ($beer, $type, $abv) = $tap_name =~ /^(.+?) - (.+?) (\d+\.\d+)%$/;
    }
    $abv = $abv || 0;

    # Parse tap_brewery: "Brewed by Maker in Country"
    my ($maker, $country) = $tap_brewery =~ /Brewed by (.+?) in (.+)$/;
    $maker = $maker || 'Unknown';
    $country = $country || 'Unknown';

    # Parse pricings
    my @sizePrices;
    foreach my $pricing (@tap_pricings) {
        # Handle "20cl: 40 kr. / 40cl: 65 kr."
        while ($pricing =~ /(\d+)cl:\s*(\d+)\s*kr\./g) {
            my $vol = $1;
            my $price = $2;
            push @sizePrices, { vol => 1.0 * $vol, price => 1.0 * $price };
        }
        # Handle pitchers "1.5L Pitcher: 250 kr."
        if ($pricing =~ /(\d+\.\d+)L Pitcher:\s*(\d+)\s*kr\./) {
            my $vol = $1 * 1000;  # Convert to cl
            my $price = $2;
            push @sizePrices, { vol => 1.0 * $vol, price => 1.0 * $price };
        }
    }

    my $tapItem = {
        id => 0 + $tap_number,
        country => $country,
        maker => $maker,
        beer => $beer,
        type => $type,
        alc => 1.0 * $abv,
        sizePrice => [ @sizePrices ]
    };

    if ($beer) {
        push @taps, $tapItem;
    }
}

print JSON->new
  ->pretty(1)   # Pretty-print the json
  ->ascii(1)    # Encode anything non-ascii
  ->canonical(1) # Always order tags, produces same json
  ->encode(\@taps);