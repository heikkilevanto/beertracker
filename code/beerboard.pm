# Part of my beertracker
# Routines for displaying the beer list (board) for the current bar
# and buttons for quickly marking a beer has been drunk

# TODO - Rethink the whole beer board system, keep them all in the database,
# etc. See #390
# Later
#  - Add tap records showing when we have seen said beer at which tap

package beerboard;
use strict;
use warnings;
use feature 'unicode_strings';
use utf8;  # Source code and string literals are utf-8
use URI::Escape;
use JSON;
use POSIX qw(strftime localtime);



################################################################################
# Beer board (list) for the location.
# Scraped from their website
################################################################################

sub beerboard {
  my $c = shift;

  my $qrylim = util::param($c,"f");

  my $extraboard = -1; # Which of the entries to open, or -1 current, -2 for all, -3 for none
  if ( $c->{op} =~ /board(-?\d+)/i ) {
    $extraboard = $1;
  }

  my ($locparam, $foundrec) = get_location_param($c);
  
  if (!$scrapeboard::scrapers{$locparam}) {
    print "Sorry, no  beer list for '$locparam' - showing 'Ølbaren' instead<br/>\n";
    $locparam="Ølbaren"; # A good default
  }
  
  render_location_selector($c, $locparam);

  my ($beerlist, $last_epoch) = load_beerlist_from_db($c, $locparam, $qrylim);

  if (!$beerlist || !@$beerlist) {
    print "No beer data available for $locparam<br/>\n";
    # Trigger background update
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
    return;
  }

  my $is_old = $last_epoch && (time() - $last_epoch) > 20 * 60;
  if ($is_old) {
    my $timestamp = strftime('%Y-%m-%d %H:%M', localtime($last_epoch));
    print "<div style='color: red; font-weight: bold;'>The beer board is too old / from $timestamp</div>\n";
    # Trigger background update
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

  my $nbeers = 0;
    if ($c->{qry}) {
      print "Filter:<b>$c->{qry}</b> " .
        "(<a href='$c->{url}?o=$c->{op}&loc=$locparam'><span>Clear</span></a>) " .
        "<p>\n";
    }
    $extraboard = determine_expansion_state($c, $extraboard, $foundrec, $beerlist);

    my $all_expanded = ($extraboard == -2);
    my $expand_display = $all_expanded ? 'block' : 'none';
    print "<div id='expand-all' style='display:$expand_display;'><a href='#' onclick='expandAll(); return false;'><span>Expand All</span></a> | <a href='#' onclick='collapseAll(); return false;'><span>Collapse All</span></a></div>\n";

    print "<table id='beerboard' border=0 style='white-space: nowrap;'>\n";
    my $previd  = 0;
    foreach my $e ( sort {$a->{"id"} <=> $b->{"id"} } @$beerlist )  {
      $nbeers++;
      my $id = $e->{"id"} || 0;
      my $mak = $e->{"maker"} || "" ;
      my $beer = $e->{"beer"} || "" ;
      my $sty = $e->{"type"} || "";
      my $loc = $locparam;
      my $alc = $e->{"alc"} || "";
      $alc = sprintf("%4.1f",$alc) if ($alc);
      my $seenkey = seenkey($mak,$beer);
      if ( $c->{qry} && $c->{qry} =~ /PA/i ) {
        next unless ( "$sty $mak $beer" =~ /PA/i );
      }

      if ( $id != $previd +1 ) {
        print "<tr><td align=right>&nbsp;</td><td align=right>. . .</td></tr>\n";
      }

      my $processed_data = prepare_beer_entry_data($c, $e, $locparam);
      my $locrec = db::findrecord($c,"LOCATIONS","Name",$locparam, "collate nocase");
      my $locid = $locrec->{Id};
      my $hiddenbuttons = generate_hidden_fields($c, $e, $locparam, $locid, $id, $processed_data);
      my $buttons_compact = render_beer_buttons($c, $e->{"sizePrice"}, $hiddenbuttons, 0, $alc);
      my $buttons_expanded = render_beer_buttons($c, $e->{"sizePrice"}, $hiddenbuttons, 1, $alc);

      my $beerstyle = beercolorstyle($c, $processed_data->{sty}, "Board:$e->{'id'}", "[$e->{'type'}] $e->{'maker'} : $e->{'beer'}" );

      my $dispid = $id;
      $dispid = "&nbsp;&nbsp;$id"  if ( length($dispid) < 2);

      my $seenline = seenline($c, $mak, $beer);

      render_beer_row($c, $e, $buttons_compact, $buttons_expanded, $beerstyle, $extraboard, $id, $dispid, $processed_data, $seenline, $locparam, $hiddenbuttons);

      $previd = $id;
    } # beer loop
    print "</table>\n";
    print "<script>\nvar allExpanded = " . ($all_expanded ? 'true' : 'false') . ";
function toggleBeer(id) {
  var compact = document.getElementById('compact_' + id);
  var expanded = document.querySelectorAll('.expanded_' + id);
  if (compact.style.display === 'none') {
    compact.style.display = 'table-row';
    expanded.forEach(function(row) { row.style.display = 'none'; });
  } else {
    compact.style.display = 'none';
    expanded.forEach(function(row) { row.style.display = 'table-row'; });
  }
  document.getElementById('expand-all').style.display = 'block';
}
function expandAll() {
  var compacts = document.querySelectorAll('[id^=\"compact_\"]');
  var expandeds = document.querySelectorAll('[class^=\"expanded_\"]');
  compacts.forEach(function(row) { row.style.display = 'none'; });
  expandeds.forEach(function(row) { row.style.display = 'table-row'; });
  setTimeout(() => window.scrollTo(0, document.getElementById('beerboard').offsetTop), 10);
}
function collapseAll() {
  var compacts = document.querySelectorAll('[id^=\"compact_\"]');
  var expandeds = document.querySelectorAll('[class^=\"expanded_\"]');
  compacts.forEach(function(row) { row.style.display = 'table-row'; });
  expandeds.forEach(function(row) { row.style.display = 'none'; });
  setTimeout(() => window.scrollTo(0, document.getElementById('beerboard').offsetTop), 10);
}
</script>\n";
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

# Helper to make a filter link
sub filt {
  my $c = shift;
  my $f = shift; # filter term
  my $tag = shift || "span";
  my $dsp = shift || $f;
  my $op = shift || $c->{op} || "";
  my $fld = shift || ""; # Field to filter by
  $op = "o=$op" if ($op);
  my $param = $f;
  $param =~ s"[\[\]]""g; # remove the [] around styles etc
  my $endtag = $tag;
  $endtag =~ s/ .*//; # skip attributes
  my $style = "";
  if ( $tag =~ /background-color:([^;]+);/ ) { #make the link underline disappear
    $style = "style='color:$1'";
  }
  $param = "&q=" . uri_escape_utf8($param) if ($param);
  $fld = "&qf=$fld" if ($fld);
  my $link = "<a href='$c->{url}?$op$param$fld' $style>" .
    "<$tag>$dsp</$endtag></a>";
  return $link;
}



# Helper to make a seenkey, an index to %lastseen and %seen
# Normalizes the names a bit, to catch some misspellings etc
sub seenkey {
  my $rec= shift;
  my $maker;
  my $name = shift;
  my $key;
  if (ref($rec)) {
    $maker = $rec->{maker} || "";
    $name = $rec->{name} || "";
    if ($rec->{type} eq "Beer") {
      $key = "$rec->{maker}:$rec->{name}"; # Needs to match m:b in beer board etc
    } elsif ( $rec->{type} =~ /Restaurant|Night/ ) {
      $key = "$rec->{type}:$rec->{loc}";  # We only have loc to match (and subkey?)
    } elsif ( $rec->{name} && $rec->{subkey} ) {  # Wine and booze: Wine:Red:Foo
      $key = "$rec->{type}:$rec->{subkey}:$rec->{name}";
    } elsif ( $rec->{name} ) {  # Wine and booze: Wine::Mywine
      $key = "$rec->{type}::$rec->{name}";
    } else { # TODO - Not getting keys for many records !!!
      #print STDERR "No seenkey for $rec->{rawline} \n";
      return "";  # Nothing to make a good key from
    }
  } else { # Called  the old way, like for beer board
    $maker = $rec;
    $key = "$maker:$name";
    #return "" if ( !$maker && !$name );
  }
  $key = lc($key);
  return "" if ( $key =~ /misc|mixed/ );
  $key =~ s/&amp;/&/g;
  $key =~ s/[^a-zåæø0-9:]//gi;  # Skip all special characters and spaces
  return $key;
} # seenkey

# Helper to produce a "Seen" line
sub seenline {
  my $c = shift;
  my $maker = shift;
  my $beer = shift;
  my $seenkey;
  $seenkey = seenkey($maker,$beer);
  return "" unless ($seenkey);
  return "" unless ($seenkey =~ /[a-z]/ );  # At least some real text in it
  my $countsql = q{
    select brews.id, count(glasses.id)
    from brews, glasses, locations
    where brews.id = glasses.brew
    and locations.id = brews.producerlocation
    and locations.name = ?
    and brews.name = ?
  };
  my $get_sth = $c->{dbh}->prepare($countsql);
  $get_sth->execute($maker,$beer);
  my ( $brewid, $count ) = $get_sth->fetchrow_array;
  return "" unless($count);
  my $seenline = "Seen <b>$count</b> times: ";
  my $listsql = q{
    select
      distinct strftime ('%Y-%m-%d', timestamp,'-06:00') as effdate
    from glasses
    where brew = ?
    order by timestamp desc
    limit 7
  };
  my $prefix = "";
  my $detail="";
  my $detailpattern = "";
  my $nmonths = 0;
  my $nyears = 0;
  my $list_sth = $c->{dbh}->prepare($listsql);
  $list_sth->execute($brewid);
  while ( my $eff = $list_sth->fetchrow_array ) {
    my $comma = ",";
    if ( ! $prefix || $eff !~ /^$prefix/ ) {
      $comma = ":" ;
      if ( $nmonths++ < 2 ) {
        ($prefix) = $eff =~ /^(\d+-\d+)/ ;  # yyyy-mm
        $detailpattern = "(\\d\\d)\$";
      } elsif ( $nyears++ < 1 ) {
        ($prefix) = $eff =~ /^(\d+)/ ;  # yyyy
        $detailpattern = "(\\d\\d)-\\d\\d\$";
      } else {
        $prefix = "20";
        $detailpattern = "^20(\\d\\d)";
        $comma = "";
      }
      $seenline .= " <b>$prefix</b>";
    }
    my ($det) = $eff =~ /$detailpattern/ ;
    next if ($det eq $detail);
    $detail = $det;
    $seenline .= $comma . "$det";
  }

  return $seenline;
} # seenline


# Helper to shorten a beer style
# TODO - Drop these from here. We have similar things in brews.pm,
# but they operate on a brew record, which we don't get from the
# scrapers.
sub shortbeerstyle {
  my $sty = shift || "";
  return "" unless $sty;
  $sty =~ s/\b(Beer|Style)\b//i; # Stop words
  $sty =~ s/\W+/ /g;  # non-word chars, typically dashes
  $sty =~ s/\s+/ /g;  # multiple spaces etc
  if ( $sty =~ /( PA |Pale Ale)/i ) {
    return "APA"   if ( $sty =~ /America|US/i );
    return "BelPA" if ( $sty =~ /Belg/i );
    return "NEPA"  if ( $sty =~ /Hazy|Haze|New England|NE/i);
    return "PA";
  }
  if ( $sty =~ /(IPA|India)/i ) {
    return "SIPA"  if ( $sty =~ /Session/i);
    return "BIPA"  if ( $sty =~ /Black/i);
    return "DNE"   if ( $sty =~ /(Double|Triple).*(New England|NE)/i);
    return "DIPA"  if ( $sty =~ /Double|Dipa|Triple/i);
    return "WIPA"  if ( $sty =~ /Wheat/i);
    return "NEIPA" if ( $sty =~ /New England|NE|Hazy/i);
    return "NZIPA" if ( $sty =~ /New Zealand|NZ/i);
    return "WC"    if ( $sty =~ /West Coast|WC/i);
    return "AIPA"  if ( $sty =~ /America|US/i);
    return "IPA";
  }
  return "Dunk"  if ( $sty =~ /.*Dunkel.*/i);
  return "Bock"  if ( $sty =~ /Bock/i);
  return "Smoke" if ( $sty =~ /(Smoke|Rauch)/i);
  return "Lager" if ( $sty =~ /Lager|Keller|Pils|Zwickl/i);
  return "Berl"  if ( $sty =~ /Berliner/i);
  return "Weiss" if ( $sty =~ /Hefe|Weizen|Hvede|Wit/i);
  return "Stout" if ( $sty =~ /Stout|Porter|Imperial/i);
  return "Farm"  if ( $sty =~ /Farm/i);
  return "Sais"  if ( $sty =~ /Saison/i);
  return "Dubl"  if ( $sty =~ /(Double|Dubbel)/i);
  return "Trip"  if ( $sty =~ /(Triple|Tripel|Tripple)/i);
  return "Quad"  if ( $sty =~ /(Quadruple|Quadrupel)/i);
  return "Trap"  if ( $sty =~ /Trappist/i);
  return "Blond" if ( $sty =~ /Blond/i);
  return "Brown" if ( $sty =~ /Brown/i);
  return "Strng" if ( $sty =~ /Strong/i);
  return "Belg"  if ( $sty =~ /Belg/i);
  return "BW"    if ( $sty =~ /Barley.*Wine/i);
  return "Sour"  if ( $sty =~ /Lambic|Gueuze|Sour|Kriek|Frmaboise/i);
  $sty =~ s/^ *([^ ]{1,5}).*/$1/; # First word, only five chars, in case we didn't get it above
  return $sty;
} # shortbeerstyle

# Helper to assign a color for a beer
sub beercolorstyle {
  my $c = shift;
  my $rec = shift;  # Can also be style as text, see below
  my $line = shift; # for error logging
  my $type = "";
  if (ref($rec)) {
    $type = "$rec->{type},$rec->{subtype}: $rec->{style} $rec->{maker}";  # something we can match
    $line = $rec->{rawline};
  } else {
    $type = $rec;
  }
  return brews::brewtextstyle($c, $type);
} # beercolorstyle


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
  my $sql = "SELECT ct.Tap, ct.Brew, ct.BrewName AS beer, pl.Name AS maker, pl.Id AS maker_id, b.SubType AS type, b.Alc AS alc,
                    tb.SizeS, tb.PriceS, tb.SizeM, tb.PriceM, tb.SizeL, tb.PriceL,
                    br.rating_count, br.average_rating, br.comment_count, strftime('%Y-%m-%d', tb.FirstSeen) as first_seen_date
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
      first_seen_date => $row->{first_seen_date}
    };
  }
  
  print "<!-- Loaded beerlist from DB for '$locparam' -->\n";
  return ($beerlist, $last_epoch);
}

sub determine_expansion_state {
  my ($c, $extraboard, $foundrec, $beerlist) = @_;
  if ($extraboard == -1) {
    my $oldbeer = "$foundrec->{maker} : $foundrec->{name}";
    $oldbeer =~ s/&[a-z]+;//g;  # Drop things like &amp;
    $oldbeer =~ s/[^a-z0-9]//ig; # and all non-ascii characters
    foreach my $e (@$beerlist) {
      my $mak = $e->{maker} || "";
      my $beer = $e->{beer} || "";
      
      # Apply the same transformations as prepare_beer_entry_data
      $beer =~ s/(Warsteiner).*/$1/;  # Shorten some long beer names
      $beer =~ s/.*(Hopfenweisse).*/$1/;
      $beer =~ s/.*(Ungespundet).*/$1/;
      if ( $beer =~ s/Aecht Schlenkerla Rauchbier[ -]*// ) {
        $mak = "Schlenkerla";
      }
      $mak =~ s/'//g; # Remove apostrophes
      $beer =~ s/'//g; # Remove apostrophes
      
      my $thisbeer = "$mak : $beer";
      $thisbeer =~ s/&[a-z]+;//g;
      $thisbeer =~ s/[^a-z0-9]//gi;
      if ($thisbeer eq $oldbeer) {
        $extraboard = $e->{id};
        last;
      }
    }
  }
  return $extraboard;
}

sub prepare_beer_entry_data {
  my ($c, $e, $locparam) = @_;
  my $mak = $e->{"maker"} || "";
  my $beer = $e->{"beer"} || "";
  my $sty = $e->{"type"} || "";
  my $origsty = $sty;
  $sty = shortbeerstyle($sty);
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
    first_seen_date => $e->{first_seen_date}
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
  my $compact_display = ($extraboard == $id || $extraboard == -2) ? 'none' : 'table-row';
  my $expanded_display = ($extraboard == $id || $extraboard == -2) ? 'table-row' : 'none';
  # Compact row
  print "<tr id='compact_$id' style='display: $compact_display;'>\n";
  print "<td align=right $beerstyle><a href='#' onclick=\"toggleBeer('$id'); return false;\"><span width=100% $beerstyle>$dispid</span></a></td>\n";
  print "<td style='$beerstyle white-space: normal;'>$buttons_compact</td>\n";
  print "<td style='font-size: x-small;' align=right>$e->{alc}</td>\n";
  print "<td>$processed_data->{dispbeer} $processed_data->{dispmak} ";
  print "<span style='font-size: x-small;'>($processed_data->{country})</span> " if ($processed_data->{country});
  print "$processed_data->{sty}</td>\n";
  print "</tr>\n";
  # Expanded rows
  print "<tr class='expanded_$id' style='display: $expanded_display;'><td colspan=5><hr></td></tr>\n";
  print "<tr class='expanded_$id' style='display: $expanded_display;'><td align=right $beerstyle>";
  print "<a href='#' onclick=\"toggleBeer('$id'); return false;\"><span width=100% $beerstyle id='here'>$dispid</span></a> ";
  print "</td>\n";
  print "<td colspan=4 >";
  print "<span style='white-space:nowrap;overflow:hidden;text-overflow:clip;max-width=100px'>\n";
  print "$processed_data->{mak}: $processed_data->{dispbeer} ";
  print "<span style='font-size: x-small;'>($processed_data->{country})</span>" if ($processed_data->{country});
  print "</span></td></tr>\n";
  print "<tr class='expanded_$id' style='display: $expanded_display;'><td>&nbsp;</td><td colspan=4> $buttons_expanded &nbsp;\n";
  print "<form method='POST' accept-charset='UTF-8' style='display: inline;' class='no-print' >\n";
  print "$hiddenbuttons";
  print "<input type='hidden' name='vol' value='T' />\n" ;  # taster
  print "<input type='hidden' name='pr' value='X' />\n" ;  # at no cost
  print "<input type='submit' name='submit' value='Taster ' /> \n";
  print "</form>\n";
  print "</td></tr>\n";
  print "<tr class='expanded_$id' style='display: $expanded_display;'><td>&nbsp;</td><td colspan=4><span $beerstyle>$processed_data->{origsty}</span> <span style='font-size: x-small;'><b>$e->{alc}%</b></span>";
  if ($processed_data->{first_seen_date}) {
    print " <span style='font-size: x-small;'>On since $processed_data->{first_seen_date}.</span>";
  }
  if ( $processed_data->{average_rating} ) {
    print " " . comments::avgratings($c, $processed_data->{rating_count}, $processed_data->{average_rating}, $processed_data->{comment_count});
  }
  print "</td></tr> \n";
  if ($seenline) {
    print "<tr class='expanded_$id' style='display: $expanded_display;'><td>&nbsp;</td><td colspan=4> $seenline";
    print "</td></tr>\n";
  }
}


################################################################################
# Tell Perl the module loaded fine
1;
