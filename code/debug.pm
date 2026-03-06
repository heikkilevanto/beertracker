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

  # Inline JS for collapsible sections and auto-scroll on expand
  print qq{<script>
function toggleDebug(id) {
  var el = document.getElementById(id);
  if (!el) return;
  if (el.style.display === 'none' || el.style.display === '') {
    el.style.display = 'block';
    // Scroll the last line into view so tail is visible
    var last = el.querySelector('pre') || el;
    if (last && last.scrollIntoView) last.scrollIntoView(false);
  } else {
    el.style.display = 'none';
  }
}
</script>};

  print "<b style='cursor:pointer' onclick=\"toggleDebug('mods')\">Loaded modules (click to expand)</b>\n";
  print "<div id='mods' style='display:none'>\n";
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
  print "</div>\n";

  # visible separator between sections, shown even when sections are collapsed
  print "<hr style='margin:1em 0' />\n";

  # Log tail
  print "<b style='cursor:pointer' onclick=\"toggleDebug('logtail')\">Log tail (click to expand)</b>\n";
  print "<div id='logtail' style='display:none'>\n";
  my $logfile = $c->{datadir} . "debug.log";
  if ( ! -f $logfile ) {
    print "<p>No log file found.</p>\n";
  } else {
    # Read only the tail of the file to avoid slurping a very large log
    my $max_bytes = 200_000; # read up to ~200k from EOF
    my @tail;
    if ( open my $fh, '<:raw', $logfile ) {
      binmode $fh, ':utf8';
      my $size = -s $fh;
      my $pos = $size > $max_bytes ? $size - $max_bytes : 0;
      seek $fh, $pos, 0;
      # If we started in the middle of a line, discard the partial first line
      my $first = <$fh> if $pos;
      while ( my $line = <$fh> ) { push @tail, $line }
      close $fh;
      # Keep only the last 200 lines
      @tail = @tail > 200 ? @tail[-200..-1] : @tail;
      print "<pre style='font-size:0.8em;'>";
      for my $line (@tail) {
        $line =~ s/&/&amp;/g;
        $line =~ s/</&lt;/g;
        $line =~ s/>/&gt;/g;
        print $line;
      }
      print "</pre>\n";
    } else {
      print "<p>Cannot open log file: $!</p>\n";
    }
    print "</div>\n";
  }

} # debugpage


################################################################################
# Report module loaded ok
1;
