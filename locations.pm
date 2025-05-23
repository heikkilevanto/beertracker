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

  if ( $c->{edit} =~ /^\d+$/ ) {  # Id for full info
    editlocation($c);
    return;
  }
  print "<b>Locations</b><br/>\n";
  my $sort = $c->{sort} || "Last-";
  # print util::listrecords($c, "LOCATIONS_LIST", $sort, "Type NOT LIKE  'Producer%'" );
  print util::listrecords($c, "LOCATIONS_LIST", $sort );
  return;
} # listlocations



################################################################################
# Editlocation - Show a form for editing a location record
################################################################################

sub editlocation {
  my $c = shift;
  my $sql = "select * from Locations where id = ?";
    # This Can leak info from persons filed by other users. Not a problem now
  my $get_sth = $c->{dbh}->prepare($sql);
  $get_sth->execute($c->{edit});
  my $p = $get_sth->fetchrow_hashref;
  for my $f ( "Location", "RelatedPerson" ) {
    $p->{$f} = "" unless $p->{$f};  # Blank out null fields
  }
  if ( $p->{Id} ) {  # found the person
    print "\n<form method='POST' accept-charset='UTF-8' class='no-print' " .
        "enctype='multipart/form-data'>\n";
    print "<input type='hidden' name='id' value='$p->{Id}' />\n";
    print "<b>Editing Location $p->{Id}: $p->{Name}</b><br/>\n";
    print util::inputform($c, "LOCATIONS", $p );
    print "<input type='submit' name='submit' value='Update Location' /><br/>\n";

    # Come back to here after updating
    print "<input type='hidden' name='o' value='$c->{op}' />\n";
    print "<input type='hidden' name='e' value='$p->{Id}' />\n";
    print "</form>\n";
    print "<hr/>\n";
    print "(This should show the last n visits to the location, etc)<br/>\n"; # TODO
  } else {
    print "Oops - location id '$c->{edit}' not found <br/>\n";
  }
} # editlocation

################################################################################
# Update a location (posted from the form above)
################################################################################
sub postlocation {
  my $c = shift; # context
  my $id = shift || $c->{edit};
  if ( $id eq "new" ) {
    my $name = $c->{cgi}->param("newlocName");
    util::error ("A Location must have a name" )
      unless $name;
    $id = util::insertrecord($c, "LOCATIONS", "newloc");
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

