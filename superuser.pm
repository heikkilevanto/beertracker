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
use File::Basename;
use Cwd qw(cwd);
use HTML::Entities;

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
# Verify that the user is a superuser
################################################################################
# TODO - This could be stored in $c, or even retrieved from the db. For now,
# a simple check is sufficient
sub checksuperuser {
  my $c = shift;
  util::error("Not allowed") unless $c->{username} eq "heikki";
}


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
  my $c = shift;
  checksuperuser($c);
  my $cur = basename(cwd());
  my $p = util::param($c, "p", $cur);
  util::error("Bad path '$p'") unless $p =~ /^beertracker/ ;
  print "<b>Git status for <i>'$p'</i> </b><p/>\n";
  for my $d ( <../beertracker*> ) { #/  #The / needed to sync Kate's highlight
    my $b = basename($d);
    next if ($b eq $p );
    print "&nbsp;(Switch to <a href='$c->{url}?o=$c->{op}&p=$b'><i>'$b'</i></a>)<br>\n";
  }
  print "<p/>\n";
  chdir("../$p") or
    util::error("Can not chdir to '$p' ");
  my $cmd = "sudo -u heikki /usr/bin/git status -uno 2>&1";
  print "Running $cmd <p/>\n";
  my $style = $c->{mobile} ? "" : "style='font-size:14px;'";
  my $st = `$cmd` ;
  my $rc = $?;  # return code
  $st = encode_entities($st);
  print "<pre $style>\n$st\n</pre> \n";
  if ($rc){
    print STDERR "gitstatus: $st \n";
    return;
  }
  print "<hr>\n";
  my $reloc = "window.location.href=\"$c->{url}?o=GitPull&p=$p\"";
  print "$reloc <br>\n";
  print "Are you sure you want to do a <button onclick='$reloc'>Git Pull</button><br>\n";

}

################################################################################
# Do a git pull
################################################################################
sub gitpull {
  my $c = shift;
  checksuperuser($c);
  my $cur = basename(cwd());
  my $p = util::param($c, "p", $cur);
  util::error("Bad path '$p'") unless $p =~ /^beertracker/ ;
  print "<b>Doing a Git pull for <i>'$p'</i> </b><p/>\n";
  chdir("../$p") or
    util::error("Can not chdir to '$p' ");
  my $cmd = "sudo -u heikki /usr/bin/git pull --ff-only 2>&1";
  print "Running $cmd <p/>\n";
  my $style = $c->{mobile} ? "" : "style='font-size:14px;'";
  my $st = `$cmd` ;
  my $rc = $?;  # return code
  $st = encode_entities($st);
  print "<pre $style>\n$st\n</pre> \n";
  if ($rc){
    print STDERR "gitstatus: $st \n";
    return;
  }

}



################################################################################
# Report module loaded ok
1;
