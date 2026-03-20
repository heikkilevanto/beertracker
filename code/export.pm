# export.pm: Allow the user to download his data
# and optionally all supporting records (locations, brews, photos)

package export;
use strict;
use warnings;

use feature 'unicode_strings';
use utf8;  # Source code and string literals are utf-8

use POSIX qw(strftime localtime locale_h);
use File::Copy ();
use File::Path qw(make_path remove_tree);
use URI::Escape qw(uri_escape_utf8);

################################################################################
# Helper to get the html parameters for the export
################################################################################
sub export_params {
  my $c = shift;

  my $sql = "SELECT
      min( strftime('%Y-01-01', Timestamp, '-06:00') ) AS first,
      max( strftime('%Y-%m-%d', Timestamp, '-06:00') ) AS last
    FROM Glasses
    WHERE Username = ?";
  my $dates = db::queryrecord( $c, $sql, $c->{username} );
  my $datefrom = util::param($c, "datefrom", $dates->{first});
  my $dateto   = util::param($c, "dateto",   $dates->{last});
  my $mode     = util::param($c, "mode")   || "partial";
  my $schema   = util::param($c, "schema") || "none";
  my $action   = util::param($c, "action") || "";
  my $taps     = util::param($c, "taps")   || "none";

  my $export_username = $c->{username};
  if ( superuser::is_superuser($c) ) {
    my $p = util::param($c, "export_username");
    $export_username = $p if $p;
  }

  return ( $datefrom, $dateto, $mode, $schema, $action, $taps, $export_username );

} # export_params


################################################################################
# Form for parameters
################################################################################
sub exportform {
  my $c = shift;

  my ( $datefrom, $dateto, $mode, $schema, $action, $taps, $export_username ) = export_params($c);

  my $username_select = "";
  if ( superuser::is_superuser($c) ) {
    my @users = db::queryrecordarray($c,
      "SELECT DISTINCT Username FROM Glasses ORDER BY Username");
    my $opts = "";
    for my $u (@users) {
      my $sel = ($u eq $export_username) ? " selected" : "";
      $opts .= "          <option value='$u'$sel>$u</option>\n";
    }
    $username_select = qq{    <tr>
      <td>User</td>
      <td>
        <select name="export_username" id="export_username">
$opts        </select>
      </td>
    </tr>};
  }

  print qq{
  <form method="GET" style='padding-bottom: 200px;'>
  <input type="hidden" name="o" value="Export">
  Export data<br>
  <table>
    <tr>
      <td>From date</td>
      <td><input type="text" name="datefrom" value='$datefrom' placeholder="YYYY-MM-DD"></td>
    </tr>
    <tr>
      <td>To date</td>
      <td><input type="text" name="dateto" value='$dateto' placeholder="YYYY-MM-DD"></td>
    </tr>
$username_select
    <tr>
      <td>Support records &nbsp;</td>
      <td>
        <select name="mode" id="mode">
          <option value="partial">Only referenced</option>
          <option value="full">All in related tables</option>
        </select>
      </td>
    </tr>
    <tr>
      <td>Tap data &nbsp;</td>
      <td>
        <select name="taps" id="taps">
          <option value="none">No tap data</option>
          <option value="brews">Taps for referenced brews</option>
          <option value="range">All taps in date range</option>
        </select>
      </td>
    </tr>
    <tr>
      <td>Schema</td>
      <td>
        <select name="schema" id="schema">
          <option value="none">Data only</option>
          <option value="dropcreate">Drop + Create</option>
        </select>
      </td>
    </tr>
    <tr>
      <td>Action</td>
      <td>
        <select name="action" id="action">
          <option value="display">Show on screen</option>
          <option value="tarball">Tarball (SQL only)</option>
          <option value="tarball_photos">Tarball (SQL + photos)</option>
        </select>
      </td>
    </tr>
    <tr>
      <td style="text-align:center">
        <br>
        <button type="submit">Export</button>
      </td>
    </tr>
  </table>
  </form>
  <script>
    replaceSelectWithCustom(document.getElementById("mode"));
    replaceSelectWithCustom(document.getElementById("taps"));
    replaceSelectWithCustom(document.getElementById("schema"));
    replaceSelectWithCustom(document.getElementById("action"));
  </script>
  };

  my @tarball_users;
  if ( superuser::is_superuser($c) ) {
    @tarball_users = db::queryrecordarray($c,
      "SELECT DISTINCT Username FROM Glasses ORDER BY Username");
  } else {
    @tarball_users = ($c->{username});
  }
  list_tarballs($c, \@tarball_users);

} # exportform


################################################################################
# List existing tarballs in the user's photo dir with download and delete links
################################################################################
sub list_tarballs {
  my ($c, $users_ref) = @_;

  my $found_any = 0;
  for my $user (@$users_ref) {
    my $photodir = $c->{datadir} . $user . ".photo";
    for my $path ( sort { (stat $b)[9] <=> (stat $a)[9] }
                   glob("$photodir/beertracker_export_*.tgz") ) {
    next unless -f $path;

    unless ($found_any) {
      print qq{<h3>Existing tarballs</h3>\n<table>\n};
      $found_any = 1;
    }

    my $name  = (split '/', $path)[-1];
    my @st    = stat($path);
    my $size  = int($st[7] / 1024 + 0.5) . "&nbsp;KB";
    my $mtime = strftime("%Y-%m-%d %H:%M", localtime($st[9]));
    (my $href = $path) =~ s{^\./}{};
    my $delurl = "$c->{url}?o=Export&action=delete_tarball&tarball=" . uri_escape_utf8($name);
    $delurl .= "&export_username=" . uri_escape_utf8($user)
      if $user ne $c->{username};
    print qq{  <tr>
    <td>$mtime</td>
    <td>$size</td>
    <td><a href='$href'><span>$name</span></a></td>
    <td><a href='$delurl'><span>[delete]</span></a></td>
  </tr>\n};
    } # for each tarball file
  } # for each user
  print qq{</table>\n} if $found_any;

} # list_tarballs


################################################################################
# Delete a tarball (GET, no DB change)
################################################################################
sub delete_tarball {
  my $c = shift;
  my ( undef, undef, undef, undef, undef, undef, $export_username ) = export_params($c);
  my $tarball = util::param($c, "tarball") || "";

  # Validate: no path components, must match our naming convention
  util::error("Invalid tarball name")
    unless $tarball =~ /^beertracker_export_[a-zA-Z0-9_T]+\.tgz$/;

  my $export_photodir = $c->{datadir} . $export_username . ".photo";
  my $path = "$export_photodir/$tarball";
  if (-f $path) {
    unlink $path or util::error("Could not delete $tarball: $!");
    print { $c->{log} } "Deleted tarball: $path\n";
  }

  exportform($c);

} # delete_tarball


################################################################################
# Collect record IDs for all tables to be exported
################################################################################
sub collect_ids {
  my ($c, $datefrom, $dateto, $mode, $taps_mode, $export_username) = @_;

  my %ids;

  # Glasses ---
  my @glasses_ids = db::queryrecordarray($c, "
      SELECT Id FROM Glasses
      WHERE Username=? AND strftime('%Y-%m-%d', Timestamp, '-06:00') BETWEEN ? AND ?
  ", $export_username, $datefrom, $dateto);
  $ids{glasses} = \@glasses_ids;
  my $glasses_list = @glasses_ids ? join(",", @glasses_ids) : "NULL";

  # Comments --- by owner and date range
  my @comment_ids = db::queryrecordarray($c, "
      SELECT Id FROM Comments
      WHERE Username=? AND strftime('%Y-%m-%d', Ts, '-06:00') BETWEEN ? AND ?
  ", $export_username, $datefrom, $dateto);
  $ids{comments} = \@comment_ids;
  my $comment_list = @comment_ids ? join(",", @comment_ids) : "NULL";

  # Photos --- by uploader and date range
  my @photo_ids = db::queryrecordarray($c, "
      SELECT Id FROM Photos
      WHERE Uploader=? AND strftime('%Y-%m-%d', Ts, '-06:00') BETWEEN ? AND ?
  ", $export_username, $datefrom, $dateto);
  $ids{photos} = \@photo_ids;

  # Supporting tables ---
  my @brew_ids;
  my @loc_ids;
  my @person_ids;

  if ( $mode eq 'full' ) {
    @brew_ids   = db::queryrecordarray($c, "SELECT Id FROM Brews");
    @loc_ids    = db::queryrecordarray($c, "SELECT Id FROM Locations");
    @person_ids = db::queryrecordarray($c, "SELECT Id FROM Persons");
  } else {
    # Brews from glasses and comments
    @brew_ids = db::queryrecordarray($c,
      "SELECT DISTINCT Brew FROM Glasses WHERE Id IN ($glasses_list) AND Brew IS NOT NULL");
    my @comment_brew_ids = db::queryrecordarray($c,
      "SELECT DISTINCT Brew FROM Comments WHERE Id IN ($comment_list) AND Brew IS NOT NULL");
    my %brew_seen = map { $_ => 1 } @brew_ids;
    for my $id (@comment_brew_ids) {
      push @brew_ids, $id unless $brew_seen{$id}++;
    }
    my $brew_list = @brew_ids ? join(",", @brew_ids) : "NULL";

    # Locations from glasses, comments, and brews.ProducerLocation
    @loc_ids = db::queryrecordarray($c,
      "SELECT DISTINCT Location FROM Glasses WHERE Id IN ($glasses_list) AND Location IS NOT NULL");
    my %loc_seen = map { $_ => 1 } @loc_ids;
    my @extra_locs = db::queryrecordarray($c,
      "SELECT DISTINCT ProducerLocation FROM Brews WHERE Id IN ($brew_list) AND ProducerLocation IS NOT NULL");
    push @extra_locs, db::queryrecordarray($c,
      "SELECT DISTINCT Location FROM Comments WHERE Id IN ($comment_list) AND Location IS NOT NULL");
    for my $id (@extra_locs) {
      push @loc_ids, $id unless $loc_seen{$id}++;
    }

    # Persons via comment_persons
    if (@comment_ids) {
      @person_ids = db::queryrecordarray($c,
        "SELECT DISTINCT Person FROM comment_persons WHERE Comment IN ($comment_list) AND Person IS NOT NULL");
    }
  }

  $ids{brews}     = \@brew_ids;
  $ids{locations} = \@loc_ids;
  $ids{persons}   = \@person_ids;

  # tap_beers ---
  my @tap_ids;
  if ( $taps_mode eq 'brews' && @brew_ids ) {
    my $brew_list = join(",", @brew_ids);
    @tap_ids = db::queryrecordarray($c,
      "SELECT Id FROM tap_beers WHERE Brew IN ($brew_list)");
  } elsif ( $taps_mode eq 'range' ) {
    @tap_ids = db::queryrecordarray($c,
      "SELECT Id FROM tap_beers
       WHERE strftime('%Y-%m-%d', FirstSeen, '-06:00') <= ?
         AND (Gone IS NULL OR strftime('%Y-%m-%d', Gone, '-06:00') >= ?)",
      $dateto, $datefrom);
  }
  $ids{tap_beers} = \@tap_ids;

  return \%ids;

} # collect_ids


################################################################################
# Generate SQL INSERT statements from collected IDs
# Returns arrayref of { table => $name, sql => $text }
################################################################################
sub generate_sql {
  my ($c, $ids, $schema) = @_;

  # Dependency order so FK constraints are satisfied on import
  my @table_order = qw(locations brews persons glasses comments photos comment_persons tap_beers);

  # Fetch columns once per table (except comment_persons which has no Id)
  my %table_columns;
  for my $table (@table_order) {
    next if $table eq 'comment_persons';
    my $sth = db::query($c, "PRAGMA table_info($table)");
    my @cols;
    while ( my $row = db::nextrow($sth) ) {
      push @cols, $row->{name};
    }
    $table_columns{$table} = \@cols;
  }

  my @result;

  for my $table (@table_order) {
    my $header = "";
    my $body   = "";

    if ( $schema eq 'dropcreate' ) {
      my ($create_sql) = db::queryrecordarray($c,
        "SELECT sql FROM sqlite_master WHERE type='table' AND name=?", $table);
      $header = "DROP TABLE IF EXISTS $table;\n$create_sql;\n\n" if $create_sql;
    }

    # comment_persons uses composite PK — handle without Id lookup
    if ( $table eq 'comment_persons' ) {
      my @comment_ids = @{ $ids->{comments} || [] };
      my @rows;
      if (@comment_ids) {
        my $clist = join(",", @comment_ids);
        my $sth = db::query($c,
          "SELECT Comment, Person FROM comment_persons WHERE Comment IN ($clist) ORDER BY Comment, Person");
        while ( my $row = db::nextrow($sth) ) {
          push @rows, $row;
        }
      }
      $body .= "-- Table: $table (" . scalar(@rows) . " records)\n";
      for my $row (@rows) {
        $body .= "INSERT INTO comment_persons (Comment,Person) VALUES ($row->{Comment},$row->{Person});\n";
      }
      push @result, { table => $table, sql => $header . $body };
      next;
    }

    my @ids  = @{ $ids->{$table} || [] };
    my $nrecs = scalar(@ids);
    $body .= "-- Table: $table ($nrecs records)\n";
    print { $c->{log} } "Exporting table '$table' ($nrecs rows)\n";

    if (@ids) {
      my $idlist = join(",", @ids);  # safe: IDs come from DB
      my $sth = db::query($c, "SELECT * FROM $table WHERE Id IN ($idlist) ORDER BY Id");
      while ( my $row = db::nextrow($sth) ) {
        $body .= insert_statement($c, $table, $row, $table_columns{$table}) . "\n";
      }
    }

    push @result, { table => $table, sql => $header . $body };
  }

  return \@result;

} # generate_sql


# Produce a single INSERT statement
sub insert_statement {
  my ($c, $table, $row, $cols_ref) = @_;

  my @vals;
  for my $col (@$cols_ref) {
    my $val = $row->{$col};
    if (!defined $val) {
      push @vals, "NULL";
    } elsif ($val =~ /^-?\d+(\.\d+)?$/) {
      push @vals, $val;
    } else {
      $val =~ s/'/''/g;
      push @vals, "'$val'";
    }
  }

  return "INSERT INTO $table (" . join(",", @$cols_ref) . ") VALUES (" . join(",", @vals) . ");";

} # insert_statement


################################################################################
# Display export on screen — one <pre> block per table
################################################################################
sub show_export {
  my $c = shift;
  my ( $datefrom, $dateto, $mode, $schema, $action, $taps, $export_username ) = export_params($c);

  my $ids    = collect_ids($c, $datefrom, $dateto, $mode, $taps, $export_username);
  my $tables = generate_sql($c, $ids, $schema);

  print qq{<h2>Export for '$export_username', $datefrom to $dateto</h2>\n};
  print qq{<p><a href='$c->{url}?o=Export'><span>[Back to export form]</span></a></p>\n};

  for my $t (@$tables) {
    my $sql = $t->{sql};
    $sql =~ s/&/&amp;/g;
    $sql =~ s/</&lt;/g;
    $sql =~ s/>/&gt;/g;
    print qq{<pre class='export-block'>$sql</pre>\n};
  }

  print qq{<p><a href='$c->{url}?o=Export'><span>[Back to export form]</span></a></p>\n};

} # show_export


################################################################################
# Build a tarball in the user's photo dir and show a download link
################################################################################
sub make_tarball {
  my ($c, $with_photos) = @_;
  my ( $datefrom, $dateto, $mode, $schema, $action, $taps, $export_username ) = export_params($c);

  my $ids    = collect_ids($c, $datefrom, $dateto, $mode, $taps, $export_username);
  my $tables = generate_sql($c, $ids, $schema);

  # Build SQL text
  my $sql_text  = "-- Export of BeerTracker data\n";
  $sql_text    .= "-- for user '$export_username'\n";
  $sql_text    .= "-- Date range: $datefrom to $dateto\n";
  $sql_text    .= "-- Export done at " . util::datestr() . "\n\n";
  for my $t (@$tables) {
    $sql_text .= $t->{sql} . "\n";
  }

  # Temp working directory
  my $tmpdir = "/tmp/beertracker_export_$$";
  make_path("$tmpdir/photos");
  util::error("Cannot create temp dir $tmpdir: $!") unless -d "$tmpdir/photos";

  # Write SQL file
  open my $fh, '>:utf8', "$tmpdir/data.sql"
    or util::error("Cannot write data.sql: $!");
  print $fh $sql_text;
  close $fh;

  # Copy original photo files if requested
  if ($with_photos) {
    my @photo_ids = @{ $ids->{photos} || [] };
    if (@photo_ids) {
      my $id_list = join(",", @photo_ids);
      # Photos may belong to the export_username, so build their photodir directly
      my $export_photodir = $c->{datadir} . $export_username . ".photo";
      my $sth = db::query($c, "SELECT Filename FROM Photos WHERE Id IN ($id_list)");
      while ( my $row = db::nextrow($sth) ) {
        my $orig = $export_photodir . "/" . $row->{Filename} . "+orig.jpg";
        if (-f $orig) {
          my $basename = $row->{Filename} . "+orig.jpg";
          File::Copy::copy($orig, "$tmpdir/photos/$basename")
            or print { $c->{log} } "Could not copy $orig: $!\n";
        } else {
          print { $c->{log} } "Photo file not found: $orig\n";
        }
      }
    }
  }

  # Ensure destination photo dir exists and build tar path
  my $export_photodir = $c->{datadir} . $export_username . ".photo";
  make_path($export_photodir);
  my $now_stamp = util::datestr("%Y%m%d-%H%M%S", 0, 1);
  my $tarname = "beertracker_export_${export_username}_${now_stamp}.tgz";
  my $tarpath = "$export_photodir/$tarname";

  system("tar", "czf", $tarpath, "-C", $tmpdir, ".") == 0
    or util::error("tar failed (exit " . ($? >> 8) . ")");

  remove_tree($tmpdir);

  exportform($c);

} # make_tarball


################################################################################
# Unified entry point
################################################################################
sub exportpage {
  my $c = shift;
  my $action = util::param($c, "action") || "";

  if ( $action eq 'display' ) {
    show_export($c);
  } elsif ( $action eq 'tarball' ) {
    make_tarball($c, 0);
  } elsif ( $action eq 'tarball_photos' ) {
    make_tarball($c, 1);
  } elsif ( $action eq 'delete_tarball' ) {
    delete_tarball($c);
  } else {
    exportform($c);
  }

} # exportpage


################################################################################
# Report module loaded ok
1;
