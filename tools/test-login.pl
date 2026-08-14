#!/usr/bin/perl
# Standalone test for login.pm token functions.
# Run from the repo root: perl tools/test-login.pl

use strict;
use warnings;
use FindBin qw($Bin);
use lib "$Bin/../code";  # so 'require' finds login.pm

# We need a test secret — use a fixed string, not the real secret file.
# Temporarily override $login::SECRET_FILE by using a scalar ref trick:
# Instead, we test the internal functions directly via their package names,
# and monkey-patch read_secret to return a known value.

require "$Bin/../code/login.pm";

# Override read_secret so tests don't need /etc/lsd/login.secret
{ no warnings qw(redefine once);
  *login::read_secret = sub { return "test-secret-value-for-unit-tests" };
}

my $secret = "test-secret-value-for-unit-tests";
my $username = "testuser";
my $pass = 1;

# Test 1: make_token produces a three-part token
my $token = login::make_token($username, $secret);
if ($token && $token =~ /^[^:]+:\d+:[0-9a-f]+$/) {
  print "PASS: make_token produces a valid-looking token\n";
} else {
  print "FAIL: make_token returned unexpected value: '$token'\n";
  $pass = 0;
}

# Test 2: verify_token returns correct username for a valid token
my $got = login::verify_token($token, $secret);
if (defined $got && $got eq $username) {
  print "PASS: verify_token returns correct username '$got'\n";
} else {
  print "FAIL: verify_token returned " . (defined $got ? "'$got'" : "undef") . "\n";
  $pass = 0;
}

# Test 3: tampered token (flip one character in the hmac) is rejected
my $tampered = $token;
$tampered =~ s/([0-9a-f])$/($1 eq 'a' ? 'b' : 'a')/e;
my $result = login::verify_token($tampered, $secret);
if (!defined $result) {
  print "PASS: tampered token correctly rejected\n";
} else {
  print "FAIL: tampered token was accepted, returned '$result'\n";
  $pass = 0;
}

# Test 4: expired token is rejected
my $past_expiry = time() - 1;
my $payload = "$username:$past_expiry";
use Digest::SHA qw(hmac_sha256_hex);
my $hmac = hmac_sha256_hex($payload, $secret);
my $expired_token = "$payload:$hmac";
my $result2 = login::verify_token($expired_token, $secret);
if (!defined $result2) {
  print "PASS: expired token correctly rejected\n";
} else {
  print "FAIL: expired token was accepted, returned '$result2'\n";
  $pass = 0;
}

# Test 5: wrong secret is rejected
my $result3 = login::verify_token($token, "wrong-secret");
if (!defined $result3) {
  print "PASS: token verified with wrong secret correctly rejected\n";
} else {
  print "FAIL: wrong secret was accepted, returned '$result3'\n";
  $pass = 0;
}

print $pass ? "\nAll tests passed.\n" : "\nSome tests FAILED.\n";
exit($pass ? 0 : 1);
