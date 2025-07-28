# Various routines to deal with the geo coordnates of locations


package geo;
use strict;
use warnings;

use feature 'unicode_strings';
use utf8;  # Source code and string literals are utf-8

use POSIX qw(strftime localtime locale_h);
#Use Math::Trig qw(deg2rad);


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
    return sqrt($dlat * $dlat + $dlon * $dlon) * 111;
}


################################################################################
# Report module loaded ok
1;
