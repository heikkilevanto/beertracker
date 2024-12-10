# Part of my beertracker
# Drawing the graph of daily drinks



package graph;

use strict;
use warnings;
use feature 'unicode_strings';
use utf8;  # Source code and string literals are utf-8


# TODO LATER - Move the graph here. Use db instead of @records.

# Helper to clear the cached files from the data dir.
sub clearcachefiles {
  my $c = shift;
  my $datadir = $c->{datadir};
  print STDERR "clear: d='$datadir'\n";
  foreach my $pf ( glob($datadir."*") ) {
    next if ( $pf =~ /(\.data)|(.db.*)$/ ); # Always keep data files
    next if ( -d $pf ); # Skip subdirs, if we have such
    if ( $pf =~ /\/$c->{username}.*png/ ||   # All png files for this user
         -M $pf > 7 ) {  # And any file older than a week
      unlink ($pf)
        or error ("Could not unlink $pf $!");
      }
  }
} # clearcachefiles

################################################################################
# Report module loaded ok
1;
