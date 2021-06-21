
#!/usr/bin/perl
use XML::LibXML;
use URI::URL;
use JSON qw(to_json);
use LWP::UserAgent;

my $base_url = "https://oelbaren.dk/oel/";

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
my $xpath = '//*[@id="beerTable"]/tbody/tr';
foreach my $design ($dom->findnodes($xpath)) {

    my @beer;
    my $index = 0;
    foreach my $tdNodes ($design->findnodes('./td')) {
	push @beer, $tdNodes->toString;
#	print($index . " " . $tdNodes->toString . "\n");
	$index++;
    }
    my ($number) = $beer[0] =~ m/\<td.*?\>(.*?)\<\/td\>/g;
    
    my ($maker, $model, $type) = $beer[1] =~ m/\<td\>\<big\>(.*?) *\<b\>(.*?)\<\/b\>.*?\<br\/\>(.*?)\<\/td\>/g;
    # <br/>DK - NEIPA - 7.5%
    # <br/>DK - NEIPA - 7.5% - <a
    # <br/>DK - NEIPA - SUBTYPE - 7.5% [ - <a]
    
    
    my ($country, $type, $subtype) = $beer[1] =~ m/\<br\/\>(.*?) - (.*?) - (.*?) [-<]/g;
    my ($abv) = $beer[1] =~ m/([^ -]*?%)/g;
    # <br/>DK - NEIPA - 7.5% - <a
    if ($subtype == $abv) {
	undef $subtype;
    }	    
    
    # <td>30cl <big>65</big><br/>20cl <big>45</big></td>
    # <td>30cl <big>55</big></td>
    # and one bad?
    # <td> <br>30cl <big>60</big></td>
    my ($size, $price,$size2, $price2) = $beer[2]   =~ m/\>([0-9\.,]*?)cl  *?\<big\>([0-9\.,]*?)\<\/big\>/g;
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
	    sizePrice => [ @sizePrices ]
    };
    # why doesn't this work?
    $tapItem{'subtype'} = $subtype;
	
    if ($model) {
	push @taps, $tapItem;
    };
    # [ { size => $size, price => $price}, { size => $size2, price => $price2}]	    
}

print(to_json(\@taps, {pretty => 1}));
