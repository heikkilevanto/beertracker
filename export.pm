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
      min( strftime('%Y-%m-%d', timestamp, '-06:00') ),
      max( strftime('%Y-%m-%d', timestamp, '-06:00') )
    from GLASSES
    where username = ?
  ";
  my ( $first, $last ) = db::queryrecordarray( $c, $sql, $c->{username} );

  my $datefrom = util::param($c,"datefrom", $first);
  my $dateto = util::param($c,"dateto", $last);
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


sub do_export{
    my $c = shift;
    my ( $datefrom, $dateto, $mode, $schema ) = export_params($c);
    # 1. Get tables
    my @tables_orig = map { $_->[0] } @{ $c->{dbh}->selectall_arrayref(
        "SELECT name FROM sqlite_master WHERE type='table' AND name NOT LIKE 'sqlite_%'"
    ) };
    my @tables = map { lc $_ } @tables_orig;   # use lowercase internally
    my %table_case = map { lc($tables_orig[$_]) => $tables_orig[$_] } 0..$#tables_orig;

    print STDERR "Got tables " , join(', ', @tables)  , "\n";


    # 2. Foreign key maps
    my (%parents, %children);
    for my $t_orig (@tables_orig) {
        my $t = lc $t_orig;
        my $fks = $c->{dbh}->selectall_arrayref("PRAGMA foreign_key_list($t_orig)", { Slice => {} });
        for my $fk (@$fks) {
            my $parent = lc $fk->{table};
            push @{$parents{$t}},   { col => $fk->{from}, parent => $parent, pcol => $fk->{to} };
            push @{$children{$parent}}, { child => $t, col => $fk->{from}, pcol => $fk->{to} };
        }
    }
    for my $t (@tables) {
        print STDERR "FK parents of $t: ",
          join(", ", map { "$t.$_->{col} -> $_->{parent}.$_->{pcol}" } @{$parents{$t} // []}), "\n";
        print STDERR "FK children of $t: ",
          join(", ", map { "$_->{child}.$_->{col} -> $t.$_->{pcol}" } @{$children{$t} // []}), "\n";
    }


    # 3. Initial restrictions
    my $glasses_filter = "username = ? AND strftime('%Y-%m-%d', timestamp, '-06:00') BETWEEN ? AND ?";
    my %restrict = (
        glasses  => { where => $glasses_filter, bind => [$c->{username},$datefrom,$dateto] }
    );

    # track already included IDs per table to avoid infinite loops
    my %seen = map { $_ => {} } @tables;


    # 4. Expand restrictions both ways
    my $changed = 1;
    while ($changed) {
        $changed = 0;

        # UPWARD
        for my $table (@tables) {
            next unless $restrict{$table};
            my ($pk) = $c->{dbh}->selectrow_array("SELECT name FROM pragma_table_info(?) WHERE pk=1", undef, $table_case{$table});
            next unless $pk;

            my $ids = $c->{dbh}->selectcol_arrayref(
                "SELECT $pk FROM " . $table_case{$table} . " WHERE $restrict{$table}{where}",
                undef, @{$restrict{$table}{bind}}
            );
            next unless @$ids;
            my %idset = map { $_ => 1 } @$ids;

            for my $fk (@{$parents{$table} // []}) {
                my $parent = $fk->{parent};
                my $pcol   = $fk->{pcol};
                next unless $parent;

                my @new_ids = grep { !$seen{$parent}{$_}++ } keys %idset;
                next unless @new_ids;

                my $ph = join(",", ("?") x @new_ids);
                if ($restrict{$parent}) {
                    $restrict{$parent}{where} .= " OR $pcol IN ($ph)";
                    push @{$restrict{$parent}{bind}}, @new_ids;
                } else {
                    $restrict{$parent} = { where => "$pcol IN ($ph)", bind => \@new_ids };
                }
                $changed = 1;
                print STDERR "Upward: $table -> $parent restricted to " . join(", ", @new_ids) . "\n";
            }
        }

        # DOWNWARD
        for my $table (@tables) {
            next unless $restrict{$table};
            my ($pk) = $c->{dbh}->selectrow_array("SELECT name FROM pragma_table_info(?) WHERE pk=1", undef, $table_case{$table});
            next unless $pk;

            my $ids = $c->{dbh}->selectcol_arrayref(
                "SELECT $pk FROM " . $table_case{$table} . " WHERE $restrict{$table}{where}",
                undef, @{$restrict{$table}{bind}}
            );
            next unless @$ids;
            my %idset = map { $_ => 1 } @$ids;

            for my $ch (@{$children{$table} // []}) {
                my $child = $ch->{child};
                my $col   = $ch->{col};
                next unless $child;

                my @new_ids = grep { !$seen{$child}{$_}++ } keys %idset;
                next unless @new_ids;

                my $ph = join(",", ("?") x @new_ids);
                if ($restrict{$child}) {
                    $restrict{$child}{where} .= " OR $col IN ($ph)";
                    push @{$restrict{$child}{bind}}, @new_ids;
                } else {
                    $restrict{$child} = { where => "$col IN ($ph)", bind => \@new_ids };
                }
                $changed = 1;
                print STDERR "Downward: $table -> $child restricted to " . join(", ", @new_ids) . "\n";
            }
        }
    }


    # 5. Dump schema + data
    my $sql = "";

    for my $table (@tables) {
        my $table_lc = lc $table;
        my $table_out = $table_case{$table_lc};  # original case from schema

        my $sth_cols = $c->{dbh}->selectall_arrayref("PRAGMA table_info($table)");
        my @cols = map { $_->[1] } @$sth_cols;
        my $col_list = join(", ", map { qq("$_") } @cols);

        # Schema
        if ($schema eq 'dropcreate') {
            $sql .= "DROP TABLE IF EXISTS \"$table_out\";\n";
            my ($create) = $c->{dbh}->selectrow_array(
                "SELECT sql FROM sqlite_master WHERE type='table' AND name=?", undef, $table_out
            );
            $sql .= "$create;\n";
        }

        # Data
        my $query = "SELECT * FROM $table";
        my @bind;
        if ($restrict{$table}) {
            $query .= " WHERE $restrict{$table}{where}";
            @bind = @{$restrict{$table}{bind}};
        }
        my $rows = $c->{dbh}->selectall_arrayref($query, { Slice => {} }, @bind);
        for my $row (@$rows) {
            my @vals = map { defined $_ ? $c->{dbh}->quote($_) : "NULL" } @{$row}{@cols};
            $sql .= "INSERT INTO \"$table_out\" ($col_list) VALUES (" . join(", ", @vals) . ");\n";
        }
    }
    print STDERR "Export done \n";
    print "Content-Disposition: attachment; filename=beertracker_export.sql\n";  # Make it a download
    print "Content-Type: text/plain\n\n";
    print $sql;
    exit();
    return $sql;
} # do_export


################################################################################
# Report module loaded ok
1;
