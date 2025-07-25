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
sub listpersons {
  my $c = shift; # context

  if ( $c->{edit} ) {
    editperson($c);
    return;
  }
  print "&nbsp;Persons <a href=\"$c->{url}?o=$c->{op}&e=new\"><span>(New)</span></a>";

  my $sort = $c->{sort} || "Last-";
  print listrecords::listrecords($c, "PERSONS_LIST", $sort );
  return;

} # listpersons

################################################################################
# Person details
################################################################################
# Show when and where we have seen that person, and comments
sub showpersondetails {
  my $c = shift;
  my $pers = shift;

  my $pers_seen_sql = "
  select
    comments.*,
    PERSONS.Name as PersName,
    PERSONS.Id as PersId,
    strftime('%Y-%m-%d %w', g.timestamp, '-06:00') as effdate,
    strftime('%H:%M', g.timestamp, '-06:00') as time,
    g.Location as loc,
    g.brewtype as brewtype,
    g.subtype as subtype,
    g.id as id
  from comments
  left join persons on persons.id = comments.person
  left join glasses g on g.id = comments.glass
  left join locations l on l.id = g.location
  where
  comments.Glass in  ( select Glass from comments c2 where c2.person = ? )
    order by g.Timestamp desc, comments.id desc
  ";
  my $sth = db::query($c, $pers_seen_sql, $pers->{Id} );
  my $curgl = "";
  while ( my $rec = $sth->fetchrow_hashref) {
    if ( $curgl ne $rec->{Glass} ) {
      $curgl = $rec->{Glass};
      mainlist::locationhead($c,$rec);
      mainlist::nameline($c,$rec);
    }
    print comments::commentline($c,$rec), "<br/>\n";
  }

} # showpersondetails


################################################################################
# Editperson - Show a form for editing a person record
################################################################################
# TODO - Show extended info about the person, like when and where seen,
# associations with other people etc
sub editperson {
  my $c = shift;
  my $p={};
  $p->{Id} = "";  # to avoid undefs in insert case

  print "\n<form method='POST' accept-charset='UTF-8' class='no-print' " .
      "enctype='multipart/form-data'>\n";

  if ( $c->{edit} !~ /^new/i ) {
    $p = db::getrecord($c,"PERSONS", $c->{edit} );
    util::error("Could not find person '$c->{edit}'" ) unless $p;
    print "<input type='hidden' name='id' value='$p->{Id}' />\n";
    print "<input type='hidden' name='e' value='$p->{Id}' />\n";
    print "<b>Editing Person $c->{edit}: $p->{Name}</b><br/>\n";
  } else {
    print "<b>New Person:</b><br/>";
  }

  print inputs::inputform( $c, "PERSONS", $p );
  if ( $c->{edit} =~ /^new/i ) {
    print "<br/><input type='submit' name='submit' value='Insert Person' />\n";
  } else {
    print "<br/><input type='submit' name='submit' value='Update Person' />\n";
    print "<br/><br/><input type='submit' name='submit' value='Create a Copy' />\n";
    print "<input type='submit' name='submit' value='Delete Person' />\n";
  }
  # Come back to here after updating
  print "<input type='hidden' name='o' value='$c->{op}' />\n";
  print "</form>\n";
  print "<hr/>\n";

  showpersondetails($c,$p);
} # editperson


################################################################################
# Update a person (posted from the form above)
################################################################################
sub postperson {
  my $c = shift; # context
  # Validate
  my $name = $c->{cgi}->param("Name");
  error ("A Person must have a name" )
    unless $name;
  db::postrecord($c, "PERSONS");
  return;

} # postperson

################################################################################
# Helper to select a person
################################################################################
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
  my $s = inputs::dropdown( $c, $fieldname, $selected, $current, $opts, "PERSONS", "newperson" );
  return $s;
} # selectperson


################################################################################
# Report module loaded ok
1;
