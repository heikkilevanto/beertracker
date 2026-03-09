# In-process cache helpers for the FastCGI beertracker.
# The cache lives in $c->{cache}, which points to a hash declared outside the
# FastCGI loop so it persists across requests for the lifetime of the process.
# Invalidate the whole cache after every POST (data may have changed).

package cache;
use strict;
use warnings;
use feature 'unicode_strings';
use utf8;

# Process-lifetime counters (survive across requests).
my $hits   = 0;
my $misses = 0;
my $clears = 0;

# Return cached value for $key, or undef if not present.
sub get {
  my $c   = shift;
  my $key = shift;
  if ( exists $c->{cache}{$key} ) {
    $hits++;
    return $c->{cache}{$key};
  }
  $misses++;
  return undef;
} # get

# Store $value under $key.
sub set {
  my $c     = shift;
  my $key   = shift;
  my $value = shift;
  $c->{cache}{$key} = $value;
} # set

# Wipe the entire cache (call after a successful POST).
sub clear {
  my $c      = shift;
  my $reason = shift || "";
  $clears++;
  my $entries = scalar keys %{ $c->{cache} };
  my $msg = "cache: cleared $entries entries";
  $msg .= " ($reason)" if $reason;
  print { $c->{log} } "$msg\n";
  %{ $c->{cache} } = ();  # Empty in-place so the $cache ref in index.fcgi stays valid
} # clear

# Return a one-line stats summary for logging.
sub stats {
  my $c      = shift;
  my $entries = scalar keys %{ $c->{cache} };
  return "cache: entries=$entries hits=$hits misses=$misses clears=$clears";
} # stats

1;
