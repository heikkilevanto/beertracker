# Part of my beertracker
# Single source of truth for foreign currencies: codes, DKK rates, aliases.
# Used by postglass (price entry) and mainlist (sumline totals).
# Notes store canonical codes; sumline may display short symbols instead.

package currencies;
use strict;
use warnings;
use feature 'unicode_strings';
use utf8;  # Source code and string literals are utf-8

my @CURRENCIES = (
  { code => "EUR", rate => 7.5,  aliases => [qw(e eur)], symbol => "€" },
  { code => "USD", rate => 6.3,  aliases => [qw(u usd)], symbol => "\$" },  # 'u' matches the manual
  { code => "GBP", rate => 8.5,  aliases => [qw(p gbp)], symbol => "£" },
  { code => "SEK", rate => 0.65, aliases => [qw(s sek)] },  # no short symbol
);

my %by_alias;
foreach my $cur (@CURRENCIES) {
  foreach my $alias (@{ $cur->{aliases} }) {
    $by_alias{lc $alias} = $cur;
  }
}

# Lookup any alias or full code (case-insensitive). Returns { code, rate, ... } or undef.
sub lookup {
  my $token = shift;
  return undef unless defined $token && $token ne "";
  return $by_alias{lc $token};
} # lookup

# Canonical code for a note/currency token, or undef.
sub code {
  my $token = shift;
  my $cur = lookup($token);
  return undef unless $cur;
  return $cur->{code};
} # code

# Short display symbol for a code (€, $, £), or the code itself if none.
sub symbol {
  my $token = shift;
  my $cur = lookup($token);
  return undef unless $cur;
  return $cur->{symbol} if $cur->{symbol};
  return $cur->{code};
} # symbol

# All known aliases (lowercase), for price-suffix matching.
sub aliases {
  return sort keys %by_alias;
} # aliases

# Canonical codes: "EUR", "USD", ...
sub codes {
  return map { $_->{code} } @CURRENCIES;
} # codes

1; # currencies.pm loaded ok
