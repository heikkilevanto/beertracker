#!/usr/bin/perl

# Perl cross-refernce. Created with ChatGtp and modified by myself

# TODO - Check loose (unqualified) calls, if made in a module that is not
# where the func is defined (probably after refactoring the func to its
# own module, it may make calls to its prev module)


use strict;
use warnings;
use File::Basename;

my $targetsub = $ARGV[0] || "";
my $dir = '.';
my $fileglobs = "$dir/*.cgi $dir/*.pm" ;
my @files = glob($fileglobs);


#my $trace = "selectbrewsubtype";
my $trace = "NO TRACE";

my (%definitions, %calls, %lengths);

# First pass: find all sub definitions
for my $file (@files) {
    open my $fh, '<', $file or die "Can't open $file: $!";
    my $line_num = 0;
    my $name = "";
    while (my $line = <$fh>) {
        $line_num++;
        $lengths{$name}++;
        if ($line =~ /^\s*sub\s+([\w:]+)/) {
            $name = $1;
            $definitions{$name} = [$file, $line_num];
            $lengths{$name} = 0;
            print "Definition of $name at $file: $line_num \n" if ( $name=~/$trace/ );
        }
    }
    close $fh;
}

# Second pass: find all function calls
for my $file (@files) {
    open my $fh, '<', $file or die "Can't open $file: $!";
    my $line_num = 0;
    my $sub_name = "";
    my $filesub = $file;
    while (my $line = <$fh>) {
        $line_num++;
        if ( $line =~ /^\s*sub\s+([\w]+)/ ) { # Skip sub itself
          $sub_name = $1;
          $filesub = "$file: $sub_name()";
          print "Found sub $filesub on line $line_num\n" if ( $line=~/$trace/ );
          next;
        }
        while ($line =~ /\b([\w]+::)?([\w]+)\s*\(/g) {
            my $name = $2;
            push @{ $calls{$name}{$filesub} }, $line_num;
            print "Use of $name at $filesub: $line_num as number " .
              scalar(@{ $calls{$name}{$filesub} }). " \n" if ( $name=~/$trace/ );
        }
    }
    close $fh;
}

# Print cross reference
for my $func (sort keys %definitions) {
    next if ( $targetsub && $targetsub ne $func );
    my ($file, $line) = @{ $definitions{$func} };
    print "Function '$func' defined in $file: $line ($lengths{$func} lines long)\n";
    if ($calls{$func}) {
        #print "  Called from:\n";
        for my $caller (sort keys %{ $calls{$func} }) {
            my @lines = @{ $calls{$func}{$caller} };
            print "    $caller: @lines\n";
        }
    } else {
        print "  NOT CALLED\n";
    }
    print "\n";
}
