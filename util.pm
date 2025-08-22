# Small helper routines

package util;
use strict;
use warnings;

use feature 'unicode_strings';
use utf8;  # Source code and string literals are utf-8

use POSIX qw(strftime localtime locale_h);
use Carp qw(longmess);

# --- insert new functions here ---
# This is a marker for the refactoring scripts
# This file acts as a template for new modules, up to the marker above

################################################################################
# Table of contents
#
# Helpers for normalizing strings
# Helpers for date and timestamps
# Helpers for cgi parameters
# Error handling and debug logging
# The top line and pulldown menu


################################################################################
# Helpers for normalizing strings
################################################################################


# Helper to trim leading and trailing spaces
sub trim {
  my $val = shift // "";  # // checks if value is defined, even if it is a false value
  $val =~ s/^ +//; # Trim leading spaces
  $val =~ s/ +$//; # and trailing
  $val =~ s/\s+/ /g; # and repeated spaces in the middle
  return $val;
}

# Helper to sanitize numbers
sub number {
  my $v = shift || "";
  $v =~ s/,/./g;  # occasionally I type a decimal comma
  return $v if ( $v =~ /^ *x/i ); # X means explicit clearing of the field
  $v =~ s/[^0-9.-]//g; # Remove all non-numeric chars
  $v =~ s/[-.]*$//; # No trailing '.' or '-', as in price 45.-
  $v = 0 unless $v;
  return $v;
}

# Sanitize prices to whole ints
sub price {
  my $v = shift || "";
  $v = number($v);
  $v =~ s/[^0-9-]//g; # Remove also decimal points etc
  return $v;
}

# Split date and weekday, convert weekday to text
# Get the date from Sqlite with a format like '%Y-%m-%d %w'
# The %w returns the number of the weekday.
sub splitdate {
  my $stamp = shift || return ( "(never)", "", "" );
  my ($date, $wd, $time ) = split (' ', $stamp);
  if (defined($wd)) {
    my @weekdays = ( "Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun" );
    $wd = $weekdays[$wd];
  }
  return ( $date, $wd || "", $time || "" );
}

# helper to make a unit displayed in smaller font
sub unit {
  my $v = shift;
  my $u = shift || "XXX";  # Indicate missing units so I see something is wrong
  return "" unless $v;
  return "$v<span style='font-size: xx-small'>$u</span> ";
}


# Helper for logging lists of values
# Puts quotes around the values, separates them by commas, and handles
# undef nicely
sub loglist {
  return join(", ", map { defined($_) ? "'$_'" : "(undef)" } @_);
}

################################################################################
# Helpers for date and timestamps
################################################################################

# Helper to get a date string, with optional delta (in days)
sub datestr {
  my $form = shift || "%F %T";  # "YYYY-MM-DD hh:mm:ss"
  my $delta = shift || 0;  # in days, may be fractional. Negative for ealier
  my $exact = shift || 0;  # Pass non-zero to use the actual clock, not starttime
  my $starttime = time();
  my $clockhours = strftime("%H", localtime($starttime));
  $starttime = $starttime - $clockhours*3600 + 12 * 3600;
    # Adjust time to the noon of the same date
    # This is to fix dates jumping when script running close to miodnight,
    # when we switch between DST and normal time. See issue #153
  my $usetime = $starttime;
  if ( $form =~ /%T/ || $exact ) { # If we want the time (when making a timestamp),
    $usetime = time();   # base it on unmodified time
  }
  my $dstr = strftime ($form, localtime($usetime + $delta *60*60*24));
  return $dstr;
} # datestr


################################################################################
# Helpers for cgi parameters
################################################################################

# Get a cgi parameter
sub param {
  my $c = shift;
  my $tag = shift;
  my $def = shift || "";
  util::error("No context c ") unless $c;
  util::error("No cgi in c") unless $c->{cgi};
  my $val = $c->{cgi}->param($tag) // $def;
  $val =~ s/[^a-zA-ZñÑåÅæÆøØÅöÖäÄéÉáÁāĀüÜß\/ 0-9.,&:\(\)\[\]?%-]/_/g;
  return $val;
}

sub paramnumber {
  my $c = shift;
  my $tag = shift;
  my $def = shift || "";
  my $val = param($c, $tag, $def);
  $val = number($val);
  return $val;
}

################################################################################
# Error handling and debug logging
################################################################################

# Helper to make an error message
sub error {
  my $msg = shift;
  print "\n\n";  # Works if have sent headers or not
  print "<pre>\n";
  $msg = "ERROR  <br>\n$msg\n\n";
  $msg .= longmess("Stack Trace:");
  print "$msg\n";
  print STDERR "ERROR: $msg\n";
  exit();
}

# Helper to get version info
# Takes a relative dir path, defaults to the current one
# A bit tricky code, but seems to work
sub getversioninfo {
    my ($file, $namespace) = @_;
    $file = "$file/VERSION.pm";
    $namespace ||= 'VersionTemp' . int(rand(1000000));

    my $code = do {
        open my $fh, '<', $file or error("Can't open $file: $!");
        local $/;
        <$fh>;
    };

    # Replace package name with unique one
    $code =~ s/\bpackage\s+Version\b/package $namespace/;

    my $full = "package main; no warnings; eval q{$code};";
    my $ok = eval $full;
    error( "Error loading $file: $@") if $@;

    no strict 'refs';
    my $func = "${namespace}::version_info";
    return $func->();
}

################################################################################
# Top line, including the Show menu
################################################################################

# Return the current stats: Drinks, blood alc, and money for today
sub topstats {
  my $c = shift;
  my $sql = "select
   strftime ( '%Y-%m-%d', 'now', 'localtime', '-06:00' ) as today,
   strftime ( '%Y-%m-%d', timestamp, '-06:00' ) as effdate,
   strftime ( '%w', timestamp, '-06:00' ) as wday,
   julianday(strftime('%Y-%m-%d', 'now', 'localtime', '-06:00')) -
      julianday(strftime('%Y-%m-%d', timestamp, '-06:00')) AS daydiff,
   sum(price) as price,
   sum(stdrinks) as drinks
 from GLASSES
 where username = ?
 and effdate = ( select max (strftime('%Y-%m-%d', timestamp, '-06:00' ) ) from GLASSES )
   ";
  my $rec = db::queryrecord($c, $sql, $c->{username});
  util::error("Something wrong in topstats query: $sql") unless ($rec);
  return "" if ( $rec->{daydiff} > 6 );
  my ($date, $wday) = splitdate( "$rec->{effdate} $rec->{wday}" );
  my $ba = mainlist::bloodalc( $c, $rec->{effdate});
  my $banow = $ba->{now};
  if ( $banow > 1 ) {
    $banow = sprintf("%1.1f", $banow);
  } elsif ( $banow > 0 ) {
    $banow = sprintf("%1.2f", $banow);
  } else {
    $banow = "";
  }
  $banow =~ s/^0//;
  my $bamax = $ba->{max};
  if ( $bamax > 1 ) {
    $bamax = sprintf("%1.1f", $bamax);
  } elsif ( $bamax > 0 ) {
    $bamax = sprintf("%1.2f", $bamax);
  } else {
    $bamax = "";
  }
  $bamax =~ s/^0//;
  my $balc = $bamax;
  if ( $banow && ($banow ne $bamax) ) {
    $balc .= "-$banow";
  }
  my $s = "";
  my $border = "2px";
  if ( $rec->{daydiff} ) {
    $wday = " <b>$wday</b>: ";
    $border = "1px";
  } else {
    $wday = " ";
  }
  my $color = "";
  $color = "white"  if ($rec->{drinks} >= 0.1 );
  $color = "yellow" if ($rec->{drinks} >= 4 );
  $color = "orange" if ($rec->{drinks} >= 7 );
  $color = "red" if ($rec->{drinks} >=10 );
  $color = "#f409c9" if ($rec->{drinks} >=13 ); # pinkish purple
  if ($rec->{drinks} >= 10) {
    $rec->{drinks} = sprintf("%1.0f", $rec->{drinks}) ;
  } elsif ($rec->{drinks} > 0) {
    $rec->{drinks} = sprintf("%1.1f", $rec->{drinks}) ;
  } else  {
    $rec->{drinks} = "0";
  }
  $s .= "&nbsp;";
  if ( $color ) {
    $s .= "<span style='font-size: small; border:$border solid $color'>";
    $s .= $wday;
    $s .=  util::unit($rec->{price}, ".-") if ($rec->{price});
    $s .=  util::unit($rec->{drinks},"d") if ($rec->{drinks});
    $s .=  util::unit($balc, "/₀₀") ;
    $s .= "&nbsp;";
    $s .= "</span>";
  }
  return $s;
} # topstats

# The top bar, on every page
sub topline {
  my $c = shift; # context;
  my $s = "";
  $s .= "<span style='white-space: nowrap;'>\n";
  $s .= showmenu($c);
  my $name = "Footracker";
  if ( $c->{devversion} ) {
    $name =~ s/tracker/-DEV/;
  }
  $s .= $name;
  my $v = Version::version_info();
  $s .= "&nbsp;\n";
  $s .= "$v->{tag}+$v->{commits}";
  $s .= "+" if ($v->{dirty});
  $s .= "&nbsp;\n";

  $s .= topstats($c);

  $s .= "</span>";
  $s .= "<hr>\n";
} # topline


sub showmenu {
  my $c = shift; # context;
  my $s = "";
  my $prod = "";
  if ( $c->{devversion} ) {
    $prod = '{ label: "Get Production Data", url: "o=CopyProdData" },' ;
  }
  my $gitfuncs = "";
  if ( $c->{username} eq "heikki" ) {
    $gitfuncs = '{ label: "Git Status", url: "o=GitStatus" },';
              #  '{ label: "Git Pull", url: "o=GitPull" },' ;
  }
  my $current = "o=$c->{op}";

  $s .= <<END;
    <button id='menu-toggle'>☰ Menu</button>
    <div id='menu'></div>
    <script>
      var menuData = {
        currentLabel: "$current",
        menu: [
          { label: "Main ...", children: [
            { label: "List only", url: "o=Full" },
            { label: "With Graph", url: "o=Graph" },
            { label: "Beer Board", url: "o=Board" },
          ]},
          { label: "Stats ...", children: [
            { label: "Months", url: "o=Months" },
            { label: "Years", url: "o=Years" },
            { label: "Data", url: "o=DataStats" },
            { label: "Ratings", url: "o=Ratings" },
          ]},
          { label: "List / Edit ...", children: [
            { label: "Brews", url: "o=Brews" },
            { label: "Locations", url: "o=Locations" },
            { label: "Comments", url: "o=Comment" },
            { label: "Persons", url: "o=Persons" },
          ]},
          { label: "More ...", children: [
            { label: "Download your data", url: "o=Export" },
            $prod
            $gitfuncs
            { label: "About", url: "o=About" },
          ]},
        ] };
      initMenu(menuData, "menu", "menu-toggle" );
    </script>
END
  return $s;
}

################################################################################
# Old stuff
################################################################################
# Some helpers from the old index.cgi. For now they are not used at all.
# Kept here for future reference, in case I wish to reintroduce them.

# # Helper to make a google link
#sub glink {
#   my $qry = shift;
#   my $txt = shift || "Google";
#   return "" unless $qry;
#   $qry = uri_escape_utf8($qry);
#   my $lnk = "&nbsp;<i>(<a href='https://www.google.com/search?q=$qry'" .
#     " target='_blank' class='no-print'><span>$txt</span></a>)</i>\n";
#   return $lnk;
# }

#
# # Helper to make a Untappd search link
#sub utlink {
#   my $qry = shift;
#   my $txt = shift || "Untappd";
#   return "" unless $qry;
#   $qry = uri_escape_utf8($qry);
#   my $lnk = "<i>(<a href='https://untappd.com/search?q=$qry'" .
#     " target='_blank' class='no-print'><span>$txt<span></a>)</i>\n";
#   return $lnk;
# }

#sub maplink {
#   my $g = shift;
#   my $txt = shift || "Map";
#   return "" unless $g;
#   my ( $la, $lo, undef ) = geo($g);
#   my $lnk = "<a href='https://www.google.com/maps/place/$la,$lo' " .
#   "target='_blank' class='no-print'><span>$txt</span></a>";
#   return $lnk;
# }


################################################################################
# Report module loaded ok
1;
