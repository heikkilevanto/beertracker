# Small helper routines

package copyproddata;
use strict;
use warnings;

use feature 'unicode_strings';
use utf8;  # Source code and string literals are utf-8

use POSIX qw(strftime localtime locale_h);


################################################################################
# Copy production data to dev file
# Needs to be before the HTML head, as it forwards back to the page
################################################################################
# Nice to see up to date data when developing
# NOTE Had some problems with file permissions and the -wal and -shm files. Now I
# delete those first, and copy over if they exist. Seems to work. But I leave
# noted to STDERR so I can look in the log if I run into problems later.
sub copyproddata {
  my $c = shift;
  if (!$c->{devversion}) {
    util::error ("Not allowed");
  }
  my $databasefile = $c->{databasefile};
  my $datadir = $c->{datadir};
  my $photodir = $c->{photodir};

  $c->{dbh}->disconnect;
  print STDERR "Before: \n" . `ls -l $databasefile* ` . `ls -l ../beertracker/$databasefile*`;
  system("rm $databasefile-*");  # Remove old -shm and -wal files
  print STDERR "rm $databasefile-* \n";
  system("cp ../beertracker/$databasefile* $datadir"); # And copy all such files over
  print STDERR "cp ../beertracker/$databasefile* $datadir \n";
  graph::clearcachefiles( $c );
  system("cp ../beertracker/$photodir/* $photodir");
  print STDERR "After: \n" . `ls -l $databasefile* ` . ` ls -l ../beertracker/$databasefile*`;
  print $c->{cgi}->redirect( "$c->{url}" ); # without the o=, so we don't copy again and again
  exit();
} # copyproddata




# --- FUNCTIONS BELOW ---/
# insert functions below



################################################################################
# Report module loaded ok
1;
