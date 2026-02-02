# Part of my beertracker
# Stuff for listing, selecting, adding, and editing brews


package brews;

use strict;
use warnings;
use feature 'unicode_strings';
use utf8;  # Source code and string literals are utf-8

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
  print listrecords::listrecords($c, "BREWS_LIST", "Last-" );
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
       and Glasses.username = ?
      order by GLASSES.Timestamp Desc ";
  #print STDERR "listbrewcomments: id='$brew->{Id}': $sql \n";
  my $sth = $c->{dbh}->prepare($sql);
  $sth->execute($brew->{Id}, $c->{username});
  print "<div onclick='toggleElement(this.nextElementSibling);'>";
  print "Comments and ratings for <b>$brew->{Name}</b> <br/>\n";
  print "</div>\n";
  print "<div style='overflow-x: auto;'>";
  print "<table >\n";
  my $ratesum = 0;
  my $ratecount = 0;
  my $comcount = 0;
  my $perscount = 0;
  my $count = 0;
  my $sty = "style='border-bottom: 1px solid white; vertical-align: top;' ";
  while ( my $com = $sth->fetchrow_hashref ) {
    print "<tr><td $sty>\n";
    print "<a href='$c->{url}?o=Full&e=$com->{Gid}&ec=$com->{Cid}'><span>";
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
    if ( $com->{Lid} ) {
      print "<a href='$c->{url}?o=Location&e=$com->{Lid}' ><span><b>$com->{Loc}</b></span></a> &nbsp;";
    } else {
      print "<b>$com->{Loc}</b> &nbsp;" if $com->{Loc};
    }
    print util::unit($com->{Volume},"c")   if ( $com->{Volume} ) ;
    print util::unit($com->{Price},",-")   if ( $com->{Price} ) ;
    print "<br/>";
    print "<i>$com->{Comment}</i>" if $com->{Comment};
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
  print "<div onclick='toggleElement(this.previousElementSibling);'><br/>";
  if ( $comcount == 0 ) {
    print "(No Comments by $c->{username})";
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
  $sth->finish;
  print "<!-- listbrewcomments end -->\n";
  print "<hr/>\n";

} # listbrewcomments


################################################################################
# List latest prices at various locations
################################################################################
sub listbrewprices {
  my $c = shift; # context
  my $brew = shift;
  print "<!-- listbrewprices -->\n";
  my $sql = "
    SELECT * from LatestPrices
    WHERE Brew = ?
      AND username = ?
    ORDER by Timestamp DESC";
  my $sth = $c->{dbh}->prepare($sql);
  $sth->execute($brew->{Id}, $c->{username});
  print "<div onclick='toggleElement(this.nextElementSibling);'>";
  print "Latest prices for <b>$brew->{Name}</b> <br/>\n";
  print "</div>\n";
  print "<div style='overflow-x: auto;'>";
  print "<table >\n";
  my $sty = "style='white-space: nowrap;' ";
  while ( my $com = $sth->fetchrow_hashref ) {
    print "<tr><td $sty>\n";
    print "$com->{Timestamp}<br/> \n";
    print "<td $sty>\n";
    print util::unit($com->{Volume},"c")   if ( $com->{Volume} ) ;
    print "</td><td $sty>\n";
    print util::unit($com->{Price},",-")   if ( $com->{Price} ) ;
    print "</td><td $sty>\n";
    if ( $com->{Price} && $com->{Volume} ) {
      print "<form method='POST' accept-charset='UTF-8' style='display:inline;'>\n";
      print "<input type='hidden' name='o' value='Brews' />\n";
      print "<input type='hidden' name='e' value='$brew->{Id}' />\n";
      print "<input type='hidden' name='setdefaultprice' value='$com->{Price}' />\n";
      print "<input type='hidden' name='setdefaultvol' value='$com->{Volume}' />\n";
      print "<input type='submit' value='Def' style='font-size: x-small;' />\n";
      print "</form>\n";
    } else {
      print "&nbsp;";
    }
    print "</td><td $sty>\n";
    print $com->{LocationName};
    print " ($com->{Count})" if ($com->{Count} && $com->{Count} > 1);
    print "</td>\n";
    print "</tr>\n";
  }
  print "</table></div>\n";
  print "<div onclick='toggleElement(this.previousElementSibling);'><br/>";
  print "</div>";
  $sth->finish;
  print "<!-- listbrewprices end -->\n";
  print "<hr/>\n";

} # listbrewprices

################################################################################
sub update_brew_defaults {
  my ($c, $brew_id, $price, $vol) = @_;
  my $rows = $c->{dbh}->do("UPDATE brews SET DefPrice = ?, DefVol = ? WHERE Id = ?", undef, $price, $vol, $brew_id);
  if ($rows != 1) {
    util::error("Failed to update defaults for brew $brew_id");
  }
  print STDERR "Updated brew $brew_id DefPrice to $price, DefVol to $vol\n";
} # update_brew_defaults

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
        and Glasses.username = ?
      order by GLASSES.Timestamp Desc ";
  my $sth = $c->{dbh}->prepare($sql);
  $sth->execute($brew->{Id}, $c->{username});
  my $glcount = 0;
  my %years;
  my $firstrec;
  my $lastrec;
  while ( my $com = $sth->fetchrow_hashref ) {
    $glcount++;
    $firstrec = $com unless($firstrec);
    $lastrec = $com;
    my $year = substr($com->{Date}, 0, 4);
    push @{$years{$year}}, $com;
  }
  print "<div onclick='toggleElement(this.nextElementSibling);'><br/>";
  print "When and where: </div>\n";
  print "<div style='overflow-x: auto; display:none'>\n";
  my $latest_year = (sort {$b cmp $a} keys %years)[0] if %years;
  for my $year (sort {$b cmp $a} keys %years) {
    my $count = scalar @{$years{$year}};
    my $display = ($year eq $latest_year) ? '' : 'display: none; ';
    print "<div style='overflow-x: auto; $display'>\n";
    print "<br><div style='font-weight: bold;'>$year</div>\n";
    print "<table style='white-space: nowrap;'>\n";
    for my $com (@{$years{$year}}) {
      print "<tr><td>\n";
      print "<span style='font-size: xx-small'>" .
            "[$com->{Gid}]</span></td>\n";
      print "<td><a href='$c->{url}?o=Full&e=$com->{Gid}'><span>";
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

      print "<a href='$c->{url}?o=Location&e=$com->{Lid}' ><span>@<b>$com->{Loc}</b></span></a> &nbsp;";
      print "</td>\n";
      print "</tr>\n";
    }
    print "</table>\n";
    print "</div>\n";
    print "<div onclick='toggleElement(this.previousElementSibling);' style='cursor: pointer;'>";
    print "<b>$count</b> times in <b>$year</b></div>\n";
  }
  print "</div>\n";
  print "<div onclick='toggleElement(this.previousElementSibling);'><br/>";
  if ( $glcount) {
    print "$glcount Glasses between ";
    print "$firstrec->{Date} and $lastrec->{Date}\n"
  } else {
    print "Not a single glass";
  }
  print "</div>";
  $sth->finish;
  print "<!-- listbrewglasses end -->\n";
  print "<hr/>\n";

} # listbrewglasses

################################################################################
# brewdeduplist - List all brews, for selecting those that duplicate the current
################################################################################
sub brewdeduplist {
  my $c = shift; # context
  my $brew = shift;
  print "<!-- brewdeduplist -->\n";
  print "<div onclick='toggleElement(this.nextElementSibling);'>";
  print "<b>Deduplicate</b><br/>\n";
  print "</div>\n";
  print "<div style='display: none;'>\n";
  print "<form method='POST' accept-charset='UTF-8' class='no-print' >\n";
  print "Mark brews that are duplicates of [$brew->{Id}] $brew->{Name} ";
  print "and click here: \n";
  print "<input type=submit name=submit value='Deduplicate' />\n";
  print "<input type=hidden name='o' value='$c->{op}' />\n";
  print "<input type=hidden name='e' value='$c->{edit}' />\n";
  print "<input type=hidden name='dedup' value='1' />\n";
  print "<br/>\n";
  my $sort = $c->{sort} || "Last-";
  print listrecords::listrecords($c, "BREWS_DEDUP_LIST", $sort, "Id <> $brew->{Id}" );
  print "</form>\n";
  print "</div>\n";
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
  my $duplicate_id = $c->{duplicate};
  if ($duplicate_id) {
    # Load the brew to duplicate
    my $sql = "select * from BREWS where id = ?";
    my $get_sth = $c->{dbh}->prepare($sql);
    $get_sth->execute($duplicate_id);
    $p = $get_sth->fetchrow_hashref;
    $get_sth->finish;
    $p->{Id} = "new";
    $submit = "Insert";
    print "<b>Duplicating Brew $duplicate_id: $p->{Name}</b><br/>\n";
  } elsif ( $c->{edit} =~ /new/i ) {
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

    print inputs::inputform($c, "BREWS", $p );
    
    if ( $p->{Id} ne "new" ) {
      # Editing existing record: show Edit button, hide submit
      print "<button type='button' class='edit-enable-btn' onclick='enableEditing(this.form)'>Edit</button>\n";
      print "<button type='button' onclick=\"window.location.href='$c->{url}?o=$c->{op}&e=new&duplicate=$p->{Id}'\">Duplicate</button>\n";
      print "<input type='submit' name='submit' value='$submit Brew' class='edit-submit-btn' hidden />\n";
    } else {
      # New record: normal submit button
      print "<input type='submit' name='submit' value='$submit Brew' />\n";
    }
    print "<a href='$c->{url}?o=$c->{op}'><span>Cancel</span></a>\n";
    print "<br/>\n";

    # Come back to here after updating
    print "<input type='hidden' name='o' value='$c->{op}' />\n";
    print "</form>\n";
    print "<hr/>\n";
    if ( $p->{Id} ne "new" ) {
      listbrewcomments($c, $p);
      listbrewtaps($c, $p);
      listbrewprices($c, $p);
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
      BREWS.IsGeneric,
      Locations.Name as Producer,
      BREWS.Alc,
      BREWS.DefPrice,
      BREWS.DefVol,
      GROUP_CONCAT(DISTINCT SeenLocations.Name) as SeenAt,
      br.rating_count,
      br.average_rating,
      br.comment_count
    from BREWS
    left join GLASSES on GLASSES.Brew= BREWS.ID
    left join LOCATIONS on LOCATIONS.Id = BREWS.ProducerLocation
    left join LOCATIONS as SeenLocations on SeenLocations.Id = GLASSES.Location
    left join brew_ratings br on BREWS.Id = br.brew
    group by BREWS.id
    order by max(GLASSES.Timestamp) DESC
    ";
  my $list_sth = $c->{dbh}->prepare($sql);
  $list_sth->execute();

  my $opts = "";
  my $current = "";

  while ( my ($id, $bt, $su, $na, $generic, $pr, $alc, $defprice, $defvol, $seenat, $rating_count, $average_rating, $comment_count )  = $list_sth->fetchrow_array ) {
    if ( $id eq $selected ) {
      $current = $na;
    }
    my $disp = "";
    if ($pr && $na !~ /$pr/ ) {
      $disp .= "<i><span style='font-size: x-small;'>$pr:</span></i> ";
    }
    $disp .= "<b>$na</b>" if ($na);
    $disp .= " <span style='font-size: xx-small;'>";
    $disp .= " " . util::unit($alc, "%") if $alc;
    my $style_html = styles::brewstyledisplay($c, $bt, $su);
    # Remove main type if there's a subtype (e.g., [Wine,Red] -> [Red])
    if ($su) {
      $style_html =~ s/\[$bt,([^\]]+)\]/[$1]/;
    }
    $disp .= $style_html;
    $disp .= "&nbsp;(Gen)" if $generic;
    $disp .= " " . comments::avgratings($c, $rating_count, $average_rating, $comment_count) if (!$generic);
    $disp .= "</span>";
    $alc = $alc || "";
    $defprice = $defprice || "";
    $defvol = $defvol || "";
    $seenat = $seenat || "";
    $opts .= "<div class='dropdown-item' id='$id' alc='$alc' " .
       "defprice='$defprice' defvol='$defvol' brewtype='$bt' seenat='$seenat' >$disp</div>\n";
  }
  my $s = inputs::dropdown( $c, "Brew", $selected, $current, $opts, "BREWS", "newbrew" );

  return $s;
} # selectbrew

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
  my $setdefaultprice = util::param($c, "setdefaultprice");
  my $setdefaultvol = util::param($c, "setdefaultvol");
  if ($setdefaultprice && $setdefaultvol) {
    update_brew_defaults($c, $id, $setdefaultprice, $setdefaultvol);
    $c->{redirect_url} = "?o=Brews&e=$id";
    return;
  }
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
    $defaults->{BrewType} = util::param($c, "selbrewtype");
    $defaults->{IsGeneric} = "0";
    $id = db::insertrecord($c,  "BREWS", $section, $defaults);
    return $id;

  } else {
    util::error ("A brew must have a name" ) unless util::param($c, "Name");
    util::error ("A brew must have a type" ) unless util::param($c, "BrewType");
    $id = db::updaterecord($c, "BREWS", $id,  "");
  }
  return $id;
} # postbrew

################################################################################
# List tap information for the given brew
################################################################################
sub listbrewtaps {
  my $c = shift; # context
  my $brew = shift;
  print "<!-- listbrewtaps -->\n";

  my $sql = qq{
    SELECT * FROM brew_taps WHERE Brew = ? ORDER BY Gone DESC, FirstSeen DESC
  };
  my $sth = $c->{dbh}->prepare($sql);
  $sth->execute($brew->{Id});
  my $taps = $sth->fetchall_arrayref({});

  my @current = grep { !defined $_->{Gone} } @$taps;
  my @history = grep { defined $_->{Gone} } @$taps;

  if (@current) {
    print "<div style='white-space: nowrap;'>\n";
    foreach my $tap (@current) {
      print "<b>#$tap->{Tap}</b> at <b><a href='$c->{url}?o=Location&e=$tap->{Location}'><span>$tap->{LocationName}</span></a></b> since $tap->{Since} ($tap->{Days} days)<br/>\n";
    }
    print "</div>\n";
  } else {
    print "This beer is not currently on tap anywhere.<br/>\n";
  }

  my $history_count = scalar(@history);

  if ($history_count > 0) {
    print "<br/>\n";
    print "<div onclick='toggleElement(this.nextElementSibling);'>\n";
    print "<b>Tap history, $history_count entries</b><br/>\n";
    print "</div>\n";
    print "<div style='display: none; white-space: nowrap;'>\n";
    foreach my $tap (@history) {
      print "<b>#$tap->{Tap}</b> at <b><a href='$c->{url}?o=Location&e=$tap->{Location}'><span>$tap->{LocationName}</span></a></b> $tap->{Since} to $tap->{GoneFormatted} ($tap->{Days} days)<br/>\n";
    }
    print "</div>\n";
  } else {
    print "<br/>\n(no tap history)\n";
  }
  print "<hr/>\n";
} # listbrewtaps

################################################################################
# Report module loaded ok
1;
