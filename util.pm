# Small helper routines

package util;
use strict;
use warnings;

use feature 'unicode_strings';
use utf8;  # Source code and string literals are utf-8

use POSIX qw(strftime localtime locale_h);


# --- insert new functions here ---
# This is a marker for the refactoring scripts
# This file acts as a template for new modules, up to the marker above

################################################################################
# Table of contents
#
# Helpers for normalizing strings
# Helpers for date and timestamps
# Helpers for cgi parameters
# Error handling and debug logging
# The top line and pulldown menu


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
  return $v if ( $v =~ /^ *x/i ); # X means explicit clearing of the field
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

# Split date and weekday, convert weekday to text
# Get the date from Sqlite with a format like '%Y-%m-%d %w'
# The %w returns the number of the weekday.
sub splitdate {
  my $stamp = shift || return ( "(never)", "", "" );
  my ($date, $wd, $time ) = split (' ', $stamp);
  if (defined($wd)) {
    my @weekdays = ( "Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun" );
    $wd = $weekdays[$wd];
  }
  return ( $date, $wd || "", $time || "" );
}

# helper to make a unit displayed in smaller font
sub unit {
  my $v = shift;
  my $u = shift || "XXX";  # Indicate missing units so I see something is wrong
  return "" unless $v;
  return "$v<span style='font-size: xx-small'>$u</span> ";
}

################################################################################
# Helpers for date and timestamps
################################################################################

# Helper to get a date string, with optional delta (in days)
sub datestr {
  my $form = shift || "%F %T";  # "YYYY-MM-DD hh:mm:ss"
  my $delta = shift || 0;  # in days, may be fractional. Negative for ealier
  my $exact = shift || 0;  # Pass non-zero to use the actual clock, not starttime
  my $starttime = time();
  my $clockhours = strftime("%H", localtime($starttime));
  $starttime = $starttime - $clockhours*3600 + 12 * 3600;
    # Adjust time to the noon of the same date
    # This is to fix dates jumping when script running close to miodnight,
    # when we switch between DST and normal time. See issue #153
  my $usetime = $starttime;
  if ( $form =~ /%T/ || $exact ) { # If we want the time (when making a timestamp),
    $usetime = time();   # base it on unmodified time
  }
  my $dstr = strftime ($form, localtime($usetime + $delta *60*60*24));
  return $dstr;
} # datestr


################################################################################
# Helpers for cgi parameters
################################################################################

# Get a cgi parameter
sub param {
  my $c = shift;
  my $tag = shift;
  my $def = shift || "";
  util::error("No context c ") unless $c;
  util::error("No cgi in c") unless $c->{cgi};
  my $val = $c->{cgi}->param($tag) || $def;
  $val =~ s/[^a-zA-ZñÑåÅæÆøØÅöÖäÄéÉáÁāĀüÜß\/ 0-9.,&:\(\)\[\]?%-]/_/g;
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
  print "$msg <br/>\n";
  print STDERR "ERROR: $msg\n";
  my $i = 0;
  while (my($pkg,$fname,$lineno,$subroutine) = caller($i++)) {
    my $s = "  [$i]: $pkg:$lineno: $subroutine";
    print "$s  <br/>\n";
    print STDERR "$s \n";
  }
  exit();
}

# Helper to get version info
# Takes a relative dir path, defaults to the current one
# A bit tricky code, but seems to work
sub getversioninfo {
    my ($file, $namespace) = @_;
    $file = "$file/VERSION.pm";
    $namespace ||= 'VersionTemp' . int(rand(1000000));

    my $code = do {
        open my $fh, '<', $file or error("Can't open $file: $!");
        local $/;
        <$fh>;
    };

    # Replace package name with unique one
    $code =~ s/\bpackage\s+Version\b/package $namespace/;

    my $full = "package main; no warnings; eval q{$code};";
    my $ok = eval $full;
    error( "Error loading $file: $@") if $@;

    no strict 'refs';
    my $func = "${namespace}::version_info";
    return $func->();
}

################################################################################
# Top line, including the Show menu
################################################################################

# Return the current stats: Drinks, blood alc, and money for today
# TODO
sub topstats {
  my $c = shift;
  my $sql = "select
   strftime ( '%Y-%m-%d', 'now', '-06:00' ) as today,
   strftime ( '%Y-%m-%d', timestamp, '-06:00' ) as effdate,
   sum(price) as price,
   sum(stdrinks) as drinks
    from GLASSES
    where username = ?
    and effdate = today";
  my $rec = db::queryrecord($c, $sql, $c->{username});
  util::error("Something wrong in topstats query: $sql") unless ($rec);
  return "" unless ( $rec->{drinks} );
  my $ba = mainlist::bloodalc( $c, $rec->{today});
  my $s = "";
  my $color = "";
  $color = "white"  if ($rec->{drinks} >= 0.1 );
  $color = "yellow" if ($rec->{drinks} >= 4 );
  $color = "orange" if ($rec->{drinks} >= 7 );
  $color = "red" if ($rec->{drinks} >=10 );
  $color = "#f409c9" if ($rec->{drinks} >=13 ); # pinkish purple
  $s .= "&nbsp;&nbsp;";
  if ( $color ) {
    $s .= "<span style='font-size: small; border:1px solid $color'>";
    $s .= "&nbsp;" . util::unit($rec->{price}, ".-") if ($rec->{price});
    $s .= "&nbsp;" . util::unit($rec->{drinks},"d") if ($rec->{drinks});
    $s .= "&nbsp;" . util::unit($ba->{now}, "/₀₀") if ($ba->{now});
    $s .= "&nbsp;";
    $s .= "</span>";
  }
  return $s;
} # topstats

# The top bar, on every page
sub topline {
  my $c = shift; # context;
  my $s = "";
  $s .= "<span style='white-space: nowrap;'>\n";
  $s .= "Beertracker";
  if ( $c->{devversion} ) {
    $s =~ s/tracker/-DEV/;
  }
  my $v = Version::version_info();
  $s .= "&nbsp;\n";
  $s .= "$v->{tag}+$v->{commits}";
  $s .= "+" if ($v->{dirty});
  $s .= "&nbsp;\n";
  $s .= showmenu($c);

  $s .= topstats($c);

  $s .= "</span>";
  $s .= "<hr>\n";
} # topline

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
  $s .= "<option value='o=Brew' >Brews</option>\n";
  $s .= "<option value='o=Location' >Locations</option>\n";
  $s .= "<option value='o=Comment' >Comments</option>\n";
#  $s .= "<option value='o=Style' >Styles</option>\n";  # Disabled, see #417
  $s .= "<option value='o=Person' >Persons</option>\n";
  $s .= "<option value='o=About' >About</option>\n";
  if ( $c->{devversion} ) {
    $s .= "<option value='o=copyproddata'>Get Production Data</option>\n";
  }
  $s .= "</select>\n";
#  $s .=  " &nbsp; &nbsp; &nbsp;";
#  if ( $c->{op} && $c->{op} !~ /graph/i ) {
#    $s .= "<a href='$c->{url}'><b>G</b></a>\n";
#  } else {
#    $s .= "<a href='$c->{url}?o=board'><b>B</b></a>\n";
#  }

  return $s;
}


# Some helpers from the old index.cgi. For now they are not used at all.
# Kept here for future reference, in case I wish to reintroduce them.

# # Helper to make a google link
#sub glink {
#   my $qry = shift;
#   my $txt = shift || "Google";
#   return "" unless $qry;
#   $qry = uri_escape_utf8($qry);
#   my $lnk = "&nbsp;<i>(<a href='https://www.google.com/search?q=$qry'" .
#     " target='_blank' class='no-print'><span>$txt</span></a>)</i>\n";
#   return $lnk;
# }

# # Helper to make a Ratebeer search link
#sub rblink {
#   my $qry = shift;
#   my $txt = shift || "Ratebeer";
#   return "" unless $qry;
#   $qry = uri_escape_utf8($qry);
#   my $lnk = "<i>(<a href='https://www.ratebeer.com/search?q=$qry' " .
#     " target='_blank' class='no-print'><span>$txt<span></a>)</i>\n";
#   return $lnk;
# }
#
# # Helper to make a Untappd search link
#sub utlink {
#   my $qry = shift;
#   my $txt = shift || "Untappd";
#   return "" unless $qry;
#   $qry = uri_escape_utf8($qry);
#   my $lnk = "<i>(<a href='https://untappd.com/search?q=$qry'" .
#     " target='_blank' class='no-print'><span>$txt<span></a>)</i>\n";
#   return $lnk;
# }

#sub maplink {
#   my $g = shift;
#   my $txt = shift || "Map";
#   return "" unless $g;
#   my ( $la, $lo, undef ) = geo($g);
#   my $lnk = "<a href='https://www.google.com/maps/place/$la,$lo' " .
#   "target='_blank' class='no-print'><span>$txt</span></a>";
#   return $lnk;
# }




# TODO - Geo stuff not (re)implemented in the new code.
# TODO - Move all geo stuff into its own module
# Kept here as an example

# Helper to validate and split a geolocation string
# Takes one string, in either new or old format
# returns ( lat, long, string ), or all "" if not valid coord
# sub geo {
#   my $g = shift || "";
#   return ("","","") unless ($g =~ /^ *\[?\d+/ );
#   $g =~ s/\[([-0-9.]+)\/([-0-9.]+)\]/$1 $2/ ;  # Old format geo string
#   my ($la,$lo) = $g =~ /([0-9.-]+) ([0-9.-]+)/;
#   return ($la,$lo,$g) if ($lo);
#   return ("","","");
# }

# # Helper to return distance between 2 geolocations
# sub geodist {
#   my $g1 = shift;
#   my $g2 = shift;
#   return "" unless ($g1 && $g2);
#   my ($la1, $lo1, undef) = geo($g1);
#   my ($la2, $lo2, undef) = geo($g2);
#   return "" unless ($la1 && $la2 && $lo1 && $lo2);
#   my $pi = 3.141592653589793238462643383279502884197;
#   my $earthR = 6371e3; # meters
#   my $latcorr = cos($la1 * $pi/180 );
#   my $dla = ($la2 - $la1) * $pi / 180 * $latcorr;
#   my $dlo = ($lo2 - $lo1) * $pi / 180;
#   my $dist = sqrt( ($dla*$dla) + ($dlo*$dlo)) * $earthR;
#   return sprintf("%3.0f", $dist);
# }

# # Helper to guess the closest location
#sub guessloc {
#   my $g = shift;
#   my $def = shift || ""; # def value, not good as a guess
#   $def =~ s/ *$//;
#   $def =~ s/^ *//;
#   return ("",0) unless $g;
#   my $dist = 200;
#   my $guess = "";
#   foreach my $k ( sort(keys(%geolocations)) ) {
#     my $d = geodist( $g, $geolocations{$k} );
#     if ( $d && $d < $dist ) {
#       $dist = $d;
#       $guess = $k;
#       $guess =~ s/ *$//;
#       $guess =~ s/^ *//;
#     }
#   }
#   if ($def eq $guess ){
#     $guess = "";
#     $dist = 0;
#   }
#   return ($guess,$dist);
# }



# ################################################################################
# # Get all geo locations
# # TODO - Don't use this for the javascript, send also the 'last' time
# ################################################################################
# sub XXextractgeo {
# #  Earlier version of the sql, with last seen and sorting
# #     select name, GeoCoordinates, max(timestamp) as last
# #     from Locations, glasses
# #     where  LOCATIONS.id = GLASSES.Location
# #       and GeoCoordinates is not null
# #     group by location
# #     order by last desc
#   my $sql = q(
#     select name, GeoCoordinates
#     from Locations, glasses
#     where  LOCATIONS.id = GLASSES.Location
#       and GeoCoordinates is not null
#     group by location
#   ); # No need to sort here, since put it all in a hash.
#   my $get_sth = $dbh->prepare($sql);
#   $get_sth->execute();
#   while ( my ($name, $geo, $last) = $get_sth->fetchrow_array ) {
#     $geolocations{$name} = $geo;
#   }
# }
#











################################################################################
# Report module loaded ok
1;
