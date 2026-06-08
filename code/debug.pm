# Debug page for beertracker

package debug;
use strict;
use warnings;

use feature 'unicode_strings';
use utf8;  # Source code and string literals are utf-8

use POSIX qw(strftime localtime locale_h);
use File::Basename;
use Cwd qw(abs_path cwd);

my $STARTUP_DIR = abs_path(cwd());



################################################################################
# Debug page
################################################################################

sub debugpage {
  my $c = shift;

  print "<h2>Debug</h2>\n";

  print "<b style='cursor:pointer' onclick='toggleElement(this.nextElementSibling)'>Loaded modules (click to expand)</b>\n";
  print "<div style='display:none'>\n";
  my $tot = 0;
  my $perlcount = 0;
  print "<table class=data>";
  print "<tr><td>Module</td><td>Lines</td><td>Modified</td></tr>\n";
  for my $mod ("./code/index.fcgi", sort keys %INC) {
      my $file = $INC{$mod} || $mod;
      my $short = $mod;
      if ($file =~ m{\./code/}) {
          $perlcount++;
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
  my $perltot = $tot;
  print "<tr><td>= Total</td><td class='num'>$perltot</td><td>= $perlcount files</td></tr>\n";
  print "<tr><td colspan='3'><b>JS files</b></td></tr>\n";
  $tot = 0;
  my $jscount = 0;
  for my $ext (qw(js)) {
    for my $file (sort glob("$STARTUP_DIR/static/*.$ext")) {
      $jscount++;
      my $basename = basename($file);
      my $lines = 0;
      if (open my $fh, '<', $file) {
        $lines++ while <$fh>;
        close $fh;
      }
      my @st = stat($file);
      my $mtime = strftime "%Y-%m-%d %H:%M", localtime $st[9];
      print "<tr><td>$basename</td><td class='num'>$lines</td><td>$mtime</td></tr>\n";
      $tot += $lines;
    }
  }
  my $jstot = $tot;
  print "<tr><td>= Total</td><td class='num'>$jstot</td><td>= $jscount files</td></tr>\n";
  print "<tr><td colspan='3'><b>CSS files</b></td></tr>\n";
  $tot = 0;
  my $csscount = 0;
  for my $ext (qw(css)) {
    for my $file (sort glob("$STARTUP_DIR/static/*.$ext")) {
      $csscount++;
      my $basename = basename($file);
      my $lines = 0;
      if (open my $fh, '<', $file) {
        $lines++ while <$fh>;
        close $fh;
      }
      my @st = stat($file);
      my $mtime = strftime "%Y-%m-%d %H:%M", localtime $st[9];
      print "<tr><td>$basename</td><td class='num'>$lines</td><td>$mtime</td></tr>\n";
      $tot += $lines;
    }
  }
  my $csstot = $tot;
  print "<tr><td>= Total</td><td class='num'>$csstot</td><td>= $csscount files</td></tr>\n";
  my $grandtotal = $perltot + $jstot + $csstot;
  my $totalcount = $perlcount + $jscount + $csscount;
  print "<tr><td>= Grand total</td><td class='num'>$grandtotal</td><td>= $totalcount files</td></tr>\n";
  print "</table>\n";
  print "</div>\n";
  print "<hr style='margin:1em 0' />\n";

  # Log tail
  my $nlines = util::param($c, "nlines") || 200;
  $nlines = int($nlines);
  $nlines = 200 unless $nlines > 0;
  print "<b style='cursor:pointer' onclick='toggleElement(this.nextElementSibling); setTimeout(function(){ this.nextElementSibling.scrollIntoView(false); }.bind(this), 0)'>Log tail ($nlines lines, click to expand)</b>\n";
  print "<div style='display:none'>\n";
  my $logfile = $c->{datadir} . "debug.log";
  if ( ! -f $logfile ) {
    print "<p>No log file found.</p>\n";
  } else {
    my $output = `tail -n $nlines \Q$logfile\E`;
    if ( $? == 0 ) {
      $output =~ s/&/&amp;/g;
      $output =~ s/</&lt;/g;
      $output =~ s/>/&gt;/g;
      print "<pre style='font-size:0.8em;'>$output</pre>\n";
    } else {
      print "<p>Could not read log file.</p>\n";
    }
    my $baseurl = "$c->{url}?o=Debug";
    print "<p>";
    foreach my $n (200, 1000, 5000) {
      print "<a href='$baseurl&amp;nlines=$n'><span>$n lines</span></a> ";
    }
    print "</p>\n";
    print "</div>\n";
  }

} # debugpage


################################################################################
# Report module loaded ok
1;
