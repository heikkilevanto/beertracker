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
    return;
  }

  # Sort order or filtering
  my $sort = "last DESC";
  $sort = "BREWS.Id" if ( $c->{sort} eq "id" );
  $sort = "BREWS.Name" if ( $c->{sort} eq "name" );
  $sort = "BREWS.Producer" if ( $c->{sort} eq "maker" );
  $sort = "BREWS.BrewType, BREWS.Subtype COLLATE NOCASE" if ( $c->{sort} eq "type" );
  $sort = "last DESC" if ( $c->{sort} eq "last" );
  $sort = "LOCATIONS.Name" if ( $c->{sort} eq "where" );

  # Print list of people
  my $sql = "
  select
    BREWS.Id,
    BREWS.Name,
    BREWS.Producer,
    BREWS.BrewType,
    BREWS.Subtype,
    strftime ( '%Y-%m-%d %w', max(GLASSES.Timestamp), '-06:00' ) as last,
    LOCATIONS.Name as loc,
    count(COMMENTS.Id) as count
  from BREWS
  left join GLASSES on Glasses.Brew = BREWS.Id
  left join COMMENTS on COMMENTS.Glass = GLASSES.Id
  left join LOCATIONS on LOCATIONS.id = GLASSES.Location
  group by BREWS.id
  order by $sort
  ";
  my $list_sth = $c->{dbh}->prepare($sql);
  #$list_sth->execute($c->{username});
  $list_sth->execute();

  print "<table><tr>\n";
  my $url = $c->{url};
  my $op = $c->{op};
  my $maxwidth = "style='max-width:20em;'";
  print "<td><a href='$url?o=$op&s=id'><i>Id</i></a></td>";
  print "<td><a href='$url?o=$op&s=name'><i>Name</i></a></td>";
  print "<td><a href='$url?o=$op&s=maker'><i>Producer</i></a></td>";
  print "<td><a href='$url?o=$op&s=type'><i>Type</i></a></td>";
  print "<td colspan=2 ><a href='$url?o=$op&s=last'><i>Last seen</i></a></td>";
  print "<td><a href='$url?o=$op&s=where'><i>Where</i></a></td></tr>";
  while ( my ($id, $name, $maker, $typ, $sub, $last, $loc, $count) = $list_sth->fetchrow_array ) {
    $loc = "" unless ($loc);
    my ($stamp, $wd) = util::splitdate($last);

    print "<tr><td style='font-size: xx-small' align='right'>$id</td>\n";
    print "<td $maxwidth><a href='$url?o=$op&e=$id'><b>$name</b></a>";
    print " ($count) " if ( $count > 1 );
    print "<td $maxwidth>$maker</td>";
    print "</td>\n";
    print "<td>$typ, $sub </td>\n";
    print "<td>$wd</td>\n";
    print "<td>" . main::filt($stamp,"","","full") . "</td>\n";
    print "<td>$loc</td></tr>\n";
  }
  print "</table>\n";
  print "<hr/>\n" ;
} # listbrews


################################################################################
# Select a brew
# A key component of the main input form
################################################################################
# TODO - Many features missing
# TODO - Display the brew details under the selection, with an edit link


sub selectbrew {
  my $c = shift; # context
  my $selected = shift || "";  # The id of the selected brew
  my $brewtype = shift || "";

  my $sql = "
    select
      BREWS.Id, BREWS.Brewtype, BREWS.SubType, Name, Producer, BREWS.Alc
    from BREWS
    left join GLASSES on GLASSES.Brew= BREWS.ID
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
# TODO - Calculate subtype, if not set. Make a separate helper, use in import
sub postbrew {
  my $c = shift; # context
  my $id = shift || $c->{edit};
  if ( $id eq "new" ) {
    my $name = util::param($c, "newbrewName");
    util::error ("A brew must have a name" ) unless $name;
    util::error ("A brew must have a type" ) unless util::param($c, "newbrewBrewType");

    $id = util::insertrecord($c,  "BREWS", "newbrew");
    return $id;

    my $sql = "insert into BREWS
       ( Name, BrewType, SubType,
         BrewStyle, Producer, Alc,
         Country, Region, Flavor, Year, Details )
       values ( ?, ?, ?,  ?, ?, ?,  ?, ?, ?, ?, ? ) ";
    my $sth = $c->{dbh}->prepare($sql);
    $sth->execute(
      $name,
      util::param($c,"selbrewtype"),
      util::param($c,"newbrewsub"),
      util::param($c,"newbrewstyle"),
      util::param($c,"newbrewproducer"),
      util::param($c,"newalc"),
      util::param($c,"newbrewcountry"),
      util::param($c,"newbrewregion"),
      util::param($c,"newbrewflavor"),
      util::param($c,"newbrewyear"),
      util::param($c,"newbrewdetails")
    );
    $id = $c->{dbh}->last_insert_id(undef, undef, "BREWS", undef) || undef;
    print STDERR "Inserted Brew id '$id' '$name' \n";
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
