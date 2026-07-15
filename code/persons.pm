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
  my $sort = $c->{sort} || "Last-";
  print listrecords::listrecords($c, "PERSONS_LIST", $sort,
      { title => "Persons" });
  return;
} # listpersons


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
    print "<br/><button type='button' class='edit-enable-btn' onclick='enableEditing(this.form)'>Edit</button>&nbsp;<a href='$c->{url}?o=$c->{op}'><span>Cancel</span></a>\n";
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

  my $name = $p->{Name};
  print listrecords::listrecords($c, "COMMENTS_LIST", "Last-", {
      where => "EXISTS (SELECT 1 FROM comment_persons cp WHERE cp.Comment = \"Id_A_link:Comment\" AND cp.Person = ?) AND xUsername = ?",
      params => [$p->{Id}, $c->{username}],
      title => "Comments mentioning $name",
      initial_filter => { CommentType => "person" },
      no_new_link => 1,
  });
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
  my $s = inputs::dropdown( $c, $fieldname, $selected, $current, $opts,
   { table => "PERSONS", newfield => "newperson", skip => "Id|Username", disabled => $disabled, multi => $multi, prechips => $prechips } );
  return $s;
} # selectperson


################################################################################
# Report module loaded ok
1;
