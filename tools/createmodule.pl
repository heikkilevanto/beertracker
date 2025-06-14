#!/usr/bin/env perl
use strict;
use warnings;

# Usage: createmodule.pl <modulename>
my $mod = shift or die "Usage: $0 <modulename>\n";
my $modfile = "./${mod}.pm";
my $utilfile = "util.pm";
my $indexfile = "index.cgi";

# 1. Fail if module exists
if (-e $modfile) {
    die "Module '$modfile' already exists. Aborting.\n";
}

# 2. Read util.pm up through marker
open my $u, '<', $utilfile or die "Cannot open '$utilfile': $!\n";
my @boiler;
my $marker = qr/^# --- FUNCTIONS BELOW ---/;
while (my $line = <$u>) {
    push @boiler, $line;
    last if $line =~ $marker;
}
close $u;

# Replace package util; with package <mod>;
$boiler[0] =~ s/^package\s+\w+;/package $mod;/;

# Append placeholder
push @boiler, "# insert functions below\n";

# Write new module
open my $out, '>', $modfile or die "Cannot write '$modfile': $!\n";
print $out @boiler;
close $out;
print "Created module '$modfile'.\n";

# 3. Update index.cgi
open my $in, '<', $indexfile or die "Cannot open '$indexfile': $!\n";
my @lines = <$in>;
close $in;

# Find last require of ".pm"
my $last;
for my $i (0..$#lines) {
    $last = $i if $lines[$i] =~ /require\s+"\.\/.*\.pm"/;
}

# Prepare require line
my $req = "require \"./$mod.pm\";\n";
# Check for duplicate
unless (grep { \$_ eq \$req } @lines) {
    splice(@lines, $last+1, 0, $req);
    open my $out2, '>', $indexfile or die "Cannot write '$indexfile': $!\n";
    print $out2 @lines;
    close $out2;
    print "Updated '$indexfile' to require './$mod.pm'.\n";
} else {
    print "Require line already exists in '$indexfile'.\n";
}
