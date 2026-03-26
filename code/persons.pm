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
  print listrecords::listrecords($c, "PERSONS_LIST", $sort);
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
    group_concat(cp_persons.Name, ', ') as PeopleNames,
    strftime('%Y-%m-%d %w', g.timestamp, '-06:00') as effdate,
    strftime('%H:%M', g.timestamp, '-06:00') as time,
    g.Location as loc,
    l.Name as locname,
    l.Website as locwebsite,
    g.brewtype as brewtype,
    g.subtype as subtype,
    g.id as id
  from comments
  left join comment_persons cp on cp.Comment = comments.Id
  left join persons cp_persons on cp_persons.Id = cp.Person
  left join glasses g on g.id = comments.glass
  left join locations l on l.id = g.location
  where comments.Glass in (
    select c2.Glass from comments c2
    join comment_persons cp2 on cp2.Comment = c2.Id
    join glasses g2 on g2.Id = c2.Glass
    where cp2.Person = ?
      and g2.username = ?
      and c2.Glass IS NOT NULL)
  and (comments.Username IS NULL OR comments.Username = ?)
  group by comments.Id
  order by COALESCE(g.Timestamp, comments.Ts) desc, comments.id desc
  ";
  my $sth = db::query($c, $pers_seen_sql, $pers->{Id}, $c->{username}, $c->{username} );
  my $curgl = "";
  while ( my $rec = $sth->fetchrow_hashref) {
    if ( $curgl ne $rec->{Glass} ) {
      $curgl = $rec->{Glass};
      mainlist::locationhead($c,$rec);
      mainlist::nameline($c,$rec);
    }
    print comments::commentline($c, $rec, 1), "<br/>\n";
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

  my $tags_ref = db::all_tags($c, "PERSONS");
  print inputs::inputform( $c, "PERSONS", $p, "", "", "<br/>", "Id", $tags_ref );
  if ( $c->{edit} =~ /^new/i ) {
    print "<br/><input type='submit' name='submit' value='Insert Person' />\n";
  } else {
    print "<br/><button type='button' class='edit-enable-btn' onclick='enableEditing(this.form)'>Edit</button>\n";
    print "<input type='submit' name='submit' value='Update Person' class='edit-submit-btn' hidden />\n";
    print "<br/><br/><input type='submit' name='submit' value='Create a Copy' class='edit-submit-btn' hidden />\n";
    print "<input type='submit' name='submit' value='Delete Person' class='edit-submit-btn' hidden />\n";
  }
  # Come back to here after updating
  print "<input type='hidden' name='o' value='$c->{op}' />\n";
  print "</form>\n";
  print "<hr/>\n";

  if ( $c->{edit} !~ /^new/i ) {
    my $return_url = "$c->{url}?o=$c->{op}&e=$p->{Id}";
    print photos::thumbnails_html($c, 'Person', $p->{Id});
    print photos::photo_form($c, person => $p->{Id}, public_default => 0, return_url => $return_url);
    print "&nbsp;<a href='$c->{url}?o=Comment&e=new&person=$p->{Id}&commenttype=person'><span>(new comment)</span></a>\n";
    print "<hr/>\n";
  }

  showpersondetails($c,$p);
} # editperson


################################################################################
# Update a person (posted from the form above)
################################################################################
sub postperson {
  my $c = shift; # context
  # Validate
  my $name = util::param($c, "Name");
  util::error ("A Person must have a name" )
    unless $name;
  $c->{cgi}->param('Tags', util::clean_tags(util::param($c, 'Tags')));
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
  my $disabled = shift || "";  # "disabled" or ""
  my $multi    = shift || "";  # "multi" for chip multi-select
  my $prechips = shift || "";  # pre-rendered chip HTML for edit mode
  my $sql = "
  select
    PERSONS.Id,
    PERSONS.Name,
    strftime ( '%Y-%m-%d %w', max(GLASSES.Timestamp), '-06:00' ) as last,
    PERSONS.Tags
  from PERSONS
  left join comment_persons cp on cp.Person = Persons.Id
  left join COMMENTS on COMMENTS.Id = cp.Comment
  left join GLASSES on GLASSES.Id = COMMENTS.Glass
  group by Persons.id
  order by GLASSES.Timestamp DESC
  ";
  my $list_sth = db::query($c, $sql);

  my $opts = "";

  my $current = "";
  while ( my ($id, $name, $last, $tags) = $list_sth->fetchrow_array ) {
    my $tags_attr = $tags ? " tags='" . util::htmlesc($tags) . "'" : "";
    $opts .= "      <div class='dropdown-item' id='$id'$tags_attr>$name</div>\n";
    if ( $id eq $selected ) {
      $current = $name;
    }
  }
  my $s = inputs::dropdown( $c, $fieldname, $selected, $current, $opts, "PERSONS",
   "newperson", "Id|Username", $disabled, "", $multi, $prechips );
  return $s;
} # selectperson


################################################################################
# Report module loaded ok
1;
