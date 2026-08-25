# Part of my beertracker
# Routines for displaying the beer list (board) for the current bar
# and buttons for quickly marking a beer has been drunk

package beerboard;
use strict;
use warnings;
use feature 'unicode_strings';
use utf8;  # Source code and string literals are utf-8
use POSIX qw(strftime localtime);
use Time::Local;



################################################################################
# Beer board (list) for the location.
# Scraped from their website
################################################################################

sub beerboard {
  my $c = shift;


  my ($locparam, $foundrec) = get_location_param($c);

  # Check that the location has a scraper configured; fall back to a default if not
  my $loc_rec_check = db::findrecord($c, "LOCATIONS", "Name", $locparam, "collate nocase");
  if (!$loc_rec_check || !$loc_rec_check->{Scraper}) {
    print "Sorry, no beer list for '$locparam' - showing 'Ølbaren' instead<br/>\n";
    $locparam = "Ølbaren"; # A good default
  }
  # Closed places still show their last cached board, with a note
  if ($loc_rec_check && $loc_rec_check->{Closed}) {
    print "<div style='font-weight: bold;'>This place is closed</div>\n";
  }

  # Parse the beerboard datetime parameter (bd)
  # Supports: HH, HH:MM, HHMM, YYYY-MM-DD, YYYY-MM-DD HH:MM, -N, Y/YY/YYY (N days ago)
  my $bd_param = util::param($c, "bd");
  my $as_of = undef;
  my $bd_display = "";
  if ($bd_param) {
    $as_of = util::parse_beerboard_date($c, $bd_param);
    if ($as_of) {
      $bd_display = substr($as_of, 0, 16); # YYYY-MM-DD HH:MM for display
    }
  }

  # Compute reference epoch for "is new" checks (use $as_of if historical)
  my $ref_time = time();
  if ($as_of) {
    if ($as_of =~ /^(\d{4})-(\d{2})-(\d{2}) (\d{2}):(\d{2}):(\d{2})$/) {
      $ref_time = Time::Local::timelocal($6, $5, $4, $3, $2 - 1, $1);
    }
  }

  # If showing a historical board, open the controls section by default
  my $open_controls = $as_of ? 1 : 0;
  render_location_selector($c, $locparam, $bd_param, $as_of, $open_controls);

  my ($beerlist, $last_epoch) = load_beerlist_from_db($c, $locparam, $as_of);

  if (!$beerlist || !@$beerlist) {
    print "Trying to get the list for $locparam - reload to see it <br/>\n";
    trigger_background_update($c, $locparam) unless $as_of;
    return;
  }

  my $is_old = $last_epoch && (time() - $last_epoch) > 20 * 60;
  if ($is_old) {
    my $timestamp = strftime('%Y-%m-%d %H:%M', localtime($last_epoch));
    print "<div style='font-weight: bold;'>The beer board is from $timestamp ";
    print scrapeboard::post_form($c, 'updateboard', $locparam, '(Reload)');
    print "</div>\n";
    trigger_background_update($c, $locparam);
  }

  # Display the datetime if showing a historical board
  if ($bd_display) {
    print "<div style='font-weight: bold;'>Board as of $bd_display</div>\n";
  }

  # Always expand the beer I drank most recently, if any
  my $extraboard = -3; # none by default
  if ($foundrec && $foundrec->{brewid} && @$beerlist) {
    foreach my $e (@$beerlist) {
      if ($foundrec->{brewid} == $e->{brew_id}) {
        $extraboard = $e->{id};
        last;
      }
    }
  }

  my $nbeers = 0;
  my $expand_display = 'none';
  print "<div id='expand-all' style='display:$expand_display;'><a href='#' onclick='collapseAll(); return false;'><span>Collapse All</span></a></div>\n";

  print "<table id='beerboard' border=0 style='white-space: nowrap;'>\n";
  my $previd  = 0;
  my $locrec = db::findrecord($c,"LOCATIONS","Name",$locparam, "collate nocase");
  my $locid = undef;
  $locid = $locrec->{Id} if ($locrec);
  foreach my $e ( sort {$a->{"id"} <=> $b->{"id"} } @$beerlist )  {
    $nbeers++;
    my $id = $e->{"id"} || 0;
    my $processed_data = prepare_beer_entry_data($c, $e, $locparam, $ref_time);
    my $hiddenbuttons = generate_hidden_fields($c, $e, $locparam, $locid, $id, $processed_data);
    my $buttons_compact = render_beer_buttons($c, $e->{"sizePrice"}, $hiddenbuttons, 0, $e->{"alc"} || 0);
    my $buttons_expanded = render_beer_buttons($c, $e->{"sizePrice"}, $hiddenbuttons, 1, $e->{"alc"} || 0);

    my $beerstyle = styles::brewtextstyle($c, $processed_data->{origsty}, "Board:$e->{'id'} '$e->{'beer'}' $e->{'maker'} sty=$processed_data->{origsty}");

    my $dispid = $id;

    my $seenline = seenline($c, $e->{seen_count}, $e->{seen_min_date}, $e->{seen_max_date});

    render_beer_row($c, $e, $processed_data, $buttons_compact, $buttons_expanded, $beerstyle, $extraboard, $id, $dispid, $seenline, $locparam, $hiddenbuttons, $ref_time);

    $previd = $id;
  } # beer loop
  print "</table>\n";
  if (! $nbeers ) {
    print "Sorry, got no beers from $locparam\n";
  }
  print "<hr/>\n";
} # beerboard


################################################################################
# Small helpers
################################################################################

# Helper to produce a "Seen" line (pure formatting, data comes from main SQL)
sub seenline {
  my $c = shift;
  my ($count, $min_date, $max_date) = @_;
  return "" unless $count;
  my $times_word = "times";
  $times_word = "time" if ($count == 1);
  my $seenline = "Seen <b>$count</b> $times_word";
  if ($min_date) {
    my $display_date = $min_date;
    if ($count > 1 && $max_date) {
      $display_date .= " to " . util::reldate($max_date);
    }
    $seenline .= " $display_date";
  }
  return $seenline;
} # seenline

sub format_date_relative {
  my ($date_str, $time_str) = @_;
  return "" unless $date_str;
  my $rel = util::reldate($date_str);

  my $formatted_time = $time_str;
  $formatted_time = "($time_str)" if ($time_str && $time_str lt "06:00");

  if ($rel eq "today") {
    return $formatted_time;
  } elsif ($rel eq "yesterday") {
    return "yesterday $formatted_time";
  } else {
    return $date_str;
  }
} # format_date_relative

sub format_duration_relative {
  my ($first_seen_ts, $ref_time) = @_;
  $ref_time //= time();
  return "" unless $first_seen_ts;
  my $age = $ref_time - $first_seen_ts;
  if ($age < 3600) {
    my $minutes = int($age / 60);
    if ($minutes <= 0) { return "less than 1m"; }
    return "${minutes}m";
  } elsif ($age < 4 * 3600) {
    my $hours = int($age / 3600);
    my $mins = int(($age % 3600) / 60);
    return "${hours}h${mins}m";
  } elsif ($age < 48 * 3600) {
    my $hours = int($age / 3600);
    return "${hours}h";
  } else {
    my $days = int($age / 86400);
    my $unit = "days";
    $unit = "day" if ($days == 1);
    return "$days $unit";
  }
} # format_duration_relative

sub format_date_absolute {
  my ($date_str, $time_str) = @_;
  return "" unless $date_str;
  my @months = qw(Jan Feb Mar Apr May Jun Jul Aug Sep Oct Nov Dec);
  my ($y, $m, $d) = split /-/, $date_str;
  my $mon = $months[$m - 1];
  my $result = "$d-$mon";
  $result .= " $time_str" if $time_str;
  return $result;
} # format_date_absolute


################################################################################
# Helper functions for beerboard
################################################################################

sub render_location_selector {
  my ($c, $locparam, $bd_param, $as_of, $open_controls) = @_;
  $bd_param //= "";
  my $controls_display = $open_controls ? 'block' : 'none';
  # Pull-down for choosing the bar — always visible
  my $url = $c->{url};
  $url =~ s/"/&quot;/g;
  print "\n<form method='POST' accept-charset='UTF-8' style='display:inline;' class='no-print' >\n";
  print "<a href='#' onclick='toggleControls(); return false;'><span>Beer list</span></a> \n";
  print "<select onchange=\"document.location='$url?o=Board&loc=' +
       encodeURIComponent(this.value);\" style='display:inline-block; width:5.5em;'>\n";
  for my $l ( scrapeboard::get_scraper_locations($c) ) {
    my $sel = "";
    $sel = "selected" if ( $l eq $locparam);
    print "<option value='$l' $sel>$l</option>\n";
  }
  print "</select>\n";
  print "</form>\n";

  # Collapsible controls section — initially hidden
  # Contains: datetime+Show, filter+PA+Clr, www link, Reload, Exp/Collapse
  print "<div id='board-controls' style='display:$controls_display; margin: 0.5em 0;'>\n";
  print "<table border=0 style='white-space: nowrap;'>\n";

  # Row 1: Datetime field + Show button (GET navigation, clears JS filters)
  my $now_display = strftime('%Y-%m-%d %H:%M', localtime(time()));
  # Prefill: show actual datetime, not relative shortcuts like 'y'
  my $bd_value = "";
  if ($as_of) {
    $bd_value = substr($as_of, 0, 16); # YYYY-MM-DD HH:MM
  } else {
    $bd_value = $now_display;
  }
  print "<tr>\n";
  print "<td><input type='text' id='bd-input' size='16' value='" . util::htmlesc($bd_value) . "' pattern='\\d{4}-\\d{2}-\\d{2}[T ]\\d{1,2}(:\\d{2})?|\\d{4}-\\d{2}-\\d{2}|\\d{1,2}:\\d{2}|\\d{1,2}|\\d{4}|[Yy]+|-\\d+d?' onfocus='this.select();' title='YYYY-MM-DD HH:MM, YYYY-MM-DD, HH:MM, HHMM, Y (yesterday), YY (2d ago), -N (N d ago)' onkeydown=\"if(event.key==='Enter'){document.getElementById('bd-form-input').value=this.value;document.getElementById('bd-form-input').form.submit();return false;}\" /> &nbsp;</td>\n";
  print "<td>";
  print "<form method='GET' style='display:inline;'>\n";
  print "<input type='hidden' name='o' value='$c->{op}' />\n";
  print "<input type='hidden' name='loc' value='" . util::htmlesc($locparam) . "' />\n";
  print "<input type='hidden' name='bd' id='bd-form-input' value='' />\n";
  print "<input type='submit' value='Show' onclick=\"document.getElementById('bd-form-input').value = document.getElementById('bd-input').value;\" />\n";
  print "</form>\n";
  print "</td>\n";
  print "</tr>\n";

  # Row 2: Text filter + PA + Clr buttons (JS client-side filtering)
  print "<tr>\n";
  print "<td><input type='text' id='board-filter' size='12' placeholder='Filter' onfocus='this.select();' /> &nbsp;</td>\n";
  print "<td>";
  print "<input type='button' value='PA' onclick='applyPAFilter();' /> \n";
  print "<input type='button' value='Clr' onclick='clearBoardFilter();' />\n";
  print "</td>\n";
  print "</tr>\n";

  # Row 3: External links (www, untappd) + Reload + Exp — all on one line
  print "<tr>\n";
  print "<td>\n";
  my $locrec = db::findrecord($c,"LOCATIONS","Name",$locparam, "collate nocase");
  if ($locrec && $locrec->{Website}) {
    print "<i><a href='$locrec->{Website}' target='_blank'><span>www</span></a></i> ";
  }
  if ($locrec->{UntappdLink}) {
    print "<i><a href='$locrec->{UntappdLink}' target='_blank'><span>Ut</span></a></i> ";
  }
  print "</td>\n";
  print "<td>\n";
  print scrapeboard::post_form($c, 'updateboard', $locparam, '(Reload)');
  print " &nbsp; <a href='#' onclick='expandAll(); return false;'><span>(Exp)</span></a>";
  print "</td>\n";
  print "</tr>\n";

  print "</table>\n";
  print "</div>\n";
  print "<p>\n";
} # render_location_selector

sub get_location_param {
  my $c = shift;
  # Get the last used location for this user
  my $sql = "SELECT * FROM glassrec " .
            "WHERE username = ? " .
            "ORDER BY stamp DESC ".
            "LIMIT 1";
  my $foundrec = db::queryrecord($c, $sql, $c->{username});

  my $locparam = util::param($c,"loc") || $foundrec->{loc} || "";
  $locparam =~ s/^ +//; # Drop the leading space for guessed locations
  return ($locparam, $foundrec);
}

sub load_beerlist_from_db {
  my ($c, $locparam, $as_of) = @_;

  # Get location ID
  my $loc_rec = db::findrecord($c, "LOCATIONS", "Name", $locparam);
  return ([], undef) unless $loc_rec;
  my $loc_id = $loc_rec->{Id};

  # Get the latest scrape marker (only meaningful for current view)
  my $last_epoch = undef;
  if (!$as_of) {
    ($last_epoch) = db::queryarray($c,
      "SELECT strftime('%s', LastSeen) AS last_epoch FROM tap_beers " .
      "WHERE Location = ? AND Tap IS NULL ORDER BY LastSeen DESC LIMIT 1",
      $loc_id);
  }

  # Common SELECT columns and JOINs
  # For historical view ($as_of set), query tap_beers directly with date filter
  # instead of using the current_taps view (which only shows Gone IS NULL).
  my ($sql, @params);
  if ($as_of) {
    $sql = "SELECT
        tb.Tap, tb.Brew, b.Name AS beer,
        pl.Name AS maker, pl.Id AS maker_id,
        b.SubType AS type, b.Alc AS alc,
        b.BrewType AS brewtype,
        b.DetailsLink AS details_link,
        b.ShortName AS brew_shortname,
        pl.SearchLink AS maker_search_link,
        pl.ShortName AS shortname,
        tb.SizeS, tb.PriceS, tb.SizeM, tb.PriceM, tb.SizeL, tb.PriceL,
        b.DefPrice, b.DefVol,
        ur.rating_count, ur.average_rating, ur.comment_count,
        strftime('%Y-%m-%d', tb.FirstSeen) AS first_seen_date,
        strftime('%H:%M', tb.FirstSeen) AS first_seen_time,
        strftime('%s', tb.FirstSeen) AS first_seen_ts,
        ug.seen_count, ug.seen_min_date, ug.seen_max_date,
        (SELECT round(avg(julianday(h.Gone) - julianday(h.FirstSeen)), 1)
         FROM tap_beers h
         WHERE h.Brew = tb.Brew AND h.Location = tb.Location
           AND h.Gone IS NOT NULL
           AND julianday(h.Gone) - julianday(h.FirstSeen) < 45
         HAVING count(*) >= 2) as avg_days_on_tap,
        (SELECT count(*) FROM tap_beers h
         WHERE h.Brew = tb.Brew AND h.Location = tb.Location
           AND h.Gone IS NOT NULL
           AND julianday(h.Gone) - julianday(h.FirstSeen) < 45
         HAVING count(*) >= 2) as tap_history_count
    FROM tap_beers tb
      JOIN brews b ON tb.Brew = b.Id
      LEFT JOIN locations pl ON b.ProducerLocation = pl.Id
      LEFT JOIN (
        SELECT brew, rating_count, average_rating, comment_count
        FROM brew_ratings WHERE Username = ?
      ) ur ON ur.Brew = tb.Brew
      LEFT JOIN (
        SELECT Brew,
               count(Id) AS seen_count,
               strftime('%Y-%m-%d', min(Timestamp), '-06:00') AS seen_min_date,
               strftime('%Y-%m-%d', max(Timestamp), '-06:00') AS seen_max_date
        FROM glasses
        WHERE Username = ?
        GROUP BY Brew
      ) ug ON ug.Brew = tb.Brew
    WHERE tb.Location = ?
      AND tb.FirstSeen <= ?
      AND (tb.Gone IS NULL OR tb.Gone >= ?)
      AND tb.Tap IS NOT NULL AND tb.Brew IS NOT NULL
    ORDER BY tb.Tap";
    @params = ($c->{username}, $c->{username}, $loc_id, $as_of, $as_of);
  } else {
    $sql = "SELECT
        ct.Tap, ct.Brew, ct.BrewName AS beer,
        pl.Name AS maker, pl.Id AS maker_id,
        b.SubType AS type, b.Alc AS alc,
        b.BrewType AS brewtype,
        b.DetailsLink AS details_link,
        b.ShortName AS brew_shortname,
        pl.SearchLink AS maker_search_link,
        pl.ShortName AS shortname,
        tb.SizeS, tb.PriceS, tb.SizeM, tb.PriceM, tb.SizeL, tb.PriceL,
        b.DefPrice, b.DefVol,
        ur.rating_count, ur.average_rating, ur.comment_count,
        strftime('%Y-%m-%d', tb.FirstSeen) AS first_seen_date,
        strftime('%H:%M', tb.FirstSeen) AS first_seen_time,
        strftime('%s', tb.FirstSeen) AS first_seen_ts,
        ug.seen_count, ug.seen_min_date, ug.seen_max_date,
        (SELECT round(avg(julianday(h.Gone) - julianday(h.FirstSeen)), 1)
         FROM tap_beers h
         WHERE h.Brew = ct.Brew AND h.Location = ct.Location
           AND h.Gone IS NOT NULL
           AND julianday(h.Gone) - julianday(h.FirstSeen) < 45
         HAVING count(*) >= 2) as avg_days_on_tap,
        (SELECT count(*) FROM tap_beers h
         WHERE h.Brew = ct.Brew AND h.Location = ct.Location
           AND h.Gone IS NOT NULL
           AND julianday(h.Gone) - julianday(h.FirstSeen) < 45
         HAVING count(*) >= 2) as tap_history_count
      FROM current_taps ct
        JOIN tap_beers tb ON ct.Id = tb.Id
        JOIN brews b ON ct.Brew = b.Id
        LEFT JOIN locations pl ON b.ProducerLocation = pl.Id
        LEFT JOIN (
          SELECT brew, rating_count, average_rating, comment_count
          FROM brew_ratings WHERE Username = ?
        ) ur ON ur.Brew = ct.Brew
        LEFT JOIN (
          SELECT Brew,
                 count(Id) AS seen_count,
                 strftime('%Y-%m-%d', min(Timestamp), '-06:00') AS seen_min_date,
                 strftime('%Y-%m-%d', max(Timestamp), '-06:00') AS seen_max_date
          FROM glasses
          WHERE Username = ?
          GROUP BY Brew
        ) ug ON ug.Brew = ct.Brew
      WHERE ct.Location = ?
      ORDER BY ct.Tap";
    @params = ($c->{username}, $c->{username}, $loc_id);
  }
  my $sth = db::query($c, $sql, @params);

  my $beerlist = [];
  while (my $row = $sth->fetchrow_hashref) {
    my $sizePrice = [];
    if ($row->{SizeS}) {
      push @$sizePrice, { vol => $row->{SizeS}, price => $row->{PriceS} };
    }
    if ($row->{SizeM}) {
      push @$sizePrice, { vol => $row->{SizeM}, price => $row->{PriceM} };
    }
    if ($row->{SizeL}) {
      push @$sizePrice, { vol => $row->{SizeL}, price => $row->{PriceL} };
    }
    # Fallback when no sizes were scraped
    my $sizes_are_default = 0;
    if (!scalar(@$sizePrice)) {
      if ($row->{DefVol}) {
        $sizes_are_default = 1;
        push @$sizePrice, { vol => 'S', price => undef };
        push @$sizePrice, { vol => $row->{DefVol}, price => $row->{DefPrice} };
      } else {
        $sizes_are_default = 1;
        push @$sizePrice, { vol => 'S', price => undef };
        push @$sizePrice, { vol => 'L', price => undef };
      }
    }

    push @$beerlist, {
      id => $row->{Tap},
      maker => $row->{maker} || "",
      maker_id => $row->{maker_id},
      beer => $row->{beer} || "",
      type => $row->{type} || "",
      alc => $row->{alc} || "",
      brew_id => $row->{Brew},
      sizePrice => $sizePrice,
      sizes_are_default => $sizes_are_default,
      rating_count => $row->{rating_count},
      average_rating => $row->{average_rating},
      comment_count => $row->{comment_count},
      first_seen_date => $row->{first_seen_date},
      first_seen_time => $row->{first_seen_time},
      first_seen_ts => $row->{first_seen_ts},
      seen_count => $row->{seen_count},
      seen_min_date => $row->{seen_min_date},
      seen_max_date => $row->{seen_max_date},
      details_link => $row->{details_link},
      brew_shortname => $row->{brew_shortname},
      maker_search_link => $row->{maker_search_link},
      shortname => $row->{shortname},
      brewtype => $row->{brewtype},
      avg_days_on_tap => $row->{avg_days_on_tap},
      tap_history_count => $row->{tap_history_count}
    };
  }

  print "<!-- Loaded beerlist from DB for '$locparam' -->\n";
  return ($beerlist, $last_epoch);
}

sub prepare_beer_entry_data {
  my ($c, $e, $locparam, $ref_time) = @_;
  $ref_time //= time();
  my $mak = $e->{"maker"} || "";
  my $beer = $e->{"beer"} || "";
  my $sty = $e->{"type"} || "";
  my $origsty = $sty;
  $sty = styles::shortbeerstyle($sty);
  print "<!-- sty='$origsty' -> '$sty'\n'$e->{'beer'}' -> '$beer'\n'$e->{'maker'}' -> '$mak' -->\n";

  my $dispmak = $e->{shortname} || $mak;
  if ( $beer =~ /$dispmak/ || !$mak) {
    $dispmak = ""; # Same word in the beer, don't repeat
  } else {
    $dispmak = "<a href='$c->{url}?o=Location&e=$e->{maker_id}'><i>$dispmak</i></a>" if ($dispmak && $e->{maker_id});
  }
  $beer =~ s/(Warsteiner).*/$1/;  # Shorten some long beer names
  $beer =~ s/.*(Hopfenweisse).*/$1/;
  $beer =~ s/.*(Ungespundet).*/$1/;
  if ( $beer =~ s/Aecht Schlenkerla Rauchbier[ -]*// ) {
    $mak = "Schlenkerla";
    $dispmak = "<a href='$c->{url}?o=Location&e=$e->{maker_id}'><i>$mak</i></a>" if ($e->{maker_id});
  }
  my $dispbeer = "<a href='$c->{url}?o=Brew&e=$e->{brew_id}'><b>$beer</b></a>" if ($e->{brew_id});
  my $shortbeer = $e->{brew_shortname} || $beer;
  my $dispbeer_short = "<a href='$c->{url}?o=Brew&e=$e->{brew_id}'><b>$shortbeer</b></a>" if ($e->{brew_id});
  $dispbeer_short ||= $dispbeer;

  $mak =~ s/'//g; # Apostrophes break the input form below
  $beer =~ s/'//g; # So just drop them
  $sty =~ s/'//g;

  # Compute external link (priority: DetailsLink > MakerSearchLink > DDG fallback)
  my $ddg_query = "";
  $ddg_query = "$mak $beer" if ($mak || $beer);
  my $extlink_html = util::brewlinks($c, $e->{details_link}, $beer, $e->{maker_search_link}, $ddg_query, $e->{brewtype}, $e->{brew_shortname});

  # Full maker name as a link for the expanded header
  my $dispmak_full = $mak;
  $dispmak_full = "<a href='$c->{url}?o=Location&e=$e->{maker_id}'><span>$mak</span></a>" if ($e->{maker_id});

  my $country = $e->{'country'} || "";

  return {
    mak => $mak,
    beer => $beer,
    sty => $sty,
    origsty => $origsty,
    dispmak => $dispmak,
    dispbeer => $dispbeer,
    dispbeer_short => $dispbeer_short,
    country => $country,
    rating_count => $e->{rating_count},
    average_rating => $e->{average_rating},
    comment_count => $e->{comment_count},
    first_seen_date => $e->{first_seen_date},
    first_seen_time => $e->{first_seen_time},
    first_seen_ts => $e->{first_seen_ts},
    first_seen_date_formatted => format_date_relative($e->{first_seen_date}, $e->{first_seen_time}),
    first_seen_relative => format_duration_relative($e->{first_seen_ts}, $ref_time),
    first_seen_absolute => format_date_absolute($e->{first_seen_date}, $e->{first_seen_time}),
    extlink_html => $extlink_html,
    dispmak_full => $dispmak_full,
    avg_days_on_tap => $e->{avg_days_on_tap},
    tap_history_count => $e->{tap_history_count}
  };
}

sub generate_hidden_fields {
  my ($c, $e, $locparam, $locid, $id, $processed_data) = @_;
  my $hiddenbuttons = "";
  $hiddenbuttons .= "<input type='hidden' name='Brew' value='$e->{brew_id}' />\n" if ($e->{brew_id});
  if (!$e->{brew_id}) {
    # Fallback to old style
    if ( $processed_data->{sty} =~ /Cider/i ) {
      $hiddenbuttons .= "<input type='hidden' name='type' value='Cider' />\n" ;
    } else {
      $hiddenbuttons .= "<input type='hidden' name='type' value='Beer' />\n" ;
    }
    $hiddenbuttons .= "<input type='hidden' name='country' value='$processed_data->{country}' />\n"
      if ($processed_data->{country}) ;
    $hiddenbuttons .= "<input type='hidden' name='maker' value='$processed_data->{mak}' />\n" ;
    $hiddenbuttons .= "<input type='hidden' name='name' value='$processed_data->{beer}' />\n" ;
    $hiddenbuttons .= "<input type='hidden' name='style' value='$processed_data->{origsty}' />\n" ;
    $hiddenbuttons .= "<input type='hidden' name='subtype' value='$processed_data->{sty}' />\n" ;
    $hiddenbuttons .= "<input type='hidden' name='alc' value='$e->{alc}' />\n" ;
  }
  $hiddenbuttons .= "<input type='hidden' name='loc' value='$locparam' />\n" ;
  $hiddenbuttons .= "<input type='hidden' name='Location' value='$locid' />\n" ;
  $hiddenbuttons .= "<input type='hidden' name='tap' value='$id' />\n" ; # Signals this comes from a beer board
  $hiddenbuttons .= "<input type='hidden' name='o' value='board' />\n" ;  # come back to the board display
  return $hiddenbuttons;
}

sub render_beer_buttons {
  my ($c, $sizes, $hiddenbuttons, $detailed, $alc) = @_;
  my $buttons = "";
  foreach my $sp ( @$sizes ) {
    my $vol = $sp->{"vol"} || "";
    my $pr = $sp->{"price"} || "";
    next unless $vol || $pr;  # Skip empty entries
    my $lbl;
    if ($detailed) {
      my $dispvol = $vol;
      $dispvol = $1 if ( $glasses::volumes{$vol} && $glasses::volumes{$vol} =~ /(^\d+)/);   # Translate S and L
      $lbl = "$dispvol cl  ";
      $lbl .= sprintf( "%3.1fd", $dispvol * $alc / $c->{onedrink});
      $lbl .= "\n$pr.- " . sprintf( "%d/l ", $pr * 100 / $vol ) if ($pr);
    } else {
      if ( $pr ) {
        $lbl = "$pr.-";
      } elsif ( $vol =~ /\d/ ) {
        $lbl = "$vol cl";
      } elsif ( $vol ) {
        $lbl = "&nbsp; $vol &nbsp;";
      } else {
        next;  # Skip if no label
      }
    }
    $buttons .= "<form method='POST' accept-charset='UTF-8' style='display: inline-block; margin-right: 5px; vertical-align: top;' class='no-print' >\n";
    $buttons .= $hiddenbuttons;
    $buttons .= "<input type='hidden' name='vol' value='$vol' />\n" ;
    $buttons .= "<input type='hidden' name='pr' value='$pr' />\n" ;
    $buttons .= "<input type='submit' name='submit' value='$lbl'/> \n";
    $buttons .= "</form>\n";
  }
  return $buttons;
}

sub render_beer_row {
  my ($c, $e, $processed_data, $buttons_compact, $buttons_expanded, $beerstyle, $extraboard, $id, $dispid, $seenline, $locparam, $hiddenbuttons, $ref_time) = @_;
  $ref_time //= time();
  my $is_new = $processed_data->{first_seen_ts} && ($ref_time - $processed_data->{first_seen_ts}) < 86400;
  my $bg = "";
  $bg = "background-color: $c->{altbgcolor}; " if ($is_new);
  my $compact_display = 'table-row';
  $compact_display = 'none' if ($extraboard == $id);
  my $expanded_display = 'none';
  $expanded_display = 'table-row' if ($extraboard == $id);

  # Data attributes for client-side JS filtering
  my $data_style = util::htmlesc($processed_data->{origsty} || "");
  my $data_maker = util::htmlesc($e->{maker} || "");
  my $data_name  = util::htmlesc($e->{beer} || "");
  my $data_brewtype = util::htmlesc($e->{brewtype} || "");

  # Clickable style label — opens controls + filters by style
  my $style_disp = styles::brewstyledisplay($c, "Beer", $processed_data->{origsty});
  my $style_link = "<a href='#' data-fstyle=\"" . util::htmlesc($processed_data->{origsty} || "") . "\" onclick='openControlsAndFilter(this.getAttribute(\"data-fstyle\")); return false;'>$style_disp</a>";

  # Compact row
  print "<tr id='compact_$id' style='$bg display: $compact_display;' " .
    "data-style='$data_style' data-maker='$data_maker' data-name='$data_name' data-brewtype='$data_brewtype'>\n";
  print "<td align=right $beerstyle onclick=\"toggleBeer('$id'); return false;\" ><span $beerstyle>#$dispid</span></td>\n";
  print "<td>$buttons_compact</td>\n";
  print "<td style='font-size: x-small;' align=center>$e->{alc}</td>\n";
  print "<td>$processed_data->{dispbeer_short} $processed_data->{dispmak} ";
  print "<span style='font-size: x-small;'>($processed_data->{country})</span> " if ($processed_data->{country});
  print $style_link;
  if ( $processed_data->{average_rating} ) {
    print " " . comments::avgratings($c, $processed_data->{rating_count}, $processed_data->{average_rating}, $processed_data->{comment_count});
  }
  print "</td>\n";
  print "</tr>\n";
  # Expanded rows
  print "<tr class='expanded_$id' style='$bg display: $expanded_display;'><td colspan=5><hr></td></tr>\n";
  print "<tr class='expanded_$id' style='$bg display: $expanded_display;'><td align=right $beerstyle onclick=\"toggleBeer('$id'); return false;\" >";
  print "<span $beerstyle id='here'>#$dispid</span> ";
  print "</td>\n";
  print "<td colspan=4 >";
  print "<span style='white-space:nowrap;overflow:hidden;text-overflow:clip;max-width:100px'>\n";
  if ($e->{maker_id}) {
    print "<a href='$c->{url}?o=Location&e=$e->{maker_id}' style='cursor:pointer; border:1px solid #888; border-radius:4px; padding:0 5px; font-size:small; text-decoration:none; color:inherit'><span>L$e->{maker_id}</span></a> ";
  }
  print "$processed_data->{dispmak_full}: ";
  if ($e->{brew_id}) {
    print "<a href='$c->{url}?o=Brew&e=$e->{brew_id}' style='cursor:pointer; border:1px solid #888; border-radius:4px; padding:0 5px; font-size:small; text-decoration:none; color:inherit'><span>B$e->{brew_id}</span></a> ";
  }
  print "$processed_data->{dispbeer} ";
  print "<span style='font-size: x-small;'>($processed_data->{country})</span>" if ($processed_data->{country});
  print "</span></td></tr>\n";
  print "<tr class='expanded_$id' style='$bg display: $expanded_display;'><td>&nbsp;</td><td colspan=4> $buttons_expanded &nbsp;\n";
  print "<form method='POST' accept-charset='UTF-8' style='display: inline;' class='no-print' >\n";
  print "$hiddenbuttons";
  print "<input type='hidden' name='vol' value='T' />\n" ;  # taster
  print "<input type='hidden' name='pr' value='0' />\n" ;  # at no cost
  print "<input type='submit' name='submit' value='Taster ' /> \n";
  print "</form>\n";
  if ($processed_data->{extlink_html}) {
    print " &nbsp; $processed_data->{extlink_html}";
  }
  print "</td></tr>\n";
  print "<tr class='expanded_$id' style='$bg display: $expanded_display;'><td>&nbsp;</td><td colspan=4><span style='font-size: x-small;'><b>$e->{alc}%</b></span> " . $style_link;
  if ($processed_data->{first_seen_relative}) {
    my $rel = $processed_data->{first_seen_relative};
    my $abs = $processed_data->{first_seen_absolute};
    my $daysleft = "";
    my $kegcount = "";
    if ($processed_data->{avg_days_on_tap}) {
      my $elapsed = ($ref_time - $processed_data->{first_seen_ts}) / 86400;
      my $remaining = $processed_data->{avg_days_on_tap} - $elapsed;
      if ($remaining > 0) {
        $daysleft = ", ~" . sprintf("%.1f", $remaining) . " days left";
      } else {
        $daysleft = ", should be empty soon";
      }
      $kegcount = ", based on $processed_data->{tap_history_count} kegs";
    }
    print " <span style='font-size: x-small; cursor: pointer;'"
        . " onclick=\"var s=this.nextElementSibling; s.style.display=(s.style.display==='none'?'inline':'none');\">"
        . "On for $rel$daysleft</span>"
        . "<span style='font-size: x-small; display:none;'>, since $abs$kegcount</span>";
  }
  if ( $processed_data->{average_rating} ) {
    print " " . comments::avgratings($c, $processed_data->{rating_count}, $processed_data->{average_rating}, $processed_data->{comment_count});
  }
  print "</td></tr> \n";
  if ($seenline) {
    print "<tr class='expanded_$id' style='$bg display: $expanded_display;'><td>&nbsp;</td><td colspan=4> $seenline";
    print "</td></tr>\n";
  }
}

sub trigger_background_update {
  my ($c, $locparam) = @_;
  print "<!-- Triggering background update -->\n";
  my $form_id = "form_updateboard_" . $locparam;
  $form_id =~ s/\W/_/g;
  my $form = "<form id='$form_id' method='POST' action='$c->{url}' style='display:none;'>";
  $form .= "<input type='hidden' name='o' value='updateboard'>";
  $form .= "<input type='hidden' name='loc' value='$locparam'>";
  $form .= "</form>";
  print $form;
  print "<script>
    setTimeout(() => {
      fetch('$c->{url}', {
        method: 'POST',
        body: new FormData(document.getElementById('$form_id'))
      }).then(response => {
        if (response.ok) {
          console.log('Background update completed successfully');
        } else {
          console.error('Background update failed with status', response.status);
        }
      }).catch(error => {
        console.error('Background update error:', error);
      });
    }, 3000);
  </script>\n";
}


################################################################################
# Tell Perl the module loaded fine
1;
