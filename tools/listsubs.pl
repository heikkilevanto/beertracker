#!/usr/bin/env perl
# A simple script to list all sub defintions in a given file
# and how many times they are used in that file
# May be deleted once I kill all the old cruft from index.pl

use strict;
use warnings;

my $filename = shift or die "Usage: $0 <perl_file.pl>\n";

open my $fh, '<', $filename or die "Cannot open $filename: $!\n";
my @lines = <$fh>;
close $fh;

# Step 1: Extract subroutine names
print "Finding subs...\n";
my %subs;
my %defs;
for my $i (0 .. $#lines) {
    if ($lines[$i] =~ /^\s*sub\s+([a-zA-Z_]\w*)\b/) {
        $subs{$1} = 0;
        $defs{$1} = $i;
    }
}

# Step 2: Count calls to those subroutines
print "Counting calls... \n";
for my $line (@lines) {
    # Remove comments
    $line =~ s/#.*//;

    for my $sub (keys %subs) {
        # Skip the sub definition line
        next if $line =~ /^\s*sub\s+$sub\b/;
        # Match sub calls: sub_name( or ->sub_name(
        my $count = () = $line =~ /\b$sub\s*\(/g;
        $subs{$sub} += $count;
    }
}

# Step 3: Print results
for my $sub (sort keys %subs) {
    print sprintf("%4d",$subs{$sub})," $sub :$defs{$sub}\n"
      if ( $subs{$sub} == 0 ); # Only unused ones
}
