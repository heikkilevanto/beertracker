# Part of my beertracker
# Routines for displaying the beer list (board) for the current bar
# and buttons for quickly marking a beer has been drunk

package beerboard;
use strict;
use warnings;
use feature 'unicode_strings';
use utf8;  # Source code and string literals are utf-8
use POSIX qw(strftime localtime);



################################################################################
# Beer board (list) for the location.
# Scraped from their website
################################################################################

sub beerboard {
  my $c = shift;

  my $qrylim = util::param($c,"f");

  my ($locparam, $foundrec) = get_location_param($c);
  
  if (!$scrapeboard::scrapers{$locparam}) {
    print "Sorry, no  beer list for '$locparam' - showing 'Ølbaren' instead<br/>\n";
    $locparam="Ølbaren"; # A good default
  }
  
  render_location_selector($c, $locparam);

  my ($beerlist, $last_epoch) = load_beerlist_from_db($c, $locparam, $qrylim);

  if (!$beerlist || !@$beerlist) {
    print "No beer data available for $locparam<br/>\n";
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
      print "Filter:<b>$c->{qry}</b> " .
        "(<a href='$c->{url}?o=$c->{op}&loc=$locparam'><span>Clear</span></a>) " .
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

      my $seenline = seenline($c, $e->{brew_id});

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

# Helper to produce a "Seen" line
sub seenline {
  my $c = shift;
  my $brew_id = shift;
  return "" unless $brew_id;
  my $sql = q{
    select count(id),
           strftime('%Y-%m-%d', min(timestamp), '-06:00') as min_date,
           strftime('%Y-%m-%d', max(timestamp), '-06:00') as max_date
    from glasses
    where brew = ?
  };
  my $sth = $c->{dbh}->prepare($sql);
  $sth->execute($brew_id);
  my ($count, $min_date, $max_date) = $sth->fetchrow_array;
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
  print "<select onchange=\"document.location='$url?o=Board&loc=' + this.value;\" style='display:inline-block; width:5.5em;'>\n";
  if (!$scrapeboard::scrapers{$locparam}) { #Include the current location, even if no scraper
    $scrapeboard::scrapers{$locparam} = ""; #that way, the pulldown looks reasonable
  }
  for my $l ( sort(keys(%scrapeboard::scrapers)) ) {
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
  print "&nbsp; (<a href='$c->{url}?o=$c->{op}&loc=$locparam&q=PA'><span>PA</span></a>) "
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
  my $sth = $c->{dbh}->prepare($sql);
  $sth->execute( $c->{username} );
  my $foundrec = $sth->fetchrow_hashref;
  $sth->finish;

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
  my $marker_sql = "SELECT strftime('%s', LastSeen) as last_epoch FROM tap_beers WHERE Location = ? AND Tap IS NULL ORDER BY LastSeen DESC LIMIT 1";
  my $marker_sth = $c->{dbh}->prepare($marker_sql);
  $marker_sth->execute($loc_id);
  my ($last_epoch) = $marker_sth->fetchrow_array;
  
  # Load from DB
  my $sql = "SELECT 
      ct.Tap, ct.Brew, ct.BrewName AS beer, 
      pl.Name AS maker, pl.Id AS maker_id, 
      b.SubType AS type, b.Alc AS alc,
      tb.SizeS, tb.PriceS, tb.SizeM, tb.PriceM, tb.SizeL, tb.PriceL,
      br.rating_count, br.average_rating, br.comment_count, 
      strftime('%Y-%m-%d', tb.FirstSeen) as first_seen_date,
      strftime('%H:%M', tb.FirstSeen) as first_seen_time, 
      strftime('%s', tb.FirstSeen) as first_seen_ts
    FROM current_taps ct
      JOIN tap_beers tb ON ct.Id = tb.Id
      JOIN brews b ON ct.Brew = b.Id
      LEFT JOIN locations pl ON b.ProducerLocation = pl.Id
      LEFT JOIN brew_ratings br ON b.Id = br.brew
    WHERE ct.Location = ?
    ORDER BY ct.Tap";
  my $sth = $c->{dbh}->prepare($sql);
  $sth->execute($loc_id);
  
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
      first_seen_ts => $row->{first_seen_ts}
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

  my $dispmak = $mak;
  $dispmak =~ s/\b(the|brouwerij|brasserie|van|den|Bräu|Brauerei)\b//ig; #stop words
  $dispmak =~ s/.*(Schneider).*/$1/i;
  $dispmak =~ s/ &amp; /&amp;/;  # Special case for Dry & Bitter (' & ' -> '&')
  $dispmak =~ s/ & /&/;  # Special case for Dry & Bitter (' & ' -> '&')
  $dispmak =~ s/^ +//;
  $dispmak =~ s/^([^ ]{1,4}) /$1&nbsp;/; #Combine initial short word "To Øl"
  $dispmak =~ s/[ -].*$// ; # first word
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

  $mak =~ s/'//g; # Apostrophes break the input form below
  $beer =~ s/'//g; # So just drop them
  $sty =~ s/'//g;

  my $country = $e->{'country'} || "";

  return {
    mak => $mak,
    beer => $beer,
    sty => $sty,
    origsty => $origsty,
    dispmak => $dispmak,
    dispbeer => $dispbeer,
    country => $country,
    rating_count => $e->{rating_count},
    average_rating => $e->{average_rating},
    comment_count => $e->{comment_count},
    first_seen_date => $e->{first_seen_date},
    first_seen_time => $e->{first_seen_time},
    first_seen_ts => $e->{first_seen_ts},
    first_seen_date_formatted => format_date_relative($e->{first_seen_date}, $e->{first_seen_time})
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
  print "<td>$processed_data->{dispbeer} $processed_data->{dispmak} ";
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
  print "$processed_data->{mak}: $processed_data->{dispbeer} ";
  print "<span style='font-size: x-small;'>($processed_data->{country})</span>" if ($processed_data->{country});
  print "</span></td></tr>\n";
  print "<tr class='expanded_$id' style='$bg display: $expanded_display;'><td>&nbsp;</td><td colspan=4> $buttons_expanded &nbsp;\n";
  print "<form method='POST' accept-charset='UTF-8' style='display: inline;' class='no-print' >\n";
  print "$hiddenbuttons";
  print "<input type='hidden' name='vol' value='T' />\n" ;  # taster
  print "<input type='hidden' name='pr' value='0' />\n" ;  # at no cost
  print "<input type='submit' name='submit' value='Taster ' /> \n";
  print "</form>\n";
  print "</td></tr>\n";
  print "<tr class='expanded_$id' style='$bg display: $expanded_display;'><td>&nbsp;</td><td colspan=4><span style='font-size: x-small;'><b>$e->{alc}%</b></span> " . styles::brewstyledisplay($c, "Beer", $processed_data->{origsty});
  if ($processed_data->{first_seen_date_formatted}) {
    print " <span style='font-size: x-small;'>On since $processed_data->{first_seen_date_formatted}.</span>";
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
