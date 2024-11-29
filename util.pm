# Part of my beertracker
# Small helper routines

package util;
use strict;
use warnings;

################################################################################
# Table of contents
#  - Helpers for normalizing strings
#  - Helpers for cgi parameters
#  - Error handling and debug logging

################################################################################
# Helpers for normalizing strings
################################################################################


# Helper to trim leading and trailing spaces
sub trim {
  my $val = shift || "";
  $val =~ s/^ +//; # Trim leading spaces
  $val =~ s/ +$//; # and trailing
  $val =~ s/\s+/ /g; # and repeated spaces in the middle
  return $val;
}

# Helper to sanitize numbers
sub number {
  my $v = shift || "";
  $v =~ s/,/./g;  # occasionally I type a decimal comma
  $v =~ s/[^0-9.-]//g; # Remove all non-numeric chars
  $v =~ s/[-.]*$//; # No trailing '.' or '-', as in price 45.-
  $v = 0 unless $v;
  return $v;
}

# Sanitize prices to whole ints
sub price {
  my $v = shift || "";
  $v = number($v);
  $v =~ s/[^0-9-]//g; # Remove also decimal points etc
  return $v;
}

################################################################################
# Helpers for cgi parameters
################################################################################

# Get a cgi parameter
sub param {
  my $c = shift;
  my $tag = shift;
  my $def = shift || "";
  my $val = $c->{cgi}->param($tag) || $def;
  $val =~ s/[^a-zA-ZñÑåÅæÆøØÅöÖäÄéÉáÁāĀ\/ 0-9.,&:\(\)\[\]?%-]/_/g;
  return $val;
}

sub paramnumber {
  my $c = shift;
  my $tag = shift;
  my $def = shift || "";
  my $val = param($c, $tag, $def);
  $val = number($val);
  return $val;
}

################################################################################
# Error handling and debug logging
################################################################################

# Helper to make an error message
sub error {
  my $msg = shift;
  print "\n\n";  # Works if have sent headers or not
  print "<hr/>\n";
  print "ERROR   <br/>\n";
  print $msg;
  print STDERR "ERROR: $msg\n";
  exit();
}

################################################################################
# Pull-down menus for the Show menu and for selecting a list
################################################################################


# The main "Show" menu
sub showmenu {
  my $c = shift; # context;
  my $s = "";
  $s .= " <select  style='width:4.5em;' " .
              "onchange='document.location=\"$c->{url}?\"+this.value;' >";
  $s .= "<option value='' >Show</option>\n";
  $s .= "<option value='o=full&' >Full List</option>\n";
  $s .= "<option value='o=Graph' >Graph</option>\n";
  $s .= "<option value='o=board' >Beer Board</option>\n";
  $s .= "<option value='o=Months' >Stats</option>\n";
  $s .= "<option value='o=Beer' >Lists</option>\n";
  $s .= "<option value='o=About' >About</option>\n";
  $s .= "</select>\n";
  $s .=  " &nbsp; &nbsp; &nbsp;";
  if ( $c->{op} && $c->{op} !~ /graph/i ) {
    $s .= "<a href='$c->{url}'><b>G</b></a>\n";
  } else {
    $s .= "<a href='$c->{url}?o=board'><b>B</b></a>\n";
  }
  return $s;
}

########## Menu for the various lists we have
sub listsmenu {
  my $c = shift or die ("No context for listsmenubar" );
  my $s = "";
  $s .= " <select  style='width:7em;' " .
              "onchange='document.location=\"$c->{url}?\"+this.value;' >";
  my @ops = ( "Beer",  "Brewery", "Wine", "Booze", "Location", "Restaurant", "Style", "Persons");
  for my $l ( @ops ) {
    my $sel = "";
    $sel = "selected" if ($l eq $c->{op});
    $s .= "<option value='o=$l' $sel >$l</option>\n"
  }
  $s .= "</select>\n";
  $s .= "<a href='$c->{url}?o=$c->{op}'><span>List</span></a> ";
  $s .= "&nbsp; &nbsp; &nbsp;";
  return $s;
} # listsmenubar


################################################################################
# Report module loaded ok
1;
