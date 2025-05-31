# Part of my beertracker
# Routines for displaying and editing locations

package locations;
use strict;
use warnings;
use feature 'unicode_strings';
use utf8;  # Source code and string literals are utf-8


# TODO - Add current and latest as options to it
# TODO - Add a way to add a new location

# TODO - Add a button to use current geo (needs JS trickery)

# TODO LATER - Add a way to merge two locations, in case of spelling errors

# TODO - Move most of geolocation stuff here as well (or in its own module?)


# Formatting magic
my $clr = "Onfocus='value=value.trim();select();' autocapitalize='words'";
#my $sz = "size='4' style='text-align:right' $clr";

################################################################################
# Lists of locations
################################################################################
sub listlocations {
  my $c = shift; # context

  if ( $c->{edit} ) {  # Id for full info
    editlocation($c);
    return;
  }
  print "<b>Locations</b>";
  print "&nbsp;<a href=\"$c->{url}?o=$c->{op}&e=new\"><span>(New)</span></a>\n";
  my $sort = $c->{sort} || "Last-";
  # print util::listrecords($c, "LOCATIONS_LIST", $sort, "Type NOT LIKE  'Producer%'" );
  print util::listrecords($c, "LOCATIONS_LIST", $sort );
  return;
} # listlocations

################################################################################
# List comments for the given location
################################################################################
sub listlocationcomments {
  my $c = shift;
  my $loc = shift;
  print "<!-- listlocationcomments -->\n";
  my $sql = "
    SELECT
      COMMENTS.* ,
      strftime('%Y-%m-%d', GLASSES.Timestamp,'-06:00') as Date,
      strftime('%H:%M', GLASSES.Timestamp) as Time,
      PERSONS.Name as PersName,
      PERSONS.ID as Pid,
      GLASSES.Id as Gid,
      GLASSES.BrewType,
      GLASSES.SubType
      from GLASSES, COMMENTS
      LEFT JOIN PERSONS on PERSONS.ID = COMMENTS.Person
      where Comments.glass = glasses.id
      and (glasses.brew IS NULL or glasses.brew = '')
      and glasses.BrewType in ( 'Restaurant', 'Night')
      and glasses.username = ?
      and Glasses.location = ?
      order by Glasses.Timestamp desc
  ";
#        and ( glasses.brew = '' OR glasses.brew = NULL )

  my $sth = $c->{dbh}->prepare($sql);
  $sth->execute($c->{username}, $loc->{Id});
  print "<div style='overflow-x: auto;'>";
  #print "<table  style='white-space: nowrap;'>\n";
  print "<table>\n";
  my $ratesum = 0;
  my $ratecount = 0;
  my $comcount = 0;
  my $perscount = 0;
  my $lastglass = "";
  while ( my $com = $sth->fetchrow_hashref ) {
    my $sty = "style='border-top: 1px solid white; vertical-align: top;' ";
    if ( $lastglass ne $com->{Gid} ) {
      print "<tr><td $sty>\n";
      print "<a href='$c->{url}?o=full&e=$com->{Glass}&ec=$com->{Id}'><b>";
      print "$com->{Date}</b></a>\n";
      my $tim = $com->{Time};
      $tim = "($tim)" if ($tim lt "06:00");
      print "$tim\n";
      print "<span style='font-size: xx-small'>[$com->{Glass}]</span>\n";
      print "[$com->{BrewType}/$com->{SubType}]\n";
      $lastglass = $com->{Gid};
      print "</td></tr>\n";
    } else {
    }
    print "<tr>\n";


    print "<td>\n";
    print comments::commentline($c,$com);

    $perscount++ if ( $com->{PersName} );
    $comcount++ if ($com->{Comment});
    if ( $com->{Rating} ) {
      $ratesum += $com->{Rating};
      $ratecount++;
    }

    print "</td>\n";
    # TODO - Photo thumbnail in its own TD
    print "</tr>\n";
  }
  print "</table></div>\n";
  print "<div onclick='toggleCommentTable(this);'><br/>";
  if ( $comcount == 0 ) {
    print "(No Comments)";
  } else {
    if ( $ratecount == 1) {
      print "One rating: <b>" . comments::ratingline($ratesum) . "</b> ";
    } elsif ( $ratecount > 0 ) {
      my $avg = sprintf( "%3.1f", $ratesum / $ratecount);
      print "$ratecount Ratings averaging <b>" . comments::ratingline($avg) . "</b>. ";
    } else {
      print "Comments: $comcount. ";
    }
  }
  print "</div>";
  print "<script>
    function toggleCommentTable(div) {
      let table = div.previousElementSibling;
      if (table) {
        table.style.display = (table.style.display === 'none') ? 'table' : 'none';
      }
    }
    </script>
    ";
  $sth->finish;
  print "<!-- listbrewcomments end -->\n";
  print "<hr/>\n";
} # listlocationcomments

################################################################################
# locationdeduplist - List all locations, for selecting those that duplicate the current
################################################################################
sub locationdeduplist {
  my $c = shift; # context
  my $loc = shift;
  print "<!-- locationdeduplist -->\n";
  print "<form method='POST' accept-charset='UTF-8' class='no-print' >\n";
  print "Mark locations that are duplicates of <b>[$loc->{Id}] $loc->{Name}</b> ";
  print "and click here: \n";
  print "<input type=submit name=submit value='Deduplicate' />\n";
  print "<input type=hidden name='o' value='$c->{op}' />\n";
  print "<input type=hidden name='e' value='$c->{edit}' />\n";
  print "<input type=hidden name='dedup' value='1' />\n";
  print "<br/>\n";
  my $sort = $c->{sort} || "Last-";
  print util::listrecords($c, "LOCATIONS_DEDUP_LIST", $sort, "Id <> $loc->{Id}" );
  print "</form>\n";
  print "<!-- locationdeduplist end -->\n";
  print "<hr/>\n";
} # brewdeduplist

################################################################################
# Editlocation - Show a form for editing a location record
################################################################################

sub editlocation {
  my $c = shift;
  my $submit = "Update";
  my $p = {};
  if ( $c->{edit} =~ /new/i ) {
    $p->{Id} = "new";
    $p->{LocType} = "Bar"; # Some decent defaults
    $p->{LocSubType} = "Beer"; # More for guiding the input than true values
    print "<b>Inserting a new location<br/>\n";
    $submit = "Insert";
  } else {
    my $sql = "select * from Locations where id = ?";
    my $get_sth = $c->{dbh}->prepare($sql);
    $get_sth->execute($c->{edit});
    $p = $get_sth->fetchrow_hashref;
    $get_sth->finish;
    print "<b>Editing Location $p->{Id}: $p->{Name}</b><br/>\n";
  }

  if ( $p->{Id} ) {  # found the person
    print "\n<form method='POST' accept-charset='UTF-8' class='no-print' " .
        "enctype='multipart/form-data'>\n";
    print "<input type='hidden' name='id' value='$p->{Id}' />\n";
    print util::inputform($c, "LOCATIONS", $p );
    print "<input type='submit' name='submit' value='$submit Location' /><br/>\n";

    # Come back to here after updating
    print "<input type='hidden' name='o' value='$c->{op}' />\n";
    print "<input type='hidden' name='e' value='$p->{Id}' />\n";
    print "</form>\n";
    print "<hr/>\n";
    if ( $p->{Id} ne "new" ) {
      listlocationcomments($c,$p);
      locationdeduplist($c,$p);
    }
  } else {
    print "Oops - location id '$c->{edit}' not found <br/>\n";
  }
} # editlocation

################################################################################
# Deduplicate location
################################################################################
sub deduplocations {
  my $c = shift; # context
  my $id = shift; # The id of the location we keep
  foreach my $paramname ($c->{cgi}->param) {
    if ( $paramname =~ /^Chk(\d+)$/ ) {
      my $dup = $1;
      my $sql = "UPDATE GLASSES set Location = ? where Location = ?  ";
      print STDERR "$sql with '$id' and '$dup' \n";
      my $rows = $c->{dbh}->do($sql, undef, $id, $dup);
      util::error("Deduplicate Locations: Failed to update glasses") unless $rows;
      print STDERR "Updated $rows glasses from $dup to $id\n";

      $sql = "UPDATE PERSONS set Location = ? where Location = ?  ";
      print STDERR "$sql with '$id' and '$dup' \n";
      $rows = $c->{dbh}->do($sql, undef, $id, $dup);
      print STDERR "Updated $rows glasses from $dup to $id\n";

      $sql = "UPDATE BREWS set ProducerLocation = ? where ProducerLocation = ?  ";
      print STDERR "$sql with '$id' and '$dup' \n";
      $rows = $c->{dbh}->do($sql, undef, $id, $dup);
      print STDERR "Updated $rows brews from $dup to $id\n";

      $sql = "DELETE FROM LOCATIONS WHERE Id = ? ";
      $rows = $c->{dbh}->do($sql, undef, $dup);
      util::error("Deduplicate Locations: Failed to delete brew '$dup'") unless $rows;
      print STDERR "Deleted $rows brews with id  $dup\n";
    }
  }

} # deduplocations

################################################################################
# Update a location (posted from the form above)
################################################################################
sub postlocation {
  my $c = shift; # context
  my $id = shift || $c->{edit};
  if ( util::param($c,"dedup") ) {
    deduplocations($c,$id);
    return;
  }

  if ( $id eq "new" ) {
    my $name = $c->{cgi}->param("newlocName");
    my $section = "newloc";
    if ( ! $name ) {
      $name = $c->{cgi}->param("Name");
      $section = "";
    }
    util::error ("A Location must have a name" )
      unless $name;
    $id = util::insertrecord($c, "LOCATIONS", $section);
  } else {
    my $name = $c->{cgi}->param("Name");
    util::error ("A Location must have a name" )
      unless $name;
    $id = util::updaterecord($c, "LOCATIONS", $id,  "");
  }
  return $id;
} # postlocation

################################################################################
# Helper to select a location
################################################################################
# Offers a list to select a location, or (optionally) to enter values for a
# new one. The optional 5th parameter limits the locations to those that are
# Producers, or those that are not. Default is not to limit at all.

sub selectlocation {
  my $c = shift; # context
  my $fieldname = shift || "Location";
  my $selected = shift || "0";  # The id of the selected location
  my $newprefix = shift || ""; # Prefix for new-location fields. Enables the "new"
  my $prods = shift || "";  # "prod" for prod locs only, "non" for non-prods only. Defaults to all

  if ( $selected && $selected !~ /^\d+$/ ){
    print STDERR "selectlocation called with non-numerical 'selected' argument: '$selected' \n";
    $selected = 0;
  }
  my $where = "";
  my $skip = "Id";
  my $newfield = "newloc";
  if ( $prods eq "prod" ) {
    $where = "where LOCATIONS.LocType = \"Producer\" ";
    $newfield = "newprod";
    $skip .= "|LocType|LocSubType";
  } elsif ( $prods eq "non" ) {
    $where = "where LOCATIONS.LocType <>  \"Producer\" ";
  }
  my $sql = "
  select
    LOCATIONS.Id,
    LOCATIONS.Name,
    LOCATIONS.LocType,
    LOCATIONS.LocSubType
  from LOCATIONS
  left join GLASSES on GLASSES.Location = LOCATIONS.Id
  $where
  group by LOCATIONS.id
  order by max(GLASSES.Timestamp) DESC
  ";
  my $list_sth = $c->{dbh}->prepare($sql);
  $list_sth->execute(); # username ?
  my $opts = "";

  my $current = "";
  while ( my ($id, $name, $type ) = $list_sth->fetchrow_array ) {
    if ($type) {
      $type = "[$type]";
    } else {
      $type = "";
    }
    $opts .= "      <div class='dropdown-item' id='$id'>$name $type</div>\n";
    if ( $id eq $selected ) {
      $current = $name;
    }
  }
  my $s = util::dropdown( $c, $fieldname, $selected, $current, $opts, "LOCATIONS", $newfield, $skip );
  return $s;

} # seleclocation


################################################################################
1; # Tell perl that the module loaded fine

