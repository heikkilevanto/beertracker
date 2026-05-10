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
    if ($heading_text =~ /tap|menu/i) {
        $tap_section = $section;
        last;
    }
}

die "Could not find tap section on $base_url\n" unless $tap_section;

my @taps;
my %used_tap_numbers;
foreach my $item ($tap_section->findnodes('.//li[@class="menu-item"]')) {
    print STDERR "=== item ===\n" . $item->toString() . "\n" if $debug;

    # Beer name, tap number, and Untappd URL — all from h5 > a
    my $link = ($item->findnodes('.//h5/a'))[0];
    next unless $link;
    my $href = $link->getAttribute('href') || '';
    my $untappdurl = ($href =~ m{^https?://}) ? $href : "https://untappd.com$href";
    my $link_text = $link->textContent;
    $link_text =~ s/^\s+|\s+$//g;  # trim
    $link_text =~ s/\s+/ /g;       # collapse internal whitespace
    my ($raw_tap_num, $beer) = $link_text =~ /^(\d+)\.\s*(.+)$/;
    next unless defined $beer;
    $beer =~ s/\s+$//;

    my $tap_num;
    if (!defined $raw_tap_num) {
      # No tap number in the data - assign sequential decimals starting at 0
      my $seq = 0;
      $seq += 0.1 while $used_tap_numbers{sprintf("%.1f", $seq)};
      $tap_num = sprintf("%.1f", $seq);
      $used_tap_numbers{$tap_num} = 1;
      print STDERR "No tap number in data, assigned $tap_num\n" if $debug;
    } else {
      # Format as X.0 first, then check for duplicates
      my $formatted = sprintf("%.1f", $raw_tap_num);
      if ($used_tap_numbers{$formatted}) {
        # Duplicate - add suffix
        my $suffix = 0.1;
        my $suffixed = sprintf("%.1f", $raw_tap_num + $suffix);
        $suffixed = sprintf("%.1f", $raw_tap_num + $suffix) while $used_tap_numbers{$suffixed};
        $tap_num = $suffixed;
        $used_tap_numbers{$tap_num} = 1;
        print STDERR "Duplicate tap number, assigned $tap_num\n" if $debug;
      } else {
        # First occurrence
        $tap_num = $formatted;
        $used_tap_numbers{$tap_num} = 1;
      }
    }
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
