#!/usr/bin/perl -w
use XML::LibXML;
use URI::URL;
use JSON qw(to_json);
use LWP::UserAgent;
use utf8;

my $base_url = "https://taphouse.dk";
my $xpath        = '//*[@id="beerTable"]/tbody/tr';
my $xpath_number = './/td[position()=1]/text()';
my $regex_number = '([0-9]*)';
my $xpath_model  = './/td[position()=3]/text()';
my $regex_model  = '.*?\. (.*)$';
my $xpath_type   = './/td[position()=4]/text()';
my $regex_type   = '.*';
my $xpath_maker  = './/td[position()=2]/text()';
my $regex_maker  = '.*';
my $xpath_abv    = './/td[position()=2]/text()';
my $regex_abv    = '([0-9\.,]*)%';


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
	print("NUMBER: " . $node->toString . "\n");
	($number) = $node->toString =~ m/$regex_number/g;
	$number = $count if not $number;
	$index++;
    }

    foreach my $node ($design->findnodes($xpath_model)) {
	print("MODEL: " . $node->toString . "\n");
	($model) = $node->toString =~ m/$regex_model/g;
	$index++;
    }
    foreach my $node ($design->findnodes($xpath_maker)) {
	print("MAKER: " . $node->toString . "\n");
	($maker) = $node->toString =~ m/$regex_maker/g;
	$index++;
    }
    foreach my $node ($design->findnodes($xpath_type)) {
	print("ABV: " . $node->toString . "\n");
	($type) = $node->toString =~ m/$regex_type/g;
	$index++;
    }
#     print("RESULT: $number,$model, $maker, $type, $abv \n");
    
    $node = ($design->findnodes($xpath_abv))[0];
    ($abv) = $node->toString =~ m/$regex_abv/g;
	    
    my ($size, $price,$size2, $price2) = (20, 30, 40, 50);
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
#	    desc   => $desc,
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
