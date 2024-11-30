# Part of my beertracker
# Routines for displaying and editing persons

package persons;
use strict;
use warnings;

################################################################################
# List of persons
################################################################################
# TODO - Filtering by location or date  (not just last seen)
# TODO - When editing, show the most recent dates, other people involved, etc
sub listpersons {
  my $c = shift; # context
  print util::listsmenu($c), util::showmenu($c);

  if ( $c->{edit} =~ /^\d+$/ ) {  # Id for full info
    editperson($c);
    return;
  }

  # Sort order or filtering
  my $sort = "last DESC";
  $sort = "PERSONS.Id" if ( $c->{sort} eq "id" );
  $sort = "PERSONS.Name" if ( $c->{sort} eq "name" );
  $sort = "last DESC" if ( $c->{sort} eq "last" );
  $sort = "LOCATIONS.Name" if ( $c->{sort} eq "where" );

  # Print list of people
  my $sql = "
  select
    PERSONS.Id,
    PERSONS.Name,
    strftime ( '%Y-%m-%d %w', max(GLASSES.Timestamp), '-06:00' ) as last,
    LOCATIONS.Name as loc,
    count(COMMENTS.Id) as count
  from PERSONS
  left join COMMENTS on COMMENTS.Person = PERSONS.Id
  left join GLASSES on COMMENTS.Glass = GLASSES.Id
  left join LOCATIONS on LOCATIONS.id = GLASSES.Location
  group by Persons.id
  order by $sort
  ";
  # , GLASSES, COMMENTS, LOCATIONS
  #  and GLASSES.Username = ?
  my $list_sth = $c->{dbh}->prepare($sql);
  #$list_sth->execute($c->{username});
  $list_sth->execute();

  print "<table><tr>\n";
  my $url = $c->{url};
  my $op = $c->{op};
  print "<td><a href='$url?o=$op&s=id'><i>Id</i></a></td>";
  print "<td><a href='$url?o=$op&s=name'><i>Name</i></a></td>";
  print "<td colspan=2><a href='$url?o=$op&s=last'><i>Last seen</i></a></td>";
  print "<td><a href='$url?o=$op&s=where'><i>Where</i></a></td></tr>";
  while ( my ($persid, $name, $last, $loc, $count) = $list_sth->fetchrow_array ) {
    my ($stamp, $wd) = util::splitdate($last);
    $loc = "" unless ($loc);

    print "<tr><td style='font-size: xx-small' align='right'>$persid</td>\n";
    print "<td><a href='$url?o=$op&e=$persid'><b>$name</b></a>";
    print " ($count) " if ( $count > 1 );
    print "</td>\n";
    print "<td>$wd</td>";
    print "<td >" . main::filt($stamp,"","","full") . "</td>\n";
    print "<td>$loc</td></tr>\n";
  }
  print "</table>\n";
  print "<hr/>\n" ;
} # listpersons


################################################################################
# Editperson - Show a form for editing a person record
################################################################################
# TODO - Show extended info about the person, like when and where seen,
# associations with other people etc
sub editperson {
  my $c = shift;
  my $sql = "select * from Persons where id = ?";
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
    print "<tr><td $c2><b>Editing Person $p->{Id}: $p->{Name}</b></td></tr>\n";
    print "<tr><td>Name</td>\n";
    print "<td><input name='name' value='$p->{Name}' /></td></tr>\n";
    print "<tr><td>Full name</td>\n";
    print "<td><input name='full' value='$p->{FullName}' /></td></tr>\n";
    print "<tr><td>Description</td>\n";
    print "<td><input name='desc' value='$p->{Description}' /></td></tr>\n";
    print "<tr><td>Contact</td>\n";
    print "<td><input name='cont' value='$p->{Contact}' /></td></tr>\n";
    print "<tr><td>Location $p->{Location}</td>\n";
    print "<td>" . locations::selectlocation($c, $p->{Location}, "newloc") ." </td></tr>\n";
    print "<tr><td>Related $p->{RelatedPerson} </td>\n";
    print "<td>" . selectperson($c, "rela", $p->{RelatedPerson}, "", "newperson" ) . "</td></tr>\n";
    print "<tr><td $c2> <input type='submit' name='submit' value='Update Person' /></td></tr>\n";
    print "</table>\n";
    # Come back to here after updating
    print "<input type='hidden' name='o' value='$c->{op}' />\n";
    print "<input type='hidden' name='e' value='$p->{Id}' />\n";
    print "</form>\n";
    print "<hr/>\n";
    print "(This should show a list when the person seen, comments, and with whom)<br/>\n"; # TODO
  } else {
    print "Oops - Person id '$c->{edit}' not found <br/>\n";
  }
} # editperson

################################################################################
# Update a person (posted from the form above)
################################################################################
sub postperson {
  my $c = shift; # context
  my $id = $c->{edit};
  main::error ("Bad id for updating a person '$id' ")
    unless $id =~ /^\d+$/;
  my $name = $c->{cgi}->param("name");
  error ("A Person must have a name" )
    unless $name;
  my $full= $c->{cgi}->param("full") || "" ;
  my $desc= $c->{cgi}->param("desc") || "" ;
  my $cont= $c->{cgi}->param("cont") || "" ;
  my $loc=  $c->{cgi}->param("loc") || undef ;
  my $rela= $c->{cgi}->param("rela") || "" ;
  my $new = $c->{cgi}->param("newperson") || "" ;
  my $newloc = $c->{cgi}->param("newloc") || "" ;
  if ( $new ) {  # Want to add a new related person
    my $insql = "
      insert into PERSONS ( Name, RelatedPerson )
      values ( ?, ? );
    ";
    my $insert_person = $c->{dbh}->prepare($insql);
    $insert_person->execute($new, $id);
    $rela = $c->{dbh}->last_insert_id(undef, undef, "PERSONS", undef) || undef;
    print STDERR "Inserted a new person as '$rela' as a relatedperson for '$id' \n";
  }
  if ( $newloc ) { # Create a new location
    my $insql = "
      insert into LOCATIONS ( Name )
      values ( ? );
    ";
    my $insert_person = $c->{dbh}->prepare($insql);
    $insert_person->execute($newloc);
    $loc = $c->{dbh}->last_insert_id(undef, undef, "LOCATIONS", undef) || undef;
    print STDERR "Inserted a new location '$newloc' as '$loc' for '$id' \n";
  }
  my $sql = "
    update PERSONS
      set
        Name = ?,
        FullName = ?,
        Description = ?,
        Contact = ?,
        Location = ?,
        RelatedPerson = ?
    where id = ? ";
  my $sth = $c->{dbh}->prepare($sql);
  $sth->execute( $name, $full, $desc, $cont, $loc, $rela, $id );
  print STDERR "Updated " . $sth->rows .
    " Person records for id '$id' : '$name' \n";
  if ( $rela ) {  # Update Relation backlink, if not already set
    my $sql = "
      update PERSONS
        set
          RelatedPerson = ?
      where id = ?
      and RelatedPerson = ''
      ";
    my $sth = $c->{dbh}->prepare($sql);
    $sth->execute( $id, $rela );
    print STDERR "Updated RelatedPerson of $rela to point back to $id \n"
      if  ( $sth->rows > 0 );
  }
  print $c->{cgi}->redirect( "$c->{url}?o=$c->{op}&e=$c->{edit}" );
} # postperson

################################################################################
# Helper to select a person
################################################################################
# For now, just produces a pull-down list. Later we can add filtering, options
# for sort order etc
sub selectperson {
  my $c = shift; # context
  my $fieldname = shift || "person";
  my $selected = shift || "";  # The id of the selected person
  my $width = shift || "";
  my $newpersonfield = shift || ""; # If set, allows the 'new' option
  my $sql = "
  select
    PERSONS.Id,
    PERSONS.Name,
    strftime ( '%Y-%m-%d %w', max(GLASSES.Timestamp), '-06:00' ) as last
  from PERSONS
  left join COMMENTS on COMMENTS.Person = Persons.Id
  left join GLASSES on GLASSES.Id = COMMENTS.Glass
  group by Persons.id
  order by GLASSES.Timestamp DESC
  ";
  my $list_sth = $c->{dbh}->prepare($sql);
  $list_sth->execute(); # username ?
  my $s = "";
  $s .= "<input name='$newpersonfield' id='$newpersonfield' $width hidden placeholder='New person'/>\n";
  $s .= << "scriptend";
    <script>
      function personselchange() {
        var sel = document.getElementById("$fieldname");
        if ( sel.value == "new" ) {
          var inp = document.getElementById("$newpersonfield");
          sel.hidden = true;
          inp.hidden = false;
        }
      }
      </script>
scriptend
  $s .= " <select name='$fieldname' id='$fieldname' $width onchange='personselchange();'>\n";
  my $sel = "";
  $sel = "Selected" unless $selected ;
  $s .= "<option value='' $sel >(select)</option>\n";
  $s .= "<option value='new' >(new)</option>\n"  if ( $newpersonfield );
  while ( my ($persid, $name, $last) = $list_sth->fetchrow_array ) {
    $sel = "";
    $sel = "Selected" if $persid eq $selected;
    $s .=  "<option value='$persid' $sel $width >$name</option>\n";
  }
  $s .= "</select>\n";
  return $s;
} # selectperson


################################################################################
# Report module loaded ok
1;
