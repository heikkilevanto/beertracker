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

  my $clr = "Onfocus='value=value.trim();select();' autocapitalize='words' ".
    "OnInput='geodist(\"$inputprefix\")'";

  my $latname = $inputprefix."Lat";
  my $lonname = $inputprefix."Lon";
  my $s = "";
  $s .= "<td>\n";
  $s .= "<input name='$latname' id='$latname' value='$lat' $clr />\n";
  $s .= "<br>";
  $s .= "<input name='$lonname' id='$lonname' value='$lon' $clr />\n";
  $s .= "<br>";
  $s .= "<span onclick='geoclear(\"$inputprefix\")'>&nbsp; (Clear)</span>\n";
  $s .= "<span onclick='geohere(\"$inputprefix\")'>&nbsp; (Here)</span>\n";
  $s .= "<script> geodist('$inputprefix');</script>\n";
  return $s;
}

################################################################################
# Javascript for the geo input
################################################################################
sub geojs {
  my $c = shift;
  my $js = <<'SCRIPT' ;

  function geoclear(prefix) {
    const latinp = document.getElementById(prefix+"Lat");
    const loninp = document.getElementById(prefix+"Lon");
    latinp.value = "";
    loninp.value = "";
    latinp.dispatchEvent(new Event("input"));
  }

  function geohere(prefix) {
    const latinp = document.getElementById(prefix+"Lat");
    const loninp = document.getElementById(prefix+"Lon");
    if (!navigator.geolocation) {
      console.log("Geolocation is not supported by your browser.");
      return;
    }
    navigator.geolocation.getCurrentPosition(
      function(pos) {
        latinp.value = pos.coords.latitude.toFixed(6);
        loninp.value = pos.coords.longitude.toFixed(6);
        latinp.dispatchEvent(new Event("input"));
      },
      function(err) {
        console.log("Geo Error: " + err.message);
      }
    );
  }

  function haversineKm(lat1, lon1, lat2, lon2) {
    const R = 6371; // Earth radius in km
    const toRad = Math.PI / 180;

    const dLat = (lat2 - lat1) * toRad;
    const dLon = (lon2 - lon1) * toRad;

    const a = Math.sin(dLat / 2) ** 2 +
              Math.cos(lat1 * toRad) * Math.cos(lat2 * toRad) *
              Math.sin(dLon / 2) ** 2;

    const c = 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a));
    return R * c;
  }

  function geodist(prefix) {
    if (!navigator.geolocation) {
      return;
    }
    const latinp = document.getElementById(prefix+"Lat");
    const loninp = document.getElementById(prefix+"Lon");
    const distspan = document.getElementById(prefix+"Dist");
    if ( ! latinp.value || ! loninp.value ) {
      distspan.textContent = "...";
      return;
    }
    navigator.geolocation.getCurrentPosition(
      function(pos) {
        const lat1 = pos.coords.latitude.toFixed(7);
        const lon1 = pos.coords.longitude.toFixed(7);
        const lat2 = latinp.value;
        const lon2 = loninp.value;
        if ( lat2 && lon2 ) {
          var dist = haversineKm(lat1,lon1, lat2,lon2);
          if ( dist > 10 )
            dist = dist.toFixed(1) + " km";
          else if ( dist > 1 )
            dist = dist.toFixed(3) + " km";
          else
            dist = (dist * 1000)  .toFixed(0) + " m";

          distspan.textContent= " " + dist ;
        } else {
          distspan.textContent = "...";
        }

      },
      function(err) {
        console.log("Geo Error: " + err.message);
      }
    );
  }


SCRIPT
  print "<script>$js</script>\n";

}

################################################################################
# Report module loaded ok
1;
