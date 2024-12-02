# Part of my beertracker
# Stuff for listing, selecting, adding, and editing brews

# TODO SOON - Edit a brew, maybe insert a new

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
    #editbrew($c);  # TODO
    print "Editing of BREWS not implemented yet";
    return;
  }
  my $sort = $c->{sort} || "Last-";
  print util::listrecords($c, "BREWS_LIST", $sort );
  return;

} # listbrews


################################################################################
# Select a brew
# A key component of the main input form
################################################################################
# TODO - Many features missing
# TODO - Display the brew details under the selection, with an edit link
# TODO - Some fields not handled right yet: Producer, Year. BrewStyle as a select with default?

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
    $disp = "$pr: $disp  " if ($pr && $na !~ /$pr/ ); # TODO Shorten producer names
    my $disptype = $su;
    $disptype .= $bt unless ($su);
    $disp .= " [$disptype]";
    #$disp = substr($disp, 0, 30);
    $opts .= "<div class='dropdown-item' id='$id'>$disp</div>\n";
  }
  my $s = util::dropdown( $c, "Brew", $selected, $current, $opts, "BREWS", "newbrew" );

  return $s;
}


################################################################################
# Update a brew, posted from the form in the selection above
################################################################################
# TODO SOON - Get a default BrewType
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
    # TODO - Implement updating Brews when we have the edit form in place
  }
  return $id;
} # postbrew

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
