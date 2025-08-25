# The About page for my beertracker

package aboutpage;
use strict;
use warnings;

use feature 'unicode_strings';
use utf8;  # Source code and string literals are utf-8

use POSIX qw(strftime localtime locale_h);



# Helper to make a link on the about page
# These links should have the URL visible
# They all are inside a bullet list, so we enclose them in li tags
# Unless third argument gives another tag to use
# Displaying only a part of the url on narrow devices
sub aboutlink {
  my $name = shift;
  my $url = shift;
  my $tag = shift || "li";
  my $long = $url;
  $long =~ s/^https?:\/\/(www)?\.?\/?//i;  # remove prefixes
  $long =~ s/\/$//;
  $long =~ s/\?.*$//; # Remove parameters
  my $short = $1 if ( $long =~ /([^#\/]+)\/?$/ );  # last part of the path
  return "<$tag>$name: <a href='$url' target='_blank' > ".
    "<span class='only-wide'>$long</span>".
    "<span class='no-wide'>$short</span>".
  "</a></$tag>\n";
}



################################################################################
# About page
################################################################################

sub about {
  my $c = shift;

  print "<h2>Beertracker</h2>\n";
  print "Copyright 2016-2025 Heikki Levanto. <br/>";
  print "Beertracker is my little script to help me remember all the beers I meet.\n";
  print "It is Open Source (GPL v2)\n";
  print "<hr/>";

  my $v = Version::version_info();
  print "This is ";
  print "DEVELOPMENT " if ( $c->{devversion} );
  print "version $v->{tag} ";
  print "plus $v->{commits} commits " if ( $v->{commits} );
  print "<br>\n";
  print "commit $v->{commit} from $v->{date} ";
  print "on '$v->{branch}' " if ( $v->{branch} ne "master" );
  print "<br/><br/>\n";
  if ( $c->{devversion} ) {
    print "The production version is ";
    $v = util::getversioninfo("../beertracker");
  } else {
    print "The development version is ";
    $v = util::getversioninfo("../beertracker-dev");
  }
  print "$v->{tag} ";
  print "plus $v->{commits} commits " if ( $v->{commits} );
  print "<br>\n";
  print "commit $v->{commit} from $v->{date} ";
  print "on '$v->{branch}' " if ( $v->{branch} ne "master" );
  print "<hr/>\n";

  print "Beertracker on GitHub: <ul>";
  print aboutlink("GitHub","https://github.com/heikkilevanto/beertracker");
  print aboutlink("Issues", "https://github.com/heikkilevanto/beertracker/issues?".
       "q=is%3Aissue%20is%3Aopen%20sort%3Aupdated-desc%20-label%3ALater%20-label%3ANextVersion");
  print aboutlink("Edit","https://github.dev/heikkilevanto/beertracker/tree/master");

  print aboutlink("User manual", "https://github.com/heikkilevanto/beertracker/blob/master/manual.md" );
  print "</ul><p>\n";
  #print "Some of my favourite bars and breweries<ul>";
  #for my $k ( sort keys(%links) ) {  # TODO - Get these from the database somehow. Or skip
  #  print aboutlink($k, $links{$k});
  #}
  print "</ul><p>\n";
  print "Other useful links: <ul>";
  print aboutlink("Events", "https://www.beercph.dk/");
  #print aboutlink("Ratebeer", "https://www.ratebeer.com");   # RIP RB Feb 2025
  print aboutlink("Untappd", "https://untappd.com");
  print "</ul><p>\n";
  print "<hr/>";

  print "Shorthand for drink volumes<br/><ul>\n";
  for my $k ( keys(%glasses::volumes) ) {
    print "<li><b>$k</b> $glasses::volumes{$k}</li>\n";
  }
  print "</ul>\n";
  print "You can prefix them with 'h' for half, as in HW = half wine = 37cl<br/>\n";
  print "Of course you can just enter the number of centiliters <br/>\n";
  print "Or even ounces, when traveling: '6oz' = 18 cl<br/>\n";

  print "<p><hr>\n";
  print "This site uses no cookies, and collects no personally identifiable information<p>\n";


  print "<p><hr/>\n";
  #print "<b>Debug info </b><br/>\n";  # TODO - Add new debug helpers here if needed
  #print "&nbsp; <a href='$url?o=Datafile&maxl=30' target='_blank' ><span>Tail of the data file</span></a><br/>\n";
  #print "&nbsp; <a href='$url?o=Datafile'  target='_blank' ><span>Download the whole data file</span></a><br/>\n";
  exit();
} # About


################################################################################
# Report module loaded ok
1;
