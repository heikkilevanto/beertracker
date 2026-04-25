# Part of my beertracker
# Stuff for listing, selecting, adding, and editing brews


package brews;

use strict;
use warnings;
use feature 'unicode_strings';
use utf8;  # Source code and string literals are utf-8
use URI::Escape qw(uri_escape_utf8);

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
  print listrecords::listrecords($c, "BREWS_LIST", "Last-",
    "xUsername = ?", $c->{username} ); # for getting user-specific ratings and counts
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
      strftime('%Y-%m-%d', COALESCE(COMMENTS.Ts, GLASSES.Timestamp), '-06:00') as Date,
      strftime('%H:%M', COALESCE(COMMENTS.Ts, GLASSES.Timestamp)) as Time,
      COMMENTS.Rating as Rating,
      COMMENTS.Comment,
      group_concat(PERSONS.Id, ',') as Pid,
      group_concat(PERSONS.Name, ', ') as Person,
      GLASSES.Id as Gid,
      GLASSES.Brew as Brew,
      GLASSES.Volume,
      GLASSES.Price,
      COALESCE(COMLOC.Name, GLASSLOC.Name) as Loc,
      COALESCE(COMLOC.Id, GLASSLOC.Id) as Lid
      FROM COMMENTS
      LEFT JOIN GLASSES ON GLASSES.Id = COMMENTS.Glass
      LEFT JOIN comment_persons cp ON cp.Comment = COMMENTS.Id
      LEFT JOIN PERSONS on PERSONS.id = cp.Person
      LEFT JOIN LOCATIONS COMLOC on COMLOC.Id = COMMENTS.Location
      LEFT JOIN LOCATIONS GLASSLOC on GLASSLOC.Id = GLASSES.Location
      WHERE (COMMENTS.Brew = ? OR GLASSES.Brew = ?)
        AND (COMMENTS.Username = ? OR COMMENTS.Username IS NULL)
      GROUP BY COMMENTS.Id
      ORDER BY COALESCE(COMMENTS.Ts, GLASSES.Timestamp) DESC ";
  #print { $c->{log} } "listbrewcomments: id='$brew->{Id}': $sql \n";
  my $sth = db::query($c, $sql, $brew->{Id}, $brew->{Id}, $c->{username});
  print "<div onclick='toggleElement(this.nextElementSibling);'>";
  print "Comments and ratings for <b>$brew->{Name}</b> <br/>\n";
  print "</div>\n";
  print "<div style='overflow-x: auto;'>";
  print "<table >\n";
  my $ratesum = 0;
  my $ratecount = 0;
  my $comcount = 0;
  my $sty = "style='border-bottom: 1px solid white; vertical-align: top;' ";
  while ( my $com = $sth->fetchrow_hashref ) {
    my $cid = defined $com->{Cid} ? $com->{Cid} : "";
    my $date = defined $com->{Date} ? $com->{Date} : "";
    my $tim = defined $com->{Time} ? $com->{Time} : "";
    my $rating = defined $com->{Rating} ? $com->{Rating} : undef;
    my $comment = defined $com->{Comment} ? $com->{Comment} : undef;
    my $lid = defined $com->{Lid} ? $com->{Lid} : undef;
    my $loc = defined $com->{Loc} ? $com->{Loc} : "";
    my $volume = defined $com->{Volume} ? $com->{Volume} : undef;
    my $price = defined $com->{Price} ? $com->{Price} : undef;
    my $person = defined $com->{Person} ? $com->{Person} : undef;
    my $pid = defined $com->{Pid} ? $com->{Pid} : "";

    print "<tr><td $sty>\n";
    print "<a href='$c->{url}?o=Comment&e=$cid'><span>";
    print "$date</span></a><br/> \n";
    if ( defined $tim && $tim ne '' && $tim lt "06:00" ) { $tim = "($tim)"; }
    print "$tim\n";
    print "<a href='$c->{url}?o=Comment&e=$cid'>" .
          "<span style='font-size: xx-small'>[$cid]</span></a>";
    print "</td>\n";

    print "<td style='border-bottom: 1px solid white'>\n";
    if ( defined $rating ) {
      print "<b>($rating)</b>\n";
      $ratesum += $rating;
      $ratecount++;
    }
    print "</td>\n";

    print "<td style='border-bottom: 1px solid white; vertical-align: top; white-space:normal'>\n";
    if ( $lid ) {
      print "<a href='$c->{url}?o=Location&e=$lid' ><span><b>$loc</b></span></a> &nbsp;";
    } else {
      print "<b>$loc</b> &nbsp;" if $loc;
    }
    print util::unit($volume,"c")   if ( $volume ) ;
    print util::unit($price,",-")   if ( $price ) ;
    print "<br/>";
    print "<i>$comment</i>" if $comment;
    $comcount++ if ($comment);
    print "</td>\n";

    print "<td $sty>\n";
    if ( $person ) {
      print "<a href='$c->{url}?o=Person&e=$pid'><span style='font-weight: bold;'>$person</span></a>\n";
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
  my $sth = db::query($c, $sql, $brew->{Id}, $c->{username});
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
      my $is_default = ( ($brew->{DefPrice} // "") eq $com->{Price} &&
                         ($brew->{DefVol}   // "") eq $com->{Volume} );
      if ( !$is_default ) {
        print "<form method='POST' accept-charset='UTF-8' style='display:inline;'>\n";
        print "<input type='hidden' name='o' value='Brews' />\n";
        print "<input type='hidden' name='e' value='$brew->{Id}' />\n";
        print "<input type='hidden' name='setdefaultprice' value='$com->{Price}' />\n";
        print "<input type='hidden' name='setdefaultvol' value='$com->{Volume}' />\n";
        print "<input type='submit' value='Def' style='font-size: x-small;' />\n";
        print "</form>\n";
      }
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
  my $rows = db::execute($c, "UPDATE brews SET DefPrice = ?, DefVol = ? WHERE Id = ?", $price, $vol, $brew_id);
  if (!defined $rows || $rows != 1) {
    util::error("Failed to update defaults for brew $brew_id");
  }
  print { $c->{log} } "Updated brew $brew_id DefPrice to $price, DefVol to $vol\n";
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
      GLASSES.Volume,
      GLASSES.Price,
      LOCATIONS.Name as Loc,
      LOCATIONS.Id as Lid
      FROM GLASSES
      LEFT JOIN COMMENTS ON COMMENTS.Glass = GLASSES.Id
      LEFT JOIN LOCATIONS ON LOCATIONS.Id = GLASSES.Location
      WHERE GLASSES.Brew = ?
        AND GLASSES.username = ?
      ORDER BY GLASSES.Timestamp DESC ";
  my $sth = db::query($c, $sql, $brew->{Id}, $c->{username});
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
    my $first = util::reldate($firstrec->{Date});
    my $last  = util::reldate($lastrec->{Date});
    if ( $first eq $last ) {
      print "$glcount Glasses on $first\n";
    } else {
      print "$glcount Glasses between $first and $last\n";
    }
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
  my $extra = {};
  $extra->{refname} = $brew->{Name};
  print listrecords::listrecords($c, "BREWS_DEDUP_LIST", $sort, "Id <> $brew->{Id} AND xUsername = ?", $c->{username}, $extra);
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
    $p = db::getrecord($c, "BREWS", $duplicate_id);
    $p ||= {};
    $p->{Id} = "new";
    $p->{Parent} = $duplicate_id;  # New brew inherits from the duplicated one
    $submit = "Insert";
    print "<b>Duplicating Brew $duplicate_id: $p->{Name}</b><br/>\n";
  } elsif ( $c->{edit} =~ /new/i ) {
    $p->{Id} = "new";
    $p->{BrewType} = "Beer"; # Some decent defaults
    $p->{SubType} = "NEIPA"; # More for guiding the input than true values
    # Country left empty so it can be auto-filled from the selected producer
    print "<b>Inserting a new brew<br/>\n";
    $submit = "Insert";
  } else {
    $p = db::getrecord($c, "BREWS", $c->{edit});
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
    print <<'JS';
<script>
(function() {
  var nameInp  = document.querySelector("input[name='Name']");
  var shortInp = document.querySelector("input[name='ShortName']");
  if (!nameInp || !shortInp) return;
  nameInp.addEventListener('input', function() {
    var s = computeShortName(this.value);
    if (s !== null) { shortInp.value = s; }
  });
})();
</script>
JS
    print "<hr/>\n";
    if ( $p->{Id} ne "new" ) {
      # Search line: producer (if SearchLink set), untappd, ddg
      my $prodname = "";
      my $search_html = "Search: ";
      if ($p->{ProducerLocation}) {
        my $prod = db::getrecord($c, "LOCATIONS", $p->{ProducerLocation});
        if ($prod) {
          $prodname = $prod->{Name} // "";
          if ($prod->{SearchLink}) {
            my $sq = $prod->{SearchLink} . uri_escape_utf8($p->{Name});
            $search_html .= util::extlink($sq, "producer") . " ";
          }
        }
      }
      my $uq = uri_escape_utf8(($prodname ? "$prodname " : "") . ($p->{Name} // ""));
      $search_html .= util::extlink("https://untappd.com/search?q=$uq", "untappd") . " ";
      my $gq = uri_escape_utf8(($prodname ? "$prodname " : "") . ($p->{Name} // "") . " beer");
      $search_html .= util::extlink("https://duckduckgo.com/?q=$gq", "search");
      print "$search_html<br/>\n";
      print "<hr/>\n";
      my $return_url = "$c->{url}?o=$c->{op}&e=$p->{Id}";
      print photos::thumbnails_html($c, 'Brew', $p->{Id});
      print photos::photo_form($c, brew => $p->{Id}, public_default => 1, return_url => $return_url);
      print "&nbsp;<a href='$c->{url}?o=Comment&e=new&brew=$p->{Id}&commenttype=brew'><span>(new comment)</span></a>\n";
      print "<hr/>\n";
      listbrewcomments($c, $p);
      listbrewrelations($c, $p);
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
# listbrewrelations - Show parent/child relationships for a brew
################################################################################
sub listbrewrelations {
  my $c = shift;
  my $brew = shift;

  my $parent = undef;
  if ( $brew->{Parent} ) {
    $parent = db::getrecord($c, "BREWS", $brew->{Parent});
  }

  my $sth = db::query($c, "SELECT * FROM BREWS WHERE Parent = ? ORDER BY Name", $brew->{Id});
  my $children = $sth->fetchall_arrayref({});

  return unless ($parent || @$children);

  print "<!-- listbrewrelations -->\n";

  if ($parent) {
    print "Inherits from: <a href='$c->{url}?o=$c->{op}&e=$parent->{Id}'><span>[$parent->{Id}] $parent->{Name}</span></a><br/>\n";
    brewfielddiff($c, $parent, $brew, "Parent", "This brew");
  }

  if (@$children) {
    print "Variants of this brew:<br/>\n";
    foreach my $child (@$children) {
      print "<a href='$c->{url}?o=$c->{op}&e=$child->{Id}'><span>[$child->{Id}] $child->{Name}</span></a><br/>\n";
      brewfielddiff($c, $brew, $child, "This brew", $child->{Name});
    }
  }

  print "<hr/>\n";

} # listbrewrelations

################################################################################
# brewfielddiff - Print a table of differing fields between two brew records
################################################################################
sub brewfielddiff {
  my $c    = shift;
  my $base = shift;  # hashref - the reference brew (left column)
  my $comp = shift;  # hashref - the brew to compare (right column)
  my $baselabel = shift || "Base";
  my $complabel = shift || "This brew";

  my @diffs;
  foreach my $field ( db::tablefields($c, "BREWS", "Id|Parent", 1) ) {
    my $bval = defined $base->{$field} ? $base->{$field} : "";
    my $cval = defined $comp->{$field} ? $comp->{$field} : "";
    next if ($bval eq $cval);
    my $bdisp = $bval ne "" ? util::htmlesc($bval) : "&mdash;";
    my $cdisp = $cval ne "" ? util::htmlesc($cval) : "&mdash;";
    push @diffs, "<tr><td>$field</td><td>$bdisp</td><td>&rarr;</td><td>$cdisp</td></tr>\n";
  }
  if (@diffs) {
    print "<table>\n";
    print "<tr><th>Field</th><th>$baselabel</th><th></th><th>$complabel</th></tr>\n";
    print @diffs;
    print "</table>\n";
  }
} # brewfielddiff

################################################################################
# Select a brew
# A key component of the main input form
################################################################################
# TODO - Display the brew details under the selection, with an edit link

sub selectbrew {
  my $c = shift; # context
  my $selected = shift || "";  # The id of the selected brew
  my $brewtype = shift || "";

  # The opts list is expensive (large join over all brews). Cache it per user
  # and brewtype for the lifetime of the FastCGI process; cleared after POSTs.
  my $cache_key = "selectbrew_opts:$c->{username}:$brewtype";
  my $opts = cache::get($c, $cache_key);

  if ( !defined $opts ) {
    my $sql = "
      select
        BREWS.Id, BREWS.Brewtype, BREWS.SubType, Brews.Name,
        BREWS.IsGeneric,
        Locations.Name as Producer,
        BREWS.Alc,
        BREWS.DefPrice,
        BREWS.DefVol,
        BREWS.Barcode,
        GROUP_CONCAT(DISTINCT SeenLocations.Name) as SeenAt,
        br.rating_count,
        br.average_rating,
        br.comment_count
      from BREWS
      left join GLASSES on GLASSES.Brew= BREWS.ID
      left join LOCATIONS on LOCATIONS.Id = BREWS.ProducerLocation
      left join LOCATIONS as SeenLocations on SeenLocations.Id = GLASSES.Location
      left join (select brew, rating_count, average_rating, comment_count
                 from brew_ratings where Username = ?) br on br.brew = BREWS.Id
      group by BREWS.id
      order by max(GLASSES.Timestamp) DESC
      ";
    my $list_sth = db::query($c, $sql, $c->{username});

    $opts = "";
    while ( my ($id, $bt, $su, $na, $generic, $pr, $alc, $defprice, $defvol, $barcode, $seenat, $rating_count, $average_rating, $comment_count )  = $list_sth->fetchrow_array ) {
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
      $defprice = " $defprice" if ($defprice =~ /^-\d/);  # Leading space = container price; JS will pre-fill with space so onfocus trim activates
      $defvol = $defvol || "";
      $barcode = $barcode || "";
      $seenat = $seenat || "";
      $opts .= "<div class='dropdown-item' id='$id' alc='$alc' " .
         "defprice='$defprice' defvol='$defvol' brewtype='$bt' barcode='$barcode' seenat='$seenat' >$disp</div>\n";
    }
    cache::set($c, $cache_key, $opts);
  }

  # Look up the display name of the selected brew (cheap primary-key lookup)
  my $current = "";
  if ( $selected ) {
    ($current) = db::queryarray($c, "SELECT Name FROM BREWS WHERE Id = ?", $selected);
    $current //= "";
  }

  my $s = inputs::dropdown( $c, "Brew", $selected, $current, $opts, "BREWS", "newbrew", "", "", "scan" );

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
      print { $c->{log} } "$sql with '$id' and '$dup' \n";
      my $rows = db::execute($c, $sql, $id, $dup);
      util::error("Deduplicate brews: Failed to update glasses") unless $rows;
      print { $c->{log} } "Updated $rows glasses from $dup to $id\n";

      $sql = "UPDATE COMMENTS set Brew = ? where Brew = ?  ";
      print { $c->{log} } "$sql with '$id' and '$dup' \n";
      $rows = db::execute($c, $sql, $id, $dup);
      util::error("Deduplicate brews: Failed to update comments") unless defined $rows;
      print { $c->{log} } "Updated $rows comments from $dup to $id\n";

      $sql = "UPDATE TAP_BEERS set Brew = ? where Brew = ?  ";
      print { $c->{log} } "$sql with '$id' and '$dup' \n";
      $rows = db::execute($c, $sql, $id, $dup);
      util::error("Deduplicate brews: Failed to update tap_beers") unless defined $rows;
      print { $c->{log} } "Updated $rows tap_beers from $dup to $id\n";

      $sql = "UPDATE PHOTOS set Brew = ? where Brew = ?  ";
      print { $c->{log} } "$sql with '$id' and '$dup' \n";
      $rows = db::execute($c, $sql, $id, $dup);
      util::error("Deduplicate brews: Failed to update photos") unless defined $rows;
      print { $c->{log} } "Updated $rows photos from $dup to $id\n";

      $sql = "UPDATE BREWS set Parent = ? where Parent = ?  ";
      print { $c->{log} } "$sql with '$id' and '$dup' \n";
      $rows = db::execute($c, $sql, $id, $dup);
      util::error("Deduplicate brews: Failed to update child Parent pointers") unless defined $rows;
      print { $c->{log} } "Updated $rows child Parent pointers from $dup to $id\n";

      $sql = "DELETE FROM Brews WHERE Id = ? ";
      $rows = db::execute($c, $sql, $dup);
      util::error("Deduplicate brews: Failed to delete brew '$dup'") unless $rows;
      print { $c->{log} } "Deleted $rows brews with id  $dup\n";
    }
  }
} # dedupbrews

################################################################################
# Update a brew, posted from the form in the selection above
################################################################################
# TODO - Calculate subtype, if not set. Make a separate helper
sub postbrew {
  my $c = shift; # context
  my $id = shift || $c->{edit};
  my $setdefaultprice = util::param($c, "setdefaultprice");
  my $setdefaultvol = util::param($c, "setdefaultvol");
  if ($setdefaultprice && $setdefaultvol) {
    update_brew_defaults($c, $id, $setdefaultprice, $setdefaultvol);
    $c->{redirect_url} = "?o=Brew&e=$id";
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
  my $sth = db::query($c, $sql, $brew->{Id});
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
