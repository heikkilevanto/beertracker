# export.pm: Allow the user to download his data
# and optionally all supporting records (locations, brews)

package export;
use strict;
use warnings;

use feature 'unicode_strings';
use utf8;  # Source code and string literals are utf-8

use POSIX qw(strftime localtime locale_h);

use Data::Dumper;   # Useful when debugging
local $Data::Dumper::Terse = 1;
local $Data::Dumper::Indent = 0;

################################################################################
# Helper to get the html parameters for the export
################################################################################
sub export_params {
  my $c = shift;

  my $sql = "
    select
      min( strftime('%Y-%m-%d', timestamp, '-06:00') ) as first,
      max( strftime('%Y-%m-%d', timestamp, '-06:00') ) as last
    from GLASSES
    where username = ?
  ";
  my $dates = db::queryrecord( $c, $sql, $c->{username} );
  $dates->{first} = "2025-08-13"; # While debugging the code ###
  my $datefrom = util::param($c,"datefrom", $dates->{first});
  my $dateto = util::param($c,"dateto", $dates->{last});
  my $mode = util::param($c,"mode");
  my $schema= util::param($c,"schema");

  return ( $datefrom, $dateto, $mode, $schema );

}


################################################################################
# Form for parameters
################################################################################
sub exportform {
  my $c = shift;
  # TODO - Check if $c->{superuser}, and if so, allow choosing any/all users

  my ( $datefrom, $dateto, $mode, $schema ) = export_params($c);
  print qq{
  <form method="GET" action="index.cgi">
  <input type="hidden" name="o" value="DoExport">
  Export all data for user <b>'$c->{username}'</b><br>
  <table>
    <tr>
      <td>From date:</td>
      <td><input type="text" name="datefrom" value='$datefrom' placeholder="YYYY-MM-DD"></td>
    </tr>
    <tr>
      <td>To date:</td>
      <td><input type="text" name="dateto" value='$dateto' placeholder="YYYY-MM-DD"></td>
    </tr>
    <tr>
      <td>Support records:</td>
      <td>
        <select name="mode">
          <option value="partial">Only referenced</option>
          <option value="full">All in related tables</option>
        </select>
      </td>
    </tr>
    <tr>
      <td>Schema:</td>
      <td>
        <select name="schema">
          <option value="none">Data only</option>
          <option value="dropcreate">Drop + Create</option>
        </select>
      </td>
    </tr>
    <tr>
      <td  style="text-align:center">
        <button type="submit">Export</button>
      </td>
    </tr>
  </table>
  </form>

    };

}


################################################################################
# Dump of the users data
################################################################################

my $loglevel = 1;

sub do_export {
    my $c = shift;
    my ($datefrom, $dateto, $mode, $schema) = export_params($c);

    # --- 1. Collect glasses IDs ---
    my @glasses_ids = db::queryarray($c, "
        SELECT Id FROM Glasses
        WHERE Username=? AND Timestamp BETWEEN ? AND ?
    ", $c->{username}, $datefrom, $dateto);
    dblog($c, "Glasses to export: ".scalar(@glasses_ids), $loglevel);

    # --- 2. Collect other IDs manually ---
    my %ids = (
        Glasses   => \@glasses_ids,
        Comments  => [],
        Brews     => [],
        Locations => [],
        Persons   => [],
    );

    # Always include comments for selected glasses
    my @comments = db::queryarray($c, "
        SELECT Id FROM Comments WHERE Glass IN (".join(",", @glasses_ids).")
    ");
    $ids{Comments} = \@comments;
    dblog($c, "Comments to export: ".scalar(@comments), $loglevel);

    # TODO: add Brew, Locations, Persons collection manually as needed

    # --- 3. Output headers for download ---
    print "Content-Disposition: attachment; filename=beertracker_export.sql\n";
    print "Content-Type: text/plain; charset=utf-8\n\n";

    # --- 4. Drop/create statements from sqlite_master ---
    if ($schema && $schema eq 'dropcreate') {
        my @tables = db::queryarray($c, "
            SELECT name FROM sqlite_master WHERE type='table' ORDER BY name
        ");
        for my $table (@tables) {
            my ($create_sql) = db::queryarray($c, "
                SELECT sql FROM sqlite_master WHERE type='table' AND name=?
            ", $table);
            print "DROP TABLE IF EXISTS $table;\n$create_sql;\n\n";
        }
    }

    # --- 5. Output INSERTs ---
    for my $table (qw/Locations Brews Persons Glasses Comments/) {
        for my $id (@{ $ids{$table} }) {
            my $row = db::queryrecord($c, "SELECT * FROM $table WHERE Id=?", $id);
            print insert_statement($c, $table, $row)."\n";
        }
    }

    dblog($c, "Export finished", $loglevel);
} # do_export


# Cache the column order for each table
my %_table_columns_cache;


# Produce the insert statement
sub insert_statement {
    my ($c, $table, $row) = @_;

    # TODO - Seems to have problems with the column names, only inserts the Id
    # Get column order once per table
    my $cols_ref = $_table_columns_cache{$table};
    unless ($cols_ref) {
        $cols_ref = [ map { $_->{name} } db::queryrecord($c, "PRAGMA table_info($table)") ];
        $_table_columns_cache{$table} = $cols_ref;
    }

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
    print STDERR "$ins \n";
    return $ins;
}


# Simple logging helper
sub dblog {
    my ($c, $msg, $level) = @_;
    print STDERR "$msg\n" if $level;
}

################################################################################
# Report module loaded ok
1;
