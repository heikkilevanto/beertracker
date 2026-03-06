# Debug page for beertracker

package debug;
use strict;
use warnings;

use feature 'unicode_strings';
use utf8;  # Source code and string literals are utf-8

use POSIX qw(strftime localtime locale_h);



################################################################################
# Debug page
################################################################################

sub debugpage {
  my $c = shift;

  print "<h2>Debug</h2>\n";

  print "<b>Loaded modules</b>\n";
  my $tot = 0;
  print "<table class=data>";
  print "<tr><td>Module</td><td>Lines</td><td>Modified</td></tr>\n";
  for my $mod ("./code/index.fcgi", sort keys %INC) {
      my $file = $INC{$mod} || $mod;
      (my $short = $mod) =~ s/\.pm$//;
      if ($file =~ m{\./code/}) {
          my $lines = 0;
          if (open my $fh, '<', $file) {
              $lines++ while <$fh>;
              close $fh;
          }
          $short =~ s/\.\/code\///;
          my @st = stat($file);
          my $mtime = strftime "%Y-%m-%d %H:%M", localtime $st[9];
          print "<tr><td>$short</td><td class='num'>$lines</td><td>$mtime</td></tr>\n";
          $tot += $lines;
      }
  }
  print "<tr><td>= Total</td><td class='num'>$tot</td><td>&nbsp;</td></tr>\n";
  print "</table>\n";

  # Log tail
  print "<h3>Log tail</h3>\n";
  my $logfile = $c->{datadir} . "debug.log";
  if ( ! -f $logfile ) {
    print "<p>No log file found.</p>\n";
  } elsif ( !open my $fh, '<:utf8', $logfile ) {
    print "<p>Cannot open log file: $!</p>\n";
  } else {
    my @lines = <$fh>;
    close $fh;
    my @tail = @lines > 100 ? @lines[-100..-1] : @lines;
    print "<pre style='font-size:0.8em; overflow:auto; max-height:40em;'>";
    for my $line (@tail) {
      $line =~ s/&/&amp;/g;
      $line =~ s/</&lt;/g;
      $line =~ s/>/&gt;/g;
      print $line;
    }
    print "</pre>\n";
  }

} # debugpage


################################################################################
# Report module loaded ok
1;
