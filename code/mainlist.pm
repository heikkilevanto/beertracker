
# Part of my beertracker
# Routines for displaying the full list

package mainlist;
use strict;
use warnings;
use feature 'unicode_strings';
use utf8;  # Source code and string literals are utf-8
use URI::Escape qw(uri_escape_utf8);

my $form_counter = 0;  # Counter for unique form IDs across page load



################################################################################
# Db helpers
################################################################################

# The sql query that gets the glass records we are interested in.
# TODO - Various filters
sub glassquery {
  my $c = shift;
  my $date = shift;
  $date .= " 9"; # fake a weekday number to get comparable effdate
  my $sql = q {
    SELECT
      glasses.id AS id,
      strftime('%Y-%m-%d %w', timestamp, '-06:00') AS effdate,
      strftime('%H:%M', timestamp) AS time,
      timestamp AS stamp,
      glasses.price AS price,
      glasses.volume AS vol,
      glasses.alc AS alc,
      glasses.stdrinks AS drinks,
      glasses.note AS note,
      glasses.tap AS tap,
      location AS loc,
      glasses.Brewtype AS brewtype,
      glasses.Subtype AS subtype,
      brews.Id AS brewid,
      brews.Name AS brewname,
      brews.ShortName AS shortname,
      brews.IsGeneric AS generic,
      brews.DetailsLink AS brewlink,
      locations.name AS producer,
      locations.Id AS prodid,
      locations.SearchLink AS prodsearchlink,
      gloc.Name AS locname,
      gloc.Website AS locwebsite,
      gloc.UntappdLink AS locutlink,
      (SELECT count(*) FROM comments WHERE comments.glass = glasses.id) AS comcount,
      (SELECT count(*) FROM photos WHERE photos.Glass = glasses.id) AS photocount,
      br.rating_count,
      br.average_rating,
      br.comment_count
    FROM glasses
    LEFT JOIN brews ON brews.id = glasses.brew
    LEFT JOIN locations ON locations.id = brews.producerlocation
    LEFT JOIN locations gloc ON gloc.id = glasses.location
    LEFT JOIN brew_ratings br ON glasses.brew = br.brew AND br.Username = ?
    WHERE glasses.Username = ?
      AND effdate <= ?
    ORDER BY timestamp DESC
  };
  # TODO - Location stats?
  # TODO - Price guesses for various sizes? (Needed for copy buttons to different volumes)
  my $sth = db::query($c, $sql, $c->{username}, $c->{username}, $date);
  return $sth;
} # glassquery




################################################################################
# A helper to calculate blood alcohol for a given effdate
################################################################################
# Compute blood alcohol from a pre-fetched list of glasses (DESC timestamp order).
# Iterates from the back (chronological order). Sets $rec->{ba} on each record.
# Returns a hashref with {max, last_alcinbody, last_balctime, bodyweight, burnrate}.
sub bloodalc_compute {
  my $c = shift;
  my $glasses = shift; # arrayref of hashrefs, DESC timestamp order, with {id, timestamp, drinks}
  my $result = {};
  my $bodyweight;  # in kg, for blood alc calculations
  $bodyweight = 120 if ( $c->{username} eq "heikki" );  # TODO - Move these somewhere else
  $bodyweight =  83 if ( $c->{username} eq "dennis" );
  my $burnrate = .10; # g of alc pr kg of weight (.10 to .15)
    # Assume .10 as a pessimistic value. Would need an alc meter to calibrate

  if ( !$bodyweight ) {
    print { $c->{log} } "Can not calculate alc for $c->{username}, don't know body weight \n";
    return $result;
  }
  my $alcinbody = 0;
  my $balctime = 0;
  my $max = 0;
  # Glasses are in DESC timestamp order; iterate from the back for chronological order
  foreach my $rec ( reverse @$glasses ) {
    my $stdrinks = $rec->{drinks};
    next unless $stdrinks && $stdrinks > 0;
    my $stamp = $rec->{stamp}; # 'stamp' alias set in both glassquery and bloodalc wrapper SQL
    my $drtime = $1 + $2/60 if ($stamp =~ / (\d?\d):(\d\d)/ ); # frac hrs
    $drtime += 24 if ( $drtime < $balctime ); # past midnight
    my $timediff = $drtime - $balctime;
    $balctime = $drtime;
    $alcinbody -= $burnrate * $bodyweight * $timediff;
    $alcinbody = 0 if ( $alcinbody < 0 );
    $alcinbody += $stdrinks * 12; # grams of alc in std drink
    my $ba = $alcinbody / ( $bodyweight * .68 ); # non-fat weight
    $max = $ba if ( $ba > $max );
    $rec->{ba} = sprintf("%0.2f", $ba);
    #print { $c->{log} } "BA:  '$rec->{id}' '$stamp' : $ba \n";
  }
  $result->{max}            = sprintf("%0.2f", $max);
  $result->{last_alcinbody} = $alcinbody;
  $result->{last_balctime}  = $balctime;
  $result->{bodyweight}     = $bodyweight;
  $result->{burnrate}       = $burnrate;
  return $result;
} # bloodalc_compute

# Thin wrapper: fetches glasses for an effdate, calls bloodalc_compute, caches result.
# Also populates per-ID BA entries for backward compat with current oneday
# Old code, used only from util::topstats
sub bloodalc {
  my $c = shift;
  my $effdate = shift; # effdate we are interested in
  my $cache_key = "bloodalc:" . $c->{username} . ":" . $effdate;
  my $cached = cache::get($c, $cache_key);
  return $cached if $cached;
  my $sql = q(
    SELECT
      id AS id,
      stdrinks AS drinks,
      timestamp AS stamp
    FROM glasses
    WHERE strftime('%Y-%m-%d', timestamp, '-06:00') = ?
      AND username = ?
      AND stdrinks > 0
      AND volume > 0
    ORDER BY timestamp DESC
  );
  my $get_sth = db::query($c, $sql, $effdate, $c->{username});
  my @glasses;
  while ( my $row = $get_sth->fetchrow_hashref ) {
    push @glasses, $row;
  }
  my $bloodalc = bloodalc_compute($c, \@glasses);
  $bloodalc->{date} = $effdate;
  # Cache the computed bloodalc blob for this user+date
  cache::set($c, $cache_key, $bloodalc);
  return $bloodalc;
} # bloodalc

# Compute current blood alcohol for an effdate by using the cached/static
# bloodalc data and applying the time-based burn since the last drink.
sub bloodalcnow {
  my $c = shift;
  my $effdate = shift;
  my $ba = bloodalc($c, $effdate);
  return undef unless $ba;
  return 0 unless $ba->{last_alcinbody} && defined $ba->{last_balctime};
  my $alcinbody = $ba->{last_alcinbody};
  my $balctime   = $ba->{last_balctime};
  my $bodyweight = $ba->{bodyweight} // 0;
  my $burnrate   = $ba->{burnrate} // .10;
  return 0 unless $bodyweight; # cannot compute without bodyweight

  my $now = dateutil::datestr( "%H:%M", 0, 1);
  my ($h,$m) = (0,0);
  ($h,$m) = ($1,$2) if ( $now =~ /^(\d?\d):(\d\d)/ );
  my $drtime = $h + $m/60;
  $drtime += 24 if ( $drtime < $balctime ); # past midnight
  my $timediff = $drtime - $balctime;
  return 0 if ( $timediff < 0 );
  $alcinbody -= $burnrate * $bodyweight * $timediff;
  $alcinbody = 0 if ( $alcinbody < 0);
  my $curba = $alcinbody / ( $bodyweight * .68 ); # non-fat weight
  return sprintf("%0.2f", $curba );
} # bloodalcnow

################################################################################
# List glasses for one day
################################################################################

sub locationhead {
  my $c = shift;
  my $rec = shift;
  my $locname = $rec->{locname};
  my $locwebsite = $rec->{locwebsite} || '';
  my $locutlink  = $rec->{locutlink}  || '';
  my ( $date, $wd ) = dateutil::splitdate($rec->{effdate} );
  my $html = "";
  my $display = "@" . $locname;
  $html .= "<br/>";
  $html .= "<b><a href='$c->{url}?o=$c->{op}&date=$date'><span>$wd $date</span></a> " .
    "<a href='$c->{url}?o=Location&e=$rec->{loc}'><span>$display</span></a> </b>";
  $html .= " <span style='font-size: x-small;'>[$rec->{loc}]</span>\n";
  $html .= util::locationlinks($c, $locwebsite, $locutlink, $locname);
  $html .= "<br/>";
  $html .= "<br/>" unless ( $rec->{PersName} ); # not for person detail list
  return ( $html, $rec->{effdate}, $rec->{loc}, "@".$locname, "$wd $date", $date );
}

sub nameline {
  # 22:19 [Beer,NEIPA] Gamma: Freak Wave
  my $c = shift;
  my $rec = shift;
  my $locationid = shift; # The location we are at, not producer of current drink
  my $locationname = shift;
  my $html = "";
  my $time = $rec->{time};
  $time = "($time)" if ($time lt "0600");
  my $op = $c->{op};
  $op = "Graph" if ( $op eq "Person" ); # Edit the glass, even if coming from persons
   $html .= "<span style='white-space: nowrap;'>\n";
   $html .= "<a href='$c->{url}?o=$op&e=$rec->{id}'>" .
         "<span>$time</span></a> \n";
   my $style_str;
   if ( $rec->{brewtype} eq 'Beer' ) {
     $style_str = $rec->{subtype} || 'Beer';
   } else {
     $style_str = $rec->{brewtype};
     $style_str .= ",$rec->{subtype}" if $rec->{subtype};
   }
   my $style_url = uri_escape_utf8($style_str);
   $html .= "<a href='$c->{url}?o=$c->{op}&q=$style_url'>" .
     styles::brewstyledisplay($c, $rec->{brewtype}, $rec->{subtype}, "glass:$rec->{id} '" . ($rec->{brewname} // "") . "' $rec->{brewtype}/" . ($rec->{subtype} // "")) .
     "</a> \n";
  $html .= "<a href='$c->{url}?o=Location&e=$rec->{prodid}' ><span><i>$rec->{producer}:</i></span></a> " if ( $rec->{producer} );
  if ( $rec->{brewname} ) {
    $html .= "<a href='$c->{url}?o=Brew&e=$rec->{brewid}' ><span><b>$rec->{brewname}</b></span></a> " ;
  } elsif ($locationid) {
    $html .= "<a href='$c->{url}?o=Location&e=$locationid' ><span><b>$locationname</b></span></a> " ;
  }
  $html .= "<span style='font-size: x-small;'> [$rec->{brewid}]</span>" if($rec->{brewid});
  $html .= " " . util::brewlinks($c, $rec->{brewlink}, $rec->{brewname}, $rec->{prodsearchlink}, "", $rec->{brewtype}, $rec->{shortname}) if ($rec->{brewid});
  if (glasses::isemptyglass($rec->{brewtype}) && $rec->{price}) {
    $html .= util::unit($rec->{price}, ",-");
  }
  $html .= "</span>\n";
  $html .= "<br/>\n";
  return $html;
}

sub numbersline {
  # [14951] 40cl 70.- 6.2% 1.63d 0.93/₀₀ (7.5)/2 3*  (glass note)
  # id, vol, price, alc, drinks, blood alc, avg rating /count, comment count
  # The ratings and comments are globally for that brew.
  my $c = shift;
  my $rec = shift;
  my $html = "";
  #$html .= "<span style='font-size: x-small;'>[$rec->{id}] </span>";
  $html .= "<b>".util::unit($rec->{vol},"c")."</b>";
  $html .= util::unit($rec->{price},",-");
  $html .= util::unit($rec->{alc},"%");
  $html .= util::unit($rec->{drinks},"d");
  my $ba = $rec->{ba} || "";
  $html .= util::unit($ba,"/\x{2080}\x{2080}");
  if ( ! $rec->{generic} ) {  # No ratings or comments on generics like Beer,Mixed or House Red Wine
    $html .= comments::avgratings($c, $rec->{rating_count}, $rec->{average_rating}, $rec->{comment_count});
  }
  if ( $rec->{note} ) {
    $html .= " (<i>$rec->{note}</i>)";
  }
  if ( $rec->{tap} ) {
    $html .= " #$rec->{tap}";
  }
  $html .= "<br/>\n";
  return $html;
}

sub photoline {
  my $c = shift;
  my $rec = shift;
  return "" unless $rec->{photocount};  # skip query for the common case
  my $html = photos::thumbnails_html($c, 'Glass', $rec->{id});
  return $html || "";
} # photoline

sub commentlines {
  my $c = shift;
  my $rec = shift;
  my $html = "";
  if ( $rec->{comcount} ) {
    my $sql = "SELECT COMMENTS.*,
      group_concat(cp_persons.Name || '|' || cp.Person, ', ') AS PeopleData,
      (SELECT count(*) FROM photos WHERE photos.Comment = comments.Id) AS photocount
      FROM comments
      LEFT JOIN comment_persons cp ON cp.Comment = comments.Id
      LEFT JOIN persons cp_persons ON cp_persons.Id = cp.Person
      WHERE glass = ?
      GROUP BY comments.Id
      ORDER BY comments.Id"; # To keep the order consistent
    my $sth = db::query($c, $sql, $rec->{id});
    $html .= "<ul style='margin:0; padding-left:1.2em;'>\n";
    while ( my $com = $sth->fetchrow_hashref() ) {
      $html .= "<li>". comments::commentline($c, $com). "</li>\n  ";
    }
    $html .= "</ul>\n";
  }
  return $html;
}

sub buttonline {
  # edit (copy 25) (copy 40)
  my $c = shift;
  my $rec = shift;
  my $html = "";
  my %vols;     # guess sizes for small/large beers
  $vols{$rec->{vol}} = 1 if ($rec->{vol});
  # TODO - more logic, if 20, say 20/30, if 25, say 25/40,
  if ( glasses::isemptyglass($rec->{brewtype}) || $rec->{brewtype} =~ /Adjustment/i ) {
    %vols=(); # nothing to copy
  } elsif ( $rec->{brewtype}  eq "Wine" ) {
    $vols{12} = 1;
    $vols{16} = 1 unless ( $rec->{vol} == 15 );
    $vols{75} = 1;
  } elsif ( $rec->{brewtype}  eq "Spirit" ) {
    $vols{2} = 1;
    $vols{4} = 1;
  } elsif ( $rec->{vol} == 30 ||  $rec->{vol} == 50  ) {
    $vols{30} = 1;  # SOme beers come in 30/50
    $vols{50} = 1;
  } else { # Default to beer, usual sizes in craft beer world
    $vols{25} = 1;
    $vols{40} = 1;
  }
  # Hidden fields to post (same for all copy buttons)
  my $brewid = $rec->{brewid} || "";
  my $locid = $rec->{loc} || "";

  # Actual copy buttons
  foreach my $volx (sort {no warnings; $a <=> $b || $a cmp $b} keys(%vols) ){
    # The sort order defaults to numerical, but if that fails, takes
    # alphabetical ('R' for restaurant). Note the "no warnings".
    $html .= "<form method='POST' style='display:inline;' class='no-print' onClick='setdate();'>\n";
    $html .= "<input type='hidden' name='Location'  value='$locid' />\n";
    $html .= "<input type='hidden' name='Brew'  value='$brewid' />\n";
    $html .= "<input type='hidden' name='selbrewtype'  value='$rec->{brewtype}' />\n";
    $html .= "<input type='hidden' name='date' id='date' value=' ' />\n";
    $html .= "<input type='hidden' name='time' id='time' value=' ' />\n";
    # For copy buttons, pass the original price only if volume matches, else leave empty to trigger guessing
    # Set price to 0 if the source glass has a negative price (bottle purchase), for all copy buttons
    my $copy_price = '';
    # Check for currency note pattern like [5.50 e] - pass original format
    if ($rec->{note} && $rec->{note} =~ /\[([0-9.]+) +(\w+)\]/) {
      $copy_price = "$1$2";  # e.g., "5.50e"
    } elsif ( defined $rec->{price} && $rec->{price} < 0 ) {
      $copy_price = 0;  # Negative price means bottle purchase, copy as zero price
    } elsif ( $rec->{vol} && $volx == $rec->{vol} && defined $rec->{price} ) {
      $copy_price = $rec->{price};  # Same volume, copy the price
    }
    my $tap_val = $rec->{tap} // '';
    my $orig_vol_val = $rec->{vol} // '';
    $html .= "<input type='hidden' name='pr' value='$copy_price' />\n";
    $html .= "<input type='hidden' name='tap' value='$tap_val' />\n";
    $html .= "<input type='hidden' name='orig_vol' value='$orig_vol_val' />\n";
    $html .= "<input type='hidden' name='o' value='$c->{op}' />\n";  # Stay on page
    $html .= "<input type='hidden' name='q' value='$c->{qry}' />\n";
    $html .= "<input type='submit' name='submit' value='Copy $volx' " .
                "style='display: inline; font-size: small' />\n";
    $html .= "</form>\n";
  }
  if (glasses::isemptyglass($rec->{brewtype}) || $rec->{photocount}) {
    $html .= photos::photo_form($c, glass => $rec->{id}) . "\n";
  }
  if (glasses::isemptyglass($rec->{brewtype}) || $rec->{comcount}) {
    my $ctype = $rec->{brewtype} eq 'Night'                          ? 'night'
              : $rec->{brewtype} =~ /^(Restaurant|Bar)$/i            ? 'location'
              :                                                         'brew';
    $html .= "<a href='$c->{url}?o=Comment&e=new&glass=$rec->{id}&commenttype=$ctype'>" .
             "<span>(Comment)</span></a>\n";
  }
  $html .= "<br/>\n";
  return $html;
} # buttonline

sub sumline {
  my $c = shift;
  my $txt = shift;
  my $drinksum = shift;
  my $prsum = shift;
  my $balc = shift;
  my $html = "";
  #$html .= "<table border=0 style='table-layout: fixed' > <tr>";
  $html .= "<table border=0 > <tr>";
  my $attr = "align='right'  ";
  $html .= "<td>=</td>\n";
  $html .= "<td $attr width='50px' ><b>" . util::unit($prsum,".-") . "</b></td>\n";
  $html .= "<td $attr width='50px' ><b>" . util::unit($drinksum, "d") . "</b></td>\n";
  $html .= "<td $attr width='53px' ><b>" . util::unit($balc, "/\x{2080}\x{2080}") . "</b></td>\n";
  $html .= "<td>&nbsp; <b>$txt</b></td>";
  $html .= "</tr></table>";
  return $html;
}

sub adjustment_form {
  my $c = shift;
  my $locationid = shift;
  my $effdate = shift;
  my $locprsum = shift;
  my $current_adjustment = shift;
  my $current_adjustment_price = shift || 0;
  my $last_glass_time = shift || "23:59";  # Default to end of day if no glasses
  my ($date) = split(' ', $effdate);

  # Generate unique ID for this form instance (to handle multiple sessions at same location)
  $form_counter++;
  my $form_id = "adj_${locationid}_${form_counter}";

  # Get adjustment brew ID (cached per request in $c)
  my $adjustment_brew_id;
  if (exists $c->{adjustment_brew_id}) {
    $adjustment_brew_id = $c->{adjustment_brew_id};
  } else {
    my $sql = "SELECT Id FROM brews WHERE BrewType='Adjustment' LIMIT 1";
    ($adjustment_brew_id) = db::queryarray($c, $sql);
    $c->{adjustment_brew_id} = $adjustment_brew_id;
  }
  return unless $adjustment_brew_id;  # No adjustment brew configured

  my $html = "";
  if ($current_adjustment) {
    # Adjustment exists - show delete button with amount
    my $sign = '';
    $sign = '+' if ($current_adjustment_price >= 0);
    $html .= qq{<div id='adjform_$form_id' style='display:none;'>
    <form method='POST' style='display:inline; margin-left:1em;'>
      <span style='font-size:small;'>Adjustment: ${sign}${current_adjustment_price}.-</span>
      <input type='hidden' name='o' value='Graph'/>
      <input type='hidden' name='submit' value='Del'/>
      <input type='hidden' name='e' value='$current_adjustment'/>
      <button type='submit' style='font-size:small;'>Delete ±</button>
    </form>
    <br/>
    <form method='POST' style='display:inline; margin-left:1em;' accept-charset='UTF-8'>
      <input type='hidden' name='o' value='Graph'/>
      <input type='hidden' name='submit' value='Insert'/>
      <input type='hidden' name='Location' value='$locationid'/>
      <input type='hidden' name='date' value='$date'/>
      <input type='hidden' name='time' value='$last_glass_time:00'/>
      <select name='selbrewtype' style='font-size:small;'>
        @{[glasses::emptyglass_options()]}      </select>
      <label style='font-size:small; margin-left:0.5em;'>
        <input type='checkbox' name='addcomment' value='1'/> comment
      </label>
      <button type='submit' style='font-size:small;'>Add empty</button>
    </form>
    </div>
    <script>document.addEventListener('DOMContentLoaded', function(){ initAdjForm('$form_id'); });</script>
};
  } else {
    # No adjustment - show entry form
    $html .= qq{<div id='adjform_$form_id' style='display:none;'>
      <form method='POST' style='display:inline; margin-left:1em;' onsubmit='return updateAdjustment(\"$form_id\", $locprsum);'>
      <span style='font-size:small;'>Expected: ${locprsum}.-, Paid:</span>
      <input name='actualpaid' id='actualpaid_$form_id' size='4' required style='font-size:small;'/>
      <input type='hidden' name='o' value='Graph'/>
      <input type='hidden' name='submit' value='Insert'/>
      <input type='hidden' name='Location' value='$locationid'/>
      <input type='hidden' name='Brew' value='$adjustment_brew_id'/>
      <input type='hidden' name='selbrewtype' value='Adjustment'/>
      <input type='hidden' name='selbrewsubtype' id='subtype_$form_id' value=''/>
      <input type='hidden' name='date' value='$date'/>
      <input type='hidden' name='time' value='$last_glass_time:00'/>
      <input type='hidden' name='vol' value='0'/>
      <input type='hidden' name='alc' value='0'/>
      <input type='hidden' name='tap' value=''/>
      <input type='hidden' name='pr' id='pr_$form_id' value='0'/>
      <input type='hidden' name='note' id='note_$form_id' value=''/>
      <button type='submit' style='font-size:small;'>Save ±</button>
    </form>
    <br/>
    <form method='POST' style='display:inline; margin-left:1em;' accept-charset='UTF-8'>
      <input type='hidden' name='o' value='Graph'/>
      <input type='hidden' name='submit' value='Insert'/>
      <input type='hidden' name='Location' value='$locationid'/>
      <input type='hidden' name='date' value='$date'/>
      <input type='hidden' name='time' value='$last_glass_time:00'/>
      <select name='selbrewtype' style='font-size:small;'>
        @{[glasses::emptyglass_options()]}      </select>
      <label style='font-size:small; margin-left:0.5em;'>
        <input type='checkbox' name='addcomment' value='1'/> comment
      </label>
      <button type='submit' style='font-size:small;'>Add empty</button>
    </form>
    </div>
    <script>document.addEventListener('DOMContentLoaded', function(){ initAdjForm('$form_id'); });</script>
};
  }
  $html .= "<br/>\n";
  return $html;
} # adjustment_form

sub oneday {
  my $c = shift;
  return "" unless db::peekrow($c->{sth});

  # Pass 1: collect all records for this day into @glasses
  my $day_effdate = db::peekrow($c->{sth})->{effdate};
  my @glasses;
  while ( my $row = db::nextrow($c->{sth}) ) {
    if ( $row->{effdate} ne $day_effdate ) {
      db::pushback_row($c->{sth}, $row);
      last;
    }
    push @glasses, $row;
  }
  return "" unless @glasses;

  # Annotate each record with {ba} and get day max for sumline
  my $balc = bloodalc_compute($c, \@glasses);

  # Pass 2: render
  my $html = "";
  my ($lhtml, $effdate, $loc, $locname, $weekday, $date) = locationhead($c, $glasses[0]);
  $html .= $lhtml;
  my $locdrsum = 0;  # drinks for the location
  my $locprsum = 0;  # price for the location
  my $locmaxba = 0;  # max blood alc for the location
  my $daydrsum = 0;  # drinks for the whole day
  my $dayprsum = 0;  # price for the whole day
  my $location_count = 1;  # number of locations for the day
  my $current_adjustment = undef;  # Track adjustment glass for current location session
  my $current_adjustment_price = 0;  # Track adjustment amount
  my $last_glass_time = undef;  # Track time of last glass in location session
  foreach my $rec (@glasses) {
    #print { $c->{log} } "oneday: id='$rec->{id} l='$rec->{loc}' \n";
    if ( $rec->{loc} != $loc ) {
      my $loc_total_with_adj = $locprsum + $current_adjustment_price;
      $html .= sumline($c, $locname, $locdrsum, $loc_total_with_adj, $locmaxba);
      $html .= adjustment_form($c, $loc, $effdate, $locprsum, $current_adjustment, $current_adjustment_price, $last_glass_time);
      ($lhtml, $effdate, $loc, $locname, $weekday, $date) = locationhead($c, $rec);
      $html .= $lhtml;
      $locdrsum = 0;
      $locprsum = 0;
      $locmaxba = 0;
      $location_count++;
      $current_adjustment = undef;  # Reset for new location
      $current_adjustment_price = 0;
      $last_glass_time = undef;
    }
    # Sum prices only for non-empty glasses, skipping nights, restaurants, and adjustments
    if ($rec->{price} && $rec->{brewid} && $rec->{brewtype} ne 'Adjustment') {
      $dayprsum += abs($rec->{price});
      $locprsum += abs($rec->{price}) if ($rec->{price}=~/^-?[0-9.]/);
    }
    # Track adjustment glass for current location
    if ($rec->{brewtype} eq 'Adjustment') {
      $current_adjustment = $rec->{id};
      $current_adjustment_price = $rec->{price};
      # Add adjustment to day total but not location sum (we want expected, not actual)
      $dayprsum += $rec->{price};
    }
    # Track last glass time for this location (for setting adjustment timestamp)
    $last_glass_time = $rec->{time} if $rec->{time};
    $daydrsum += $rec->{drinks} if ($rec->{drinks});
    $locdrsum += $rec->{drinks} if ($rec->{drinks});
    $locmaxba = $rec->{ba} if $rec->{ba} && $rec->{ba} > $locmaxba;
    $html .= nameline($c, $rec, $loc, $locname);
    $html .= numbersline($c, $rec) unless glasses::isemptyglass($rec->{brewtype});
    $html .= photoline($c,$rec);
    $html .= commentlines($c,$rec);
    $html .= buttonline($c,$rec);
    $html .= "<br/>\n";
  }
  my $loc_total_with_adj = $locprsum + $current_adjustment_price;
  $html .= sumline($c, $locname, $locdrsum, $loc_total_with_adj, $locmaxba);
  $html .= adjustment_form($c, $loc, $effdate, $locprsum, $current_adjustment, $current_adjustment_price, $last_glass_time);
  if ($location_count > 1) {
    $html .= sumline($c, $weekday, $daydrsum, $dayprsum, $balc->{"max"});
  }
  $html .= "<hr/>";
  return $html;

} # oneday

################################################################################
# Grep-style filtering
################################################################################

# Return true if $rec matches the current filter query $c->{qry}.
# Empty/undefined query matches all. Tokens use AND-logic across fields.
sub matching_rec {
  my $c = shift;
  my $rec = shift;
  return 1 unless $c->{qry};
  my @tokens = util::filter_tokens($c->{qry});
  return 1 unless @tokens;
  foreach my $token (@tokens) {
    my $matched = 0;
    for my $field (qw(brewname producer locname subtype brewtype shortname note tap)) {
      my $val = $rec->{$field};
      next unless defined $val && $val ne "";
      $matched = 1 if ( $val =~ /\Q$token\E/i );
      last if $matched;
    }
    return 0 unless $matched;
  }
  return 1;
} # matching_rec

# Render a filtered list of glasses matching $c->{qry}.
# Uses the $c->{sth} set by mainlist() via glassquery().
# Scans from $c->{date} backwards, showing up to $ndays days that have matches.
sub filtered_list {
  my $c = shift;
  my $ndays = util::paramnumber($c, "ndays", 7) || 7;
  my $ndays_orig = $ndays;
  my $date = $c->{date};
  my $html = "";
  my $shown = 0;

  while ( $ndays > 0 && db::peekrow($c->{sth}) ) {
    my $day_effdate = db::peekrow($c->{sth})->{effdate};
    my @glasses;
    while ( my $row = db::nextrow($c->{sth}) ) {
      if ( $row->{effdate} ne $day_effdate ) {
        db::pushback_row($c->{sth}, $row);
        last;
      }
      push @glasses, $row;
    }
    next unless @glasses;

    # Compute blood alc for the full day (per-record BA depends on full day)
    bloodalc_compute($c, \@glasses);

    # Pre-filter to matching records for this day
    my @matching = grep { matching_rec($c, $_) } @glasses;
    next unless @matching;

    # Only count days that have matching records
    $ndays--;

    my $cur_loc;
    foreach my $rec (@matching) {
      if ( !defined $cur_loc || $rec->{loc} != $cur_loc ) {
        my ($lhtml) = locationhead($c, $rec);
        $html .= $lhtml;
        $cur_loc = $rec->{loc};
      }
      $html .= nameline($c, $rec, $rec->{loc}, $rec->{locname});
      $html .= numbersline($c, $rec) unless glasses::isemptyglass($rec->{brewtype});
      $html .= photoline($c, $rec);
      $html .= commentlines($c, $rec);
      $html .= buttonline($c, $rec);
      $html .= "<br/>\n";
      $shown++;
    }
  }

  if ( $shown == 0 ) {
    my $q_disp = util::htmlesc($c->{qry});
    $html .= "<i>No matches for '$q_disp'</i><br/>\n";
  }

  if ( db::peekrow($c->{sth}) ) {
    my $q_esc = uri_escape_utf8($c->{qry});
    my $date_esc = uri_escape_utf8($date);
    my $more_ndays = $ndays_orig * 2;
    $html .= qq{<a href='$c->{url}?o=$c->{op}&q=$q_esc&ndays=$more_ndays&date=$date_esc'><span>More results</span></a><br/>\n};
  }

  $c->{sth}->finish;
  return $html;
} # filtered_list

################################################################################
# mainlist itself
################################################################################

sub mainlist {
  my $c = shift;
  $form_counter = 0;  # Reset counter for each page load
  my $date = util::param($c,"date",dateutil::datestr("%F") );
  my $ndays = util::paramnumber($c, "ndays", 7 ) || 7;
  # If no explicit date= param, try to derive from e= (glass) or ec= (comment)
  my $derived_date;
  if ( !defined $c->{cgi}->param("date") ) {
    if ( $c->{edit} ) {
      $derived_date = db::glasseffdate($c, $c->{edit}, $c->{username});
    } elsif ( my $ec = util::param($c, "ec") ) {
      ($derived_date) = $c->{dbh}->selectrow_array(
        "SELECT strftime('%Y-%m-%d', g.Timestamp, '-06:00')
         FROM comments c JOIN glasses g ON g.Id = c.Glass
         WHERE c.Id = ? AND g.Username = ?",
        undef, $ec, $c->{username});
    }
    if ( $derived_date ) {
      $date = $derived_date;
      $ndays = 1;
    }
  }
  print { $c->{log} } "mainlist $ndays days back from $date \n" if ( $c->{devversion} );
  my $original_ndays = $ndays;
  my $show_form = 0;
  $show_form = 1 if (defined $c->{cgi}->param("q") || defined $c->{cgi}->param("date") || defined $c->{cgi}->param("ndays") || $derived_date);
  my $cache_key = "mainlist:$c->{username}:$c->{op}:$c->{qry}:$date:$original_ndays:$show_form";
  my $cached_html = cache::get($c, $cache_key);
  if ($cached_html) {
    print { $c->{log} } "mainlist: cache hit\n" if $c->{devversion};
    print $cached_html;
    return;
  }
  my $html = "";
  if ($show_form) {
    $html .= qq{<b>Main List</b><br/>\n};
    $html .= qq{<form method="GET">\n};
    $html .= qq{<input type="hidden" name="o" value="$c->{op}" />\n};
    $html .= qq{<table>\n};
    my $qry_esc = util::htmlesc($c->{qry});
    $html .= qq{<tr><td>Filter:</td><td><input type="text" name="q" value="$qry_esc" style="width: 10em;" /></td></tr>\n};
    $html .= qq{<tr><td>Date from:</td><td><input type="text" name="date" value="$date" style="width: 8em;" /></td></tr>\n};
    $html .= qq{<tr><td><input type="submit" value="Show" /></td><td><input type="number" name="ndays" value="$original_ndays" style="width: 3em;" /> days &nbsp; <a href="$c->{url}?o=$c->{op}"><span>clr</span></a></td></tr>\n};
    $html .= qq{</table>\n};
    $html .= qq{</form><br/>\n};
  }
  $c->{sth} = glassquery($c, $date);
  if ($c->{qry}) {
    $c->{date} = $date;
    $html .= filtered_list($c);
  } else {
    my $days_shown = 0;
    while ( $days_shown < $ndays && db::peekrow($c->{sth}) ) {
      $html .= oneday($c);
      $days_shown++;
    }
    my $next_rec = db::peekrow($c->{sth});
    if ($next_rec) {
      my ($new_date) = split(' ', $next_rec->{effdate});
      $html .= qq{<a href="$c->{url}?o=$c->{op}&date=$new_date&ndays=$original_ndays"><span>Older records</span></a><br/>\n};
    }
    $c->{sth}->finish;
  }
  cache::set($c, $cache_key, $html);
  print $html;
}

################################################################################
1; # Tell perl that the module loaded fine

