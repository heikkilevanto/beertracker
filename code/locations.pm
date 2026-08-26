# Part of my beertracker
# Routines for displaying and editing locations

package locations;
use strict;
use warnings;
use feature 'unicode_strings';
use utf8;  # Source code and string literals are utf-8
use URI::Escape qw(uri_escape_utf8);

our $loc_field_order = [
  [ "Name",            "The name of the location", "r" ],
  [ "ShortName",       "Shorthand for the name", "a" ],
  [ "OfficialName",    "Official name" ],
  [ "LocType",         "Bar, Producer, Shop, Restaurant, etc.", "r" ],
  [ "LocSubType",      "Beer, Wine, Spirit, etc." ],
  [ "Address",         "Street address" ],
  [ "Country",         "" ],
  [ "Region",          "Region within the country" ],
  [ "Lat",             "Latitude, from gps", "a" ],
  [ "Lon",             "Longitude, from gps", "a" ],
  [ "Website",         "URL" ],
  [ "Contact",         "Phone, email, or such" ],
  [ "SearchLink",      "URL for searching this location's beer menu" ],
  [ "UntappdLink",     "URL to Untappd page" ],
  [ "Description",     "Further description" ],
  [ "Opened",          'year or full date, e.g. "2019" or "-3d" or "Y"' ],
  [ "Closed",          "empty = still open" ],
  [ "FirstSeen",       "auto-set from first visit" ],
  [ "Tags",            "for filtering" ],
  [ "Scraper",         "Scraper script for beer menu" ],
];


################################################################################
# Lists of locations
################################################################################
sub listlocations {
  my $c = shift; # context

  if ( $c->{edit} ) {  # Id for full info
    editlocation($c);
    return;
  }
  my $extraparams = {};
  $extraparams->{lat} = '?';
  $extraparams->{lon} = '?';
  my $username = $c->{dbh}->quote($c->{username});
  print listrecords::listrecords($c,
      qq{SELECT
      locations.Id AS "Id_link=Location",
      locations.Name AS "Name_A_as=LocName_cont",
      CASE
        WHEN locations.LocType IS NOT NULL AND locations.LocType != '' AND
             locations.LocSubType IS NOT NULL AND locations.LocSubType != ''
        THEN '[' || locations.LocType || ', ' || locations.LocSubType || ']'
        WHEN locations.LocType IS NOT NULL AND locations.LocType != ''
        THEN '[' || locations.LocType || ']'
        WHEN locations.LocSubType IS NOT NULL AND locations.LocSubType != ''
        THEN '[' || locations.LocSubType || ']'
        ELSE ''
      END AS "LocType_A_cont",
      COALESCE(r.rating_count, 0) || ';' || COALESCE(r.rating_average, '') || ';' || COALESCE(r.comment_count, 0) AS "Ratings_as=Stats",
      (SELECT Id || ':' || Filename FROM photos WHERE Location = locations.Id ORDER BY Ts DESC LIMIT 1) AS "Photo_R2_noheader_nofilter",
      '' AS TR1,
      locations.lat || ' ' || locations.lon AS "Geo",
      COALESCE(locations.Country,'') || ';' || COALESCE(locations.Region,'') AS "CountryRegion_A_contline",
      } . db::lastseen_sql() . qq{ AS "Last_cont",
      (SELECT } . db::lastseen_sql("g.Timestamp") . qq{
       FROM glasses g
       JOIN brews b ON g.Brew = b.Id
       WHERE b.ProducerLocation = locations.Id) AS "LastProd_cont",
      locations.Tags AS xTags,
      CASE WHEN locations.Closed IS NOT NULL AND locations.Closed != '' THEN 'X' ELSE '' END AS "Closed"
    FROM locations
    LEFT JOIN glasses ON glasses.Location = locations.Id
    LEFT JOIN (
      SELECT
        l.id,
        count(merged.Rating)   AS rating_count,
        avg(merged.Rating)     AS rating_average,
        count(merged.Comment)  AS comment_count
      FROM locations l
      LEFT JOIN (
        SELECT g.Location AS loc_id, c.Rating, c.Comment
          FROM comments c JOIN glasses g ON g.Id = c.Glass
          WHERE COALESCE(g.Username, c.Username) = $username
        UNION ALL
        SELECT c.Location AS loc_id, c.Rating, c.Comment
          FROM comments c WHERE c.Location IS NOT NULL AND c.Glass IS NULL
          AND c.Username = $username
      ) merged ON merged.loc_id = l.Id
      GROUP BY l.Id
    ) r ON r.id = locations.Id
    GROUP BY locations.Id
    ORDER BY "Last_cont" DESC, "LastProd_cont" DESC},
      { extraparams => $extraparams, title => "Locations" });
  return;
} # listlocations

################################################################################
# List comments for the given location
################################################################################
################################################################################
# Helper: render a section of location comments
# Groups by glass, shows commentline, rating summary
################################################################################

################################################################################
# List location visits
################################################################################
# TODO - Make the month+count a link to the mainlist, with filtering for the
# location and date range in that month. If I want to have filtering in the main
sub locationvisits {
  my $c = shift;
  my $locrec = shift;
  my @monthnames = qw(Jan Feb Mar Apr May Jun Jul Aug Sep Oct Nov Dec);
  my $listsql = q{
    SELECT
       strftime ('%Y-%m', timestamp,'-06:00') AS month,
       count( distinct( strftime( '%d', timestamp, '-06:00' ) ) ) AS daycount
    FROM glasses
    WHERE Location = ?
      AND username = ?
    GROUP BY month
    ORDER BY timestamp
  };
  my $sth = db::query($c, $listsql, $locrec->{Id}, $c->{username} );
  my $currentyear = "";
  my ( $y, $m, $d );
  my $totalvisits = 0;
  my $table_html = "";
  while ( my $visit = db::nextrow($sth)) {
    my $eff = $visit->{month};
    ( $y, $m ) = split('-', $eff );
    if ( $y ne $currentyear ) {
      $table_html .= "<br>\n";
      $table_html .= "<b>$y:</b> ";
      $currentyear=$y;
    }
    $table_html .= "$monthnames[$m-1]: <b>$visit->{daycount}</b> ";
    $totalvisits += $visit->{daycount};
  }
  $table_html .= "<br/>\n";
  $sth->finish;
  return if $totalvisits == 0;

  print "<div onclick='toggleElement(this.nextElementSibling);'>";
  print "<b>$totalvisits visits to $locrec->{Name}</b> [$locrec->{Id}]";
  print "</div>\n";
  print "<div style='display:none'>";
  print $table_html;
  print "<div onclick='toggleElement(this.parentElement);'>";
  print "Total $totalvisits visits";
  print "</div>\n";
  print "</div>\n";

  print "<hr/>\n";
} # locationvisits


################################################################################
# List all the brews from this producer
################################################################################
sub producerbrews {
  my $c = shift;
  my $p = shift;
  my $oldop = $c->{op};
  $c->{op} = "Brew";  # Make name links to point to brews, not locations
  print listrecords::listrecords($c,
      q{WITH users AS (
        SELECT DISTINCT Username FROM glasses
      )
      SELECT
        brews.Id AS "IdClr_A",
        brews.Name AS "Name_A_C2_cont",
        '' AS TR1,
        brews.Alc AS "Alc",
        CASE WHEN brews.Discontinued IS NOT NULL AND brews.Discontinued != '' THEN 'X' ELSE '' END AS "Discont",
        brews.BrewType || ', ' || brews.SubType AS "Type_A_cont",
        r.rating_count || ';' || r.average_rating || ';' || r.comment_count AS "Stats_A",
        strftime('%Y-%m-%d %w ', max(glasses.Timestamp), '-06:00') ||
          strftime('%H:%M', max(glasses.Timestamp)) AS "Last",
        ploc.Name AS xProducer,
        users.Username AS xUsername
      FROM brews
      CROSS JOIN users
      LEFT JOIN locations ploc ON ploc.id = brews.ProducerLocation
      LEFT JOIN glasses ON glasses.Brew = brews.Id AND glasses.Username = users.Username
      LEFT JOIN brew_ratings r ON r.Brew = brews.Id AND r.Username = users.Username
      GROUP BY brews.id, users.Username ORDER BY "Last" DESC},
      { where => "xProducer = ? AND xUsername = ?",
        params => [$p->{Name}, $c->{username}],
        title => "Brews by $p->{Name}" });
  $c->{op} = $oldop;
  print "<hr>\n";
} # producerbrews

################################################################################
# locationdeduplist - List all locations, for selecting those that duplicate the current
################################################################################
sub locationdeduplist {
  my $c = shift; # context
  my $loc = shift;
  print "<!-- locationdeduplist -->\n";
  print "<div onclick='toggleElement(this.nextElementSibling);'>";
  print "<b>Deduplicate</b><br/>\n";
  print "</div>\n";
  print "<div style='display: none;'>\n";
  print "<form method='POST' accept-charset='UTF-8' class='no-print' >\n";
  print "Mark locations that are duplicates of <b>[$loc->{Id}] $loc->{Name}</b> ";
  print "and click here: \n";
  print "<input type=submit name=submit value='Deduplicate' />\n";
  print "<input type=hidden name='o' value='$c->{op}' />\n";
  print "<input type=hidden name='e' value='$c->{edit}' />\n";
  print "<input type=hidden name='dedup' value='1' />\n";
  print "<br/>\n";
  my $extra = {};
  $extra->{lat} = $loc->{Lat};
  $extra->{lon} = $loc->{Lon};
  $extra->{refname} = $loc->{Name};
  print listrecords::listrecords($c,
      q{SELECT
        locations.Id AS "Id_A",
        locations.Name,
        '?' AS Sim,
        locations.lat || ' ' || locations.lon AS Geo,
        '' AS TR1,
        'Chk' AS Chk,
        locations.LocType || ', ' || locations.LocSubType AS Type,
        strftime('%Y-%m-%d %w ', max(glasses.Timestamp), '-06:00') ||
          strftime('%H:%M', max(glasses.Timestamp)) AS "Last_C2"
      FROM locations
      LEFT JOIN glasses ON glasses.Location = locations.Id
      GROUP BY locations.Id ORDER BY "Last_C2" DESC},
      { where => "Id_A <> ?", extraparams => $extra, params => $loc->{Id},
        browsersortcol => "Sim", title => "Similar locations",
        norecmessage => "No similar locations" });
  print "</form>\n";
  print "</div>\n";
  print "<!-- locationdeduplist end -->\n";

  print "<hr/>\n";
} # locationdeduplist

################################################################################
# Dropdown for selecting/adding LocType
################################################################################
sub selectloctype_dropdown {
  my $c = shift;
  my $selected = shift || "";
  my $disabled = shift || "";
  my $inputprefix = shift || "";
  my $inputname = $inputprefix . "LocType";
  my $sql = "SELECT DISTINCT LocType FROM locations WHERE LocType IS NOT NULL AND LocType != '' ORDER BY LocType";
  my $sth = db::query($c, $sql);
  my $opts = "";
  while ( my $lt = $sth->fetchrow_array ) {
    $opts .= "<div class='dropdown-item' id='$lt'>$lt</div>\n";
  }
  return inputs::dropdown($c, $inputname, $selected, $selected, $opts,
    { disabled => $disabled, simplenew => 1, required => 1 });
} # selectloctype_dropdown

################################################################################
# Dropdown for selecting/adding LocSubType, with loctype data attribute for cascading
################################################################################
sub selectlocsubtype_dropdown {
  my $c = shift;
  my $selected = shift || "";
  my $disabled = shift || "";
  my $inputprefix = shift || "";
  my $inputname = $inputprefix . "LocSubType";
  my $sql = "SELECT DISTINCT LocType, LocSubType FROM locations WHERE LocSubType IS NOT NULL AND LocSubType != '' ORDER BY LocType, LocSubType";
  my $sth = db::query($c, $sql);
  my $opts = "";
  while ( my $st = $sth->fetchrow_hashref ) {
    next unless $st->{LocSubType};
    my $sub   = util::htmlesc($st->{LocSubType});
    my $ltype = util::htmlesc($st->{LocType});
    $opts .= "<div class='dropdown-item' id='$sub' loctype='$ltype'>$sub</div>\n";
  }
  return inputs::dropdown($c, $inputname, $selected, $selected, $opts,
    { disabled => $disabled, simplenew => 1, required => 1 });
} # selectlocsubtype_dropdown

################################################################################
# Editlocation - Show a form for editing a location record
################################################################################

sub editlocation {
  my $c = shift;
  my $submit = "Update";
  my $p = {};
  if ( $c->{edit} =~ /new/i ) {
    $p->{Id} = "new";
    $p->{LocType} = "Bar"; # Some decent defaults
    $p->{LocSubType} = "Beer"; # More for guiding the input than true values
    print "<b>Inserting a new location<br/>\n";
    $submit = "Insert";
  } else {
    my $sql = "SELECT * FROM Locations WHERE id = ?";
    $p = db::queryrecord($c, $sql, $c->{edit});
    util::error("Location #$c->{edit} not found") unless $p && $p->{Id};
     print "<b>Editing Location $p->{Id}: $p->{Name}</b><br/>\n";
     print "<a href='$c->{url}?o=Taps&loc=" . util::htmlesc($p->{Name}) . "'><span>Tap History</span></a><br/>\n";
   }

  if ( $p->{Id} ) {  # found the location
    print "\n<form method='POST' accept-charset='UTF-8' class='no-print' " .
        "enctype='multipart/form-data'>\n";
    print "<input type='hidden' name='id' value='$p->{Id}' />\n";
    my $tags_ref = db::all_tags($c, "LOCATIONS");
    print inputs::inputform($c, "LOCATIONS", $p, "", "", "<br/>", "Id", $tags_ref, $loc_field_order );

    if ( $p->{Id} ne "new" ) {
      # Editing existing record: show Edit button, hide submit
      print "<button type='button' class='edit-enable-btn' onclick='enableEditing(this.form)'>Edit</button>\n";
      print "<input type='submit' name='submit' value='$submit Location' class='edit-submit-btn' hidden />\n";
      if ( db::can_delete($c, "LOCATIONS", $p->{Id}) && !photos::has_photos($c, "Location", $p->{Id}) ) {
        print "<input type='submit' name='submit' value='Delete Location' class='edit-submit-btn' hidden />\n";
      }
    } else {
      # New record: normal submit button
      print "<input type='submit' name='submit' value='$submit Location' />\n";
    }
    print "<a href='$c->{url}?o=$c->{op}&e='><span>Cancel</span></a><br/>\n";

    # Come back to here after updating
    print "<input type='hidden' name='o' value='$c->{op}' />\n";
    print "<input type='hidden' name='e' value='$p->{Id}' />\n";
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
    # Auto-fill scraper from untappd link
    print <<'JS';
<script>
(function() {
  var untappdInput = document.querySelector("input[name='UntappdLink']");
  var scraperInput = document.querySelector("input[name='Scraper']");
  if (!untappdInput || !scraperInput) return;
  untappdInput.addEventListener('input', function() {
    var curScraper = scraperInput.value.trim();
    if (curScraper && !curScraper.match(/^untappd\.pl/i)) return;
    var url = this.value.trim();
    var m = url.match(/untappd\.com\/v\/(.+)/i);
    if (m) {
      scraperInput.value = 'untappd.pl ' + m[1];
    }
  });
})();
</script>
JS
    # Cascading loctype -> locsubtype
    print <<'JS';
<script>
(function() {
  var loctypeInput = document.getElementById('LocType');
  var locsubtypeDropdown = document.getElementById('dropdown-LocSubType');
  if (!loctypeInput || !locsubtypeDropdown) return;
  var locsubtypeList = locsubtypeDropdown.querySelector('.dropdown-list');
  var locsubtypeFilter = locsubtypeDropdown.querySelector('.dropdown-filter');
  if (!locsubtypeList) return;
  var selloctype = document.createElement('input');
  selloctype.type = 'hidden';
  selloctype.id = 'selloctype';
  locsubtypeDropdown.parentNode.appendChild(selloctype);
  function filterLocSubTypes() {
    var lt = loctypeInput.value;
    selloctype.value = lt;
    var items = locsubtypeList.querySelectorAll('.dropdown-item');
    var hasMatch = false;
    var i;
    for (i = 0; i < items.length; i++) {
      if (items[i].id === 'actions') continue;
      var lta = items[i].getAttribute('loctype');
      if (lta && lta === lt) { hasMatch = true; break; }
    }
    for (i = 0; i < items.length; i++) {
      if (items[i].id === 'actions') continue;
      var lta = items[i].getAttribute('loctype');
      if (!lt || !lta || lta === lt || !hasMatch) {
        items[i].style.display = '';
      } else {
        items[i].style.display = 'none';
      }
    }
  }
  loctypeInput.addEventListener('input', filterLocSubTypes);
  filterLocSubTypes();
})();
</script>
JS
    print "<hr/>\n";
    if ( $p->{Id} ne "new" ) {
      # Search line: untappd venue search and ddg
      my $nq = uri_escape_utf8($p->{Name} // "");
      my $search_html = "Search: ";
      $search_html .= util::extlink("https://untappd.com/search?q=$nq&type=venues&sort=", "untappd") . " ";
      my $gq = uri_escape_utf8($p->{Name} // "");
      $search_html .= util::extlink("https://duckduckgo.com/?q=$gq", "search");
      print "$search_html<br/>\n";
      print "<hr/>\n";
      my $return_url = "$c->{url}?o=$c->{op}&e=$p->{Id}";
      print photos::thumbnails_html($c, 'Location', $p->{Id});
      print photos::photo_form($c, location => $p->{Id}, public_default => 1, return_url => $return_url);
      print "&nbsp;<a href='$c->{url}?o=Comment&e=new&location=$p->{Id}&commenttype=location' onclick='event.stopPropagation()'><span>(new comment)</span></a>\n";
      print "<hr/>\n";
      print listrecords::listrecords($c, comments::comments_list_sql(), {
          where => q{CAST("LocId_A_link=Location" AS INTEGER) = ? AND xUsername = ?},
          params => [$p->{Id}, $c->{username}],
          title => "Comments",
          initial_filter => { CommentType => "location" },

          hide_headers_default => 1,
          no_new_link => 1,
          maxrecords => 10,
          norecmessage => "No comments",
      });
      print "<hr/>\n";
      locationvisits($c, $p );
      if ( $p->{LocType} =~ /Producer/ ) {
        print listrecords::listrecords($c, comments::comments_list_sql(), {
            where => q{EXISTS (SELECT 1 FROM comments c2
                       LEFT JOIN glasses g2 ON g2.Id = c2.Glass
                       WHERE c2.Id = "Id_A_link=Comment"
                         AND (c2.Brew IN (SELECT Id FROM brews WHERE ProducerLocation = ?)
                           OR g2.Brew IN (SELECT Id FROM brews WHERE ProducerLocation = ?)))
                       AND xUsername = ?},
            params => [$p->{Id}, $p->{Id}, $c->{username}],
            title => "Producer comments",
  
            hide_headers_default => 1,
            no_new_link => 1,
            maxrecords => 10,
            norecmessage => "No producer comments",
        });
        print "<hr/>\n";
        producerbrews($c, $p);
      }
      locationdeduplist($c,$p);
    }
  } else {
    print "Oops - location id '$c->{edit}' not found <br/>\n";
  }
} # editlocation

################################################################################
# Deduplicate location
################################################################################
sub deduplocations {
  my $c = shift; # context
  my $id = shift; # The id of the location we keep
  foreach my $paramname ($c->{cgi}->param) {
    if ( $paramname =~ /^Chk(\d+)$/ ) {
      my $dup = $1;
      # Merge lifecycle dates from the duplicate before it is deleted.
      # Opened/FirstSeen: earliest wins; Closed: latest wins.
      db::merge_dates($c, "LOCATIONS", $id, $dup,
        { earliest => [qw(Opened FirstSeen)], latest => [qw(Closed)] });

      my $sql = "UPDATE GLASSES SET Location = ? WHERE Location = ?  ";
      print { $c->{log} } "$sql with '$id' and '$dup' \n";
      my $rows = db::execute($c, $sql, $id, $dup);
      util::error("Deduplicate Locations: Failed to update GLASSES") unless defined $rows;
      print { $c->{log} } "Updated $rows glasses from $dup to $id\n";

      $sql = "UPDATE PERSONS SET Location = ? WHERE Location = ?  ";
      print { $c->{log} } "$sql with '$id' and '$dup' \n";
      $rows = db::execute($c, $sql, $id, $dup);
      util::error("Deduplicate Locations: Failed to update PERSONS") unless defined $rows;
      print { $c->{log} } "Updated $rows persons from $dup to $id\n";

      $sql = "UPDATE BREWS SET ProducerLocation = ? WHERE ProducerLocation = ?  ";
      print { $c->{log} } "$sql with '$id' and '$dup' \n";
      $rows = db::execute($c, $sql, $id, $dup);
      util::error("Deduplicate Locations: Failed to update BREWS") unless defined $rows;
      print { $c->{log} } "Updated $rows brews from $dup to $id\n";

      $sql = "DELETE FROM LOCATIONS WHERE Id = ? ";
      $rows = db::execute($c, $sql, $dup);
      util::error("Deduplicate Locations: Failed to delete location '$dup'") unless defined $rows;
      print { $c->{log} } "Deleted $rows locations with id $dup\n";
    }
  }

} # deduplocations

################################################################################
# Update a location (posted from the form above)
################################################################################
sub postlocation {
  my $c = shift; # context
  my $id = shift || $c->{edit};
  my $submit = util::param($c, "submit");
  if ($submit =~ /Delete/i) {
    db::deleterecord($c, "LOCATIONS", $id);
    return $id;
  }
  if ( util::param($c,"dedup") ) {
    deduplocations($c,$id);
    return;
  }

  if ( $id eq "new" ) {
    my $name = util::param($c, "newlocName");
    my $section = "newloc";
    if ( ! $name ) {
      $name = util::param($c, "Name");
      $section = "";
    }
    util::error ("A Location must have a name" )
      unless $name;
    $id = db::insertrecord($c, "LOCATIONS", $section);
  } else {
    my $name = util::param($c, "Name");
    util::error ("A Location must have a name" )
      unless $name;
    $id = db::updaterecord($c, "LOCATIONS", $id,  "");
  }
  return $id;
} # postlocation

################################################################################
# Helper to select a location
################################################################################
# Offers a list to select a location, or (optionally) to enter values for a
# new one. The optional 5th parameter limits the locations to those that are
# Producers, or those that are not. Default is not to limit at all.

sub selectlocation {
  my $c = shift; # context
  my $fieldname = shift || "Location";
  my $selected = shift || "";  # The id of the selected location
  my $newprefix = shift || ""; # Prefix for new-location fields. Enables the "new"
  my $prods = shift || "";  # "prod" for prod locs only, "non" for non-prods only. Defaults to all
  my $disabled = shift || "";  # "disabled" or ""

  if ( $selected && $selected !~ /^\d+$/ ){
    print { $c->{log} } "selectlocation called with non-numerical 'selected' argument: '$selected' \n";
    $selected = 0;
  }
  my $where = "WHERE ( LOCATIONS.Closed IS NULL OR LOCATIONS.Closed = '') ";
  my $skip = "Id";
  my $newfield = "newloc";
  if ( $prods eq "prod" ) {
    $where = "WHERE LOCATIONS.LocType = 'Producer' AND ( LOCATIONS.Closed IS NULL OR LOCATIONS.Closed = '')";
    $newfield = "newprod";
    $skip .= "|LocType|LocSubType";
  } elsif ( $prods eq "non" ) {
    # NOTE: Must handle NULL LocType — NULL <> 'Producer' is NULL (falsy).
    $where = "WHERE (LOCATIONS.LocType IS NULL OR LOCATIONS.LocType <> 'Producer') " .
             "AND ( LOCATIONS.Closed IS NULL OR LOCATIONS.Closed = '')";
  }
  # The opts list is the expensive part. Cache per user and location filter type.
  my $cache_key = "selectlocation_opts:$c->{username}:$prods";
  my $opts = cache::get($c, $cache_key);

  if ( !defined $opts ) {
    my $sql = "
    SELECT
      LOCATIONS.Id,
      LOCATIONS.Name,
      LOCATIONS.LocType,
      LOCATIONS.LocSubType,
      LOCATIONS.Lat,
      LOCATIONS.Lon,
      LOCATIONS.Tags,
      LOCATIONS.Country,
      LOCATIONS.Region
    FROM LOCATIONS
    LEFT JOIN GLASSES ON GLASSES.Location = LOCATIONS.Id
    $where
    GROUP BY LOCATIONS.id
    ORDER BY max(GLASSES.Timestamp) DESC
    ";
    my $list_sth = db::query($c, $sql);
    $opts = "";
    while ( my ($id, $name, $type, $subtype, $lat, $lon, $tags, $country, $region) = $list_sth->fetchrow_array ) {
      if ($type) {
        $type = "[$type]";
      } elsif ( defined $type ) {
        $type = "";
      } else {
        $type = "[NULL]";
      }
      my $dist = "";
      if ($lat && $lon) {
        $dist = "<span lat=$lat lon=$lon style='pointer-events:none; font-size: xx-small;'> ??? </span>";
      }
      my $substtr = "";
      $substtr = "locsubtype='$subtype'" if ($subtype);
      my $tags_attr = "";
      $tags_attr = " tags='" . util::htmlesc($tags) . "'" if ($tags);
      my $country_attr = "";
      $country_attr = " country='" . util::htmlesc($country) . "'" if ($country);
      my $region_attr = "";
      $region_attr = " region='" . util::htmlesc($region) . "'" if ($region);
      $opts .= "      <div class='dropdown-item' id='$id' $substtr$tags_attr$country_attr$region_attr>$name $type $dist</div>\n";
    }
    cache::set($c, $cache_key, $opts);
  }

  # Look up the display name of the selected location (cheap primary-key lookup)
  my $current = "";
  if ( $selected ) {
    ($current) = db::queryarray($c, "SELECT Name FROM LOCATIONS WHERE Id = ?", $selected);
    $current //= "";
  }

  my $defaults = {};
  if ( $prods ne "prod" ) {
    # Default LocType/LocSubType for inline new-location form (issue #714)
    $defaults = { LocType => "Bar", LocSubType => "Beer" };
  }
  # Filter field_order to exclude skipped fields to avoid warnings in inputform
  my @filtered_field_order;
  my $skip_re = qr/^$skip$/;
  foreach my $entry (@$loc_field_order) {
    push @filtered_field_order, $entry unless $entry->[0] =~ $skip_re;
  }
  my $s = inputs::dropdown( $c, $fieldname, $selected, $current, $opts, { table => "LOCATIONS", newfield => $newfield, skip => $skip, disabled => $disabled, defaults => $defaults, fieldorder => \@filtered_field_order } );
  $s .= "<script>geotabledist();</script>\n";
  return $s;

} # selectlocation


################################################################################
# Return distinct countries and regions from BREWS+LOCATIONS for dropdown use.
# Returns hashref:
#   { countries => [...sorted country name strings...],
#     regions   => [...sorted {country, region} hashrefs (non-empty regions only)...] }
# Result is cached in $c->{cache}{countries_regions}.
################################################################################
sub distinct_countries_and_regions {
  my $c = shift;

  my $cached = cache::get($c, 'countries_regions');
  return $cached if defined $cached;

  my $sql = "
    SELECT DISTINCT Country, Region FROM BREWS
      WHERE Country IS NOT NULL AND Country != ''
    UNION
    SELECT DISTINCT Country, Region FROM LOCATIONS
      WHERE Country IS NOT NULL AND Country != ''
    ORDER BY Country, Region
  ";
  my $sth = db::query($c, $sql);

  my %seen_countries;
  my @countries;
  my @regions;

  while (my ($country, $region) = $sth->fetchrow_array) {
    unless ($seen_countries{$country}) {
      push @countries, $country;
      $seen_countries{$country} = 1;
    }
    if (defined $region && $region ne '') {
      push @regions, { country => $country, region => $region };
    }
  }

  my $result = { countries => \@countries, regions => \@regions };
  cache::set($c, 'countries_regions', $result);
  return $result;
} # distinct_countries_and_regions


################################################################################
1; # Tell perl that the module loaded fine

