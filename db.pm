# Database helpers for my beertracker project

package db;
use strict;
use warnings;

use feature 'unicode_strings';
use utf8;  # Source code and string literals are utf-8

use Data::Dumper;
local $Data::Dumper::Terse = 1;
local $Data::Dumper::Indent = 0;
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
    if ( ! $nomark ) { # Mark those that point to other tables, or other specials
      $name = "-$name" if ( $type eq "INTEGER" || $type eq "REAL" );
      # INTEGER usually refers to another table
      # REAL is used for Lat/Long
      # For numerical values, use DECIMAL
    }
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
  print STDERR "$sql \n(", join(',',@params), ")\n" if ( $c->{devversion} );
  my $sth = $c->{dbh}->prepare($sql);
  $sth->execute( @params );
  return $sth;
}

# Run a simple query, and return the first (only?) record
sub queryrecord {
  my $c = shift;
  my $sql = shift;
  my @params = @_;
  my $sth = query($c,$sql, @params );
  return undef unless ( $sth);
  my $rec = $sth->fetchrow_hashref;
  $sth->finish;
  return $rec;
}

# Simple buffered read of records. Keeps exactly one record in buffer, so
# we can peek at it, and consume it later. For example, peek to see if the
# year has changed, and print a header if yes.
# (Tried to set it directly inside $sth, but that did not work)
# Bit dirty, keeps the buffered record in a hash indexed by the $sth.
# This works since this is a cgi script that does not run very long, so the
# buffer will not grow very large within one HTTP request.

my %buffer;

sub nextrow {
    my ($sth) = @_;
    if (exists $buffer{$sth}) {
        my $row = $buffer{$sth};
        delete $buffer{$sth};
        return $row;
    }
    my $row = $sth->fetchrow_hashref;
    return $row;
} # nextrow

sub peekrow {
    my ($sth) = @_;
    if (exists $buffer{$sth}) {
      my $row = $buffer{$sth};
      return $row;
    }
    my $row = $sth->fetchrow_hashref;
    $buffer{$sth} = $row if $row;
    return $row;
} # peekrow

sub pushback_row {
    my ($sth, $row) = @_;
    util::error( "Buffer already occupied" ) if exists $buffer{$sth};
    $buffer{$sth} = { %$row };
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
    $val = undef if (util::trim($val) eq '');
    push @sets , "$f = ?";
    push @values, $val;
    print STDERR "updaterecord: $f = " . util::loglist($val) . "\n";
  }
  my $sql = "update $table set " .
    join( ", ", @sets) .
    " where id = ?";
  print STDERR "updaterecord: $sql \n";
  print STDERR "updaterecord: " . util::loglist( @values ) . " \n";
  my $sth = $c->{dbh}->prepare($sql);
  $sth->execute( @values, $id );
   print STDERR "Updated " . $sth->rows .
      " $table records for id '$id' : " . util::loglist( @values ) ." \n";
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
    if ( $val eq '' ) {
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
    $val = undef if (util::trim($val) eq '');
    push @sqlfields, $f;
    push @values, $val;
  }
  my $fieldlist = "(" . join( ", ", @sqlfields ) . " )";
  my $qlist = $fieldlist;
  $qlist =~ s/\w+/?/g; # Make a list like ( ?, ?, ?)
  my $sql = "insert into $table $fieldlist values $qlist";
  print STDERR "insertrecord: $sql \n";
  print STDERR "insertrecord: " . util::loglist( @values ) . "\n";
  error("insertrecord: Nothing to insert into $table") unless @values;
  my $sth = $c->{dbh}->prepare($sql);
  $sth->execute( @values );
  my $id = $c->{dbh}->last_insert_id(undef, undef, $table, undef) || undef;
  print STDERR "Inserted $table id '$id' ". util::loglist(@values) . " \n";
  return $id;
} # insertrecord


################################################################################
# Report module loaded ok
1;
