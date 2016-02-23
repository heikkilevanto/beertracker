#!/usr/bin/perl -w

# Heikki's simple beer tracker
#
# Keeps beer drinking history in a flat text file.
#


use CGI;
use URI::Escape;

my $q = CGI->new;

# Constants
my $datadir = "./beerdata/";
my $datafile = "";
if ( $q->remote_user() =~ /^[a-zA-Z0-9]+$/ ) {
  $datafile = $datadir . $q->remote_user() . ".data";
} else {
  error ("Bad username");
}
my @ratings = ( "Undrinkable", "Bad", "Unpleasant", "Could be better",
"Ok", "Goes down well", "Nice", "Pretty good", "Excellent", "Perfect",
"I'm in love" );


# Parameters - data file fields are the same order
# but there is a time stamp first, and the $del never gets to the data file
# TODO - make a helper to get the param, and sanitize it
my $stamp = param("st");
my $wday = param("wd");  # weekday
my $effdate = param("ed");  # effective date
my $loc = param("l");  # location
my $mak = param("m");  # brewery (maker)
my $beer= param("b");  # beer
my $vol = param("v");  # volume, in cl
my $sty = param("s");  # style
my $alc = param("a");  # alc, in %vol, up to 1 decimal
my $pr  = param("p");  # price, in local currency
my $rate= param("r");  # rating, 0=worst, 10=best
my $com = param("c");  # Comments
my $del = param("x");  # delete/update last entry - not in data file
my $qry = param("q");  # filter query, greps the list
my $op  = param("o");  # operation, to list breweries, locations, etc
my $edit= param("e");  # Record to edit
my $maxlines = param("maxl") || "25";  # negative = unlimites
my $localtest = 0; # Local test installation
my $hostname = `hostname`;
chomp($hostname);
if ( $hostname ne "locatelli" ) {
  $localtest = 1;
}

$qry =~ s/[&.*+^\$]/./g;  # Remove special characters

# POST data into the file
if ( $q->request_method eq "POST" ) {
  error("Can not see $datafile") if ( ! -w $datafile ) ;
  #TODO - Check if $del, and remove the last line of the file
  my $sub = $q->param("submit") || "";
  if ( ! $stamp ) {
    $stamp = `date "+%F %T"`;  # TODO - Do this in perl
    chomp($stamp);
  }
  if ( ! $effdate ) { # Effective date can be the day before
    $effdate = `date "+%a; %F" -d '8 hours ago' `;  
    chomp($effdate);
  } else {
    $effdate = "$wday; $effdate";
  }
  my $line = "$loc; $mak; $beer; $vol; $sty; $alc; $pr; $rate; $com";
  if ( $sub eq "Record" || $sub eq "Copy" ) {
    if ( $line =~ /[a-zA-Z0-9]/ ) { # has at leas something on it
        open F, ">>$datafile" 
          or error ("Could not open $datafile for appending");
        print F "$stamp; $effdate; $line \n"
          or error ("Could not write in $datafile");
        close(F) 
          or error("Could not close data file");
    }
  } else { # Editing or deleting an existing line
    # TODO Rewrite the file line by line, except the one we wanted to edit or delete
    # Copy the data file to .bak
    my $bakfile = $datafile . ".bak";
    system("cat $datafile > $bakfile");
    open BF, $bakfile
      or error ("Could not open $bakfile for reading");
    open F, ">$datafile"
      or error ("Could not open $datafile for writing");
    while (<BF>) {
      my ( $stp, undef) = split( /; */ );
      if ( $stp ne $edit ) {
        print F $_;
      } else { # found the line
        print F "#" . $_ ;  # comment the original line out
        if ( $sub eq "Save" ) {
          print F "$stamp; $effdate; $line \n";
        }
      }
    }
    close F 
      or error("Error closing $datafile: $!");
    close BF
      or error("Error closing $bakfile: $!");

  }
  print $q->redirect( $q->url ); 
  exit();
}

# Read the file
# Set defaults for the form, usually from last line in the file
open F, "<$datafile" 
  or error("Could not open $datafile for reading: $!".
     "<br/>Probably the user hasn't been set up yet" );
my $foundline = "";
my $lastline = "";
my @lines;
while (<F>) {
  chomp();
  s/#.*$//;  # remove comments
  next unless $_; # skip empty lines
  push @lines, $_; # collect them all
  my ( $t, $wd, $ed, $l, $m, $b, $v, $s, $a, $p, $r, $c ) = split( /; */ );
  if ( ! $edit || ($edit eq $t) ) {
    $foundline = $_;
  }
  $lastline = $_;
}
my ( $laststamp, undef, undef, $lastloc, $lastbeer, undef ) = split( /; */, $lastline );
# Get new values
( $stamp, $wday, $effdate, $loc, $mak, $beer, $vol, $sty, $alc, $pr, $rate, $com ) = 
    split( /; */, $foundline );
if ( ! $edit ) { # not editing, do not default rates and comments from last beer
  $rate = "";
  $com = ""; 
}

print $q->header("Content-type: text/html;charset=UTF-8");

# HTML head
print "<html><head>\n";
print "<title>Beer</title>\n";
print "<meta http-equiv='Content-Type' content='text/html;charset=UTF-8'>\n";
print "<meta name='viewport' content='width=device-width, initial-scale=1.0'>\n";
if ( ! $localtest ) {
    print "<style rel='stylesheet'>\n";
    #print "* { margin: 1px; padding: 0px; }\n";
    print "* { background-color: #493D26; color: #FFFFFF }\n";
    print "</style>\n";
}
print "</head>\n";

#print "<body bgcolor='#493D26' text='#FFFFFF' link='#46C7C7' vlink='#46C7C7'>\n";
print "<body>\n";

# Status line
my $hostname = `hostname`;
chomp($hostname);
if ( $hostname ne "locatelli" ) {
  print "Local test installation<br/>\n";
}
# print "e='$edit' f='$foundline'<br/>"; # ###

#my ($date, $time) = split(' ', $laststamp);
if ( $laststamp =~ / (\d\d:\d\d)/) {
  my $time = $1;
  print "<b>$time $lastloc: $lastbeer</b><p/>\n";
} else {
  print "<b>Welcome to BeerTrack</b><p/>\n";
}

# Main input form
print "<form method='POST'>\n";
print "<table >";
my $c2 = "colspan='2'";
my $c3 = "colspan='3'";
my $c4 = "colspan='4'";
my $c6 = "colspan='6'";
my $sz = "size='30'";
my $sz2 = "size='2'";
if ( $edit ) {
    print "<tr><td $c6><b>Editing record $edit</b> ".
        "<input name='e' type='hidden' value='$edit' /></td></tr>\n";
    print "<tr><td $c2>Stamp</td><td $c4><input name='st' value='$stamp' $sz /></td></tr>\n";
    print "<tr><td $c2>Wday</td><td $c4><input name='wd' value='$wday'  $sz /></td></tr>\n";
    print "<tr><td $c2>Effdate</td><td $c4><input name='ed' value='$effdate'  $sz /></td></tr>\n";
}
print "<tr><td $c2>Location</td><td $c4><input name='l' value='$loc' $sz /></td></tr>\n";
print "<tr><td $c2>Brewery</td><td $c4><input name='m' value='$mak' $sz /></td></tr>\n";
print "<tr><td $c2>Beer</td><td $c4><input name='b' value='$beer' $sz /></td></tr>\n";
#print "<tr><td>Volume</td><td><input name='v' value='$vol' /></td></tr>\n";
#print "<tr><td>Alc</td><td><input name='a' value='$alc' /></td></tr>\n";
#print "<tr><td>Price</td><td><input name='p' value='$pr' /></td></tr>\n";
print "<tr><td>Vol</td><td><input name='v' value='$vol' $sz2 />\n";
print "<td>Alc</td><td><input name='a' value='$alc' $sz2 /></td>\n";
print "<td>Price</td><td><input name='p' value='$pr' $sz2/></td></tr>\n";
print "<tr><td $c2>Style</td><td $c4><input name='s' value='$sty' $sz/></td></tr>\n";
#print "<tr><td>Rating</td><td><input name='r' value='$rate' /></td></tr>\n";
print "<tr><td $c2>Rating</td><td $c4><select name='r' value='$rate' />" .
   "<option value=''></option>\n";
for my $ro (0 .. scalar(@ratings)-1) {
  print "<option value='$ro'" ;
  print " selected='selected'" if ( $ro eq $rate );
  print  ">$ro - $ratings[$ro]</option>\n";
}
print "</select></td></tr>\n";
print "<tr><td $c2>Comment</td><td $c4><textarea name='c' cols='30' rows='3' />$com</textarea></td></tr>\n";
if ( $edit ) {
  print "<tr><td><input type='submit' name='submit' value='Delete'/></td>\n";
  print "<td>&nbsp;</td><td><input type='submit' name='submit' value='Save'/></td></tr>\n";
} else {
  print "<tr><td>&nbsp;</td><td><input type='submit' name='submit' value='Record'/></td></tr>\n";
}
print "</table>\n";

# List section
if ( $op eq "loc" ) { # list locations
  print "Location list not implemented yet <br/>\n";
} else { # Regular beer list, with filters
  print "<hr/><a href='" . $q->url . "'>Filter: <b>$qry</b></a><p/>\n" if $qry;
  my $i = scalar( @lines );
  my $lastloc = "";
  my $lastdate = "";
  #my $maxlines = 25;
  my $daysum = 0.0;
  while ( $i > 0 ) {
    $i--;
    next unless ( !$qry || $lines[$i] =~ /$qry/i );
    ( $stamp, $wday, $effdate, $loc, $mak, $beer, $vol, $sty, $alc, $pr, $rate, $com ) = 
       split( /; */, $lines[$i] );
    my $date = "";
    my $time = "";
    if ( $stamp =~ /(^[0-9-]+) (\d\d?:\d\d?):/ ) {
      $date = $1;
      $time = $2;
    }
    my $dateloc = "$effdate : $loc";
      if ( $lastdate ne $effdate ) {
      my $drinks = sprintf("%3.1f", $daysum / ( 33 * 4.7 )) ; # std danish beer
      print "total $drinks std drinks\n" if ( $drinks > 0.1 && !$qry);
      $daysum = 0.0;
      print "<hr/>\n" ;
      $lastloc = "";
    }
    print "<b>$wday $date </b>" .
          "<a href='" . $q->url ."?q=".uri_escape($loc) ."' ><b>$loc</b></a><p/>\n" 
        if ( $dateloc ne $lastloc );
    if ( $date ne $effdate ) {
      $time = "($time)";
    }
    $daysum += ( $alc * $vol ) ;
    print "<p><i>$time &nbsp;</i>" .
      "<a href='". $q->url ."?q=".uri_escape($mak) ."' ><i>$mak</i></a> : " .
      "<a href='". $q->url ."?q=".uri_escape($beer) ."' ><b>$beer</b></a><br/>\n";
    if ( $sty || $rate ) {
      print "$rate p ($ratings[$rate])" if ($rate);
      print " <a href='". $q->url ."?q=".uri_escape($sty) ."' ><b> $sty</b></a>\n"
        if ($sty);
      print "<br/>\n";
    }
    print "$vol cl " if ($vol);
    print "- $pr kr " if ($pr);
    print "- $alc % " if ($alc);
    print "<br/>\n";
    print "$com <br/>\n" if ($com);
    print "<form method='POST'>\n";
    print "<a href='".  $q->url ."?e=" . uri_escape($stamp) ."' >Edit</a>\n";
    print "<input type='hidden' name='l' value='$loc' />\n";
    print "<input type='hidden' name='m' value='$mak' />\n";
    print "<input type='hidden' name='b' value='$beer' />\n";
    print "<input type='hidden' name='v' value='$vol' />\n";
    print "<input type='hidden' name='s' value='$sty' />\n";
    print "<input type='hidden' name='a' value='$alc' />\n";
    print "<input type='hidden' name='p' value='$pr' />\n";
    print "<input type='submit' name='submit' value='Copy'/>\n";
    print "</form></p>\n";

    $lastloc = $dateloc;
    $lastdate = $effdate;
    $maxlines--;
    last if ($maxlines == 0); # if negative, will go for ever
  }
  my $drinks = sprintf("%3.1f", $daysum / ( 33 * 4.7 )) ; # std danish beer
  print "total $drinks std drinks\n" if ( $drinks > 0.1 && !$qry);
  print "<hr/>\n" ;
  if ( $maxlines >= 0 ) {
    print "<p/><a href='" . $q->url . "?maxl=-1&" . $q->query_string() . "'>" .
      "More</a><br/>\n";
  } else {
    print "<p/>That was the whole list<br/>\n";
  }

}

# HTML footer
print "</body></html>\n";

exit();

############################################

# Helper to sanitize input data
sub param {
  my $tag = shift;
  my $val = $q->param($tag) || "";
  $val =~ s/[^a-zA-ZåæøÅÆØöÖäÄ\/ 0-9.,&:-]/_/g; 
  return $val;
}


# Helper to make an error message
sub error {
  my $msg = shift;
  print $q->header("Content-type: text/plain");
  print "ERROR\n";
  print $msg;
  exit();
}

