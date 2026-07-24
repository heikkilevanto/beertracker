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
  [ "Tags",            "for filtering" ],
  [ "Scraper",         "Scraper script for beer menu" ],
];


# TODO - Add current and latest as options to it



# Formatting magic
my $clr = "Onfocus='value=value.trim();select();' autocapitalize='words'";
#my $sz = "size='4' style='text-align:right' $clr";

################################################################################
# Lists of locations
################################################################################
sub listlocations {
  my $c = shift; # context

  if ( $c->{edit} ) {  # Id for full info
    editlocation($c);
    return;
  }
  my $sort = $c->{sort} || "Last-";
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
      (SELECT Filename FROM photos WHERE Location = locations.Id ORDER BY Ts DESC LIMIT 1) AS "Photo_R2_noheader_nofilter",
      '' AS TR1,
      locations.lat || ' ' || locations.lon AS "Geo",
      COALESCE(locations.Country,'') || ';' || COALESCE(locations.Region,'') AS "CountryRegion_A_contline",
      strftime('%Y-%m-%d %w ', max(glasses.Timestamp), '-06:00') ||
        strftime('%H:%M', max(glasses.Timestamp)) AS "Last_cont",
      locations.Tags AS xTags
    FROM locations
    LEFT JOIN glasses ON glasses.Location = locations.Id
    LEFT JOIN (
      select
        l.id,
        count(merged.Rating)   as rating_count,
        avg(merged.Rating)     as rating_average,
        count(merged.Comment)  as comment_count
      from locations l
      left join (
        select g.Location as loc_id, c.Rating, c.Comment
          from comments c join glasses g on g.Id = c.Glass
          where COALESCE(g.Username, c.Username) = $username
        union all
        select c.Location as loc_id, c.Rating, c.Comment
          from comments c where c.Location is not null and c.Glass is null
          and c.Username = $username
      ) merged on merged.loc_id = l.Id
      group by l.Id
    ) r ON r.id = locations.Id
    GROUP BY locations.Id},
      $sort,
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
    select
       strftime ('%Y-%m', timestamp,'-06:00') as month,
       count( distinct( strftime( '%d', timestamp, '-06:00' ) ) ) as daycount
    from glasses
    where Location = ?
      and username = ?
    group by month
    order by timestamp
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
      q{with users as (
        select distinct Username from glasses
      )
      select
        brews.Id AS "IdClr_A",
        brews.Name AS "Name_A_C2_cont",
        '' AS TR1,
        brews.Alc AS "Alc",
        brews.BrewType || ', ' || brews.SubType AS "Type_A_cont",
        r.rating_count || ';' || r.average_rating || ';' || r.comment_count AS "Stats_A",
        strftime('%Y-%m-%d %w ', max(glasses.Timestamp), '-06:00') ||
          strftime('%H:%M', max(glasses.Timestamp)) AS "Last",
        ploc.Name as xProducer,
        users.Username as xUsername
      from brews
      cross join users
      left join locations ploc on ploc.id = brews.ProducerLocation
      left join glasses on glasses.Brew = brews.Id and glasses.Username = users.Username
      left join brew_ratings r on r.Brew = brews.Id and r.Username = users.Username
      group by brews.id, users.Username},
      "Last-",
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
  my $sort = $c->{sort} || "Last-";
  my $extra = {};
  $extra->{lat} = $loc->{Lat};
  $extra->{lon} = $loc->{Lon};
  $extra->{refname} = $loc->{Name};
  print listrecords::listrecords($c,
      q{select
        locations.Id AS "Id_A",
        locations.Name,
        '?' as Sim,
        locations.lat || ' ' || locations.lon AS Geo,
        '' AS TR1,
        'Chk' as Chk,
        locations.LocType || ', ' || locations.LocSubType as Type,
        strftime('%Y-%m-%d %w ', max(glasses.Timestamp), '-06:00') ||
          strftime('%H:%M', max(glasses.Timestamp)) as "Last_C2"
      from locations
      left join glasses on glasses.Location = locations.Id
      group by locations.Id},
      $sort,
      { where => "Id_A <> ?", extraparams => $extra, params => $loc->{Id},
        browsersortcol => "Sim", title => "Similar locations" });
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
  my $sql = "select distinct LocType from locations where LocType is not null and LocType != '' order by LocType";
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
  my $sql = "select distinct LocType, LocSubType from locations where LocSubType is not null and LocSubType != '' order by LocType, LocSubType";
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
    my $sql = "select * from Locations where id = ?";
    $p = db::queryrecord($c, $sql, $c->{edit});
    util::error("Location #$c->{edit} not found") unless $p && $p->{Id};
    print "<b>Editing Location $p->{Id}: $p->{Name}</b><br/>\n";
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
      print listrecords::listrecords($c, comments::comments_list_sql(), "Last-", {
          where => q{CAST("LocId_A_link=Location" AS INTEGER) = ? AND xUsername = ?},
          params => [$p->{Id}, $c->{username}],
          title => "Comments",
          initial_filter => { CommentType => "location" },
          show_rating_summary => 1,
          hide_headers_default => 1,
          no_new_link => 1,
          maxrecords => 10,
          norecmessage => "No comments",
      });
      print "<hr/>\n";
      locationvisits($c, $p );
      if ( $p->{LocType} =~ /Producer/ ) {
        print listrecords::listrecords($c, comments::comments_list_sql(), "Last-", {
            where => q{EXISTS (SELECT 1 FROM comments c2
                       LEFT JOIN glasses g2 ON g2.Id = c2.Glass
                       WHERE c2.Id = "Id_A_link=Comment"
                         AND (c2.Brew IN (SELECT Id FROM brews WHERE ProducerLocation = ?)
                           OR g2.Brew IN (SELECT Id FROM brews WHERE ProducerLocation = ?)))
                       AND xUsername = ?},
            params => [$p->{Id}, $p->{Id}, $c->{username}],
            title => "Producer comments",
            show_rating_summary => 1,
            hide_headers_default => 1,
            no_new_link => 1,
            maxrecords => 10,
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
      my $sql = "UPDATE GLASSES set Location = ? where Location = ?  ";
      print { $c->{log} } "$sql with '$id' and '$dup' \n";
      my $rows = db::execute($c, $sql, $id, $dup);
      util::error("Deduplicate Locations: Failed to update GLASSES") unless defined $rows;
      print { $c->{log} } "Updated $rows glasses from $dup to $id\n";

      $sql = "UPDATE PERSONS set Location = ? where Location = ?  ";
      print { $c->{log} } "$sql with '$id' and '$dup' \n";
      $rows = db::execute($c, $sql, $id, $dup);
      util::error("Deduplicate Locations: Failed to update PERSONS") unless defined $rows;
      print { $c->{log} } "Updated $rows persons from $dup to $id\n";

      $sql = "UPDATE BREWS set ProducerLocation = ? where ProducerLocation = ?  ";
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
  my $where = "";
  my $skip = "Id";
  my $newfield = "newloc";
  if ( $prods eq "prod" ) {
    $where = "where LOCATIONS.LocType = \"Producer\" ";
    $newfield = "newprod";
    $skip .= "|LocType|LocSubType";
  } elsif ( $prods eq "non" ) {
    # NOTE: Must handle NULL LocType — NULL <> 'Producer' is NULL (falsy).
    $where = "where (LOCATIONS.LocType IS NULL OR LOCATIONS.LocType <> \"Producer\") ";
  }
  # The opts list is the expensive part. Cache per user and location filter type.
  my $cache_key = "selectlocation_opts:$c->{username}:$prods";
  my $opts = cache::get($c, $cache_key);

  if ( !defined $opts ) {
    my $sql = "
    select
      LOCATIONS.Id,
      LOCATIONS.Name,
      LOCATIONS.LocType,
      LOCATIONS.LocSubType,
      LOCATIONS.Lat,
      LOCATIONS.Lon,
      LOCATIONS.Tags,
      LOCATIONS.Country,
      LOCATIONS.Region
    from LOCATIONS
    left join GLASSES on GLASSES.Location = LOCATIONS.Id
    $where
    group by LOCATIONS.id
    order by max(GLASSES.Timestamp) DESC
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
      my $substtr = $subtype ? "locsubtype='$subtype'" : "";
      my $tags_attr    = $tags    ? " tags='"    . util::htmlesc($tags)    . "'" : "";
      my $country_attr = $country ? " country='" . util::htmlesc($country) . "'" : "";
      my $region_attr  = $region  ? " region='"  . util::htmlesc($region)  . "'" : "";
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

} # seleclocation


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

