# Superuser functions for my beertracker

# This module implements a few routines that should only be available for
# the superuser, myself. These are
#
# - copyproddata:  Copies the production data into the dev setup, so I can test
# with data that is up to date. Only available in the dev version.
#
# - gitstatus: Shows the git status on both dev and production version, and allows
# a git pull to be run on any of them. Also lists branches and offers checkout.
#
# - gitcheckout: Checks out a branch for testing.

package superuser;
use strict;
use warnings;

use feature 'unicode_strings';
use utf8;  # Source code and string literals are utf-8

use POSIX qw(strftime localtime locale_h);
use File::Basename;
use Cwd qw(abs_path cwd);
use HTML::Entities;

# Captured once at module load. In FastCGI the process cwd can drift between
# requests, so we use this for a stable default and to build absolute paths.
my $STARTUP_DIR = abs_path(cwd());
use URI::Escape qw(uri_escape_utf8);

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
  my $databasefile = db::dbfile();
  util::error ("No db file") unless $databasefile;
  my $datadir = $c->{datadir};
  my $photodir = $c->{photodir};

  util::error("Can not copy prod database, we have opened the db connection")
    if ($c->{dbh});

  print { $c->{log} } "Before: \n" . `ls -l $databasefile* ` . `ls -l ../beertracker/$databasefile*`;
  system("rm $databasefile-*");  # Remove old -shm and -wal files
  print { $c->{log} } "rm $databasefile-* \n";
  system("cp ../beertracker/$databasefile* $datadir"); # And copy all such files over
  print { $c->{log} } "cp ../beertracker/$databasefile* $datadir \n";
  graph::clearcachefiles( $c );
  system("cp ../beertracker/$photodir/* $photodir");
  print { $c->{log} } "After: \n" . `ls -l $databasefile* ` . ` ls -l ../beertracker/$databasefile*`;
  print $c->{cgi}->redirect( "$c->{url}" ); # without the o=, so we don't copy again and again
  return;
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

# Helper: check superuser, validate param 'p' (must start with 'beertracker').
# Returns ($p, $gitdir) where $gitdir is the absolute path to the repo.
# Never chdirs - callers prefix shell commands with "cd $gitdir &&" instead.
sub git_prepare {
  my ($c) = @_;
  checksuperuser($c);
  my $p = util::param($c, "p", basename($STARTUP_DIR));
  util::error("Bad path '$p'") unless $p =~ /^beertracker/ ;
  my $gitdir = "$STARTUP_DIR/../$p";
  unless ( -d $gitdir ) {
    print { $c->{log} } "Directory not found: $gitdir\n";
    util::error("Directory not found: '$p'");
  }
  return ($p, $gitdir);
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
  my ($p, $gitdir) = git_prepare($c);
  print "<b>Git status for <i>'$p'</i> </b><p/>\n";
  # List other beertracker directories
  for my $d ( glob("$STARTUP_DIR/../beertracker*") ) {
    my $b = basename($d);
    next if ($b eq $p );
    my $loading = "document.body.innerHTML=\"<p>Switching to $b</p>\"";
    print "&nbsp;(Switch to " .
       "<a href='$c->{url}?o=$c->{op}&p=$b' onclick='$loading'>" .
       "<i>'$b'</i></a>)<br>\n";
  }
  print "<p/>\n";
  my $cdcmd = "cd " . quotemeta($gitdir) . " && ";
  my $cmd = $cdcmd . "sudo -u heikki /usr/bin/git fetch 2>&1 && " .
                     "sudo -u heikki /usr/bin/git status -uno 2>&1 " ;
  print "Running git fetch &amp;&amp; git status in $p <p/>\n";
  my $style = $c->{mobile} ? "" : "style='font-size:14px;'";
  my $st = `$cmd` ;
  my $rc = $?;  # return code
  print { $c->{log} } "gitstatus: $st \n";
  $st = encode_entities($st);
  print "<pre $style>\n$st\n</pre> \n";
  if ( $rc && $st =~ /a password is required/ ) {
    print "Make sure you have these lines in /etc/sudoers.d/beertracker: <br>\n";
    print "<pre>
    www-data ALL=(heikki) NOPASSWD: /usr/bin/git status -uno
    www-data ALL=(heikki) NOPASSWD: /usr/bin/git fetch
    www-data ALL=(heikki) NOPASSWD: /usr/bin/git pull --ff-only
    www-data ALL=(heikki) NOPASSWD: /usr/bin/git branch --list
    www-data ALL=(heikki) NOPASSWD: /usr/bin/git log *
    www-data ALL=(heikki) NOPASSWD: /usr/bin/git checkout *
      </pre>\n";
  }
  if ( ! $rc && $st =~ /can be fast-forwarded/ ) {
    print "<hr>\n";
    my $loading = 'document.body.innerHTML = "<p>Pulling ...</p>";';
    my $reloc = "window.location.href=\"$c->{url}?o=GitPull&p=$p\"";
    print "Are you sure you want to do a <button onclick='$loading;$reloc'>Git Pull</button><br>\n";
  }

  # List branches and offer checkout
  my $bcmd = $cdcmd . "sudo -u heikki /usr/bin/git branch -a  2>&1";
  my $branches = `$bcmd`;
  if ( $? == 0 && $branches ) {
    print "<hr>\n<b>Branches:</b><br>Running git branch --list in $p<br>\n";
    print "<table>\n";
    for my $line ( split /\n/, $branches ) {
      my $branch = $line;
      $branch =~ s/^\s*\*?\s*//;   # strip leading spaces and current-branch marker
      $branch =~ s/\s.*$//;        # strip trailing annotations
      next unless $branch =~ /^[\w\.\-\/]+$/;  # only safe branch names
      my $current = ( $line =~ /^\*/ ) ? " <b>(current)</b>" : "";
      my $loading = "document.body.innerHTML=\"<p>Checking out $branch ...</p>\"";
      my $reloc = "window.location.href=\"$c->{url}?o=GitCheckout&p=$p&b=" .
                  uri_escape_utf8($branch) . "\"";
      print "<tr>";
      print "<td>&nbsp;$branch</td>";
      print "<td>$current";
      print " <button onclick='$loading;$reloc'>Checkout</button>" unless $current;
      print "</td></tr>\n";
    }
    print "</table>\n";
  } else {
    print "Could not get branch list in $p: $? <br>'$branches'<br>\n";
  }

  # List last 5 commits and offer checkout by SHA
  my $lcmd = $cdcmd . "sudo -u heikki /usr/bin/git log -5 --pretty=format:%h%x09%ci%x09%s 2>&1";
  my $logout = `$lcmd`;
  if ( $? == 0 && $logout ) {
    print "<hr>\n<b>Recent commits:</b><br>\n";
    print "<div style='overflow-x: auto;'>\n";
    print "<table style='white-space: nowrap;'>\n";
    for my $line ( split /\n/, $logout ) {
      my ($sha, $ts, $msg) = split /\t/, $line, 3;
      next unless $sha && $sha =~ /^[0-9a-f]+$/;
      $ts =~ s/:\d\d \+\S+$//;  # trim seconds and timezone
      $msg = encode_entities($msg // "");
      my $loading = "document.body.innerHTML=\"<p>Checking out $sha ...</p>\"";
      my $reloc = "window.location.href=\"$c->{url}?o=GitCheckout&p=$p&b=" .
                  uri_escape_utf8($sha) . "\"";
      print "<tr>";
      print "<td><tt>$sha</tt></td>";
      print "<td>$ts</td>";
      print "<td><button onclick='$loading;$reloc'>Checkout</button></td>";
      print "</tr>\n";
      print "<tr>";
      print "<td colspan='3'>$msg</td>";
      print "</tr>\n";
    }
    print "</table>\n";
    print "</div>\n";
  } elsif ( $logout =~ /a password is required/ ) {
    print "Add to sudoers: <pre>    www-data ALL=(heikki) NOPASSWD: /usr/bin/git log *</pre>\n";
  }
} # gitstatus

################################################################################
# Do a git pull
################################################################################
sub gitpull {
  my $c = shift;
  my ($p, $gitdir) = git_prepare($c);
  print "<b>Doing a Git pull for <i>'$p'</i> </b><p/>\n";
  my $cmd = "cd " . quotemeta($gitdir) . " && sudo -u heikki /usr/bin/git pull --ff-only 2>&1";
  print "Running git pull --ff-only in $p <p/>\n";
  my $style = $c->{mobile} ? "" : "style='font-size:14px;'";
  my $st = `$cmd` ;
  print { $c->{log} } "gitpull: $st\n";
  my $rc = $?;  # return code
  $st = encode_entities($st);
  print "<pre $style>\n$st\n</pre><p> \n";
  print "Go back to <a href='$c->{url}?o=GitStatus&p=$p&reload=1'><span>Git Status</span></a>\n";
  print "Or the <a href='$c->{url}?o=Graph&reload=1'><span>Main list</span></a>\n";
  cache::clear($c, "gitpull");  # Code changed; force fresh renders on next request
}



################################################################################
# Checkout a git branch for testing
################################################################################
sub gitcheckout {
  my $c = shift;
  my ($p, $gitdir) = git_prepare($c);
  my $b = util::param($c, "b", "");
  util::error("Bad branch name '$b'") unless $b =~ /^[\w\.\-\/]+$/ ;
  print "<b>Checking out branch <i>'$b'</i> in <i>'$p'</i></b><p/>\n";
  my $cmd = "cd " . quotemeta($gitdir) . " && sudo -u heikki /usr/bin/git checkout " . quotemeta($b) . " 2>&1";
  print "Running git checkout $b in $p <p/>\n";
  my $style = $c->{mobile} ? "" : "style='font-size:14px;'";
  my $st = `$cmd` ;
  print { $c->{log} } "gitcheckout: $st\n";
  my $rc = $?;  # return code
  $st = encode_entities($st);
  print "<pre $style>\n$st\n</pre><p> \n";
  if ( $rc && $st =~ /a password is required/ ) {
    print "Make sure you have this line in /etc/sudoers.d/beertracker: <br>\n";
    print "<pre>    www-data ALL=(heikki) NOPASSWD: /usr/bin/git checkout *</pre>\n";
  }
  print "Go back to <a href='$c->{url}?o=GitStatus&p=$p&reload=1'><span>Git Status</span></a>\n";
  print "Or the <a href='$c->{url}?o=Graph&reload=1'><span>Main list</span></a>\n";
  cache::clear($c, "gitcheckout");  # Code changed; force fresh renders on next request
} # gitcheckout



################################################################################
# Report module loaded ok
1;
