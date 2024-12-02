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
# List of locations
################################################################################
sub listlocations {
  my $c = shift; # context
  print util::listsmenu($c), util::showmenu($c);

  if ( $c->{edit} =~ /^\d+$/ ) {  # Id for full info
    editlocation($c);
    return;
  }

  my $sort = $c->{sort} || "Last-";
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
    my $c2 = "colspan='2'";
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
    main::error ("A Location must have a name" )
      unless $name;
    $id = util::insertrecord($c, "LOCATIONS", "newloc");
  } else {
    my $name = $c->{cgi}->param("Name");
    main::error ("A Location must have a name" )
      unless $name;
    $id = util::updaterecord($c, "LOCATIONS", $id,  "");
  }
  return $id;
} # postlocation

################################################################################
# Helper to select a location
################################################################################
# For now, just produces a pull-down list. Later we can add filtering, options
# for sort order and some geo coord magic
# TODO - Add a few more fields.
# TODO - Drop the newlocfield, at most a boolean to say we want that option with fixed name(s)
# TODO - Add the current location as the first real one in the list, never mind if duplicates

# TODO SOON - Move CSS into its own helper.
# TODO SOON - Clean and parametrisize input names
# TODO - Use the new helper for persons
# TODO - And brews, with all the extras those need (brewstyle filtering)
sub selectlocation {
  my $c = shift; # context
  my $fieldname = shift || "Location";
  my $selected = shift || "0";  # The id of the selected location
  my $newprefix = shift || ""; # Prefix for new-location fields. Enables the "new"

  if ( $selected && $selected !~ /^\d+$/ ){
    print STDERR "selectlocation called with non-numerical 'selected' argument: '$selected' \n";
    $selected = 0;
  }

  my $sql = "
  select
    LOCATIONS.Id,
    LOCATIONS.Name
  from LOCATIONS
  left join GLASSES on GLASSES.Location = LOCATIONS.Id
  group by LOCATIONS.id
  order by max(GLASSES.Timestamp) DESC
  ";
  my $list_sth = $c->{dbh}->prepare($sql);
  $list_sth->execute(); # username ?
  my $opts = "";

  my $current = "";
  while ( my ($id, $name ) = $list_sth->fetchrow_array ) {
    $opts .= "      <div class='dropdown-item' id='$id'>$name</div>\n";
    if ( $id eq $selected ) {
      $current = $name;
    }
  }
  my $s = util::dropdown( $c, $fieldname, $selected, $current, $opts, "LOCATIONS", "newloc" );
  return $s;

} # seleclocation


################################################################################
1; # Tell perl that the module loaded fine

