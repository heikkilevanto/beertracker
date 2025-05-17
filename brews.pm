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
# Brew colors
################################################################################



# Returns the background color for the brew
# Takes a style string as the argument. That way it can also
# be used for the few non-brew items that need special color, like restaurants
# Returns just the color string with no prefix.
sub brewcolor {
  my $brew = shift;

  # TODO - Add prefixes for beers
  # TODO - Check against actual brew styles in the db
  my @drinkcolors = (   # color, pattern. First match counts, so order matters
      "003000", "restaurant", # regular bg color, no highlight
      "eac4a6", "wine[, ]+white",
      "801414", "wine[, ]+red",
      "4f1717", "wine[, ]+port",
      "aa7e7e", "wine",
      "f2f21f", "Pils|Lager|Keller|Bock|Helles|IPL",
      "e5bc27", "Classic|dunkel|shcwarz|vienna",
      "adaa9d", "smoke|rauch|sc?h?lenkerla",
      "350f07", "stout|port",  # imp comes later
      "1a8d8d", "sour|kriek|lambie?c?k?|gueuze|gueze|geuze|berliner",
      "8cf2ed", "booze|sc?h?nap+s|whisky",
      "e07e1d", "cider",
      "eaeac7", "weiss|wit|wheat|weizen",
      "66592c", "Black IPA|BIPA",
      "9ec91e", "NEIPA|New England",
      "c9d613", "IPA|NE|WC",  # pretty late, NE matches pilsNEr
      "d8d80f", "Pale Ale|PA",
      "b7930e", "Old|Brown|Red|Dark|Ale|Belgian||Tripel|Dubbel|IDA",   # Any kind of ales (after Pale Ale)
      "350f07", "Imp",
      "dbb83b", "misc|mix|random",
      "9400d3", ".",   # # dark-violet, aggressive pink to show we don't have a color
      );

  my $type;
  if ( $brew =~ /^\[?(\w+)(,(.+))?\]?$/i ) {
    $type = "$1";
    $type .= ",$3" if ( $3 );
  } else {
    util::error("Can not get style color for '$brew'");
  }
  for ( my $i = 0; $i < scalar(@drinkcolors); $i+=2) {
    my $pat = $drinkcolors[$i+1];
    if ( $type =~ /$pat/i ) {
      #print STDERR "brewcolor: got '$drinkcolors[$i]' for '$type' via '$pat' \n";
      return $drinkcolors[$i] ;
    }
  }
  error ("Can not get color for '$brew': '$type'");
}

# Returns a HTML style definition for the brew or style string
# Guesses a contrasting foreground color
sub brewtextstyle {
  my $c = shift;
  my $brew = shift;
  my $bkg = brewcolor($brew);
  my $lum = ( hex($1) + hex($2) + hex($3) ) /3  if ($bkg =~ /^(..)(..)(..)/i );
  my $fg = $c->{bgcolor};
  if ($lum < 64) {  # If a fairly dark color
    $fg = "#ffffff"; # put white text on it
  }
  return "style='background-color:#$bkg;color:$fg;'";
}

################################################################################
# List of brews
################################################################################
# TODO - More display fields. Country, region, etc
# TODO - Filtering by brew type, subtype, name, producer, etc
sub listbrews {
  my $c = shift; # context

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
  if ( $p->{Id} ) {  # found the brew
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
    $defaults->{BrewType} = util::param($c, "selbrewtype") || "WRONG"; # Signals a bad type. Should not happen
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
# TODO - Behaves funny with Restaurants and Nights
sub insert_old_style_brew {
  my $c = shift;
  my $type = util::param($c, "type");
  my $name = util::param($c, "name");
  my $maker = util::param($c, "maker");
  my $style = util::param($c, "style");
  my $subtype = util::param($c, "subtype") || "Ale"; # TODO Calculate subtype properly
  my $country = util::param($c, "country");
  my $alc= util::param($c, "alc");
  print STDERR "insert_old_style_brew: t='$type' st='$subtype' n='$name' m='$maker' sty='$style' \n";

  if ( ! $name ){  # Sanity check
    util::error( "insert_old_style_brew: NO NAME! t='$type' st='$subtype' n='$name' m='$maker'");
  }

  # Check if we have it already
  my $brew = util::findrecord($c, "BREWS", "Name", $name, "collate nocase" );
  if ( $brew) {
    print STDERR "insert_old_style_brew: Found brew: Id=$brew->{Id}  \n";
    return $brew->{Id}
  }

  util::error( "insert_old_style_brew: NO MAKER" ) unless ($maker);
  # Get the producer (as location)
  my $sql = "Select Id from LOCATIONS where Name = ? collate nocase";
  my $get_sth = $c->{dbh}->prepare($sql);
  $get_sth->execute($maker);
  my $prodlocid = $get_sth->fetchrow_array;
  if ( ! $prodlocid ) {
    $sql = "Insert into LOCATIONS ( Name, LocType, LocSubType ) values (?, 'Producer', 'Beer')";
    my $loc_sth = $c->{dbh}->prepare($sql);
    $loc_sth->execute($maker);
    $prodlocid = $c->{dbh}->last_insert_id(undef, undef, "LOCATIONS", undef);
    print STDERR "insert_old_style_brew: Inserted producer location '$maker' as id '$prodlocid' \n";
  } else {
    print STDERR "insert_old_style_brew: Found maker  m='$maker'  as id = '$prodlocid' \n";
  }
  $sql = "insert into BREWS
    ( Name, BrewType, SubType, BrewStyle, ProducerLocation, Alc, Country )
    values ( ?, ?, ?, ?, ?, ?, ? ) ";
  my $ins_sth = $c->{dbh}->prepare($sql);
  $ins_sth->execute( $name, $type, $subtype, $style, $prodlocid, $alc, $country);
  my $id = $c->{dbh}->last_insert_id(undef, undef, "LOCATIONS", undef);
  print STDERR "insert_old_style_brew: Inserted '$name' into BREWS as id '$id' \n";
  return $id;

}

################################################################################
# Report module loaded ok
1;
