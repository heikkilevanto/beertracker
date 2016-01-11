#!/usr/bin/perl -w

# Heikki's simple beer tracker
#

use CGI;

my $q = CGI->new;

# Constants
my $datafile = "./beerdata/beer.data";


# Parameters - data file fields are the same order
# but there is a time stamp first, and the $del never gets to the data file
# TODO - make a helper to get the param, and sanitize it
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

# Variables
my $feedback = "";

if ( $q->request_method eq "POST" ) {
  error("Can not see $datafile") if ( ! -w $datafile ) ;
  #TODO - Check if $del, and remove the last line of the file
  my $stamp = `date "+%F %T"`;  # TODO - Do this in perl
  chomp($stamp);
  my $line = "$loc; $mak; $beer; $vol; $sty; $alc; $pr; $rate; $com";
  if ( $line =~ /[a-zA-Z0-9]/ ) { # has at leas something on it
    open F, ">>$datafile" 
      or error ("Could not open $datafile for appending");
    print F "$stamp ; $line \n"
      or error ("Could not write in $datafile");
    close(F) 
      or error("Could not close data file");
  }
  print $q->redirect( $q->url ); 
  exit();
}

# TODO - Read the file
# Set the variables from the last line (unless url-params specify things?!)

print $q->header("Content-type: text/html;charset=UTF-8");

# HTML head
print "<html><head>\n";
print "<title>Beer</title>\n";
print "<meta http-equiv='Content-Type' content='text/html;charset=UTF-8'>\n";
print "<meta name='viewport' content='width=device-width, initial-scale=1.0'>\n";
print "</head><body>\n";

# Feedback section
if ( $feedback ) {
  print "<b>$feedback</b><p/>\n";
}

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
print "<tr><td>&nbsp;</td><td><input type='submit'/></td></tr></table>\n";

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

