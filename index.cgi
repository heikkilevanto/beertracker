#!/usr/bin/perl -w

# Heikki's simple beer tracker
#

use CGI;

my $q = CGI->new;

# Constants
my $datafile = "./beerdata/beer.data";


# Parameters
my $loc = $q->param("l") || "";  # location
my $mak = $q->param("m") || "";  # brewery (maker)
my $beer= $q->param("b") || "";  # beer
my $vol = $q->param("v") || "";  # volume, in cl
my $sty = $q->param("s") || "";  # style
my $alc = $q->param("a") || "";  # alc, in %vol, up to 1 decimal
my $pr  = $q->param("p") || "";  # price, in local currency
my $rate= $q->param("r") || "";  # rating, 0=?, 1=yuck, 10=best



print $q->header("Content-type: text/html;charset=UTF-8");

print "<html><head>\n";
print "<title>Beer</title>\n";
print "<meta http-equiv='Content-Type' content='text/html;charset=UTF-8'>\n";
print "<meta name='viewport' content='width=device-width, initial-scale=1.0'>\n";

print "</head><body>\n";

print "Hello there \n";
print "</body></html>\n";

