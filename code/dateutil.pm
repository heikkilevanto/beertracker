# Date and time helpers for BeerTracker
#
# Consolidated from util.pm and taphistory.pm. The -6h "effective day"
# convention for late-night drinking lives only in eff_day_of; reldate and
# other helpers derive from it so the rule has a single source of truth.

package dateutil;

use strict;
use warnings;

use feature 'unicode_strings';
use utf8;
use open ':encoding(UTF-8)';

use Time::Local qw(timelocal);
use POSIX qw(strftime);


################################################################################
# Helpers for date and timestamps
################################################################################

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

# Helper to get a date string, with optional delta (in days)
sub datestr {
  my $form = shift || "%F %T";  # "YYYY-MM-DD hh:mm:ss"
  my $delta = shift || 0;  # in days, may be fractional. Negative for ealier
  my $exact = shift || 0;  # Pass non-zero to use the actual clock, not starttime
  my $starttime = time();
  my $clockhours = strftime("%H", localtime($starttime));
  $starttime = $starttime - $clockhours*3600 + 12 * 3600;
    # Adjust time to the noon of the same date
    # This is to fix dates jumping when script running close to midnight,
    # when we switch between DST and normal time. See issue #153
  my $usetime = $starttime;
  if ( $form =~ /%[THM]/ || $exact ) { # If we want the time (when making a timestamp),
    $usetime = time();   # base it on unmodified time
  }
  my $dstr = strftime ($form, localtime($usetime + $delta *60*60*24));
  return $dstr;
} # datestr

# Helper to get current timestamp
sub now {
  return datestr("%F %T", 0, 1);
} # now

# Effective day of a local timestamp, shifted by the app's -6h day convention
# so late-night drinking counts as the previous day. Returns "YYYY-MM-DD",
# or "" on undef/malformed input. This is the single source of truth for the
# -6h rule.
sub eff_day_of {
  my ($ts) = @_;
  my $ep = ts_epoch($ts);
  return "" unless defined $ep;
  $ep -= 6 * 3600;
  my ($Y, $M, $D) = (localtime($ep))[5, 4, 3];
  return sprintf("%04d-%02d-%02d", $Y + 1900, $M + 1, $D);
} # eff_day_of

# Parse an ISO "YYYY-MM-DD HH:MM:SS" timestamp to a local epoch (or undef).
sub ts_epoch {
  my ($ts) = @_;
  return undef unless $ts;
  $ts =~ /^(\d{4})-(\d{2})-(\d{2})[ T](\d{2}):(\d{2}):(\d{2})/;
  return undef unless $1;
  return timelocal($6, $5, $4, $3, $2 - 1, $1 - 1900);  # local
} # ts_epoch

# Add (or subtract) a number of calendar days to a "YYYY-MM-DD" string.
# Uses local noon so DST transitions do not shift the derived date.
sub date_plus_days {
  my ($datestr, $k) = @_;
  $datestr =~ /^(\d{4})-(\d{2})-(\d{2})/;
  my $epoch = timelocal(0, 0, 12, $3, $2 - 1, $1 - 1900) + $k * 86400;
  my ($Y, $M, $D) = (localtime($epoch))[5, 4, 3];
  return sprintf("%04d-%02d-%02d", $Y + 1900, $M + 1, $D);
} # date_plus_days

# Whole-day difference (b - a) between two "YYYY-MM-DD" strings, at local noon.
sub day_diff {
  my ($a, $b) = @_;
  $a =~ /^(\d{4})-(\d{2})-(\d{2})/;
  my $ea = timelocal(0, 0, 12, $3, $2 - 1, $1 - 1900);
  $b =~ /^(\d{4})-(\d{2})-(\d{2})/;
  my $eb = timelocal(0, 0, 12, $3, $2 - 1, $1 - 1900);
  return int(($eb - $ea) / 86400);
} # day_diff

# Convert a YYYY-MM-DD date string to a relative label (today, yesterday, or the
# date itself). Derives today/yesterday from the canonical -6h effective day.
sub reldate {
  my $date = shift || return "";
  my $today     = eff_day_of(now());
  my $yesterday = date_plus_days($today, -1);
  return "today"     if $date eq $today;
  return "yesterday" if $date eq $yesterday;
  return $date;
} # reldate

# Normalize a lifecycle date value. Dates may be partial (a year, e.g. "2019")
# and are stored as entered; full dates are YYYY-MM-DD.
# - empty string clears the field (this is how you reopen / re-release)
# - "Y" means yesterday
# - "-Nd" means N days before today (e.g. "-3d")
# - anything else passes through unchanged
sub normalize_date {
  my $c = shift;
  my $val = util::trim(shift // '');
  return '' unless $val;
  if ( $val =~ /^Y$/i ) {
    return datestr("%F", -1, 1);
  }
  if ( $val =~ /^-(\d+)d$/i ) {
    return datestr("%F", -$1, 1);
  }
  return $val;
} # normalize_date

# Parse a beerboard datetime input string into a SQL-safe 'YYYY-MM-DD HH:MM:SS' string.
# Returns undef for empty input (means "current taps / now").
# Supports (case-insensitive where noted):
#   YYYY-MM-DD HH:MM  → as-is
#   YYYY-MM-DD HH     → YYYY-MM-DD HH:00:00
#   YYYY-MM-DD[T ]HH:MM → as-is (ISO T separator)
#   YYYY-MM-DD        → today's time + that date
#   HH:MM             → today at that time (local)
#   HH                → today at that hour
#   HHMM              → today at HH:MM (4-digit, no colon)
#   Y                 → yesterday (1 day back)
#   YY                → 2 days back (N Y's = N days back)
#   -N or -Nd         → N days ago, at now's time
sub parse_beerboard_date {
  my $c = shift;
  my $val = util::trim(shift // '');
  return undef unless $val;

  # Combined datetime: YYYY-MM-DD HH:MM or YYYY-MM-DD HH or YYYY-MM-DDTHH:MM
  if ( $val =~ /^(\d{4}-\d{2}-\d{2})[T ]+(\d{1,2})(?::(\d{2}))?$/ ) {
    my ($d, $h, $m) = ($1, $2, $3 // 0);
    return sprintf("%s %02d:%02d:00", $d, $h, $m);
  }

  # Full date only: YYYY-MM-DD → use current time
  if ( $val =~ /^(\d{4}-\d{2}-\d{2})$/ ) {
    return $1 . " " . strftime('%H:%M:%S', localtime(time()));
  }

  # Y / YY / YYY / ... → N days ago (number of Y's = days back)
  if ( $val =~ /^y+$/i ) {
    return datestr("%F %T", -length($val), 1);
  }

  # -N or -Nd → N days ago
  if ( $val =~ /^-(?:(\d+)d?)$/ ) {
    return datestr("%F %T", -$1, 1);
  }

  # Time only: HH:MM → today at that time
  if ( $val =~ /^(\d{1,2}):(\d{2})$/ ) {
    my $today = strftime('%Y-%m-%d', localtime(time()));
    return sprintf("%s %02d:%02d:00", $today, $1, $2);
  }

  # Time only: HH → today at that hour
  if ( $val =~ /^(\d{1,2})$/ ) {
    my $today = strftime('%Y-%m-%d', localtime(time()));
    return sprintf("%s %02d:00:00", $today, $1);
  }

  # Time only: HHMM (4 digits, no colon) → today at HH:MM
  if ( $val =~ /^(\d{2})(\d{2})$/ ) {
    my $today = strftime('%Y-%m-%d', localtime(time()));
    return sprintf("%s %02d:%02d:00", $today, $1, $2);
  }

  # Unrecognized → undef (current taps)
  print { $c->{log} } "parse_beerboard_date: unrecognized input '$val'\n"
    if $c->{devversion};
  return undef;
} # parse_beerboard_date


################################################################################
# Report module loaded ok
1;
