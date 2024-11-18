# Part of my beertracker
# Routines for displaying and editing persons


################################################################################
# List of people
################################################################################
# Prints all details of the person identified in $qry (by its id), if any,
# and under that, a list of all people in the system
# TODO Move all the PERSONS routines to their own module
# That's why updateperson() is kept here for now
# TODO - Split into listpeople and editperson
# TODO - Make a routine for selecting a person, use for RelatedPerson
# TODO - Use a similar one for selecting a Location, once I have one
sub people {
  print "<hr/><b>$op list</b>\n";
  print "<br/><div class='no-print'>\n";
  # TODO - Filtering and sorting options
  # No need for time limits, we don't have so many people
  print "Other lists: " ;
  my @ops = ( "Beer",  "Brewery", "Wine", "Booze", "Location", "Restaurant", "Style", "People");
  for my $l ( @ops ) {
    my $bold = "nop";
    $bold = "b" if ($l eq $op);
    print "<a href='$url?o=$l'><$bold>$l</$bold></a> &nbsp;\n";
  }
  print "</div><hr/>\n";

  my $sort = "last DESC";
  # Print full info on the given person
  if ( $qry ) {
    if ( $qry =~ /^\d+$/ ) {  # Id for full info
    my $sql = "select * from Persons where id = ?";
        # This Can leak info from persons filed by other users. Not a problem now
      my $get_sth = $dbh->prepare($sql);
      $get_sth->execute($qry);
      my $p = $get_sth->fetchrow_hashref;
      for my $f ( "Location", "RelatedPerson" ) {
        $p->{$f} = "" unless $p->{$f};  # Blank out null fields
      }
      if ( $p ) {  # found the person
        my $c2 = "colspan='2'";
        print "\n<form method='POST' accept-charset='UTF-8' class='no-print' " .
           "enctype='multipart/form-data'>\n";
        print "<input type='hidden' name='id' value='$p->{Id}' />\n";
        print "<table style='width:100%; max-width:500px' id='inputformtable'>\n";
        print "<tr><td $c2><b>Editing Person $p->{Id}: $p->{Name}</b></td></tr>\n";
        print "<tr><td>Name</td>\n";
        print "<td><input name='name' value='$p->{Name}' /></td></tr>\n";
        print "<tr><td>Full name</td>\n";
        print "<td><input name='full' value='$p->{FullName}' /></td></tr>\n";
        print "<tr><td>Description</td>\n";
        print "<td><input name='desc' value='$p->{Description}' /></td></tr>\n";
        print "<tr><td>Location</td>\n";
        print "<td><input name='loc' value='$p->{Location}' /></td></tr>\n"; # TODO - Select
        print "<tr><td>Related</td>\n";
        print "<td><input name='rela' value='$p->{RelatedPerson}' /></td></tr>\n"; # TODO - Select
        print "<tr><td $c2> <input type='submit' name='submit' value='Update Person' /></td></tr>\n";
        # TODO - Pulldown select for RelatedPerson
        # TODO - Pulldown (or advanced selection) for Location
        print "</table>\n";
        # Come back to here after updating
        print "<input type='hidden' name='o' value='People' />\n";
        print "<input type='hidden' name='q' value='$p->{Id}' />\n";
        print "</form>\n";
        print "<hr/>\n";
      } # found the person
    # Sort order or filtering
    } elsif ( $qry eq "id" ) {
      $sort = "PERSONS.Id";
    } elsif ( $qry eq "name" ) {
      $sort = "PERSONS.Name" ;
    } elsif ( $qry eq "last" ) {
      $sort = "last DESC" ;
    } elsif ( $qry eq "where" ) {
      $sort = "LOCATIONS.Name" ;
    }
  }

  # Print list of people
  my $sql = "
  select
    PERSONS.Id,
    PERSONS.Name,
    strftime ( '%Y-%m-%d %w', max(GLASSES.Timestamp), '-06:00' ) as last,
    LOCATIONS.Name as loc,
    count(COMMENTS.Id) as count
  from PERSONS, GLASSES, COMMENTS, LOCATIONS
  where COMMENTS.Person = PERSONS.Id
    and COMMENTS.Glass = GLASSES.Id
    and GLASSES.Username = ?
    and LOCATIONS.id = GLASSES.Location
  group by Persons.id
  order by $sort
  ";
  my $list_sth = $dbh->prepare($sql);
  $list_sth->execute($username);

  print "<table><tr>\n";
  # TODO - Set a max-width for the name, so one long one will not mess up, esp on the phone
  print "<td><a href='$url?o=$op&q=id'><i>Id</i></a></td>";
  print "<td><a href='$url?o=$op&q=name'><i>Name</i></a></td>";
  print "<td><a href='$url?o=$op&q=last'><i>Last seen</i></a></td>";
  print "<td><a href='$url?o=$op&q=where'><i>Where</i></a></td></tr>";
  while ( my ($persid, $name, $last, $loc, $count) = $list_sth->fetchrow_array ) {
    my ($stamp, $wd ) = split (' ', $last);
    my @weekdays = ( "Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun" );
    $wd = $weekdays[$wd];

    print "<tr><td style='font-size: xx-small' align='right'>$persid</td>\n";
    print "<td><a href='$url?o=$op&q=$persid'><b>$name</b></a>";
    print " ($count) " if ( $count > 1 );
    print "</td>\n";
    print "<td>$wd " . filt($stamp,"","","full") . "</td>\n";
    print "<td>$loc</td></tr>\n";
  }
  print "</table>\n";
  print "<hr/>\n" ;

} # people

# Update a person from the form above
sub updateperson {
  my $id = $q->param("id");
  error ("Bad id for updating a person '$id' ")
    unless $id =~ /^\d+$/;
  my $name = $q->param("name");
  error ("A Person must have a name" )
    unless $name;
  my $full= $q->param("full") || "" ;
  my $desc= $q->param("desc") || "" ;
  my $loc= $q->param("loc") || undef ;
  my $rela= $q->param("rela") || undef ;
  my $sql = "
    update PERSONS
      set
        Name = ?,
        FullName = ?,
        Description = ?,
        Location = ?,
        RelatedPerson = ?
    where id = ? ";
  my $sth = $dbh->prepare($sql);
  $sth->execute( $name, $full, $desc, $loc, $rela, $id );
  print STDERR "Updated " . $sth->rows .
    " Person records for id '$id' : '$name' \n";
}

# Report module loaded ok
1;
