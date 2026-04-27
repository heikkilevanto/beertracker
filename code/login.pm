# Cookie-based authentication for beertracker (and other projects).
#
# Usage in index.fcgi:
#   Build a minimal $c = { cgi => $q } before the full context is assembled,
#   call login::authenticate($c) to set $c->{username}, then after the full $c
#   is built call login::prepare_cookie($c) so htmlhead() can send the cookie.
#
# Reuse: copy or symlink this file to other projects and adjust the config
# block below. All projects sharing $SECRET_FILE and $COOKIE_NAME accept
# each other's cookies.

package login;
use strict;
use warnings;
use feature 'unicode_strings';
use utf8;

use open ':encoding(UTF-8)';
use Digest::SHA qw(hmac_sha256_hex);
use Authen::Htpasswd;
use CGI::Cookie;
use MIME::Base64 qw(decode_base64);
use Cwd;

################################################################################
# Config — adjust per project
################################################################################

my $HTPASSWD_FILE     = "./.htpasswd";
my $HTPASSWD_FALLBACK = "/var/www/html/beertracker/.htpasswd";
my $SECRET_FILE       = "/etc/lsd/login.secret";
my $COOKIE_NAME       = "lsd_login";
my $COOKIE_MAX_AGE    = 14 * 86400;  # 14 days in seconds
my $REALM             = "Lsd";          # shown in Basic Auth browser prompt
my $LOCALHOST_USER    = "heikki";       # username for unauthenticated requests from 127.0.0.1

################################################################################
# Public functions
################################################################################

# authenticate($c, $htpasswd, $allow_anon) — authenticate the request, set $c->{username}.
# Checks the login cookie first; falls back to HTTP Basic credentials.
# Sends a 401 response and sets $c->{username} to "" if neither is present or valid.
# Optional $htpasswd overrides the default $HTPASSWD_FILE path.
# If the resolved htpasswd file is missing, falls back to $HTPASSWD_FALLBACK.
# Optional $allow_anon: if true and no credentials found, sets $c->{username} to ""
# and returns instead of sending 401. Useful for publicly accessible pages.
sub authenticate {
  my $c = shift;
  my $htpasswd = resolve_htpasswd(shift);
  my $allow_anon = shift;
  my $q = $c->{cgi};

  my $secret = read_secret();

  # Try cookie first
  my $token = $q->cookie($COOKIE_NAME);
  if ($token) {
    my $username = verify_token($token, $secret);
    if ($username) {
      if (user_in_htpasswd($username, $htpasswd)) {
        $c->{username} = $username;
        return;
      } else {
        warn "login: cookie user '$username' not authorised by $htpasswd\n";
      }
    } else {
      warn "login: invalid or expired cookie\n";
    }
  }

  # Try HTTP Basic Auth credentials from Authorization header
  my $auth_header = $ENV{HTTP_AUTHORIZATION} || "";
  if ($auth_header =~ /^Basic (.+)$/i) {
    my $decoded = decode_base64($1);
    my ($username, $password) = split /:/, $decoded, 2;
    if ($username && $password && validate_htpasswd($username, $password, $htpasswd)) {
      $c->{username} = $username;
      return;
    } else {
      warn "login: basic auth failed for '" . ($username // "") . "' against $htpasswd\n";
    }
  }

  # Nothing worked — check for localhost fallback, then allow anon or send 401
  if ($ENV{REMOTE_ADDR} && $ENV{REMOTE_ADDR} eq "127.0.0.1") {
    warn "login: no credentials, accepting localhost request as '$LOCALHOST_USER'\n";
    $c->{username} = $LOCALHOST_USER;
    return;
  }
  if ($allow_anon) {
    $c->{username} = "";
    return;
  }
  send_401($q);
  $c->{username} = "";
} # authenticate


# prepare_cookie($c) — build a fresh signed cookie and store in $c->{auth_cookie}.
# Called after the full $c is constructed; htmlhead() attaches it to the response.
# Does nothing if $c->{username} is empty (anonymous / unauthenticated request).
sub prepare_cookie {
  my $c = shift;
  return unless $c->{username};
  my $secret = read_secret();
  my $token = make_token($c->{username}, $secret);
  $c->{auth_cookie} = CGI::Cookie->new(
    -name     => $COOKIE_NAME,
    -value    => $token,
    -expires  => "+${COOKIE_MAX_AGE}s",
    -path     => "/",
    -secure   => 1,
    -httponly => 1,
    -samesite => "Strict",
  );
} # prepare_cookie


# logout() is intentionally not implemented.
# Expiring the cookie is trivial, but the browser caches HTTP Basic credentials
# and re-sends them automatically on the next request, causing login.pm to
# immediately re-issue a fresh cookie. A working logout would require replacing
# the Basic Auth challenge with an HTML login form so the browser never caches
# credentials. Not worth the complexity for a personal app.


################################################################################
# Internal helpers
################################################################################

# resolve_htpasswd($path) — return $path if it exists, otherwise fall back to
# $HTPASSWD_FALLBACK with a note to STDERR. Uses $HTPASSWD_FILE if $path is undef.
sub resolve_htpasswd {
  my $path = shift || $HTPASSWD_FILE;
  return $path if -f $path;
  warn "login: $path not found (cwd=" . (Cwd::getcwd() // "unknown") . "), falling back to $HTPASSWD_FALLBACK\n";
  return $HTPASSWD_FALLBACK;
} # resolve_htpasswd


# user_in_htpasswd($username, $htpasswd) — check that $username exists in the
# htpasswd file (no password check). Returns 1 on success, undef on failure.
sub user_in_htpasswd {
  my ($username, $htpasswd) = @_;
  return undef unless -f $htpasswd;
  my $file = Authen::Htpasswd->new($htpasswd);
  return $file->lookup_user($username) ? 1 : undef;
} # user_in_htpasswd


# make_token($username, $secret) — build a signed token string.
# Format: username:expiry:hmac  where hmac covers "username:expiry".
sub make_token {
  my ($username, $secret) = @_;
  my $expiry = time() + $COOKIE_MAX_AGE;
  my $payload = "$username:$expiry";
  my $hmac = hmac_sha256_hex($payload, $secret);
  return "$payload:$hmac";
} # make_token


# verify_token($token, $secret) — validate signature and expiry.
# Returns the username on success, undef on any failure.
sub verify_token {
  my ($token, $secret) = @_;
  return undef unless $token;

  my ($username, $expiry, $hmac) = split /:/, $token, 3;
  return undef unless $username && $expiry && $hmac;

  # Check signature
  my $payload = "$username:$expiry";
  my $expected = hmac_sha256_hex($payload, $secret);
  return undef unless $hmac eq $expected;

  # Check expiry
  return undef if time() > $expiry;

  return $username;
} # verify_token


# read_secret() — read the HMAC secret from the secret file.
# Dies with a plain error message if the file is missing or empty.
sub read_secret {
  open my $fh, "<", $SECRET_FILE
    or die "login: cannot read secret file $SECRET_FILE: $!\n";
  my $secret = <$fh>;
  close $fh;
  chomp $secret;
  die "login: secret file $SECRET_FILE is empty\n" unless $secret;
  return $secret;
} # read_secret


# validate_htpasswd($username, $password, $htpasswd) — check credentials against .htpasswd.
# Returns 1 on success, undef on failure.
sub validate_htpasswd {
  my ($username, $password, $htpasswd) = @_;
  return undef unless -f $htpasswd;
  my $file = Authen::Htpasswd->new($htpasswd);
  my $user = $file->lookup_user($username);
  return undef unless $user;
  return $user->check_password($password) ? 1 : undef;
} # validate_htpasswd



# send_401($q) — print a 401 response that causes the browser to prompt for
# HTTP Basic credentials and resubmit the request.
sub send_401 {
  my $q = shift;
  print $q->header(
    -status           => "401 Unauthorized",
    -WWW_Authenticate => qq{Basic realm="$REALM"},
    -type             => "text/plain",
  );
  print "Authentication required.\n";
} # send_401

1;
