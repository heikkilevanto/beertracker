# Various routines to deal with the geo coordnates of locations


package geo;
use strict;
use warnings;

use feature 'unicode_strings';
use utf8;  # Source code and string literals are utf-8

use POSIX qw(strftime localtime locale_h);
use Math::Trig;


# --- insert new functions here ---

################################################################################
# Geo distance.
################################################################################
# Simplified  formula, should be accurate to within meters in my use cases
# (same city). For longer distances, exactness does not matter anyway.

sub approx_distance_km {
  my ($lat1, $lon1, $lat2, $lon2) = @_;

  my $dlat = $lat1 - $lat2;
  my $dlon = ($lon1 - $lon2) * cos(deg2rad($lat1));
  return sqrt($dlat * $dlat + $dlon * $dlon) * 111;   # ~111 km / deg lat
}

# Better distance function
sub haversineKm {
  my ($lat1, $lon1, $lat2, $lon2) = @_;
  my $radius = 6371;  # Earth's radius in kilometers
 # Convert degrees to radians
  ($lat1, $lon1, $lat2, $lon2) = map { deg2rad($_) } ($lat1, $lon1, $lat2, $lon2);

  my $dlat = $lat2 - $lat1;
  my $dlon = $lon2 - $lon1;

  my $a = sin($dlat / 2)**2 + cos($lat1) * cos($lat2) * sin($dlon / 2)**2;
  my $c = 2 * atan2(sqrt($a), sqrt(1 - $a));

  return $radius * $c;
}


# Same, formatted for nice reading
sub geodist {
#  my $d = approx_distance_km ( @_ );
  my $d = haversineKm ( @_ );
  return sprintf( "%3.3f", $d) if ( $d < 1 );
  return sprintf( "%3.2f", $d) if ( $d < 10 );
  return sprintf( "%3.1f", $d) if ( $d < 100 );
  return sprintf( "%3.0f", $d);
} # geodist

################################################################################
# Geo input field
################################################################################
# $form .= geo::geoInput($c, $inputprefix, $rec->{Lat}, $rec->{Lon} );

# Label for the geo input
sub geolabel {
  my $c = shift;
  my $inputprefix = shift || "";
  my $distname = $inputprefix."Dist";
  my $s = "";
  $s .= "<td>";
  $s .= "Geo Lat";
  $s .= "<br>";
  $s .= "Geo Lon";
  $s .= "<br><span id='$distname'>? km</span>\n";
  $s .= "</td>\n";
  return $s;
}

# Geo input itself
sub geoInput {
  my $c = shift;
  my $inputprefix = shift || "";
  my $lat = shift || "";
  my $lon = shift || "";
  my $disabled = shift || "";  # "disabled" or ""

  my $clr = "Onfocus='value=value.trim();select();' autocapitalize='words' ".
    "OnInput='geodist(\"$inputprefix\")'";

  my $latname = $inputprefix."Lat";
  my $lonname = $inputprefix."Lon";
  my $s = "";
  $s .= "<td>\n";
  $s .= "<input name='$latname' id='$latname' value='$lat' $clr $disabled />\n";
  $s .= "<br>";
  $s .= "<input name='$lonname' id='$lonname' value='$lon' $clr $disabled />\n";
  $s .= "<br>";
  my $hiddenclass = $disabled ? "class='geo-edit-links' hidden" : "class='geo-edit-links'";
  $s .= "<span onclick='geoclear(\"$inputprefix\")' $hiddenclass>&nbsp; (Clear)</span>\n";
  $s .= "<span onclick='geohere(\"$inputprefix\")' $hiddenclass>&nbsp; (Here)</span>\n";
  $s .= "<script> geodist('$inputprefix');</script>\n";
  return $s;
}


################################################################################
# Report module loaded ok
1;
