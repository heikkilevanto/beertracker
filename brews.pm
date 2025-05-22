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
sub listbrews {
  my $c = shift; # context

  if ( $c->{edit} ) {
    editbrew($c);
    return;
  }
  print "<b>Brews</b> ";
  print "&nbsp;<a href=\"$c->{url}?o=$c->{op}&e=new\"><span>(New)</span></a>";
  print "<br/>\n";
  print util::listrecords($c, "BREWS_LIST", "Last-" );
  return;
} # listbrews

################################################################################
# List all comments for the given brew
################################################################################
sub listbrewcomments {
  my $c = shift; # context
  my $brew = shift;
  print "<!-- listbrewcomments -->\n";
  my $sql = "
    SELECT
      COMMENTS.Id as Cid,
      strftime('%Y-%m-%d', GLASSES.Timestamp,'-06:00') as Date,
      strftime('%H:%M', GLASSES.Timestamp) as Time,
      comments.Rating as Rating,
      COMMENTS.Comment,
      PERSONS.Id as Pid,
      PERSONS.Name as Person,
      COMMENTS.Photo as XPhoto,
      GLASSES.Id as Gid,
      GLASSES.Brew as Brew,
      Glasses.Volume,
      Glasses.Price,
      Locations.Name as Loc,
      Locations.Id as Lid
      from COMMENTS, GLASSES
      LEFT JOIN PERSONS on PERSONS.id = COMMENTS.Person
      LEFT JOIN LOCATIONS on LOCATIONS.Id = GLASSES.Location
      where COMMENTS.glass = GLASSES.id
       and Brew = ?
      order by GLASSES.Timestamp Desc ";
  #print STDERR "listbrewcomments: id='$brew->{Id}': $sql \n";
  my $sth = $c->{dbh}->prepare($sql);
  $sth->execute($brew->{Id});
  print "<div style='overflow-x: auto;'>";
  print "<table >\n";
  my $ratesum = 0;
  my $ratecount = 0;
  my $comcount = 0;
  my $perscount = 0;
  my $sty = "style='border-bottom: 1px solid white; vertical-align: top;' ";
  while ( my $com = $sth->fetchrow_hashref ) {
    print "<tr><td $sty>\n";
    print "<a href='$c->{url}?o=full&e=$com->{Gid}&ec=$com->{Cid}'><span>";
    print "$com->{Date}</span></a><br/> \n";
    my $tim = $com->{Time};
    $tim = "($tim)" if ($tim lt "06:00");
    print "$tim\n";
    print "<span style='font-size: xx-small'>" .
          "[$com->{Cid}]</span>";
    print "</td>\n";

    print "<td style='border-bottom: 1px solid white'>\n";
    if ( $com->{Rating} ) {
      print "<b>($com->{Rating})</b>\n";
      $ratesum += $com->{Rating};
      $ratecount++;
    }
    print "</td>\n";

    print "<td style='border-bottom: 1px solid white; vertical-align: top; white-space:normal'>\n";
    print "<a href='$c->{url}?o=Location&e=$com->{Lid}' ><span><b>$com->{Loc}</b></span></a> &nbsp;";
    print util::unit($com->{Volume},"c")   if ( $com->{Volume} ) ;
    print util::unit($com->{Price},",-")   if ( $com->{Price} ) ;
    print "<br/>";
    print "<i>$com->{Comment}</i>";
    $comcount++ if ($com->{Comment});
    print "</td>\n";

    print "<td $sty>\n";
    if ( $com->{Person} ) {
      print "<a href='$c->{url}?o=Person&e=$com->{Pid}'><span style='font-weight: bold;'>$com->{Person}</span></a>\n";
      $perscount++;
    }
    print "</td>\n";
    # TODO - Photo thumbnail in its own TD
    print "</tr>\n";
  }
  print "</table></div>\n";
  print "<div onclick='toggleCommentTable(this);'><br/>";
  if ( $comcount == 0 ) {
    print "(No Comments)";
  } else {
    if ( $ratecount == 1) {
      print "One rating: <b>" . comments::ratingline($ratesum) . "</b> ";
    } elsif ( $ratecount > 0 ) {
      my $avg = sprintf( "%3.1f", $ratesum / $ratecount);
      print "$ratecount Ratings averaging <b>" . comments::ratingline($avg) . "</b>. ";
    } else {
      print "Comments: $comcount. ";
    }
  }
  print "</div>";
  print "<script>
    function toggleCommentTable(div) {
      let table = div.previousElementSibling;
      if (table) {
        table.style.display = (table.style.display === 'none') ? 'table' : 'none';
      }
    }
    </script>
    ";
  $sth->finish;
  print "<!-- listbrewcomments end -->\n";
  print "<hr/>\n";

} # listbrewcomments


################################################################################
# List all glasses for the given brew
################################################################################
sub listbrewglasses {
  my $c = shift; # context
  my $brew = shift;
  print "<!-- listbrewglasses -->\n";
  my $sql = "
    SELECT
      COMMENTS.Id as Cid,
      strftime('%Y-%m-%d', GLASSES.Timestamp,'-06:00') as Date,
      strftime('%H:%M', GLASSES.Timestamp) as Time,
      comments.Rating as Rating,
      COMMENTS.Comment,
      GLASSES.Id as Gid,
      GLASSES.Brew as Brew,
      Glasses.Volume,
      Glasses.Price,
      Locations.Name as Loc,
      Locations.Id as Lid
      from GLASSES
      LEFT JOIN LOCATIONS on LOCATIONS.Id = GLASSES.Location
      LEFT JOIN COMMENTS on COMMENTS.Glass = GLASSES.Id
      WHERE Brew = ?
      order by GLASSES.Timestamp Desc ";
  #print STDERR "listbrewcomments: id='$brew->{Id}': $sql \n";
  my $sth = $c->{dbh}->prepare($sql);
  $sth->execute($brew->{Id});
  my $glcount = 0;
  print "<div style='overflow-x: auto;'>";
  print "<table  style='white-space: nowrap;'>\n";
  while ( my $com = $sth->fetchrow_hashref ) {
    $glcount++;
    print "<tr><td>\n";
    print "<span style='font-size: xx-small'>" .
          "[$com->{Gid}]</span></td>\n";
    print "<td><a href='$c->{url}?o=full&e=$com->{Gid}'><span>";
    print "$com->{Date} </span></a>";
    my $tim = $com->{Time};
    $tim = "($tim)" if ($tim lt "06:00");
    print "$tim\n";
    print "</td>\n";

    print "<td>\n";
    print util::unit($com->{Volume},"c")   if ( $com->{Volume} ) ;
    print "</td><td>\n";

    print util::unit($com->{Price},",-")   if ( $com->{Price} ) ;
    print "</td><td>\n";

    if ( $com->{Rating} ) {
      print "<b>($com->{Rating})</b>" ;
    } elsif ( $com->{Comment} ) {
      print "<b>(*)</b>\n"  ;
    }
    print "</td><td>\n";

    print "<a href='$c->{url}?o=Location&e=$com->{Lid}' ><span><b>$com->{Loc}</b></span></a> &nbsp;";
    print "</td>\n";
    print "</tr>\n";
  }
  print "</table></div>\n";
  print "<div onclick='toggleCommentTable(this);'><br/>";
  print "$glcount Glasses ";
  print "</div>";
  $sth->finish;
  print "<!-- listbrewglasses end -->\n";
  print "<hr/>\n";

} # listbrewcomments

################################################################################
# brewdeduplist - List all brews, for selecting those that duplicate the current
################################################################################
sub brewdeduplist {
  my $c = shift; # context
  my $brew = shift;
  print "<!-- brewdeduplist -->\n";
  print "<form method='POST' accept-charset='UTF-8' class='no-print' >\n";
  print "Mark brews that are duplicates of [$brew->{Id}] $brew->{Name} ";
  print "and click here: \n";
  print "<input type=submit name=submit value='Deduplicate' />\n";
  print "<input type=hidden name='o' value='$c->{op}' />\n";
  print "<input type=hidden name='e' value='$c->{edit}' />\n";
  print "<input type=hidden name='dedup' value='1' />\n";
  print "<br/>\n";
  my $sort = $c->{sort} || "Last-";
  print util::listrecords($c, "BREWS_DEDUP_LIST", $sort, "Id <> $brew->{Id}" );
  print "</form>\n";
  print "<!-- brewdeduplist end -->\n";
  print "<hr/>\n";
} # brewdeduplist

################################################################################
# Editbrew - Show a form for editing a brew record
################################################################################


sub editbrew {
  my $c = shift;
  my $p = {};
  my $submit = "Update";
  if ( $c->{edit} =~ /new/i ) {
    $p->{Id} = "new";
    $p->{BrewType} = "Beer"; # Some decent defaults
    $p->{SubType} = "NEIPA"; # More for guiding the input than true values
    $p->{Country} = "DK";
    print "<b>Inserting a new brew<br/>\n";
    $submit = "Insert";
  } else {
    my $sql = "select * from BREWS where id = ?";
    my $get_sth = $c->{dbh}->prepare($sql);
    $get_sth->execute($c->{edit});
    $p = $get_sth->fetchrow_hashref;
    $get_sth->finish;
    print "<b>Editing Brew $p->{Id}: $p->{Name}</b><br/>\n";
  }
  if ( $p->{Id} ) {  # found the brew
    print "\n<form method='POST' accept-charset='UTF-8' class='no-print' " .
        "enctype='multipart/form-data'>\n";
    print "<input type='hidden' name='e' value='$p->{Id}' />\n";
    print "<input type='hidden' name='id' value='$p->{Id}' />\n";

    print util::inputform($c, "BREWS", $p );
    print "<input type='submit' name='submit' value='$submit Brew' />\n";
    print "<a href='$c->{url}?o=$c->{op}'><span>Cancel</span></a>\n";
    print "<br/>\n";

    # Come back to here after updating
    print "<input type='hidden' name='o' value='$c->{op}' />\n";
    print "</form>\n";
    print "<hr/>\n";
    if ( $p->{Id} ne "new" ) {
      listbrewcomments($c, $p);
      listbrewglasses($c, $p);
      brewdeduplist($c, $p);
    }
  } else {
    print "Oops - Brew id '$c->{edit}' not found <br/>\n";
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
  $list_sth->execute();

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
# Deduplicate brews
################################################################################
sub dedupbrews {
  my $c = shift;
  my $id = $c->{edit}; # The brew we keep
  foreach my $paramname ($c->{cgi}->param) {
    if ( $paramname =~ /^Chk(\d+)$/ ) {
      my $dup = $1;
      my $sql = "UPDATE GLASSES set Brew = ? where Brew = ?  ";
      print STDERR "$sql with '$id' and '$dup' \n";
      my $rows = $c->{dbh}->do($sql, undef, $id, $dup);
      util::error("Deduplicate brews: Failed to update glasses") unless $rows;
      print STDERR "Updated $rows glasses from $dup to $id\n";
      $sql = "DELETE FROM Brews WHERE Id = ? ";
      $rows = $c->{dbh}->do($sql, undef, $dup);
      util::error("Deduplicate brews: Failed to delete brew '$dup'") unless $rows;
      print STDERR "Deleted $rows brews with id  $dup\n";
    }
  }
} # dedupbrews

################################################################################
# Update a brew, posted from the form in the selection above
################################################################################
# TODO - Calculate subtype, if not set. Make a separate helper, use in import
sub postbrew {
  my $c = shift; # context
  my $id = shift || $c->{edit};
  if ( util::param($c,"dedup") ) {
    dedupbrews($c);
    return;
  }
  if ( $id eq "new" ) {
    my $section = "newbrew"; # as when inserted from main list
    my $name = util::param($c, "newbrewName");
    if ( !$name ) {
      $name = util::param($c, "Name");
      $section = "";
    }
    util::error ("A brew must have a name" ) unless $name;
    #util::error ("A brew must have a type" ) unless util::param($c, "newbrewBrewType");

    my $defaults = {};
    $defaults->{BrewType} = util::param($c, "selbrewtype") || "WRONG"; # Signals a bad type. Should not happen
    $id = util::insertrecord($c,  "BREWS", $section, $defaults);
    $c->{edit} = $id; # come back to the new beer
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
