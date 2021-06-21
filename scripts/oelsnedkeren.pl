#!/usr/bin/perl
use XML::LibXML;
use URI::URL;
use JSON qw(to_json);
use LWP::UserAgent;

my $base_url = "https://www.olsnedkeren.dk";

my $filename = 'oelbaren.html';

my $ua = LWP::UserAgent->new;
#$ua->ssl_opts(verify_hostname => 0);
$res = $ua->get($base_url);

die "Failed to fetch $base_urla", $res->status_line unless $res->is_success;

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
	print($index . " " . $tdNodes->toString . "\n");
	$index++;
    }
    # 0 <div class="beer-name">Slambert</div>
    # 1 <div class="beer-facts"><div class="beer-style">IPA - Imperial / Double New England</div></div>
    # 2 <div class="beer-facts"><div class="beer-abv">7.5% ABV</div><div class="beer-ibu">0.0 IBU</div></div>
    # 3 <div class="beer-facts"><div class="brewery-name"> ?lsnedkeren</div><div class="brewery-area"> Copenhagen, Region Hovedstaden</div></div>
    # 4 <div class="beer-facts"><div class="beer-description"> Double IPA with Citra and Mosaic. </div></div>
    my ($number) = $count; # $beer[0] =~ m/\<td.*?\>(.*?)\<\/td\>/g;

    my ($model) = $beer[0] =~ m/beer-name">(.*?)</g;
    my ($maker) = $beer[3] =~ m/brewery-name">(.*?)</g;
    my ($type)  = $beer[1] =~ m/beer-style">(.*?)</g;
    my ($abv)   = $beer[2] =~ m/beer-abv">(.*?)%/g;
    my ($desc)  = $beer[4] =~ m/beer-description">[ ]*(.*?)[ ]*</g;
    print "RESULT:", $model, $maker, $type, $abc;

    # <td>30cl <big>65</big><br/>20cl <big>45</big></td>
    # <td>30cl <big>55</big></td>
    # and one bad?
    # <td> <br>30cl <big>60</big></td>
    my ($size, $price,$size2, $price2) = (20, 30, 50, 50);
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
	    subtype => $subtype,
	    desc   => $desc,
	    sizePrice => [ @sizePrices ]

    };
    # why doesn't this work?
    $tapItem{'subtype'} = $subtype;

    if ($model) {
	push @taps, $tapItem;
    };
    # [ { size => $size, price => $price}, { size => $size2, price => $price2}]
    $count++;
}

print(to_json(\@taps, {pretty => 1}));
