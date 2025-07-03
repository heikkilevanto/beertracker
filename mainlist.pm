
# Part of my beertracker
# Routines for displaying the full list

package mainlist;
use strict;
use warnings;
use feature 'unicode_strings';
use utf8;  # Source code and string literals are utf-8



################################################################################
# Db helpers
################################################################################

# The sql query that gets the glass records we are interested in.
# TODO - Various filters
sub glassquery {
  my $c = shift;
  my $sql = q {
    select
      glasses.id as id,
      strftime('%Y-%m-%d %w', timestamp, '-06:00') as effdate,
      strftime('%H:%M', timestamp) as time,
      timestamp,
      glasses.price as price,
      glasses.volume as vol,
      glasses.alc as alc,
      glasses.stdrinks as drinks,
      location as loc,
      glasses.Brewtype as brewtype,
      glasses.Subtype as subtype,
      brews.Id as brewid,
      brews.Name as brewname,
      locations.name as producer,
      locations.Id as prodid,
      (select count(*) from comments where comments.glass = glasses.id) as comcount,
      br.rating_count,
      br.average_rating,
      br.comment_count
    from glasses
    left join brews on brews.id = glasses.brew
    left join locations on locations.id = brews.producerlocation
    left join brew_ratings br on glasses.brew = br.brew
    where Username = ?
    order by timestamp desc
  };
  # TODO - Move the brew_stat into a separate query. Make one for locations as
  # well.
  my $sth = $c->{dbh}->prepare($sql);
  $sth->execute($c->{username});
  return $sth;
} # glassquery

################################################################################
# Db reader
# Keeps a one-record buffer, so we can take a record, look at it, and put it
# back to be processed.
################################################################################

# TODO Use the one in db.pm

sub startlist {
  my $c = shift;
  my $reader = {};
  $reader->{sth} = glassquery($c);
  $reader->{bufrec} = undef;
  $c->{reader} = $reader;

}

# Get the next glass record. Either via the sth, or from the buffered value
sub getnext {
  my $c = shift;
  my $rec;
  if ( $c->{reader}->{bufrec} ) {
    $rec = $c->{reader}->{bufrec};
    $c->{reader}->{bufrec} = undef;
    #print STDERR "getnext got $rec->{id} from buf \n";
  } else {
    $rec = $c->{reader}->{sth}->fetchrow_hashref();
    #print STDERR "getnext got $rec->{id} from db\n";
    #print STDERR JSON->new->encode($rec) , "\n";
  }
  return $rec;
}

# Put the record back in the reader, so we will get it again on getnext
sub pushback {
  my $c = shift;
  my $rec = shift;
  error ("Can not push back more than one record")
    if ( $c->{reader}->{bufrec} );
  #print STDERR "pushback '$rec->{id}' \n";
  $c->{reader}->{bufrec} = $rec;
}

# Return a copy of the next record, without consuming it
sub peekrec {
  my $c = shift;
  my $rec = getnext($c);
  pushback($c,$rec);
  return $rec;
}

################################################################################
# A helper to calculate blood alcohol for a given effdate
# Returns a hash with bloodalcs for each timestamp for the effdate
#  $bloodalc{"max"} = max ba for the date
#  $bloodalc{$id} = ba after ingesting that glass
################################################################################
# TODO: Change this to return a list of values: ( date, max, hashref ). Add time when gone

sub bloodalc {
  my $c = shift;
  my $effdate = shift; # effdate we are interested in
  my $bodyweight;  # in kg, for blood alc calculations
  $bodyweight = 120 if ( $c->{username} eq "heikki" );  # TODO - Move these somewhere else
  $bodyweight =  83 if ( $c->{username} eq "dennis" );
  my $burnrate = .10; # g of alc pr kg of weight (.10 to .15)
    # Assume .10 as a pessimistic value. Would need an alc meter to calibrate

  if ( !$bodyweight ) {
    print STDERR "Can not calculate alc for $c->{username}, don't know body weight \n";
    return undef;
  }
  #print STDERR "Bloodalc for '$effdate' bw='$bodyweight'\n";
  my $bloodalc = {};
  $bloodalc->{"date"} = $effdate;
  my $sql = q(
    select
      id,
      strftime ('%Y-%m-%d', timestamp,'-06:00') as effdate,
      stdrinks as stdrinks,
      timestamp as stamp
    from glasses
    where effdate = ?
      and stdrinks > 0
      and volume > 0
    order by timestamp
  );
  my $get_sth = $c->{dbh}->prepare($sql);
  $get_sth->execute($effdate);
  my $alcinbody = 0;
  my $balctime = 0;
  $bloodalc->{"max"} = 0 ;
  while ( my ($id, $eff, $stdrinks, $stamp) = $get_sth->fetchrow_array ) {
    next unless $stdrinks;
    my $drtime = $1 + $2/60 if ($stamp =~/ (\d?\d):(\d\d)/ ); # frac hrs
    $drtime += 24 if ( $drtime < $balctime ); # past midnight
    my $timediff = $drtime - $balctime;
    $balctime = $drtime;
    $alcinbody -= $burnrate * $bodyweight * $timediff;
    $alcinbody = 0 if ( $alcinbody < 0);
    $alcinbody += $stdrinks * 12 ; # grams of alc in std drink
    my $ba = $alcinbody / ( $bodyweight * .68 ); # non-fat weight
    $bloodalc->{"max"} = $ba if ( $ba > $bloodalc->{"max"} );
    $bloodalc->{$id} = sprintf("%0.2f",$ba);
    #print STDERR "BA:  '$id' '$stamp' : $ba \n";
  }
  #print STDERR "BA:  max:'$bloodalc->{max}' \n";
  $bloodalc->{"max"} = sprintf("%0.2f", $bloodalc->{"max"} );
  return $bloodalc;

}

#     # Get allgone  TODO
#     my $now = datestr( "%H:%M", 0, 1);
#     my $drtime = $1 + $2/60 if ($now =~/^(\d\d):(\d\d)/ ); # frac hrs
#     $drtime += 24 if ( $drtime < $balctime ); # past midnight
#     my $timediff = $drtime - $balctime;
#     $alcinbody -= $burnrate * $bodyweight * $timediff;
#     $alcinbody = 0 if ( $alcinbody < 0);
#     $curba = $alcinbody / ( $bodyweight * .68 ); # non-fat weight
#     my $lasts = $alcinbody / ( $burnrate * $bodyweight );
#     my $gone = $drtime + $lasts;
#     $gone -= 24 if ( $gone > 24 );
#     $allgone = sprintf( "%02d:%02d", int($gone), ( $gone - int($gone) ) * 60 );


################################################################################
# List glasses for one day
################################################################################

sub locationhead {
  my $c = shift;
  my $rec = shift;
  my $loc = db::getrecord($c,"LOCATIONS", $rec->{loc});
  my ( $date, $wd ) = util::splitdate($rec->{effdate} );
  #print STDERR "Loc head: d='$rec->{effdate}' l='$rec->{loc}'='$loc->{Name}' \n";
  print "<br/>";
  my $locname = "@" . $loc->{Name};
  print "<b>$wd $date " .
    "<a href='$c->{url}?o=Location&e=$rec->{loc}'><span>$locname</span></a> </b>";
  print " <span style='font-size: x-small;'>[$rec->{loc}]</span>\n";
  print "<a href='$loc->{Website}' target='_blank'><span style='font-size: x-small;'>www</span></a>"
    if ( $loc->{Website} );
  print "<br/>";
  print "<br/>" unless ( $rec->{PersName} ); # not for person detail list
  return ( $rec->{effdate}, $rec->{loc}, "@".$loc->{Name}, "$wd $date", $date );
}

sub nameline {
  # 22:19 [Beer,NEIPA] Gamma: Freak Wave
  my $c = shift;
  my $rec = shift;
  my $locationid = shift; # The location we are at, not producer of current drink
  my $locationname = shift;
  my $style = $rec->{brewtype};
  $style .= ",$rec->{subtype}" if ($rec->{subtype});
  my $time = $rec->{time};
  $time = "($time)" if ($time lt "0600");
  my $op = $c->{op};
  $op = "Graph" if ( $op eq "Person" ); # Edit the glass, even if coming from persons
  print "<a href='$c->{url}?o=$op&e=$rec->{id}'>" .
        "<span>$time</span></a> \n";
  #print "$time ";
  my $dispstyle = brews::brewtextstyle($c,$style);
  print "<span style='white-space: nowrap;'>\n";
  print "<span $dispstyle>[$style]</span> \n";
  print "<a href='$c->{url}?o=Location&e=$rec->{prodid}' ><span><i>$rec->{producer}:</i></span></a> " if ( $rec->{producer} );
  if ( $rec->{brewname} ) {
    print "<a href='$c->{url}?o=Brew&e=$rec->{brewid}' ><span><b>$rec->{brewname}</b></span></a> " ;
  } elsif ($locationid) {
    print "<a href='$c->{url}?o=Location&e=$locationid' ><span><b>$locationname</b></span></a> " ;
  }
  print "<span style='font-size: x-small;'> [$rec->{brewid}]</span>" if($rec->{brewid});
  print "</span>\n";
  print "<br/>\n"
}
sub numbersline {
  # [14951] 40cl 70.- 6.2% 1.63d 0.93/₀₀ (7.5)/2 3*
  # id, vol, price, alc, drinks, blood alc, avg rating /count, comment count
  # The ratings and comments are globally for that brew.
  my $c = shift;
  my $rec = shift;
  my $bloodalc = shift;
  #print "<span style='font-size: x-small;'>[$rec->{id}] </span>";
  print "<b>".util::unit($rec->{vol},"c")."</b>";
  print util::unit($rec->{price},",-");
  print util::unit($rec->{alc},"%");
  print util::unit($rec->{drinks},"d");
  my $ba = $bloodalc->{ $rec->{id} } || "";
  #print STDERR "'$rec->{id}' ba=$ba \n";
  print util::unit($ba,"/₀₀");
  my $rc = $rec->{rating_count};
  if ( $rc ) {
    if ( $rc == 1 ) {
      print " <b>($rec->{average_rating})</b>";
    } else {
      print sprintf(" <b>(%3.1f)</b>/%d", $rec->{average_rating}, $rec->{rating_count} );
    }
  }
  print " $rec->{comment_count}•" if ( $rec->{comment_count} );
  print "<br/>\n"
}

sub commentlines {
  my $c = shift;
  my $rec = shift;
  if ( $rec->{comcount} ) {
    my $sql = "select COMMENTS.*,
      PERSONS.Name as PersName,
      PERSONS.Id as PersId
      from comments
      left join PERSONS on persons.id = comments.person
      where glass = ?
      order by Id"; # To keep the order consistent
    my $sth = $c->{dbh}->prepare($sql);
    $sth->execute($rec->{id});
    print "<ul style='margin:0; padding-left:1.2em;'>\n";
    while ( my $com = $sth->fetchrow_hashref() ) {
      $com->{Id} = ""; # Disable the edit link with id
      print "<li>". comments::commentline($c, $com). "</li>\n  ";  # </div>\n";
    }
    print "</ul>\n";
  }
}

sub buttonline {
  # edit (copy 25) (copy 40)
  my $c = shift;
  my $rec = shift;
  my %vols;     # guess sizes for small/large beers
  $vols{$rec->{vol}} = 1 if ($rec->{vol});
  # TODO - more logic, if 20, say 20/30, if 25, say 25/40,
  if ( $rec->{brewtype} =~ /Night|Restaurant/) {
    %vols=(); # nothing to copy
  } elsif ( $rec->{brewtype}  eq "Wine" ) {
    $vols{12} = 1;
    $vols{16} = 1 unless ( $rec->{vol} == 15 );
    $vols{37} = 1;
    $vols{75} = 1;
  } elsif ( $rec->{brewtype}  eq "Spirit" ) {
    $vols{2} = 1;
    $vols{4} = 1;
  } else { # Default to beer, usual sizes in craft beer world
    $vols{25} = 1;
    $vols{40} = 1;
  }
  print "<form method='POST' style='display:inline;' class='no-print' onClick='setdate();'>\n";

  # Hidden fields to post
  my $brewid = $rec->{brewid} || "";
  my $locid = $rec->{loc} || "";
  print "<input type='hidden' name='Location'  value='$locid' />\n";
  print "<input type='hidden' name='Brew'  value='$brewid' />\n";
  print "<input type='hidden' name='selbrewtype'  value='$rec->{brewtype}' />\n";
  print "<input type='hidden' name='date' id='date' value=' ' />\n";
  print "<input type='hidden' name='time' id='time' value=' ' />\n";
  print "<input type='hidden' name='o' value='$c->{op}' />\n";  # Stay on page
  print "<input type='hidden' name='q' value='$c->{qry}' />\n";

  # Actual copy buttons
  foreach my $volx (sort {no warnings; $a <=> $b || $a cmp $b} keys(%vols) ){
    # The sort order defaults to numerical, but if that fails, takes
    # alphabetical ('R' for restaurant). Note the "no warnings".
    print "<input type='submit' name='submit' value='Copy $volx' " .
                "style='display: inline; font-size: small' />\n";
  }
  print "</form>\n";
  print "<br/>\n";
} # buttonline

sub sumline {
  my $c = shift;
  my $txt = shift;
  my $drinksum = shift;
  my $prsum = shift;
  my $balc = shift;
  #print "<table border=0 style='table-layout: fixed' > <tr>";
  print "<table border=0 > <tr>";
  my $attr = "align='right'  ";
  print "<td>=</td>\n";
  print "<td $attr width='50px' ><b>" . util::unit($prsum,"kr") . "</b></td>\n";
  print "<td $attr width='50px' ><b>" . util::unit($drinksum, "d") . "</b></td>\n";
  print "<td $attr width='53px' ><b>" . util::unit($balc, "/₀₀") . "</b></td>\n";
  print "<td>&nbsp <b>$txt</b></td>";
  print "</tr></table>";
}

sub oneday {
  my $c = shift;
  my $rec = peekrec($c);
  my ($effdate, $loc, $locname,$weekday, $date ) = locationhead($c, $rec);
  my $balc = bloodalc($c,$date);
  my $locdrsum = 0;  # drinks for the location
  my $locprsum = 0;  # price for the location
  my $daydrsum = 0;  # drinks for the whole day
  my $dayprsum = 0;  # price for the whole day
  while ( $rec = getnext($c) ) {
    #print JSON->new->encode($rec) . "<br>";
    if ( $rec->{effdate} ne $effdate ) {
      pushback($c,$rec);
      last;
    }
    #print STDERR "oneday: id='$rec->{id} l='$rec->{loc}' \n";
    if ( $rec->{loc} != $loc ) {
      sumline($c, $locname, $locdrsum, $locprsum);
      ($effdate, $loc, $locname, $weekday, $date) = locationhead($c, $rec);
      $locdrsum = 0;
      $locprsum = 0;
    }
    $dayprsum += abs($rec->{price}) if ($rec->{price});
      # TODO - Do we still have old negative prices from boxes?
    $daydrsum += $rec->{drinks} if ($rec->{drinks});
    $locprsum += abs($rec->{price})  if ($rec->{price});
    $locdrsum += $rec->{drinks} if ($rec->{drinks});
    nameline($c, $rec, $loc, $locname);
    numbersline($c,$rec,$balc);
    commentlines($c,$rec);
    buttonline($c,$rec);
    #print "</p>\n";
    print "<br/>\n";
  }
  sumline($c, $locname, $locdrsum, $locprsum) if ( abs($locdrsum -$daydrsum) > 0.1 ) ;
  sumline($c, $weekday, $daydrsum, $dayprsum, $balc->{"max"});
  print "<hr/>";

}

################################################################################
# mainlist itself
################################################################################

sub mainlist {
  my $c = shift;
  startlist($c);
  oneday($c); # TODO - Make params for the list length and start date
  oneday($c);
  oneday($c);
  oneday($c);
  oneday($c);
  oneday($c);
  oneday($c);

  $c->{reader}->{sth}->finish;
}

################################################################################
1; # Tell perl that the module loaded fine

