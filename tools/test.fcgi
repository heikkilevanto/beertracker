#!/usr/bin/perl
use strict;
use warnings;
use utf8;
use CGI::Fast qw(-utf8);
use POSIX qw(strftime);

my $count      = 0;
my $pid        = $$;
my $start_time = time();
my $log        = "";        # persists across requests
my $mtime      = (stat($0))[9];  # mtime of this script at startup

while (my $q = CGI::Fast->new()) {
    $count++;
    print STDERR "test.fcgi: pid=$pid request=$count\n";

    # If the script file has been modified, send a redirect and exit so
    # mod_fcgid spawns a fresh process (which loads the new code) for the next request
    if ((stat($0))[9] != $mtime) {
        print $q->header(-status => '302 Found', -location => $q->url());
        exit(0);
    }

    # Handle POST: append submitted text to the persistent log
    if ($q->request_method() eq 'POST') {
        my $text = $q->param('text') // '';
        $text =~ s/^\s+|\s+$//g;   # trim
        if ($text ne '') {
            $log .= "\n" if $log ne '';
            $log .= $text;
            print STDERR "Posted '$text' \n";
        }
        # Redirect to GET to avoid form resubmission on reload
        print $q->header(-status => '303 See Other', -location => $q->url());
        next;
    }

    my $now    = time();
    my $age    = $now - $start_time;
    my $start_str = strftime("%Y-%m-%d %H:%M:%S", localtime($start_time));
    my $now_str   = strftime("%Y-%m-%d %H:%M:%S", localtime($now));
    my $mtime_str = strftime("%Y-%m-%d %H:%M:%S", localtime($mtime));

    # Escape log for HTML display
    (my $log_html = $log) =~ s/&/&amp;/g;
    $log_html =~ s/</&lt;/g;
    $log_html =~ s/>/&gt;/g;
    $log_html =~ s/\n/<br>\n/g;

    print $q->header(-type => 'text/html', -charset => 'UTF-8');

    # Buffer all body output into a scalar via select().
    # select() changes the default filehandle for print without touching the
    # FCGI::Stream handle itself (which doesn't support open-based dup).
    my $body = '';
    open my $buf, '>:utf8', \$body or die "Cannot open scalar buffer: $!";
    my $old_fh = select $buf;

    print qq{<!DOCTYPE html>
<html>
<head>
  <meta charset="UTF-8">
  <title>FastCGI demo</title>
  <style>
    body { font-family: monospace; padding: 2em; }
    table { border-collapse: collapse; }
    td { padding: 4px 16px; }
    td:first-child { color: #888; }
    td:last-child { font-weight: bold; }
    .note { margin-top: 2em; color: #555; font-size: 0.9em; }
    .logbox { margin-top: 1.5em; border: 1px solid #ccc; padding: 0.8em 1em; min-height: 2em; background: #f9f9f9; }
    form { margin-top: 1em; }
    input[type=text] { font-family: monospace; width: 30em; }
  </style>
</head>
<body>
<h2>FastCGI demo</h2>
<table>
  <tr><td>PID</td><td>$pid</td></tr>
  <tr><td>Requests handled</td><td>$count</td></tr>
  <tr><td>Process started</td><td>$start_str</td></tr>
  <tr><td>Process age</td><td>$age seconds</td></tr>
  <tr><td>Current time</td><td>$now_str</td></tr>
  <tr><td>Script mtime</td><td>$mtime_str</td></tr>
</table>
<p class="note">
  Reload the page repeatedly: <b>Requests handled</b> and <b>Process age</b> grow,
  while <b>PID</b> and <b>Process started</b> stay fixed — the process is in memory.<br>
  Edit and save this script: the next request detects the changed <b>Script mtime</b> and exits,
  so mod_fcgid spawns a fresh process — counter and log reset automatically, no Apache restart needed.<br>
  A manual <code>sudo apache2ctl restart</code> also resets everything.
  <pre>
  AE: Æ æ
  AA: Å å
  O/: Ø ø
  A:  Ä ä
  O:  Ö ö
  </pre>
</p>

<h3>Persistent log</h3>
<div class="logbox">$log_html</div>
<form method="POST" accept-charset="UTF-8">
  <input type="text" name="text" placeholder="Type something and submit">
  <input type="submit" value="Append">
</form>
</body>
</html>
};

    # Restore real STDOUT and emit the UTF-8 encoded buffer directly
    select $old_fh;
    print $body;
} # while
