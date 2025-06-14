#!/usr/bin/env perl
use strict;
use warnings;

my ($sub, $from, $to) = @ARGV;
die "Usage: $0 subname fromfile.pm tofile.pm\n" unless $sub && $from && $to;

# Read source file
open my $fh, '<', $from or die "Cannot open $from: $!";
my @lines = <$fh>;
close $fh;

# Extract function with attached comments
my @func;
my @new_lines;
my $in_func = 0;
my $brace_count = 0;
my $func_found = 0;

for (my $i = 0; $i < @lines; $i++) {
    my $line = $lines[$i];

    if (!$in_func && $line =~ /^\s*sub\s+\Q$sub\E\s*\{/) {
        # Capture preceding comments
        my $j = $i - 1;
        while ($j >= 0 && $lines[$j] =~ /^\s*#/) {
            unshift @func, $lines[$j];
            $j--;
        }

        push @func, $line;
        $in_func = 1;
        $func_found = 1;
        $brace_count = ($line =~ tr/{//) - ($line =~ tr/}//);
        next;
    }

    if ($in_func) {
        push @func, $line;
        $brace_count += ($line =~ tr/{//) - ($line =~ tr/}//);

        if ($brace_count == 0) {
            # Function ended — remove trailing comments
            while (@func && $func[-1] =~ /^\s*#/) {
                pop @func;
            }
            $in_func = 0;
        }
    } else {
        push @new_lines, $line;
    }
}

die "Function $sub not found in $from\n" unless $func_found;

# Check for marker before modifying files
my $marker = "# --- insert new functions here ---";
open my $fh_to_check, '<', $to or die "Cannot open $to: $!";
my @to_lines = <$fh_to_check>;
close $fh_to_check;

my $marker_line = undef;
for (0..$#to_lines) {
    if ($to_lines[$_] =~ /\Q$marker\E/) {
        $marker_line = $_;
        last;
    }
}
die "Marker '$marker' not found in $to\n" unless defined $marker_line;

# Rewrite source file
open my $fh_out, '>', $from or die "Cannot write $from: $!";
print $fh_out @new_lines;
close $fh_out;
print "Deleted $sub() from $from\n";

# Insert function into destination file
open my $fh_to_out, '>', $to or die "Cannot write $to: $!";
for my $i (0 .. $#to_lines) {
    print $fh_to_out $to_lines[$i];
    if ($i == $marker_line) {
        print $fh_to_out "\n", @func, "\n";
        print "Inserted $sub() into $to\n";
    }
}
close $fh_to_out;

# Update callers
my @files = @ARGV[3..$#ARGV];
@files = grep { -f $_ } glob("*.pm *.cgi") unless @files;

my $newpkg = $to;
$newpkg =~ s/\.pm$//;

for my $file (@files) {
    print "Processing $file";
    open my $in, '<', $file or die "Cannot open $file: $!";
    my @lines = <$in>;
    close $in;

    my $changes = 0;
    for (@lines) {
        $changes += s{\b\Q$sub\E\s*\(}{$newpkg\::$sub(}g;
    }

    if ($changes) {
        open my $out, '>', $file or die "Cannot write $file: $!";
        print $out @lines;
        close $out;
        print "  $changes replacements\n";
    } else {
      print "\n";
    }
}

print "Done. Remember to: git add $from $to\n";
