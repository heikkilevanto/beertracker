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
my $qrylim = param("f"); # query limit, "c" or "r" for comments or ratings
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


# Read the file
# Set defaults for the form, usually from last line in the file
# Actually, at this point only set $lastline and $foundline
# They get split later
open F, "<$datafile" 
  or error("Could not open $datafile for reading: $!".
     "<br/>Probably the user hasn't been set up yet" );
my $foundline = "";
my $lastline = "";
my $thisloc = "";
my @lines;
while (<F>) {
  chomp();
  s/#.*$//;  # remove comments
  next unless $_; # skip empty lines
  push @lines, $_; # collect them all
  my ( $t, $wd, $ed, $l, $m, $b, $v, $s, $a, $p, $r, $c ) = split( /; */ );
  $thisloc = $l if $l;
  if ( ! $edit || ($edit eq $t) ) {
    $foundline = $_;
  }
  $lastline = $_;
}


# POST data into the file
if ( $q->request_method eq "POST" ) {
  error("Can not see $datafile") if ( ! -w $datafile ) ;
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
  # Check for missing values in the input, copy from the most recent beer with
  # the same name.
  $loc = $thisloc unless $loc;  # Always default to the last one
  my $i = scalar( @lines );
  while ( $i > 0 && $beer && ( !$mak || !$vol || !$sty || !$alc || !$pr )) {
    print STDERR "Considering " . $lines[$i] . "\n";
    ( undef, undef, undef, undef, $imak, $ibeer, $ivol, $isty, $ialc, $ipr, undef, undef) = 
       split( /; */, $lines[$i] );
    if ( uc($beer) eq uc($ibeer) ) {
      $beer = $ibeer; # with proper case letters
      $mak = $imak unless $mak;
      $vol = $ivol unless $vol;
      $sty = $isty unless $sty;
      $alc = $ialc unless $alc;
      $pr  = $ipr  unless $pr;
    }
    $i--;
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
  # Redirect to the same script, without the POST, so we see the results
  print $q->redirect( $q->url ); 
  # TODO - plot the values in a graph
  exit();
}


# Get new values from the file we ingested earlier
my ( $laststamp, undef, undef, $lastloc, $lastbeer, undef ) = split( /; */, $lastline );
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
print "<link rel='shortcut icon' href='beer.png'/>\n";
print "</head>\n";
print "<body>\n";

my $script = <<'SCRIPTEND';
  function clearinputs() {
    var inputs = document.getElementsByTagName('input');
    for (var i = 0; i < inputs.length; i++ ) {
      if ( inputs[i].type == "text" ) 
        inputs[i].value = "";
    }
  };
SCRIPTEND
print "<script>\n$script</script>\n";


# Status line
if (  $localtest) {
  print "Local test installation<br/>\n";
}
# print "e='$edit' f='$foundline'<br/>"; # ###

#my ($date, $time) = split(' ', $laststamp);
#if ( $laststamp =~ / (\d\d:\d\d)/) {
#  my $time = $1;
#  print "<b>$time $lastloc: $lastbeer</b><p/>\n";
#} else {
#  print "<b>Welcome to BeerTrack</b><p/>\n";
#}

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
print "<tr><td $c2>".lst("Location")."</td><td $c4><input name='l' value='$loc' $sz /></td></tr>\n";
print "<tr><td $c2>".lst("Brewery")."</td><td $c4><input name='m' value='$mak' $sz /></td></tr>\n";
print "<tr><td $c2>".lst("Beer")."</td><td $c4><input name='b' value='$beer' $sz /></td></tr>\n";
print "<tr><td>Vol</td><td><input name='v' value='$vol' $sz2 />\n";
print "<td>Alc</td><td><input name='a' value='$alc' $sz2 /></td>\n";
print "<td>Price</td><td><input name='p' value='$pr' $sz2/></td></tr>\n";
print "<tr><td $c2>".lst("Style")."</td><td $c4><input name='s' value='$sty' $sz/></td></tr>\n";
print "<tr><td $c2><a href='" . $q->url . "?f=r'>Rating</a></td><td $c4><select name='r' value='$rate' />" .
   "<option value=''></option>\n";
for my $ro (0 .. scalar(@ratings)-1) {
  print "<option value='$ro'" ;
  print " selected='selected'" if ( $ro eq $rate );
  print  ">$ro - $ratings[$ro]</option>\n";
}
print "</select></td></tr>\n";
print "<tr><td $c2><a href='" . $q->url . "?f=c'>Comment</a></td><td $c4><textarea name='c' cols='30' rows='3' />$com</textarea></td></tr>\n";
if ( $edit ) {
  print "<tr><td>&nbsp;</td><td><input type='submit' name='submit' value='Save'/></td>\n";
  print "<td>&nbsp;</td><td><a href='". $q->url . "' >cancel</a></td>";
  print "<td>&nbsp;</td><td><input type='submit' name='submit' value='Delete'/></td></tr>\n";
} else {
  print "<tr><td>&nbsp;</td><td><input type='submit' name='submit' value='Record'/></td>";
  print "<td>&nbsp;</td><td><input type='button' value='clear' onclick='clearinputs()'/></td>";
  print "</tr>\n";
}
print "</table>\n";

# List section
if ( $op ) { # various lists
  print "<hr/><a href='" . $q->url . "'><b>$op</b> list</a><p/>\n";
  my $i = scalar( @lines );
  my $fld;
  my $line;
  my %seen;
  print "<table>\n";
  while ( $i > 0 ) {
    $i--;
    ( $stamp, $wday, $effdate, $loc, $mak, $beer, $vol, $sty, $alc, $pr, $rate, $com ) = 
       split( /; */, $lines[$i] );
    $fld = "";
    if ( $op eq "Location" ) {
      $fld = $loc;
      $line = "<td>" . filt($loc,"b") . "</td><td>$wday $effdate<br/>" . 
           filt($mak,"i") . ":" . filt($beer) . "</td>";
    } elsif ( $op eq "Brewery" ) {
      $fld = $mak;
      $mak =~ s"/"/<br/>";
      $line = "<td>" . filt($mak,"b")  . "</td><td>$wday $effdate " .filt($loc) .
            "<br/>" . filt("[$sty]") . "  " . filt($beer,"b")  ."</td>";
    } elsif ( $op eq "Beer" ) {
      $fld = $beer;
      $line = "<td>" . filt($beer,"b")  . "</td><td>$wday $effdate ". filt($loc) .
            "<br/>" . filt("[$sty]"). " " . filt($mak,"i") . "&nbsp;</td>";
    } elsif ( $op eq "Style" ) {
      $fld = $sty;
      $line = "<td>" . filt("[$sty]","b")  . "</td><td>$wday $effdate " .  filt($loc,"i") . 
            "<br/>" . filt($mak,"i") . ":" . filt($beer,"b") . "</td>";
    }
    next unless $fld;
    $fld = uc($fld); 
    next if $seen{$fld};
    print "<tr>$line</tr>\n";
    $seen{$fld} = 1;
  }
  print "</table>\n";
  
} else { # Regular beer list, with filters
  if ($qry || $qrylim) {
    print "<hr/> Filter: ";
    print "<a href='" . $q->url ."'><b>$qry (Clear)</b></a>" if ($qry);
    print " -".$qrylim if ($qrylim);
    print " &nbsp;  \n";
    print "<br/>";
    print "<a href='" . $q->url . "?q=" . uri_escape($qry) . 
        "&f=r' >Ratings</a>\n";
    print "<a href='" . $q->url . "?q=" . uri_escape($qry) . 
        "&f=c' >Comments</a>\n";
    print "<a href='" . $q->url . "?q=" . uri_escape($qry) . 
         "'>All</a>\n";
    print "<p/>\n";
  }
  my $i = scalar( @lines );
  my $lastloc = "";
  my $lastdate = "today";
  my $lastloc2 = ""; 
  my $lastwday = "";
  #my $maxlines = 25;
  my $daydsum = 0.0;
  my $daymsum = 0;
  my $locdsum = 0.0;
  my $locmsum = 0;
  while ( $i > 0 ) {
    $i--;
    next unless ( !$qry || $lines[$i] =~ /$qry/i );
    ( $stamp, $wday, $effdate, $loc, $mak, $beer, $vol, $sty, $alc, $pr, $rate, $com ) = 
       split( /; */, $lines[$i] );
    next if ( $qrylim eq "r" && ! $rate );
    next if ( $qrylim eq "c" && ! $com );
    my $date = "";
    my $time = "";
    if ( $stamp =~ /(^[0-9-]+) (\d\d?:\d\d?):/ ) {
      $date = $1;
      $time = $2;
    }

    my $dateloc = "$effdate : $loc";

    if ( $dateloc ne $lastloc && ! $qry) { # summary of loc and maybe date
      my $locdrinks = sprintf("%3.1f", $locdsum / ( 33 * 4.7 )) ; # std danish beer
      my $daydrinks = sprintf("%3.1f", $daydsum / ( 33 * 4.7 )) ; # std danish beer
      # loc summary: if nonzero, and diff from daysummary or there is a new loc coming
      if ( $locdrinks > 0.1 ) {
        print "$lastloc2: $locdrinks d, $locmsum kr. <br/>\n";
        $locdsum = 0.0;
        $locmsum = 0;
      }
      # day summary: if nonzero and diff from daysummary and end of day
      #if ( abs ( $daydrinks > 0.1 ) && abs ( $daydrinks - $locdrinks ) > 0.1 &&
      #   $lastdate ne $effdate ) {
      if ( abs ( $daydrinks > 0.1 ) && $lastdate ne $effdate ) {
      #if ( $daydrinks > 0.1 ){
        print " <b>$lastwday</b>: $daydrinks d, $daymsum kr <br/>\n";
        $daydsum = 0.0;
        $daymsum = 0;
      }
      print "<p/>";
    }
    if ( $lastdate ne $effdate ) { # New date
      print "<hr/>\n" ;
      $lastloc = "";
    }
    if ( $dateloc ne $lastloc ) { # New location and maybe also new date
      print "<b>$wday $date </b>" . filt($loc,"b") . "</a><p/>\n" ;
    }
    if ( $date ne $effdate ) {
      $time = "($time)";
    }
    $daydsum += ( $alc * $vol ) if ($alc && $vol) ;
    $daymsum += $pr if ($pr) ;
    $locdsum += ( $alc * $vol ) if ($alc && $vol) ;
    $locmsum += $pr if ($pr) ;
    print "<p>$time &nbsp;" . filt($mak,"i") . " : " . filt($beer,"b") . "<br/>\n";
    if ( $sty || $rate ) {
      print filt("[$sty]")   if ($sty);
      print " ($rate: $ratings[$rate])" if ($rate);
      print "<br/>\n";
    }
    print "<i>$com</i> <br/>\n" if ($com);
    print "$pr kr. &nbsp; " if ($pr);
    print "$vol cl " if ($vol);
    print "* $alc % " if ($alc);
    if ( $alc && $vol ) {
      my $dr = sprintf("%1.2f", ($alc * $vol) / (33 * 4.7) );
      print "= $dr d ";
    }
    print "<br/>\n";
    # guess sizes for small/large beers
    my $vol2 = $vol;
    my $vol4 = $vol;
    if ( $vol > 30 ) {
      $vol2 = 25; 
    } else {
      $vol4 = 40; 
    }
 
    print "<form method='POST'>\n";
    print "<a href='".  $q->url ."?e=" . uri_escape($stamp) ."' >Edit</a>\n";
    print "<input type='hidden' name='l' value='$loc' />\n";
    print "<input type='hidden' name='m' value='$mak' />\n";
    print "<input type='hidden' name='b' value='$beer' />\n";
    print "<input type='hidden' name='v' value='$vol2' />\n";
    print "<input type='hidden' name='s' value='$sty' />\n";
    print "<input type='hidden' name='a' value='$alc' />\n";
    print "<input type='hidden' name='p' value='$pr' />\n";
    print "<input type='submit' name='submit' value='Copy $vol2'/>\n";
    print "</form>\n";

    print "<form method='POST'>\n";
    print "<a href='".  $q->url ."?e=" . uri_escape($stamp) ."' >Edit</a>\n";
    print "<input type='hidden' name='l' value='$loc' />\n";
    print "<input type='hidden' name='m' value='$mak' />\n";
    print "<input type='hidden' name='b' value='$beer' />\n";
    print "<input type='hidden' name='v' value='$vol4' />\n";
    print "<input type='hidden' name='s' value='$sty' />\n";
    print "<input type='hidden' name='a' value='$alc' />\n";
    print "<input type='hidden' name='p' value='$pr' />\n";
    print "<input type='submit' name='submit' value='Copy $vol4'/>\n";
    print "</form>\n";

    print"</p>\n";

    $lastloc = $dateloc;
    $lastloc2 = $loc;
    $lastdate = $effdate;
    $lastwday = $wday;
    $maxlines--;
    last if ($maxlines == 0); # if negative, will go for ever
  }
  if ( ! $qry) { # final summary
    my $locdrinks = sprintf("%3.1f", $locdsum / ( 33 * 4.7 )) ; # std danish beer
    my $daydrinks = sprintf("%3.1f", $daydsum / ( 33 * 4.7 )) ; # std danish beer
    # loc summary: if nonzero, and diff from daysummary or there is a new loc coming
    if ( $locdrinks > 0.1 ) {
      print "$lastloc2: $locdrinks d, $locmsum kr. \n";
      }
      # day summary: if nonzero and diff from daysummary and end of day
    if ( abs ( $daydrinks > 0.1 ) && abs ( $daydrinks - $locdrinks ) > 0.1 &&
         $lastdate ne $effdate ) {
      print " <b>$lastwday</b>: $daydrinks d, $daymsum kr\n";
      }
      print "<p/>";
    }

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

# Helper to make a filter link
sub filt {
  my $f = shift;
  my $tag = shift || "nop";
  my $param = $f;
  $param =~ s"[\[\]]""g; # remove the [] around styles etc
  my $link = "<a href='" . $q->url ."?q=".uri_escape($param) ."' ><$tag>$f</$tag></a>";
  return $link;
}

# Helper to make a link to a list
sub lst {
  my $op = shift;
  my $link = "<a href='" . $q->url ."?o=".uri_escape($op) ."' >$op</a>";
  return $link;
}

# Helper to make an error message
sub error {
  my $msg = shift;
  print $q->header("Content-type: text/plain");
  print "ERROR\n";
  print $msg;
  exit();
}

