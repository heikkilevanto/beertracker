# Part of my beertracker
# Routines for displaying the beer list (board) for the current bar
# and buttons for quickly marking a beer has been drunk

package beerboard;
use strict;
use warnings;
use feature 'unicode_strings';
use utf8;  # Source code and string literals are utf-8
use POSIX qw(strftime localtime);
use URI::Escape qw(uri_escape_utf8);



################################################################################
# Beer board (list) for the location.
# Scraped from their website
################################################################################

sub beerboard {
  my $c = shift;

  my $qrylim = util::param($c,"f");

  my ($locparam, $foundrec) = get_location_param($c);

  # Check that the location has a scraper configured; fall back to a default if not
  my $loc_rec_check = db::findrecord($c, "LOCATIONS", "Name", $locparam, "collate nocase");
  if (!$loc_rec_check || !$loc_rec_check->{Scraper}) {
    print "Sorry, no beer list for '$locparam' - showing 'Ølbaren' instead<br/>\n";
    $locparam = "Ølbaren"; # A good default
  }

  render_location_selector($c, $locparam);

  my ($beerlist, $last_epoch) = load_beerlist_from_db($c, $locparam, $qrylim);

  if (!$beerlist || !@$beerlist) {
    print "Trying to get the list for $locparam - reload to see it <br/>\n";
    trigger_background_update($c, $locparam);
    return;
  }

  my $is_old = $last_epoch && (time() - $last_epoch) > 20 * 60;
  if ($is_old) {
    my $timestamp = strftime('%Y-%m-%d %H:%M', localtime($last_epoch));
    print "<div style='font-weight: bold;'>The beer board is from $timestamp</div>\n";
    trigger_background_update($c, $locparam);
  }

  my $nbeers = 0;
    if ($c->{qry}) {
      my $loc_esc = uri_escape_utf8($locparam);
      print "Filter:<b>$c->{qry}</b> " .
        "(<a href='$c->{url}?o=$c->{op}&loc=$loc_esc'><span>Clear</span></a>) " .
        "<p>\n";
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

    my $expand_display = 'none';
    print "<div id='expand-all' style='display:$expand_display;'><a href='#' onclick='collapseAll(); return false;'><span>Collapse All</span></a></div>\n";

    print "<table id='beerboard' border=0 style='white-space: nowrap;'>\n";
    my $previd  = 0;
    my $locrec = db::findrecord($c,"LOCATIONS","Name",$locparam, "collate nocase");
    my $locid = $locrec ? $locrec->{Id} : undef;
    foreach my $e ( sort {$a->{"id"} <=> $b->{"id"} } @$beerlist )  {
      $nbeers++;
      my $id = $e->{"id"} || 0;
      my $mak = $e->{"maker"} || "" ;
      my $beer = $e->{"beer"} || "" ;
      my $sty = $e->{"type"} || "";
      my $loc = $locparam;
      my $alc = $e->{"alc"} || "";
      $alc = sprintf("%4.1f",$alc) if ($alc);
      if ( $c->{qry} && $c->{qry} =~ /PA/i ) {
        next unless ( "$sty $mak $beer" =~ /PA/i );
      }

      if ( $id != $previd +1 ) {
        print "<tr><td align=center>. . .</td></tr>\n";
      }

      my $processed_data = prepare_beer_entry_data($c, $e, $locparam);
      my $hiddenbuttons = generate_hidden_fields($c, $e, $locparam, $locid, $id, $processed_data);
      my $buttons_compact = render_beer_buttons($c, $e->{"sizePrice"}, $hiddenbuttons, 0, $alc);
      my $buttons_expanded = render_beer_buttons($c, $e->{"sizePrice"}, $hiddenbuttons, 1, $alc);

      my $beerstyle = styles::beercolorstyle($c, $processed_data->{sty}, "Board:$e->{'id'}", "[$e->{'type'}] $e->{'maker'} : $e->{'beer'}" );

      my $dispid = $id;

      my $seenline = seenline($c, $e->{seen_count}, $e->{seen_min_date}, $e->{seen_max_date});

      render_beer_row($c, $e, $buttons_compact, $buttons_expanded, $beerstyle, $extraboard, $id, $dispid, $processed_data, $seenline, $locparam, $hiddenbuttons);

      $previd = $id;
    } # beer loop
    print "</table>\n";
    if (! $nbeers ) {
      print "Sorry, got no beers from $locparam\n";
    }
  # Keep $c->{qry}, so we filter the big list too
  $c->{qry} = "" if ($c->{qry} =~ /PA/i );   # But not 'PA', it is only for the board
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
  my $times_word = $count == 1 ? "time" : "times";
  my $seenline = "Seen <b>$count</b> $times_word";
  if ($min_date) {
    my $display_date = $min_date;
    if ($count > 1 && $max_date) {
      my $now_utc6 = time() - 6 * 3600;
      my $today = strftime('%Y-%m-%d', localtime($now_utc6));
      my $yest_utc6 = $now_utc6 - 86400;
      my $yesterday = strftime('%Y-%m-%d', localtime($yest_utc6));
      if ($max_date eq $today) {
        $display_date .= " to today";
      } elsif ($max_date eq $yesterday) {
        $display_date .= " to yesterday";
      } else {
        $display_date .= " to $max_date";
      }
    }
    $seenline .= " $display_date";
  }
  return $seenline;
} # seenline

sub format_date_relative {
  # TODO - Should probably be in util.pm
  my ($date_str, $time_str) = @_;
  return "" unless $date_str;
  my $now_utc6 = time() - 6 * 3600;
  my $today = strftime('%Y-%m-%d', localtime($now_utc6));
  my $yest_utc6 = $now_utc6 - 86400;
  my $yesterday = strftime('%Y-%m-%d', localtime($yest_utc6));
  
  my $formatted_time = $time_str ? ($time_str lt "06:00" ? "($time_str)" : $time_str) : "";
  
  if ($date_str eq $today) {
    return $formatted_time;
  } elsif ($date_str eq $yesterday) {
    return "yesterday $formatted_time";
  } else {
    return $date_str;
  }
} # format_date_relative

sub format_duration_relative {
  my ($first_seen_ts) = @_;
  return "" unless $first_seen_ts;
  my $age = time() - $first_seen_ts;
  if ($age < 3600) {
    my $minutes = int($age / 60);
    return $minutes <= 0 ? "less than 1m" : "${minutes}m";
  } elsif ($age < 4 * 3600) {
    my $hours = int($age / 3600);
    my $mins = int(($age % 3600) / 60);
    return "${hours}h${mins}m";
  } elsif ($age < 48 * 3600) {
    my $hours = int($age / 3600);
    return "${hours}h";
  } else {
    my $days = int($age / 86400);
    my $unit = $days == 1 ? "day" : "days";
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
  my ($c, $locparam) = @_;
  # Pull-down for choosing the bar
  my $url = $c->{url};
  $url =~ s/"/&quot;/g;
  print "\n<form method='POST' accept-charset='UTF-8' style='display:inline;' class='no-print' >\n";
  print "Beer list \n";
  print "<select onchange=\"document.location='$url?o=Board&loc=' + 
       encodeURIComponent(this.value);\" style='display:inline-block; width:5.5em;'>\n";
  for my $l ( scrapeboard::get_scraper_locations($c) ) {
    my $sel = "";
    $sel = "selected" if ( $l eq $locparam);
    print "<option value='$l' $sel>$l</option>\n";
  }
  print "</select>\n";
  print "</form>\n";
  my $locrec = db::findrecord($c,"LOCATIONS","Name",$locparam, "collate nocase");
  if ($locrec && $locrec->{Website}) {
    print " &nbsp; <i><a href='$locrec->{Website}' target='_blank' ><span>www</span></a></i>" ;
  }
  my $loc_esc = uri_escape_utf8($locparam);
  print "&nbsp; (<a href='$c->{url}?o=$c->{op}&loc=$loc_esc&q=PA'><span>PA</span></a>) "
    if ($c->{qry} ne "PA" );

  print scrapeboard::post_form($c, 'updateboard', $locparam, '(Reload)');

  print "&nbsp; <a href='#' onclick='expandAll(); return false;'><span>(Exp)</span></a>";

  print "<p>\n";
}

sub get_location_param {
  my $c = shift;
  # Get the last used location for this user
  my $sql = "select * from glassrec " .
            "where username = ? " .
            "order by stamp desc ".
            "limit 1";
  my $foundrec = db::queryrecord($c, $sql, $c->{username});

  my $locparam = util::param($c,"loc") || $foundrec->{loc} || "";
  $locparam =~ s/^ +//; # Drop the leading space for guessed locations
  return ($locparam, $foundrec);
}

sub load_beerlist_from_db {
  my ($c, $locparam, $qrylim) = @_;
  
  # Get location ID
  my $loc_rec = db::findrecord($c, "LOCATIONS", "Name", $locparam);
  return ([], undef) unless $loc_rec;
  my $loc_id = $loc_rec->{Id};
  
  # Get the latest scrape marker
  my ($last_epoch) = db::queryarray($c,
    "SELECT strftime('%s', LastSeen) as last_epoch FROM tap_beers " .
    "WHERE Location = ? AND Tap IS NULL ORDER BY LastSeen DESC LIMIT 1",
    $loc_id);
  
  # Load from DB
  my $sql = "SELECT 
      ct.Tap, ct.Brew, ct.BrewName AS beer, 
      pl.Name AS maker, pl.Id AS maker_id, 
      b.SubType AS type, b.Alc AS alc,
      b.DetailsLink AS details_link,
      b.ShortName AS brew_shortname,
      pl.SearchLink AS maker_search_link,
      pl.ShortName AS shortname,
      tb.SizeS, tb.PriceS, tb.SizeM, tb.PriceM, tb.SizeL, tb.PriceL,
      ur.rating_count, ur.average_rating, ur.comment_count,
      strftime('%Y-%m-%d', tb.FirstSeen) as first_seen_date,
      strftime('%H:%M', tb.FirstSeen) as first_seen_time, 
      strftime('%s', tb.FirstSeen) as first_seen_ts,
      ug.seen_count, ug.seen_min_date, ug.seen_max_date
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
               count(Id) as seen_count,
               strftime('%Y-%m-%d', min(Timestamp), '-06:00') as seen_min_date,
               strftime('%Y-%m-%d', max(Timestamp), '-06:00') as seen_max_date
        FROM glasses
        WHERE Username = ?
        GROUP BY Brew
      ) ug ON ug.Brew = ct.Brew
    WHERE ct.Location = ?
    ORDER BY ct.Tap";
  my $sth = db::query($c, $sql, $c->{username}, $c->{username}, $loc_id);
  
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
    
    push @$beerlist, {
      id => $row->{Tap},
      maker => $row->{maker} || "",
      maker_id => $row->{maker_id},
      beer => $row->{beer} || "",
      type => $row->{type} || "",
      alc => $row->{alc} || "",
      brew_id => $row->{Brew},
      sizePrice => $sizePrice,
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
      shortname => $row->{shortname}
    };
  }
  
  print "<!-- Loaded beerlist from DB for '$locparam' -->\n";
  return ($beerlist, $last_epoch);
}

sub prepare_beer_entry_data {
  my ($c, $e, $locparam) = @_;
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
  my $ddg_query = ($mak || $beer) ? "$mak $beer" : "";
  my $extlink_html = util::brewlinks($c, $e->{details_link}, $beer, $e->{maker_search_link}, $ddg_query);

  # Full maker name as a link for the expanded header
  my $dispmak_full = ($e->{maker_id})
    ? "<a href='$c->{url}?o=Location&e=$e->{maker_id}'><span>$mak</span></a>"
    : $mak;

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
    first_seen_relative => format_duration_relative($e->{first_seen_ts}),
    first_seen_absolute => format_date_absolute($e->{first_seen_date}, $e->{first_seen_time}),
    extlink_html => $extlink_html,
    dispmak_full => $dispmak_full
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
  my ($c, $e, $buttons_compact, $buttons_expanded, $beerstyle, $extraboard, $id, $dispid, $processed_data, $seenline, $locparam, $hiddenbuttons) = @_;
  my $is_new = $processed_data->{first_seen_ts} && (time() - $processed_data->{first_seen_ts}) < 86400;
  my $bg = $is_new ? "background-color: $c->{altbgcolor}; " : "";
  my $compact_display = ($extraboard == $id) ? 'none' : 'table-row';
  my $expanded_display = ($extraboard == $id) ? 'table-row' : 'none';
  # Compact row
  print "<tr id='compact_$id' style='$bg display: $compact_display;'>\n";
  print "<td align=right $beerstyle onclick=\"toggleBeer('$id'); return false;\" style=\"cursor: pointer;\"><span $beerstyle>#$dispid</span></td>\n";
  print "<td>$buttons_compact</td>\n";
  print "<td style='font-size: x-small;' align=center>$e->{alc}</td>\n";
  print "<td>$processed_data->{dispbeer_short} $processed_data->{dispmak} ";
  print "<span style='font-size: x-small;'>($processed_data->{country})</span> " if ($processed_data->{country});
  print styles::brewstyledisplay($c, "Beer", $processed_data->{sty});
  if ( $processed_data->{average_rating} ) {
    print " " . comments::avgratings($c, $processed_data->{rating_count}, $processed_data->{average_rating}, $processed_data->{comment_count});
  }
  print "</td>\n";
  print "</tr>\n";
  # Expanded rows
  print "<tr class='expanded_$id' style='$bg display: $expanded_display;'><td colspan=5><hr></td></tr>\n";
  print "<tr class='expanded_$id' style='$bg display: $expanded_display;'><td align=right $beerstyle onclick=\"toggleBeer('$id'); return false;\" style=\"cursor: pointer;\">";
  print "<span $beerstyle id='here'>#$dispid</span> ";
  print "</td>\n";
  print "<td colspan=4 >";
  print "<span style='white-space:nowrap;overflow:hidden;text-overflow:clip;max-width:100px'>\n";
  print "$processed_data->{dispmak_full}: $processed_data->{dispbeer} ";
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
  print "<tr class='expanded_$id' style='$bg display: $expanded_display;'><td>&nbsp;</td><td colspan=4><span style='font-size: x-small;'><b>$e->{alc}%</b></span> " . styles::brewstyledisplay($c, "Beer", $processed_data->{origsty});
  if ($processed_data->{first_seen_relative}) {
    my $rel = $processed_data->{first_seen_relative};
    my $abs = $processed_data->{first_seen_absolute};
    print " <span style='font-size: x-small; cursor: pointer;'"
        . " onclick=\"var s=this.nextElementSibling; s.style.display=(s.style.display==='none'?'inline':'none');\">"
        . "On for $rel</span>"
        . "<span style='font-size: x-small; display:none;'>, since $abs</span>";
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
