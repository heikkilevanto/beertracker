#!/usr/bin/env perl
use strict;
use warnings;
use File::Path qw(make_path);

# To run the tests, type 'prove' on the cmd line, in the main directrory
# It will run all tests under .../t

my $mod = shift or die "Usage: $0 modulename\n";
$mod =~ s/\.pm$//;
my $file = "t/$mod.t";

make_path("t") unless -d "t";

open my $fh, '>', $file or die "Can't write $file: $!";
print $fh <<"END";
#!/usr/bin/env perl
use strict;
use warnings;
use Test::More;

use lib '.';
use $mod;

# Add your tests here
ok(1, '$mod loaded');

done_testing;
END

close $fh or die "Can't close $file: $!";
chmod 0755, $file;

print "Created $file\n";
