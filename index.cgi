#!/usr/bin/perl -w

# Heikki's simple beer tracker
#
# Keeps beer drinking history in a flat text file.
#
# TODO - get username from CGI, use as data file name 
#
# TODO - Display the history of the last 24 hrs at the top. With a link for
# each to populate the form.
#
# TODO - Select by location, brewery, style, etc. 
#
# TODO - When selecting, show only matching entries instead of night history.
#
# TODO - Sanitize input data
#
# TODO - Change filtering to use fieldname and value
#
# TODO - A way to show lists of locations, breweries, styles, etc.
#
# Later - Reporting
# Later - Wines and other drinks?


use CGI;
my $q = CGI->new;

# Constants
my $datafile = "./beerdata/beer.data";


# Parameters - data file fields are the same order
# but there is a time stamp first, and the $del never gets to the data file
# TODO - make a helper to get the param, and sanitize it
my $stamp = "";  # make a new timestamp by default
my $loc = $q->param("l") || "";  # location
my $mak = $q->param("m") || "";  # brewery (maker)
my $beer= $q->param("b") || "";  # beer
my $vol = $q->param("v") || "";  # volume, in cl
my $sty = $q->param("s") || "";  # style
my $alc = $q->param("a") || "";  # alc, in %vol, up to 1 decimal
my $pr  = $q->param("p") || "";  # price, in local currency
my $rate= $q->param("r") || "";  # rating, 0=worst, 10=best
my $com = $q->param("c") || "";  # Comments
my $del = $q->param("x") || "";  # delete/update last entry - not in data file

# POST data into the file
if ( $q->request_method eq "POST" ) {
  error("Can not see $datafile") if ( ! -w $datafile ) ;
  #TODO - Check if $del, and remove the last line of the file
  if ( ! $stamp ) {
    $stamp = `date "+%F %T"`;  # TODO - Do this in perl
  }
  chomp($stamp);
  my $line = "$loc; $mak; $beer; $vol; $sty; $alc; $pr; $rate; $com";
  if ( $line =~ /[a-zA-Z0-9]/ ) { # has at leas something on it
    open F, ">>$datafile" 
      or error ("Could not open $datafile for appending");
    print F "$stamp; $line \n"
      or error ("Could not write in $datafile");
    close(F) 
      or error("Could not close data file");
  }
  print $q->redirect( $q->url ); 
  exit();
}

# Read the file
# Set defaults for the form, usually from last line in the file
open F, "<$datafile" 
  or error("Could not open $datafile for reading: $!");
my $foundline = "";
my $lastline = "";
while (<F>) {
  chomp();
  s/#.*$//;  # remove comments
  next unless $_; # skip empty lines
  my ( $t, $l, $m, $b, $v, $s, $a, $p, $r, $c ) = split( /; */ );
  my $found = 0;
  if ( $beer ) {
    $found = 1 if ( $beer eq $b ) ;
  } else {  # no condition, take always. Last line wins
    $found = 1;
  }
  if ( $found ) { # copy everything over to the form
    $foundline = $_;
  }
  $lastline = $_;
}
my ( $laststamp, undef, undef, $lastbeer, undef ) = split( /; */, $lastline );
# Get new values. Not rating nor comment, they should be fresh every time
( $stamp, $loc, $mak, $beer, $vol, $sty, $alc, $pr, undef, undef ) = 
    split( /; */, $foundline );


print $q->header("Content-type: text/html;charset=UTF-8");

# HTML head
print "<html><head>\n";
print "<title>Beer</title>\n";
print "<meta http-equiv='Content-Type' content='text/html;charset=UTF-8'>\n";
print "<meta name='viewport' content='width=device-width, initial-scale=1.0'>\n";
print "</head><body>\n";

# Status line
#my ($date, $time) = split(' ', $laststamp);
my $time = $1 if ( $laststamp =~ / (\d\d:\d\d)/);
print "<b>$time $lastbeer</b><p/>\n";

# Main input form
print "<form method='POST'>\n";
print "<table >";
print "<tr><td>Location</td><td><input name='l' value='$loc' /></td></tr>\n";
print "<tr><td>Brewery</td><td><input name='m' value='$mak' /></td></tr>\n";
print "<tr><td>Beer</td><td><input name='b' value='$beer' /></td></tr>\n";
print "<tr><td>Volume</td><td><input name='v' value='$vol' /></td></tr>\n";
print "<tr><td>Style</td><td><input name='s' value='$sty' /></td></tr>\n";
print "<tr><td>Alc</td><td><input name='a' value='$alc' /></td></tr>\n";
print "<tr><td>Price</td><td><input name='p' value='$pr' /></td></tr>\n";
print "<tr><td>Rating</td><td><input name='r' value='$rate' /></td></tr>\n";
print "<tr><td>Comment</td><td><input name='c' value='$com' /></td></tr>\n";
print "<tr><td>&nbsp;</td><td><input type='submit' value='Record'/></td></tr>\n";
print "</table>\n";

# HTML footer
print "</body></html>\n";

exit();

############################################

sub error {
  my $msg = shift;
  print $q->header("Content-type: text/plain");
  print "ERROR\n";
  print $msg;
  exit();
}

