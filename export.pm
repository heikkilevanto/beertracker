# export.pm: Allow the user to download his data
# and optionally all supporting records (locations, brews)

package export;
use strict;
use warnings;

use feature 'unicode_strings';
use utf8;  # Source code and string literals are utf-8

use POSIX qw(strftime localtime locale_h);

# use Data::Dumper;   # Useful when debugging
# local $Data::Dumper::Terse = 1;
# local $Data::Dumper::Indent = 0;

################################################################################
# Helper to get the html parameters for the export
################################################################################
sub export_params {
  my $c = shift;

  my $sql = "select
      min( strftime('%Y-01-01', timestamp, '-06:00') ) as first,
      max( strftime('%Y-%m-%d', timestamp, '-06:00') ) as last
    from GLASSES
    where username = ?";
  my $dates = db::queryrecord( $c, $sql, $c->{username} );
  #$dates->{first} = "2025-08-13"; # While debugging the code ###
  my $datefrom = util::param($c,"datefrom", $dates->{first});
  my $dateto = util::param($c,"dateto", $dates->{last});
  my $mode = util::param($c,"mode");
  my $schema= util::param($c,"schema");
  my $action= util::param($c,"action");

  return ( $datefrom, $dateto, $mode, $schema, $action );

}


################################################################################
# Form for parameters
################################################################################
sub exportform {
  my $c = shift;
  # TODO - Check if $c->{superuser}, and if so, allow choosing any/all users #491

  my ( $datefrom, $dateto, $mode, $schema, $action ) = export_params($c);
  print qq{
  <form method="GET" action="index.cgi" style='padding-bottom: 200px;'>
  <input type="hidden" name="o" value="DoExport">
  Export all data for user <b>'$c->{username}'</b><br>
  <table>
    <tr>
      <td>From date</td>
      <td><input type="text" name="datefrom" value='$datefrom' placeholder="YYYY-MM-DD"></td>
    </tr>
    <tr>
      <td>To date</td>
      <td><input type="text" name="dateto" value='$dateto' placeholder="YYYY-MM-DD"></td>
    </tr>
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
      <td>Schema</td>
      <td>
        <select name="schema" id="schema" >
          <option value="none">Data only</option>
          <option value="dropcreate">Drop + Create</option>
        </select>
      </td>
    </tr>
    <tr>
      <td>Action</td>
      <td>
        <select name="action" id="action">
          <option value="download">Download file</option>
          <option value="display">Show on screen</option>
        </select>
      </td>
    </tr>
    <tr>
      <td  style="text-align:center">
        <br>
        <button type="submit">Export</button>
      </td>
    </tr>
  </table>
  </form>
  <script>
    replaceSelectWithCustom(document.getElementById("mode"));
    replaceSelectWithCustom(document.getElementById("schema"));
    replaceSelectWithCustom(document.getElementById("action"));
  </script>

    };

}


################################################################################
# Dump of the users data
################################################################################

sub do_export {
  my $c = shift;
  my ( $datefrom, $dateto, $mode, $schema, $action) = export_params($c);


  # Get all tables from sqlite_master ---
  my @tables = db::queryarray(
    $c, "SELECT name FROM sqlite_master
      WHERE type='table' and name NOT LIKE 'sqlite_%' ORDER BY name" );
  @tables = map { lc $_ } @tables;    # lowercase table names

  # Fetch columns once per table
  my %table_columns;
  for my $table (@tables) {
    my $sth = db::query($c, "PRAGMA table_info($table)");
    my @cols;
    while ( my $row = db::nextrow($sth) ) {
      my $col = $row->{name};
      push ( @cols ,$col );
      }
    $table_columns{$table} = \@cols;
  }

  # Collect glasses IDs
  my @glasses_ids = db::queryarray($c, "
      SELECT Id FROM Glasses
      WHERE Username=? AND strftime ('%Y-%m-%d', Timestamp,'-06:00') BETWEEN ? AND ?
  ", $c->{username}, $datefrom, $dateto);
  my $glasses_list = join(",", @glasses_ids);

  # Collect other IDs manually ---
  my %ids;
  for my $table (@tables) {
      $ids{$table} = [];
  }
  $ids{glasses} = \@glasses_ids;

  # Always include comments for selected glasses
  my @comments = db::queryarray($c, "
      SELECT Id FROM Comments WHERE Glass IN ($glasses_list)");
  $ids{comments} = \@comments;

  # Supporting tables
  my @brew_ids;
  my @loc_ids;
  my @person_ids;
  if ( $mode eq 'full' ) {
    @brew_ids      = db::queryarray($c, "SELECT Id FROM Brews");
    @loc_ids       = db::queryarray($c, "SELECT Id FROM Locations");
    @person_ids    = db::queryarray($c, "SELECT Id FROM Persons");
  } else {
    @brew_ids = db::queryarray($c,
        "SELECT DISTINCT Brew FROM glasses
         WHERE Id IN ($glasses_list) AND Brew IS NOT NULL");
    @loc_ids = db::queryarray($c,
        "SELECT DISTINCT Location FROM Glasses
         WHERE Id IN ($glasses_list) AND Location IS NOT NULL");
    push @loc_ids, db::queryarray($c, # also include producer locations from the brews
        "SELECT DISTINCT ProducerLocation FROM Brews
         WHERE Id IN (" . join(",", @brew_ids) . ") AND ProducerLocation IS NOT NULL");

    my @person_ids = db::queryarray($c,
        "SELECT DISTINCT Person FROM Comments WHERE Glass IN ($glasses_list) AND Person IS NOT NULL");
  }
  $ids{brews} = \@brew_ids;
  $ids{locations} = \@loc_ids;
  $ids{persons} = \@person_ids;

  # Output headers for download ---
  print "Content-Disposition: attachment; filename=beertracker_export.sql\n" if ($action =~ /Download/i );
  print "Content-Type: text/plain; charset=utf-8\n\n";

  print "-- Export of BeerTracker data \n";
  print "-- for user '$c->{username}'\n";
  print "-- Date range: $datefrom to $dateto\n";
  print "-- Export done at " . util::datestr() . "\n\n";

  # Drop/create statements from sqlite_master ---
  if ($schema && $schema eq 'dropcreate') {
    for my $table (@tables) {
      my ($create_sql) = db::queryarray($c,
          "SELECT sql FROM sqlite_master WHERE type='table' AND name=?", $table);
      print "DROP TABLE IF EXISTS $table;\n$create_sql;\n\n";
    }
  }

  #  Output INSERTs ---
  for my $table (@tables) {
    my @ids = @{ $ids{$table} || [] };
    my $nrecs = scalar(@ids);
    print STDERR "Exporting table '$table' ($nrecs rows) \n";
    print "\n-- Table: $table ($nrecs records) \n";
    next unless @ids;

    my $idlist = join(",", @ids);   # safe because IDs come from DB
    my $sth = db::query($c, "SELECT * FROM $table WHERE Id IN ($idlist) ORDER BY Id");

    while (my $row = db::nextrow($sth)) {
      print insert_statement($c, $table, $row, $table_columns{$table}), "\n";
    }
  }

} # do_export


# Produce the insert statement
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

  my $ins = "INSERT INTO $table (".join(",", @$cols_ref).") VALUES (".join(",", @vals).");";
  #print STDERR "$ins \n";
  return $ins;
}



################################################################################
# Report module loaded ok
1;
