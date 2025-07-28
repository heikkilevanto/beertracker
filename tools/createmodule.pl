#!/usr/bin/perl
use strict;
use warnings;

my $newmod = shift or die "Usage: $0 modulename\n";
my $newfile = "$newmod.pm";

# Abort if file already exists
if (-e $newfile) {
    die "$newfile already exists.\n";
}

# Read util.pm up to and including the marker line
open my $in, "<", "util.pm" or die "Cannot open util.pm: $!\n";
my @lines;
my $found_marker = 0;
while (<$in>) {
    s/^package util;/package $newmod;/ ;
    push @lines, $_;
    if (/^# --- insert new functions here ---/) {
        $found_marker = 1;
        last;
    }
}
close $in;
die "Marker not found in util.pm\n" unless $found_marker;

# Add trailer
push @lines, "\n";
push @lines, "################################################################################\n";
push @lines, "# Report module loaded ok\n";
push @lines, "1;\n";

# Write new module
open my $out, ">", $newfile or die "Cannot write $newfile: $!\n";
print $out @lines;
close $out;
print "Created $newfile\n";

# Update index.cgi
open my $idx, "<", "index.cgi" or die "Cannot read index.cgi: $!\n";
my @idx_lines = <$idx>;
close $idx;

my $inserted = 0;
for (my $i = 0; $i < @idx_lines; $i++) {
    if ($idx_lines[$i] =~ /^require\s+"\.\/.*?\.pm";/) {
        my $j = $i + 1;
        while ($j < @idx_lines && $idx_lines[$j] =~ /^require\s+"\.\/.*?\.pm";/) {
            $i = $j++;
        }
        splice @idx_lines, $i + 1, 0, qq{require "./$newfile";\n};
        $inserted = 1;
        last;
    }
}
unless ($inserted) {
    die "Could not find require block in index.cgi to insert new module.\n";
}

open my $idx_out, ">", "index.cgi" or die "Cannot write index.cgi: $!\n";
print $idx_out @idx_lines;
close $idx_out;

print "Added require './$newfile'; to index.cgi\n";
print "Remember to: git add $newfile index.cgi\n";
