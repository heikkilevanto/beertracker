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
  for my $mod ("./code/index.cgi", sort keys %INC) {
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

} # debugpage


################################################################################
# Report module loaded ok
1;
