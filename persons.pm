# Part of my beertracker
# Routines for displaying and editing persons

package persons;
use strict;
use warnings;
use feature 'unicode_strings';
use utf8;  # Source code and string literals are utf-8

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

  my $sort = $c->{sort} || "Last-";
  print util::listrecords($c, "PERSONS_LIST", $sort );
  return;

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
    print "<b>Editing Person $p->{Id}: $p->{Name}</b><br/>\n";

    print util::inputform( $c, "PERSONS", $p );
    print "<input type='submit' name='submit' value='Update Person' /><br/>\n";

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
# TODO LATER - Insert new person here as well?
sub postperson {
  my $c = shift; # context
  my $id = $c->{edit};
  util::error ("Bad id for updating a person '$id' ")
    unless $id =~ /^\d+$/;
  my $name = $c->{cgi}->param("Name");
  error ("A Person must have a name" )
    unless $name;
  util::updaterecord($c, "PERSONS", $id);
  return;

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

  my $opts = "";

  my $current = "";
  while ( my ($id, $name ) = $list_sth->fetchrow_array ) {
    $opts .= "      <div class='dropdown-item' id='$id'>$name</div>\n";
    if ( $id eq $selected ) {
      $current = $name;
    }
  }
  my $s = util::dropdown( $c, $fieldname, $selected, $current, $opts, "PERSONS", "newperson" );
  return $s;
} # selectperson


################################################################################
# Report module loaded ok
1;
