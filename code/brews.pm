# Part of my beertracker
# Stuff for listing, selecting, adding, and editing brews


package brews;

use strict;
use warnings;
use feature 'unicode_strings';
use utf8;  # Source code and string literals are utf-8
use URI::Escape qw(uri_escape_utf8);

our $brew_field_order = [
  [ "Name",            "The name of the brew", "r" ],
  [ "ShortName",       "Short unique identifier, auto-computed from name", "a" ],
  [ "BrewType",        "Beer, Cider, Wine, Spirit, etc.", "r" ],
  [ "SubType",         "NEIPA, Imperial Stout, etc." ],
  [ "BrewStyle",       "Style description (West Coast IPA, etc.)" ],
  [ "ProducerLocation", "The brewery or producer" ],
  [ "Country",         "Auto-filled from the selected producer", "a" ],
  [ "Region",          "Region within the country", "a" ],
  [ "Alc",             "Alcohol percentage" ],
  [ "Year",            "Vintage year" ],
  [ "Flavor",          "Tasting notes and flavor profile" ],
  [ "Details",         "Additional information" ],
  [ "DefPrice",        "Default price per unit" ],
  [ "DefVol",          "Default volume in cl" ],
  [ "Barcode",         "EAN / GTIN barcode number" ],
  [ "DetailsLink",     "URL to Untappd or similar" ],
  [ "IsGeneric",       "Check for a generic entry (not a specific brand)" ],
  [ "Parent",          "Parent brew ID if this is a variant" ],
];

################################################################################
# List of brews
################################################################################
sub listbrews {
  my $c = shift; # context

  if ( $c->{edit} ) {
    editbrew($c);
    return;
  }
  print listrecords::listrecords($c,
    q{with users as (
      select distinct Username from glasses
    )
    select
      brews.Id AS "Id_A_link=Brew",
      brews.Name AS "Name_A_cont",
      brews.BrewType || ', ' || brews.SubType AS "Type_A",
      (SELECT Filename FROM photos WHERE Brew = brews.Id ORDER BY Ts DESC LIMIT 1)
        AS "Photo_R3_noheader_nofilter",

      '' AS TR1,
      brews.Alc AS "Alc",
      ploc.Id AS "PlocId_A_link=Location_cont",
      ploc.Name AS "Producer_A_cont",
      r.rating_count || ';' || r.average_rating || ';' || r.comment_count AS "Stats_as=Stats",

      '' AS TR2,
      count(glasses.Id) AS "Count",
      locations.Id AS "LocId_A_link=Location_cont",
      locations.Name AS "Location_A_as=LocName_cont",
      strftime('%Y-%m-%d %w ', max(glasses.Timestamp), '-06:00') ||
        strftime('%H:%M', max(glasses.Timestamp)) AS "Last",

      users.Username AS xUsername
    from brews
    cross join users
    left join locations ploc on ploc.Id = brews.ProducerLocation
    left join glasses on glasses.Brew = brews.Id and glasses.Username = users.Username
    left join locations on locations.Id = glasses.Location
    left join brew_ratings r on r.Brew = brews.Id and r.Username = users.Username
    group by brews.Id, users.Username
    ORDER BY "Last" DESC},
    undef,
    { where => "xUsername = ?", params => $c->{username}, title => "Brews" });
  return;
} # listbrews

################################################################################
# List all comments for the given brew
################################################################################

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
  print listrecords::listrecords($c,
      q{with users as (
        select distinct Username from glasses
      )
      select
        brews.Id AS "Id_A_link=Brew",
        brews.Name,
        '?' as Sim,
        r.rating_count || ';' || r.average_rating || ';' || r.comment_count as Stats,
        brews.Alc as Alc,
        brews.BrewType || ', ' || brews.Subtype AS "Type_A",
        '' AS TR1,
        'Chk' as Chk,
        ploc.Name as Producer,
        count(glasses.Id) as Count,
        strftime('%Y-%m-%d %w ', max(glasses.Timestamp), '-06:00') ||
          strftime('%H:%M', max(glasses.Timestamp)) as Last,
        locations.Name AS "Location_C2",
        users.Username as xUsername
      from brews
      cross join users
      left join locations ploc on ploc.id = brews.ProducerLocation
      left join glasses on glasses.Brew = brews.Id and glasses.Username = users.Username
      left join locations on locations.id = glasses.Location
      left join brew_ratings r on r.Brew = brews.Id and r.Username = users.Username
      group by brews.id, users.Username},
      $sort,
      { where => qq{"Id_A_link=Brew" <> $brew->{Id} AND xUsername = ?},
        params => $c->{username}, extraparams => $extra,
        browsersortcol => "Sim", title => "Similar brews" });
  print "</form>\n";
  print "</div>\n";
  print "<!-- brewdeduplist end -->\n";
  print "<hr/>\n";
} # brewdeduplist

################################################################################
# Dropdown for selecting/adding BrewType
################################################################################
sub selectbrewtype_dropdown {
  my $c = shift;
  my $selected = shift || "";
  my $disabled = shift || "";
  my $sql = "select distinct BrewType from brews where BrewType is not null and BrewType != '' order by BrewType";
  my $sth = db::query($c, $sql);
  my $opts = "";
  while ( my $bt = $sth->fetchrow_array ) {
    $opts .= "<div class='dropdown-item' id='$bt'>$bt</div>\n";
  }
  return inputs::dropdown($c, "BrewType", $selected, $selected, $opts,
    { disabled => $disabled, simplenew => 1, required => 1 });
} # selectbrewtype_dropdown

################################################################################
# Dropdown for selecting/adding SubType, with brewtype data attribute for cascading
################################################################################
sub selectbrewsubtype_dropdown {
  my $c = shift;
  my $selected = shift || "";
  my $disabled = shift || "";
  my $sql = "select distinct BrewType, SubType from brews where SubType is not null and SubType != '' order by BrewType, SubType";
  my $sth = db::query($c, $sql);
  my $opts = "";
  while ( my $st = $sth->fetchrow_hashref ) {
    next unless $st->{SubType};
    my $sub   = util::htmlesc($st->{SubType});
    my $btype = util::htmlesc($st->{BrewType});
    $opts .= "<div class='dropdown-item' id='$sub' brewtype='$btype'>$sub</div>\n";
  }
  return inputs::dropdown($c, "SubType", $selected, $selected, $opts,
    { disabled => $disabled, simplenew => 1, required => 1 });
} # selectbrewsubtype_dropdown

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

    print inputs::inputform($c, "BREWS", $p, undef, undef, undef, undef, undef, $brew_field_order);


    if ( $p->{Id} ne "new" ) {
      # Editing existing record: show Edit button, hide submit
      print "<button type='button' class='edit-enable-btn' onclick=\"enableEditing(this.form); var d=document.getElementById('dropdown-BrewType'); if(d)d.classList.remove('open'); var n=document.querySelector('input[name=\\'Name\\']'); if(n)n.focus();\">Edit</button>\n";
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
    print <<'JS';
<script>
(function() {
  var brewTypeInput = document.getElementById('BrewType');
  var subTypeDropdown = document.getElementById('dropdown-SubType');
  if (!brewTypeInput || !subTypeDropdown) return;
  var subTypeList = subTypeDropdown.querySelector('.dropdown-list');
  var subTypeFilter = subTypeDropdown.querySelector('.dropdown-filter');
  if (!subTypeList) return;
  // Add a selbrewtype hidden input so filterItems() uses it for brewtype filtering
  var selbrewtype = document.createElement('input');
  selbrewtype.type = 'hidden';
  selbrewtype.id = 'selbrewtype';
  subTypeDropdown.parentNode.appendChild(selbrewtype);
  function filterSubTypes() {
    var bt = brewTypeInput.value;
    selbrewtype.value = bt;
    var items = subTypeList.querySelectorAll('.dropdown-item');
    var hasMatch = false;
    var i;
    for (i = 0; i < items.length; i++) {
      if (items[i].id === 'actions') continue;
      var bta = items[i].getAttribute('brewtype');
      if (bta && bta === bt) { hasMatch = true; break; }
    }
    for (i = 0; i < items.length; i++) {
      if (items[i].id === 'actions') continue;
      var bta = items[i].getAttribute('brewtype');
      if (!bt || !bta || bta === bt || !hasMatch) {
        items[i].style.display = '';
      } else {
        items[i].style.display = 'none';
      }
    }
  }
  brewTypeInput.addEventListener('input', filterSubTypes);
  filterSubTypes();
})();
</script>
JS
    print <<'JS';
<script>
(function() {
  var prodDropdown = document.getElementById('dropdown-ProducerLocation');
  var countryDropdown = document.getElementById('dropdown-Country');
  var regionDropdown = document.getElementById('dropdown-Region');
  if (!prodDropdown || !countryDropdown || !regionDropdown) return;

  function getProdData() {
    var prodHidden = prodDropdown.querySelector('input[type=hidden]');
    if (!prodHidden || !prodHidden.value) return null;
    var item = prodDropdown.querySelector('.dropdown-item[id="' + prodHidden.value + '"]');
    if (!item) return null;
    return { country: item.getAttribute('country'), region: item.getAttribute('region') };
  }

  function copyFromProducer() {
    var data = getProdData();
    if (!data) return;
    var countryHidden = countryDropdown.querySelector('input[type=hidden]');
    var regionHidden = regionDropdown.querySelector('input[type=hidden]');
    if (countryHidden && data.country) setDropdownValue(countryHidden, data.country);
    if (regionHidden && data.region) setDropdownValue(regionHidden, data.region);
  }

  // On producer change: fill only if country or region is empty
  var prodHidden = prodDropdown.querySelector('input[type=hidden]');
  if (prodHidden) {
    prodHidden.addEventListener('input', function() {
      var c = countryDropdown.querySelector('input[type=hidden]');
      var r = regionDropdown.querySelector('input[type=hidden]');
      if (!c || !r || !c.value.trim() || !r.value.trim()) copyFromProducer();
    });
  }

  // On Country/Region label click: always copy
  var form = document.querySelector('form');
  if (form) {
    var cells = form.querySelectorAll('td');
    for (var i = 0; i < cells.length; i++) {
      var text = cells[i].textContent.trim();
      if (text === 'Country' || text === 'Region') {
        cells[i].style.cursor = 'pointer';
        cells[i].title = 'Fill from producer';
        cells[i].addEventListener('click', copyFromProducer);
      }
    }
  }
})();
</script>
JS
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
      print "<div onclick='toggleElement(this.nextElementSibling);'>";
      print "Comments and ratings for <b>$p->{Name}</b><br/>\n";
      print "</div>\n";
      print "<div style='overflow-x: auto;'>\n";
      print listrecords::listrecords($c, comments::comments_list_sql(), "Last-", {
          where => q{EXISTS (SELECT 1 FROM comments c2
                     LEFT JOIN glasses g2 ON g2.Id = c2.Glass
                     WHERE c2.Id = "Id_A_link=Comment"
                       AND (c2.Brew = ? OR g2.Brew = ?))
                     AND xUsername = ?},
          params => [$p->{Id}, $p->{Id}, $c->{username}],
          title => "Comments",
          show_rating_summary => 1,
          hide_headers_default => 1,
          no_new_link => 1,
      });
      print "</div>\n";
      print "<hr/>\n";
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
      my $style_html = styles::brewstyledisplay($c, $bt, $su, "brew:$id '$na' $bt/" . ($su // ""));
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
      my $tags_str = "";
      if ($su) {
          $tags_str = lc($su);
      }
      my $tags_attr = $tags_str ? " tags='" . util::htmlesc($tags_str) . "'" : "";
      $opts .= "<div class='dropdown-item' id='$id' alc='$alc' " .
         "defprice='$defprice' defvol='$defvol' brewtype='$bt' barcode='$barcode' seenat='$seenat'$tags_attr>$disp</div>\n";
    }
    cache::set($c, $cache_key, $opts);
  }

  # Look up the display name of the selected brew (cheap primary-key lookup)
  my $current = "";
  if ( $selected ) {
    ($current) = db::queryarray($c, "SELECT Name FROM BREWS WHERE Id = ?", $selected);
    $current //= "";
  }

  my $defaults = {};
  $defaults->{BrewType} = $brewtype if $brewtype;
  my $s = inputs::dropdown( $c, "Brew", $selected, $current, $opts, { table => "BREWS", newfield => "newbrew", scan => 1, defaults => $defaults, fieldorder => $brew_field_order } );

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
