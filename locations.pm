# Part of my beertracker
# Routines for displaying and editing locations

package locations;
use strict;
use warnings;


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

  # Sort order or filtering
  my $sort = "last DESC";
  $sort = "LOCATIONS.Id" if ( $c->{sort} eq "id" );
  $sort = "LOCATIONS.Name" if ( $c->{sort} eq "name" );
  $sort = "last DESC" if ( $c->{sort} eq "last" );

  # Print list of locations
  my $sql = "
  select
    LOCATIONS.Id,
    LOCATIONS.Name,
    LOCATIONS.Website,
    strftime ( '%Y-%m-%d %w', max(GLASSES.Timestamp), '-06:00' ) as last
  from LOCATIONS
  left join GLASSES on GLASSES.Location = LOCATIONS.Id
  group by LOCATIONS.Id
  order by $sort
  ";
  my $list_sth = $c->{dbh}->prepare($sql);
  $list_sth->execute();

  print "<table><tr>\n";
  my $url = $c->{url};
  my $op = $c->{op};
  print "<td><a href='$url?o=$op&s=id'><i>Id</i></a></td>";
  print "<td><a href='$url?o=$op&s=name'><i>Name</i></a></td>";
  print "<td><a href='$url?o=$op&s=last'><i>Last seen</i></a></td>";
  print "</tr>";
  while ( my ($locid, $name, $web, $last ) = $list_sth->fetchrow_array ) {
    my ($stamp, $wd) = util::splitdate($last);
    $name =~ s/( +)$/"_" x length($1)/e; # Mark trailing spaces, as in my 'Home  ' things
    print "<tr><td style='font-size: xx-small' align='right'>$locid</td>\n";
    print "<td style='max-width:30em' ><a href='$url?o=$op&e=$locid'><b>$name</b></a>";
    print "<a href='$web' target='_blank' ><span> &nbsp; $web</span></a>"
      if ( $web );
    print "</td>\n";
    print "<td>$wd</td>\n";
    print "<td>" . main::filt($stamp,"","","full") . "</td>\n";
    print "</tr>\n";
  }
  print "</table>\n";
  print "<hr/>\n" ;
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
    print "<table style='width:100%; max-width:500px' id='inputformtable'>\n";
    print "<tr><td $c2><b>Editing Location $p->{Id}: $p->{Name}</b></td></tr>\n";
    print "<tr><td>Name</td>\n";
    print "<td><input name='name' value='$p->{Name}' $clr /></td></tr>\n";
    print "<tr><td>Official</td>\n";
    print "<td><input name='off' value='$p->{OfficialName}' $clr /></td></tr>\n";
    print "<tr><td>Description</td>\n";
    print "<td><input name='desc' value='$p->{Description}' $clr /></td></tr>\n";
    print "<tr><td>Geo coord</td>\n";
    print "<td><input name='geo' value='$p->{GeoCoordinates}' $clr /></td></tr>\n";
    print "<tr><td>Website</td>\n";
    print "<td><input name='web' value='$p->{Website}' $clr /></td></tr>\n";
    print "<tr><td>Contact</td>\n";
    print "<td><input name='contact' value='$p->{Contact}' $clr /></td></tr>\n";
    print "<tr><td>Address</td>\n";
    print "<td><input name='addr' value='$p->{Address}' $clr /></td></tr>\n";
    print "<tr><td $c2> <input type='submit' name='submit' value='Update Location' /></td></tr>\n";
    print "</table>\n";
    # Come back to here after updating
    print "<input type='hidden' name='o' value='$c->{op}' />\n";
    print "<input type='hidden' name='e' value='$p->{Id}' />\n";
    print "</form>\n";
    print "<hr/>\n";
    print "(This should show the last n visits to the location, etc)<br/>\n"; # TODO
  } else {
    print "Oops - location id '$c->{edit}' not found <br/>\n";
  }
} # editperson

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
    my $sql = "insert into LOCATIONS
       ( Name, SubType, Description )
       values ( ?, ?, ? ) ";
    my $sth = $c->{dbh}->prepare($sql);
    $sth->execute( $name,
      util::param($c, "newlocSubType"),
      util::param($c, "newlocDescription") );
    $id = $c->{dbh}->last_insert_id(undef, undef, "LOCATIONS", undef) || undef;
    print STDERR "Inserted Location id '$id' '$name' \n";
  } else {
    my $name = $c->{cgi}->param("name");
    main::error ("A Location must have a name" )
      unless $name;
    my $off= $c->{cgi}->param("off") || "" ;
    my $desc= $c->{cgi}->param("desc") || "" ;
    my $geo= $c->{cgi}->param("geo") || "" ;
    my $web= $c->{cgi}->param("web") || "" ;
    my $contact=  $c->{cgi}->param("contact") || "";
    my $addr= $c->{cgi}->param("addr") || "" ;
    main::error ("Bad id for updating a location '$id' ")
      unless $id =~ /^\d+$/;
    my $sql = "
      update LOCATIONS
        set
          Name = ?,
          OfficialName = ?,
          Description = ?,
          GeoCoordinates = ?,
          Contact = ?,
          Website = ?,
          Address = ?
      where id = ? ";
    my $sth = $c->{dbh}->prepare($sql);
    $sth->execute( $name, $off, $desc, $geo, $web, $contact, $addr, $id );
    print STDERR "Updated " . $sth->rows .
      " Location records for id '$id' : '$name' \n";
  }
  return $id;
  #print $c->{cgi}->redirect( "$c->{url}?o=$c->{op}&e=$c->{edit}" );
} # postlocation

################################################################################
# Helper to select a location
################################################################################
# For now, just produces a pull-down list. Later we can add filtering, options
# for sort order and some geo coord magic
# TODO - Add a few more fields.
# TODO - Drop the newlocfield, at most a boolean to say we want that option with fixed name(s)
# TODO - Add the current location as the first real one in the list, never mind if duplicates

# TODO SOON - Abstract most of the pulldown magic into a helper.
# TODO SOON - Move CSS into its own helper. Remove fancy corners
# TODO SOON - Clean and parametrisize input names
# TODO - Use the new helper for persons
# TODO - And brews, with all the extras those need (brewstyle filtering)
sub selectlocation {
  my $c = shift; # context
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
  my $newfields = [ "newlocName", "newlocSubType", "newlocDescription" ];

  my $s = util::dropdown( "loc", $selected, $current, $opts, $newfields );
  return $s;

} # seleclocation


################################################################################
1; # Tell perl that the module loaded fine

