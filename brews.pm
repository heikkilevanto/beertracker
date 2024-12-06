# Part of my beertracker
# Stuff for listing, selecting, adding, and editing brews


package brews;

use strict;
use warnings;
use feature 'unicode_strings';
use utf8;  # Source code and string literals are utf-8

# Formatting magic
my $clr = "Onfocus='value=value.trim();select();' autocapitalize='words'";


################################################################################
# List of brews
################################################################################
# TODO - More display fields. Country, region, etc
# TODO - Filtering by brew type, subtype, name, producer, etc
sub listbrews {
  my $c = shift; # context
  print util::listsmenu($c);
  print util::showmenu($c);
  print "<hr/>";

  if ( $c->{edit} =~ /^\d+$/ ) {  # Id for full info
    editbrew($c);
    return;
  }
  my $sort = $c->{sort} || "Last-";
  print util::listrecords($c, "BREWS_LIST", $sort );
  return;
} # listbrews

################################################################################
# Editbrew - Show a form for editing a brew record
################################################################################

sub editbrew {
  my $c = shift;
  my $sql = "select * from BREWS where id = ?";
    # This Can leak info from persons filed by other users. Not a problem now
  my $get_sth = $c->{dbh}->prepare($sql);
  $get_sth->execute($c->{edit});
  my $p = $get_sth->fetchrow_hashref;
  for my $f ( "ProducerLocation" ) {
    $p->{$f} = "" unless $p->{$f};  # Blank out null fields
  }
  if ( $p->{Id} ) {  # found the person
    print "\n<form method='POST' accept-charset='UTF-8' class='no-print' " .
        "enctype='multipart/form-data'>\n";
    print "<input type='hidden' name='id' value='$p->{Id}' />\n";
    print "<b>Editing Brew $p->{Id}: $p->{Name}</b><br/>\n";

    print util::inputform($c, "BREWS", $p );
    print "<input type='submit' name='submit' value='Update Brew' /><br/>\n";

    # Come back to here after updating
    print "<input type='hidden' name='o' value='$c->{op}' />\n";
    print "<input type='hidden' name='e' value='$p->{Id}' />\n";
    print "</form>\n";
    print "<hr/>\n";
    print "(This should show when I had the brew last, comments, ratings, etc)<br/>\n"; # TODO
  } else {
    print "Oops - location id '$c->{edit}' not found <br/>\n";
  }
} # editbrew


################################################################################
# Select a brew
# A key component of the main input form
################################################################################
# TODO - Display the brew details under the selection, with an edit link

sub selectbrew {
  my $c = shift; # context
  my $selected = shift || "";  # The id of the selected brew
  my $brewtype = shift || "";

  my $sql = "
    select
      BREWS.Id, BREWS.Brewtype, BREWS.SubType, Brews.Name,
      Locations.Name as Producer,
      BREWS.Alc
    from BREWS
    left join GLASSES on GLASSES.Brew= BREWS.ID
    left join LOCATIONS on LOCATIONS.Id = BREWS.ProducerLocation
    group by BREWS.id
    order by max(GLASSES.Timestamp) DESC
    ";
  my $list_sth = $c->{dbh}->prepare($sql);
  $list_sth->execute(); # username ?

  my $opts = "";
  my $current = "";

  while ( my ($id, $bt, $su, $na, $pr, $alc )  = $list_sth->fetchrow_array ) {
    if ( $id eq $selected ) {
      $current = $na;
    }
    my $disp = "";
    $disp .= $na if ($na);
    $disp = "$pr: $disp  " if ($pr && $na !~ /$pr/ );
    my $disptype = $su;
    $disptype .= $bt unless ($su);
    $disp .= " [$disptype]";
    #$disp = substr($disp, 0, 30);
    $opts .= "<div class='dropdown-item' id='$id' alc='$alc' brewtype='$bt' >$disp</div>\n";
  }
  my $s = util::dropdown( $c, "Brew", $selected, $current, $opts, "BREWS", "newbrew" );

  return $s;
}


################################################################################
# Update a brew, posted from the form in the selection above
################################################################################
# TODO - Calculate subtype, if not set. Make a separate helper, use in import
sub postbrew {
  my $c = shift; # context
  my $id = shift || $c->{edit};
  if ( $id eq "new" ) {
    my $name = util::param($c, "newbrewName");
    util::error ("A brew must have a name" ) unless $name;
    #util::error ("A brew must have a type" ) unless util::param($c, "newbrewBrewType");

    my $defaults = {};
    $defaults->{BrewType} = util::param($c,"selbrewtype") || util::param($c, "selbrewtype") || "Cider";
    $id = util::insertrecord($c,  "BREWS", "newbrew", $defaults);
    return $id;

  } else {
    util::error ("A brew must have a name" ) unless util::param($c, "Name");
    util::error ("A brew must have a type" ) unless util::param($c, "BrewType");
    $id = util::updaterecord($c, "BREWS", $id,  "");
  }
  return $id;
} # postbrew

################################################################################
# Helper to insert a brew record from old-style params
# Happens when the user clicks on the beer board
################################################################################
# TODO - Delete this once we have a new style beer board
sub insert_old_style_brew {
  my $c = shift;
  my $type = util::param($c, "type");
  my $name = util::param($c, "name");
  my $maker = util::param($c, "maker");
  my $style = util::param($c, "style");
  my $subtype = "Ale"; # TODO Calculate subtype properly

  my $sql = "Select Id from LOCATIONS where Name = ? collate nocase";
  my $get_sth = $c->{dbh}->prepare($sql);
  $get_sth->execute($maker);
  my $prodlocid = $get_sth->fetchrow_array;
  if ( ! $prodlocid ) {
    $sql = "Insert into LOCATIONS ( Name, SubType ) values (?, 'Beer-Maker')";
    my $loc_sth = $c->{dbh}->prepare($sql);
    $loc_sth->execute($maker);
    $prodlocid = $c->{dbh}->last_insert_id(undef, undef, "LOCATIONS", undef);
    print STDERR "insert_old_style_brew: Inserted location '$maker' as id '$prodlocid' \n";
  }


  $sql = "insert into BREWS
    ( Name, BrewType, SubType, BrewStyle, ProducerLocation )
    values ( ?, ?, ?, ?, ? ) ";
  my $ins_sth = $c->{dbh}->prepare($sql);
  $ins_sth->execute( $name, $type, $subtype, $style, $prodlocid);
  my $id = $c->{dbh}->last_insert_id(undef, undef, "LOCATIONS", undef);
  print STDERR "Inserted '$name' into BREWS as id '$id' \n";
  return $id;

}
################################################################################
# Helper to get a brew record
################################################################################
sub getbrew {
  my $c = shift;
  my $id = shift;
  return undef unless ($id);
  my $sql = "select * from BREWS where id = ? ";
  my $sth = $c->{dbh}->prepare($sql);
  $sth->execute($id);
  my $brew = $sth->fetchrow_hashref;
  return $brew;
}

################################################################################
# Report module loaded ok
1;
