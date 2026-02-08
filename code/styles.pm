# Part of my beertracker
# Beer style utilities: colors, display, shortening


package styles;

use strict;
use warnings;
use feature 'unicode_strings';
use utf8;  # Source code and string literals are utf-8

################################################################################
# Brew colors
################################################################################

# Returns the background color for the brew
# Takes a style string as the argument. That way it can also
# be used for the few non-brew items that need special color, like restaurants
# Returns just the color string with no prefix.
sub brewcolor {
  my $brew = shift;

  # TODO - Add prefixes for beers
  # TODO - Check against actual brew styles in the db
  my @drinkcolors = (   # color, pattern. First match counts, so order matters
      "003000", "restaurant|night|feedback", # regular bg color, no highlight
      "808080", "adjustment", # gray for payment adjustments
      "eac4a6", "wine[, ]+white",
      "801414", "wine[, ]+red",
      "4f1717", "wine[, ]+port",
      "aa7e7e", "wine",
      "f2f21f", "Pils|Lager|Keller|Bock|Helles|IPL",
      "e5bc27", "Classic|dunkel|shcwarz|vienna",
      "adaa9d", "smoke|rauch|sc?h?lenkerla",
      "350f07", "stout|port",  # imp comes later
      "1a8d8d", "sour|kriek|framb|lambie?c?k?|gueuze|gueze|geuze|berliner",
      "8cf2ed", "booze|spirit|sc?h?nap+s|whisky",
      "e07e1d", "cider",
      "eaeac7", "weiss|wit|wheat|weizen",
      "66592c", "Black IPA|BIPA",
      "9ec91e", "NEIPA|New England",
      "c9d613", "IPA|NE|WC",  # pretty late, NE matches pilsNEr
      "d8d80f", "Pale Ale|PA",
      "b7930e", "Old|Brown|Red|Dark|Ale|Belgian||Tripel|Dubbel|IDA",   # Any kind of ales (after Pale Ale)
      "350f07", "Imp",
      "dbb83b", "misc|mix|random",
      "9400d3", ".",   # # dark-violet, aggressive pink to show we don't have a color
      );

  my $type;
  if ( $brew =~ /^\[?(\w+)(,(.+))?\]?$/i ) {
    $type = "$1";
    $type .= ",$3" if ( $3 );
  } else {
    $type = $brew;  # Fallback to the full string for matching
  }
  for ( my $i = 0; $i < scalar(@drinkcolors); $i+=2) {
    my $pat = $drinkcolors[$i+1];
    if ( $type =~ /$pat/i ) {
      #print STDERR "brewcolor: got '$drinkcolors[$i]' for '$type' via '$pat' \n";
      return $drinkcolors[$i] ;
    }
  }
  util::error ("Can not get color for '$brew': '$type'");
}

# Returns a HTML style definition for the brew or style string
# Guesses a contrasting foreground color
sub brewtextstyle {
  my $c = shift;
  my $brew = shift;
  my $bkg = brewcolor($brew);
  my $lum = ( hex($1) + hex($2) + hex($3) ) /3  if ($bkg =~ /^(..)(..)(..)/i );
  my $fg = $c->{bgcolor};
  if ($lum < 64) {  # If a fairly dark color
    $fg = "#ffffff"; # put white text on it
  }
  return "style='background-color:#$bkg;color:$fg;'";
}

# Returns HTML for a styled display of the brew type and subtype
sub brewstyledisplay {
  my $c = shift;
  my $brewtype = shift;
  my $subtype = shift;
  my $style_str;
  if ($brewtype eq 'Beer') {
    $style_str = $subtype || 'Beer';
  } else {
    $style_str = $brewtype;
    $style_str .= ",$subtype" if $subtype;
  }
  my $dispstyle = brewtextstyle($c, $style_str);
  return "<span $dispstyle>[$style_str]</span>";
}

# Helper to shorten a beer style
sub shortbeerstyle {
  my $sty = shift || "";
  return "" unless $sty;
  $sty =~ s/\b(Beer|Style)\b//i; # Stop words
  $sty =~ s/\W+/ /g;  # non-word chars, typically dashes
  $sty =~ s/\s+/ /g;  # multiple spaces etc
  if ( $sty =~ /( PA |Pale Ale)/i ) {
    return "APA"   if ( $sty =~ /America|US/i );
    return "BelPA" if ( $sty =~ /Belg/i );
    return "NEPA"  if ( $sty =~ /Hazy|Haze|New England|NE/i);
    return "PA";
  }
  if ( $sty =~ /(IPA|India)/i ) {
    return "SIPA"  if ( $sty =~ /Session/i);
    return "BIPA"  if ( $sty =~ /Black/i);
    return "DNE"   if ( $sty =~ /(Double|Triple).*(New England|NE)/i);
    return "DIPA"  if ( $sty =~ /Double|Dipa|Triple/i);
    return "WIPA"  if ( $sty =~ /Wheat/i);
    return "NEIPA" if ( $sty =~ /New England|NE|Hazy/i);
    return "NZIPA" if ( $sty =~ /New Zealand|NZ/i);
    return "WC"    if ( $sty =~ /West Coast|WC/i);
    return "AIPA"  if ( $sty =~ /America|US/i);
    return "IPA";
  }
  return "Dunk"  if ( $sty =~ /.*Dunkel.*/i);
  return "Bock"  if ( $sty =~ /Bock/i);
  return "Smoke" if ( $sty =~ /(Smoke|Rauch)/i);
  return "Lager" if ( $sty =~ /Lager|Keller|Pils|Zwickl/i);
  return "Berl"  if ( $sty =~ /Berliner/i);
  return "Weiss" if ( $sty =~ /Hefe|Weizen|Hvede|Wit/i);
  return "Stout" if ( $sty =~ /Stout|Porter|Imperial/i);
  return "Farm"  if ( $sty =~ /Farm/i);
  return "Sais"  if ( $sty =~ /Saison/i);
  return "Dubl"  if ( $sty =~ /(Double|Dubbel)/i);
  return "Trip"  if ( $sty =~ /(Triple|Tripel|Tripple)/i);
  return "Quad"  if ( $sty =~ /(Quadruple|Quadrupel)/i);
  return "Trap"  if ( $sty =~ /Trappist/i);
  return "Blond" if ( $sty =~ /Blond/i);
  return "Brown" if ( $sty =~ /Brown/i);
  return "Strng" if ( $sty =~ /Strong/i);
  return "Belg"  if ( $sty =~ /Belg/i);
  return "BW"    if ( $sty =~ /Barley.*Wine/i);
  return "Sour"  if ( $sty =~ /Lambic|Gueuze|Sour|Kriek|Frmaboise/i);
  $sty =~ s/^ *([^ ]{1,5}).*/$1/; # First word, only five chars, in case we didn't get it above
  return $sty;
} # shortbeerstyle

sub beercolorstyle {
  my $c = shift;
  my $rec = shift;  # Can also be style as text, see below
  my $line = shift; # for error logging
  my $type = "";
  if (ref($rec)) {
    $type = "$rec->{type},$rec->{subtype}: $rec->{style} $rec->{maker}";  # something we can match
    $line = $rec->{rawline};
  } else {
    $type = $rec;
  }
  return brewtextstyle($c, $type);
} # beercolorstyle

1; # Return true for require