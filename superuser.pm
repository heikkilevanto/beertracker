# Superuser functions for my beertracker

# This module implements a few routines that should only be available for
# the superuser, myself. These are
#
# - copyproddata:  Copies the production data into the dev setup, so I can test
# with data that is up to date. Only available in the dev version.
#
# - gitstatus: Shows the git status on both dev and production version, and allows
# a git pull to be run on any of them.

package superuser;
use strict;
use warnings;

use feature 'unicode_strings';
use utf8;  # Source code and string literals are utf-8

use POSIX qw(strftime localtime locale_h);


################################################################################
# Copy production database to dev
# Needs to be before the HTML head, as it forwards back to the page
################################################################################
# Nice to see up to date data when developing
# NOTE Had some problems with file permissions and the -wal and -shm files. Now I
# delete those first, and copy over if they exist. Seems to work. But I leave
# noted to STDERR so I can look in the log if I run into problems later.
# NOTE - I have stopped using journaling at all, so the file permission problems
# should be fixed
sub copyproddata {
  my $c = shift;
  if (!$c->{devversion}) {
    util::error ("Not allowed");
  }
  my $databasefile = $db::databasefile;
  util::error ("No db file") unless $databasefile;
  my $datadir = $c->{datadir};
  my $photodir = $c->{photodir};

  util::error("Can not copy prod database, we have opened the db connection")
    if ($c->{dbh});

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


################################################################################
# Show git status
################################################################################
# Shows the git status on both dev and production version, and allows
# a git pull to be run on any of them.
# Useful if I edit a file directly in
# github and commit it there. Then I can pull it first into dev and later
# into prod. In case I made a typo that breaks dev, I can fix or revert it, and
# then go to the production system and do a git pull on the dev setup.

sub gitstatus {
}

################################################################################
# Do a git pull
################################################################################
sub gitpull {
}



################################################################################
# Report module loaded ok
1;
