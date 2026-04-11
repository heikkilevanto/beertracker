#!/usr/bin/perl -w
# Generic scraper for Untappd venue pages.
# Outputs the tap beer section as JSON to STDOUT.
# Usage: perl untappd.pl <venue-id>
# Example: perl untappd.pl olsnedkeren/415314

use XML::LibXML;
use JSON;
use LWP::UserAgent;
use utf8;

my $debug = 0;

my $venue_id = $ARGV[0] or die "Usage: $0 <venue-id>\nExample: $0 olsnedkeren/415314\n";
my $base_url = "https://untappd.com/v/$venue_id";

binmode STDOUT, ":encoding(UTF-8)";
my $ua = LWP::UserAgent->new( timeout => 10 );
$ua->agent('Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36');
my $res = $ua->get($base_url);
die "Failed to fetch $base_url: " . $res->status_line . "\n" unless $res->is_success;

my $dom = XML::LibXML->load_html(
    string          => $res->content,
    recover         => 1,
    suppress_errors => 1,
);

# Find the menu section whose heading contains "tap" (case-insensitive)
my $tap_section;
foreach my $section ($dom->findnodes('//div[@class="menu-section"]')) {
    my ($heading) = $section->findnodes('.//div[@class="menu-section-header"]/h4');
    next unless $heading;
    my $heading_text = $heading->textContent;
    print STDERR "Section: '$heading_text'\n" if $debug;
    if ($heading_text =~ /tap/i) {
        $tap_section = $section;
        last;
    }
}

die "Could not find tap section on $base_url\n" unless $tap_section;

my @taps;
foreach my $item ($tap_section->findnodes('.//li[@class="menu-item"]')) {
    print STDERR "=== item ===\n" . $item->toString() . "\n" if $debug;

    # Beer name, tap number, and Untappd URL — all from h5 > a
    my ($link) = $item->findnodes('.//h5/a');
    next unless $link;
    my $href = $link->getAttribute('href') || '';
    my $untappdurl = ($href =~ m{^https?://}) ? $href : "https://untappd.com$href";
    my $link_text = $link->textContent;
    $link_text =~ s/^\s+|\s+$//g;  # trim
    $link_text =~ s/\s+/ /g;       # collapse internal whitespace
    my ($tap_num, $beer) = $link_text =~ /^(\d+)\.\s*(.+)$/;
    next unless defined $beer;
    $beer =~ s/\s+$//;
    print STDERR "Tap $tap_num: '$beer'  url=$untappdurl\n" if $debug;

    # Style from h5 > em
    my ($em) = $item->findnodes('.//h5/em');
    my $style = $em ? $em->textContent : '';
    $style =~ s/^\s+|\s+$//g;
    print STDERR "Style: '$style'\n" if $debug;

    # ABV and maker from h6 > span (text "4.8% ABV • N/A IBU • Maker •")
    my ($span) = $item->findnodes('.//h6/span');
    my $abv   = 0;
    my $maker = '';
    if ($span) {
        ($abv) = $span->textContent =~ /(\d+\.?\d*)\s*%\s*ABV/;
        $abv //= 0;
        my ($maker_link) = $span->findnodes('.//a');
        if ($maker_link) {
            $maker = $maker_link->textContent;
            $maker =~ s/^\s+|\s+$//g;
        }
    }
    print STDERR "ABV: $abv  Maker: '$maker'\n" if $debug;

    push @taps, {
        id         => 0 + $tap_num,
        maker      => $maker,
        beer       => $beer,
        type       => $style,
        alc        => 1.0 * $abv,
        untappdurl => $untappdurl,
        sizePrice  => [],
    };
} # foreach item

print JSON->new
    ->pretty(1)
    ->ascii(1)
    ->canonical(1)
    ->encode(\@taps);
