#!/usr/bin/env perl
use strict;
use warnings;

# Usage: refactorfunc.pl <subname> <sourcefile> <destfile> [<files>...]
my ($sub, $src, $dst, @files) = @ARGV;
die "Usage: $0 <subname> <sourcefile> <destfile> [<file1> ...]\n" unless $sub && $src && $dst;

# Read and modify source file
open my $in, '<', $src or die "Cannot open '$src': $!\n";
my @src_lines = <$in>;
close $in;

my @func_block;
my $in_func = 0;
my $found = 0;
for (my $i = 0; $i <= $#src_lines; $i++) {
    if (!$in_func) {
        # Detect leading comments + sub
        if ($src_lines[$i] =~ /^sub\s+$sub\s*\{/) {
            $in_func = 1;
            $found = 1;
            # include preceding comments
            my $j = $i - 1;
            while ($j >= 0 && $src_lines[$j] =~ /^\s*#/) {
                unshift @func_block, splice(@src_lines, $j, 1);
                $i--;
                $j--;
            }
        }
    }
    if ($in_func) {
        # Stop before next sub or EOF
        if ($i > 0 && $src_lines[$i] =~ /^sub\s+\w+\s*\{/ && $src_lines[$i] !~ /^sub\s+$sub\s*\{/) {
            $in_func = 0;
            $i--;
            next;
        }
        push @func_block, splice(@src_lines, $i, 1);
        $i--;
    }
}

unless ($found) {
    die "Function 'sub $sub' not found in '$src'.\n";
}

# Write updated source file
open my $out_src, '>', $src or die "Cannot write '$src': $!\n";
print $out_src @src_lines;
close $out_src;
print "Removed 'sub $sub' from '$src'.\n";

# Insert into destination
open my $in2, '<', $dst or die "Cannot open '$dst': $!\n";
my @dst_lines = <$in2>;
close $in2;

my $marker = qr/^# --- FUNCTIONS BELOW ---/;
my $pos;
for my $i (0..$#dst_lines) {
    if ($dst_lines[$i] =~ $marker) {
        $pos = $i;
        last;
    }
}
 die "Marker '# --- FUNCTIONS BELOW ---' not found in '$dst'\n" unless defined $pos;

splice(@dst_lines, $pos, 0, @func_block);

open my $out_dst, '>', $dst or die "Cannot write '$dst': $!\n";
print $out_dst @dst_lines;
close $out_dst;
print "Inserted 'sub $sub' into '$dst'.\n";

# Determine files to update calls in
if (!@files) {
    opendir my $dh, '.' or die $!;
    @files = grep { /\.pm\$|\.cgi\$/ && -f \$_ } readdir $dh;
    closedir $dh;
}

my $total = 0;
my $oldpkg = ''; # derive from src filename
if ($src =~ m{([\w_]+)\.pm\$}) {
    $oldpkg = $1;
}
my $newpkg = '';
if ($dst =~ m{([\w_]+)\.pm\$}) {
    $newpkg = $1;
}

foreach my $file (@files) {
    open my $fh, '<', $file or next;
    my @lines = <$fh>;
    close $fh;
    my $count = 0;
    for my $line (@lines) {
        # Skip comment lines
        next if $line =~ /^\s*#/;
        # Skip if inside quotes naively
        next if $line =~ /['"].*\b$sub\s*\(/;
        # Replace oldpkg::sub(), unqualified sub()
        my $orig = $line;
        $line =~ s{\b\Q$oldpkg\E::\Q$sub\E\s*\(}{$newpkg::$sub(}g if $oldpkg;
        $line =~ s{\b\Q$sub\E\s*\(}{$newpkg::$sub(}g;
        $count++ if $line ne $orig;
    }
    if ($count) {
        open my $fo, '>', $file or warn "Cannot write '$file': $!";
        print $fo @lines;
        close $fo;
        print "$file: updated $count calls.\n";
        $total += $count;
    }
}

if ($total) {
    print "Total replacements: $total\n";
    exit 0;
} else {
    die "No call sites updated.\n";
}
