# Database helpers for my beertracker project

package db;
use strict;
use warnings;

use feature 'unicode_strings';
use utf8;  # Source code and string literals are utf-8



# --- insert new functions here ---



################################################################################
# General db helpers
################################################################################

########## Get all field names for a table
sub tablefields {
  my $c = shift;
  my $table = shift;
  my $skips = shift; # Regexp for fields to skip. "Id|UnWanted|Field"
  my $nomark = shift || ""; # 1 to skip marking integer fields
  $skips = "Id" unless defined($skips);

  my $sql = "PRAGMA table_info($table)";
  my $list_sth = $c->{dbh}->prepare($sql);
  $list_sth->execute();
  my @fields;
  while ( my ($cid, $name, $type, $notnull, $def, $pk )  = $list_sth->fetchrow_array ) {
    next if ( $skips && $name =~ /^$skips$/ );
    $name = "-$name" if ( $type eq "INTEGER" && !$nomark );  # Mark those that point to other tables
    push @fields, $name ;
  }
  return @fields;
}

# Run a simple DB query
# Returns a st-handle for fetchrows
sub query {
  my $c = shift;
  my $sql = shift;
  my @params = @_;
  print STDERR "$sql ", @params, "\n" if ( $c->{devversion} );
  my $sth = $c->{dbh}->prepare($sql);
  $sth->execute( @params );
  return $sth;
}

# Simple buffered read of records. Keeps exactly one record in buffer, so
# we can peek at it, and consume it late. For example, peek to see if the
# year has changed, and print a header if yes.
# Bit dirty, keeps the buffered record inside $sth
sub nextrow {
    my ($sth) = @_;
    if (exists $sth->{my_buffered_row}) {
        my $row = $sth->{my_buffered_row};
        delete $sth->{my_buffered_row};
        return $row;
    }
    return $sth->fetchrow_hashref;
} # nextrow

sub peekrow {
    my ($sth) = @_;
    return $sth->{my_buffered_row} if exists $sth->{my_buffered_row};
    my $row = $sth->fetchrow_hashref;
    $sth->{my_buffered_row} = $row if $row;
    return $row;
} # peekrow

sub pushback_row {
    my ($sth, $row) = @_;
    error( "Buffer already occupied" ) if exists $sth->{my_buffered_row};
    $sth->{my_buffered_row} = $row;
} # pushback_row

################################################################################
# Helpers to get records
################################################################################

############ Get a single record by Id
sub getrecord {
  my $c = shift;
  my $table = shift;
  my $id = shift;
  return undef unless ($id);
  my $sql = "select * from $table where id = ? ";
  my $sth = $c->{dbh}->prepare($sql);
  $sth->execute($id);
  my $rec = $sth->fetchrow_hashref;
  $sth->finish;
  my $name = $rec->{Name} || "";
  print STDERR "getrecord: $sql '$id' -> '$name'\n";
  return $rec;
} # getrecord


############ Find a single record by a given field
sub findrecord {
  my $c = shift;
  my $table = shift;
  my $field = shift;
  my $val = shift;
  my $collate = shift || "";
  return undef unless ($val);
  my $sql = "select * from $table where $field = ? $collate";
  my $sth = $c->{dbh}->prepare($sql);
  $sth->execute($val);
  my $rec = $sth->fetchrow_hashref;
  $sth->finish;
  return $rec;
} # getrecord


############ Get given fields from (first) record that matches the where clause
# Or undef if not found
sub getfieldswhere {
  my $c = shift;
  my $table = shift;
  my $fields = shift;
  my $where = shift;
  my $order = shift || "";
  my $sql = "select $fields from $table $where $order";
  print STDERR "getfieldswhere: $sql \n";
  my $sth = $c->{dbh}->prepare($sql);
  $sth->execute();
  my $rec = $sth->fetchrow_hashref;
  $sth->finish;
  return $rec;
} # getrecord

################################################################################
# Helpers for POST functions
################################################################################
# These take CGI parameters and a table layout, and build the necessary
# insert/update statements. Insert/update forms can be recursive, with the
# user choosing a NEW subrecord (f.ex. location). There are some heuristics
# to handle those. Will not generalize to all kind of systems, but seems to
# be sufficient for the beer tracker.

############################## post a record.
#Looks at the submit parameter to decide to insert, update, or
# delete a record. The submit label must start with the operation name
# Assumes $c->{edit} has a proper id for ops that need one
sub postrecord {
  my $c = shift;
  my $table = shift;
  my $inputprefix = shift || "";  # "newloc" means inputs are "newlocName" etc
  my $defaults = shift || {};

  my $sub = util::param($c,"submit");
  if ($sub =~ /^Update/i || $c->{edit} =~ /^New/i ) {
    db::updaterecord( $c, $table, $c->{edit}, $inputprefix);
  } elsif ( $sub =~ /^Create|^Insert/i ) {
    $c->{edit} = db::insertrecord( $c, $table, $inputprefix, $defaults);
  } elsif ($sub =~ /Delete/i ) {
    db::deleterecord( $c, $table, $c->{edit});
    $c->{edit} = "";
  }
}


################### Delete a record
sub deleterecord {
  my $c = shift;
  my $table = shift;
  my $id = shift;
  my $sql = "delete from $table " .
    " where id = ?";
  print STDERR "deleterecord: $sql '$id' \n";
  my $sth = $c->{dbh}->prepare($sql);
  $sth->execute( $id );
  print STDERR "Deleted " . $sth->rows .
      " $table records for id '$id' \n";
} # deleterecord


########## Update a record directly from CGI parameters
sub updaterecord {
  my $c = shift;
  my $table = shift;
  my $id = shift;
  my $inputprefix = shift || "";  # "newloc" means inputs are "newlocName" etc

  error ( "Can not update a $table record without id ") unless ($id) ;
  error ( "Bad id '$id' for updating a $table record ") unless ( $id =~ /^\d+$/ );
  my @sets;
  my @values;
  for my $f ( db::tablefields($c, $table)) {
    my $special = $1 if ( $f =~ s/^(-)// );
    my $val = util::param($c, $inputprefix.$f );
    print STDERR "updaterecord: '$f' = '$val' \n";
    if ( $special ) {
      print STDERR "updaterecord: Met a special field '$f' \n";
      if ( $val eq "new" ) {
        print STDERR "updaterecord: Should insert a new $f \n";
        if ( $f =~ /location/i ) {
          $val = db::insertrecord($c, "LOCATIONS", "newloc");
        } elsif ( $f =~ /location/i ) {
          $val = db::insertrecord($c, "BREWS", "newbrew");
        } elsif ( $f =~ /person/i ) {
          $val = db::insertrecord($c, "PERSONS", "newperson");
        } else {
          print STDERR "updaterecord: Don't know how to insert a '$f' \n";
          $val = "TODO";
        }
      }
    }
    if ( $val ) {
      push @sets , "$f = ?";
      push @values, $val;
      print STDERR "updaterecord: $f = '$val' \n";
    }
  }
  my $sql = "update $table set " .
    join( ", ", @sets) .
    " where id = ?";
  print STDERR "updaterecord: $sql \n";
  print STDERR "updaterecord: " . join(", ", @values) . " \n";
  my $sth = $c->{dbh}->prepare($sql);
  $sth->execute( @values, $id );
   print STDERR "Updated " . $sth->rows .
      " $table records for id '$id' : " . join(", ", @values) ." \n";
} # updaterecord


######### Insert a record directly from CGI parameters
# Takes the field names from the table.
# Expects cgi inputs with same names with a prefix
# TODO - The recursion does not yet handle all possible types
sub insertrecord {
  my $c = shift;
  my $table = shift;
  my $inputprefix = shift || "";  # "newloc" means inputs are "newlocName" etc
  my $defaults = shift || {};

  my @sqlfields; # field names in sql
  my @values; # values to insert, in the same order
  for my $f ( db::tablefields($c, $table,undef,1)) {  # 1 indicates no -prefix
    my $val = util::param($c, $inputprefix.$f );
    print STDERR "insertrecord: '$inputprefix' '$f' got value '$val' \n";
    if ( !$val ) {
      $val =  $defaults->{$f} || "";
      print STDERR "insertrecord: '$f' defaults to '$val' \n" if ($val);
    }
    if ( $val eq "new" ) {
      if ( $f eq "ProducerLocation" ) {
        print STDERR "Recursing to ProducerLocation ($inputprefix) \n";
        my $def = {};
        $def->{LocType} = "Producer";
        $def->{LocSubType} = util::param($c, "selbrewtype") || "Beer";
        $val = db::insertrecord($c, "LOCATIONS", "newprod", $def );
        print STDERR "Returned from ProducerLocation, id='$val'  \n";
      } elsif ( $f eq "Location" ) {
        print STDERR "Recursing to Location ($inputprefix) \n";
        my $def = {};
        $val = db::insertrecord($c, "LOCATIONS", "newloc", $def );
        print STDERR "Returned from Location, id='$val'  \n";
      } elsif ( $f eq "RelatedPerson" ) {
        print STDERR "Recursing to RelatedPerson ($inputprefix) \n";
        my $def = {};
        $val = db::insertrecord($c, "PERSONS", "newperson", $def );
        print STDERR "Returned from NewPerson, id='$val'  \n";
      }
      else {
        error ("insertrecord can not yet handle recursion to this type. p='$inputprefix' f='$f' ");
      }
    }
    if ( $val ) {
      push @sqlfields, $f;
      push @values, $val;
    }
  }
  my $fieldlist = "(" . join( ", ", @sqlfields ) . " )";
  my $qlist = $fieldlist;
  $qlist =~ s/\w+/?/g; # Make a list like ( ?, ?, ?)
  my $sql = "insert into $table $fieldlist values $qlist";
  print STDERR "insertrecord: $sql \n";
  print STDERR "insertrecord: " . join (", ", @values ) . "\n";
  error("insertrecord: Nothing to insert into $table") unless @values;
  my $sth = $c->{dbh}->prepare($sql);
  $sth->execute( @values );
  my $id = $c->{dbh}->last_insert_id(undef, undef, $table, undef) || undef;
  print STDERR "Inserted $table id '$id' ". join (", ", @values ). " \n";
  return $id;
} # insertrecord


################################################################################
# Report module loaded ok
1;
