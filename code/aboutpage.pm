# The About page for my beertracker

package aboutpage;
use strict;
use warnings;
use feature 'unicode_strings';
use utf8;  # Source code and string literals are utf-8
use DBI;    # For connecting to the other environment's database

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
  print "Copyright 2016-2026 Heikki Levanto. <br/>";
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
  print "on '$v->{branch}' " if ( $v->{branch} && $v->{branch} ne "master" );
  print "<br>\n";

  # Current environment DB version
  my ($db_version) = db::queryarray($c, "SELECT v FROM globals WHERE k='db_version'");
  $db_version = 0 unless defined $db_version;
  my $code_db_version = $migrate::CODE_DB_VERSION;
  print "Database version: <b>$db_version</b> ";
  print "(code expects: <b>$code_db_version</b>)";
  if ( $db_version != $code_db_version ) {
    print " <span style='color:red'>MISMATCH - migration needed!</span>";
  }
  print "<br><br>\n";
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
  print "on '$v->{branch}' " if ( $v->{branch} && $v->{branch} ne "master" );
  print "<br>\n";

  # Other environment DB version
  my ($other_dir, $other_label);
  if ( $c->{devversion} ) {
    $other_dir = "../beertracker";
    $other_label = "production";
  } else {
    $other_dir = "../beertracker-dev";
    $other_label = "development";
  }

  my $other_db_path = "$other_dir/beerdata/beertracker.db";
  my $other_db_version = "N/A";
  my $other_code_db_version = "N/A";

  if ( -f $other_db_path ) {
    eval {
      my $other_dbh = DBI->connect("dbi:SQLite:uri=file:$other_db_path?mode=ro",
        "", "", { RaiseError => 1, PrintError => 0 });
      ($other_db_version) = $other_dbh->selectrow_array(
        "SELECT v FROM globals WHERE k='db_version'");
      $other_db_version //= "N/A";
      $other_dbh->disconnect;
    };
    if ($@) {
      $other_db_version = "Error";
    }
  }

  my $other_migrate_file = "$other_dir/code/migrate.pm";
  if ( -f $other_migrate_file ) {
    open my $fh, '<:utf8', $other_migrate_file or print STDERR "Cannot open $other_migrate_file: $!\n";
    my $content = do { local $/; <$fh> };
    close $fh;
    if ( $content =~ /\$\s*CODE_DB_VERSION\s*=\s*(\d+)/ ) {
      $other_code_db_version = $1;
    }
  }

  print ucfirst($other_label) . " database version: <b>$other_db_version</b> ";
  print "(code expects: <b>$other_code_db_version</b>)";
  if ( $other_db_version ne "N/A" && $other_code_db_version ne "N/A"
    && $other_db_version ne $other_code_db_version )
  {
    print " <span style='color:red'>MISMATCH - migration needed!</span>";
  }
  print "<br><br>\n";
  print "<hr/>\n";

  print "Beertracker on GitHub: <ul>";
  print aboutlink("GitHub","https://github.com/heikkilevanto/beertracker");
  print aboutlink("Issues", "https://github.com/heikkilevanto/beertracker/issues?".
       "q=is%3Aissue%20is%3Aopen%20sort%3Aupdated-desc%20-label%3ALater%20-label%3ANextVersion");
  print aboutlink("User manual", "https://github.com/heikkilevanto/beertracker/blob/master/doc/manual.md" );
  print aboutlink("Design doc", "https://github.com/heikkilevanto/beertracker/blob/master/doc/design.md" );
  print "</ul><p>\n";
  print "Other useful links: <ul>";
  print aboutlink("Events", "https://www.beercph.dk/");
  print aboutlink("Untappd", "https://untappd.com");
  print "</ul><p>\n";
  print "<hr/>";

  print "This site uses one session cookie to keep you logged in. <br/>\n";
  print "No third-party cookies or trackers of any kind. <br/>\n";
  print "It collects no personally identifiable information beyond what you enter.<br/>\n";
  print "No information is shared with any third parties. <p>\n";
} # About

################################################################################
# Report module loaded ok
1;
