#!/usr/bin/perl -w

# Heikki's simple beer tracker
#

use CGI;

my $q = CGI->new;

# Constants
my $datafile = "./beerdata/beer.data";


# Arguments
my $loc = $q->param("l") || "";  # location
my $mak = $q->param("m") || "";  # brewery (maker)
my $beer= $q->param("b") || "";  # beer
my $vol = $q->param("v") || "";  # volume, in cl
my $sty = $q->param("s") || "";  # style
my $alc = $q->param("a") || "";  # alc, in %vol, up to 1 decimal
my $pr  = $q->param("p") || "";  # price, in local currency
my $rate= $q->param("r") || "";  # rating, 0=?, 1=yuck, 10=best


print $q->header("Content-type: text/html");
print "Hello \n";

