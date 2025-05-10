
# Part of my beertracker
# Routines for displaying the full list

package mainlist;
use strict;
use warnings;
use feature 'unicode_strings';
use utf8;  # Source code and string literals are utf-8


# TODO - This is not at all ready, for now it is mostly a design document

my $design_ideas = q{

  Use Sqlite for the whole processing

  While writing this, leave the old mainlist in place for graph/board pages,
  and use the new one only for explicitly asked full list.

  Make a helper to get the next line, with a one-record buffer, so I can unget
  the latest record if it is for a different location or date


  Is it better to make a view like glassrec, or just iterate over glass records
  and fetch the additional data separately? Or a compromise, fetch brew and
  producer in the view, but get location and comments separately?

  Probably easier to make individual calls, at least to begin with. Optimize
  later, if needed.

  Make a helper to get the beer colors right. Use them when displaying the short
  style [Beer, NEIPA].

  Drop the -x modifier. Make the location headline with a section for more data,
  initially hidden, expanded when clicking on the name. In that section
    - Geo coords
    - Links to web page and google/untappd search
    - Maybe a count of visits and comments on the location

  Likewise, hide some brew details, like full style name, how many times and
  when seen.

  Add rating avg on the visible section, after name


};

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
      (select count(*) from comments where comments.glass = glasses.id) as comcount
    from glasses
    left join brews on brews.id = glasses.brew
    left join locations on locations.id = brews.producerlocation
    where Username = ?
    order by timestamp desc
  };
  print STDERR "u='$c->{username}' sql='$sql' \n";
  my $sth = $c->{dbh}->prepare($sql);
  $sth->execute($c->{username});
  return $sth;
}

################################################################################
# Db reader
# Keeps a one-record buffer, so we can take a record, look at it, and put it
# back to be processed.
################################################################################

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
  my $loc = util::getrecord($c,"LOCATIONS", $rec->{loc});
  my ( $date, $wd ) = util::splitdate($rec->{effdate} );
  #print STDERR "Loc head: d='$rec->{effdate}' l='$rec->{loc}'='$loc->{Name}' \n";
  print "<br/>";
  print "<b>$wd $date $loc->{Name} </b><br/>";
  print "<br/>";
  return ( $rec->{effdate}, $rec->{loc}, $loc->{Name}, "$wd $date", $date );
}

sub nameline {
  # 22:19 [Beer,NEIPA] Gamma: Freak Wave
  my $c = shift;
  my $rec = shift;
  my $style = $rec->{brewtype};
  $style .= ",$rec->{subtype}" if ($rec->{subtype});
  # TODO - Get a color for the style
  my $time = $rec->{time};
  $time = "($time)" if ($time lt "0600");
  print "$time ";
  my $dispstyle = brews::brewtextstyle($c,$style);
  print "<span $dispstyle>[$style]</span> \n";
  print "<i>$rec->{producer}:</i> " if ( $rec->{producer} );
  print "<b>$rec->{brewname} </b>" if ( $rec->{brewname} );
  print "<span style='font-size: x-small;'> [$rec->{brewid}]</span>" if($rec->{brewid});
  print "<br/>\n"
}
sub numbersline {
  # [14951] 40cl 70.- 6.2% 1.63d 0.93/₀₀
  my $c = shift;
  my $rec = shift;
  my $bloodalc = shift;
  print "<span style='font-size: x-small;'>[$rec->{id}] </span>";
  print "<b>".util::unit($rec->{vol},"c")."</b>";
  print util::unit($rec->{price},",-");
  print util::unit($rec->{alc},"%");
  print util::unit($rec->{drinks},"d");
  my $ba = $bloodalc->{ $rec->{id} } || "";
  #print STDERR "'$rec->{id}' ba=$ba \n";
  print util::unit($ba,"/₀₀");
  print "<br/>\n"
}

sub commentlines {
  my $c = shift;
  my $rec = shift;
  if ( $rec->{comcount} ) {
    my $ratingline = "";
    my $peopleline = "";
    my $commentlines = "";
    my $sql = "select * from comments where glass = ?";
    my $sth = $c->{dbh}->prepare($sql);
    $sth->execute($rec->{id});
    while ( my $com = $sth->fetchrow_hashref() ) {
      if ( $com->{Rating} ) {
        $ratingline .= "&nbsp; &nbsp; <b>" . comments::ratingline($com->{Rating}) . "</b>";
      }
      if ( $com->{Person} ) {
        my $pers = util::getrecord($c,"PERSONS",$com->{Person});
        $peopleline .= "<i>$pers->{Name}</i>&nbsp; ";
      }
      if ( $com->{Comment} ) {
        $commentlines .= "&nbsp; &nbsp; <i>$com->{Comment} </i><br/>";
      }
    }
    print "$ratingline <br/>" if ($ratingline);
    print "&nbsp; &nbsp; with $peopleline <br/>\n" if ($peopleline);
    print "$commentlines\n" if ($commentlines);
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
  # Edit link
  print "<a href='$c->{url}?o=$c->{op}&e=$rec->{id}'><span>edit</span></a>\n";

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
  print "<table border=0 style='table-layout: fixed' > <tr>";
  print "<td>===</td>";
  my $attr = "align='right' width='50px' ";
  print "<td $attr><b>" . util::unit($prsum,"kr") . "</b></td>\n";
  print "<td $attr><b>" . util::unit($drinksum, "d") . "</b></td>\n";
  print "<td $attr><b>" . util::unit($balc, "/₀₀") . "</b></td>\n";
  print "<td> Total for <b>$txt</b></td>";
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
    nameline($c,$rec);
    numbersline($c,$rec,$balc);
    commentlines($c,$rec);
    buttonline($c,$rec);
    #print "</p>\n";
    print "<br/>\n";
  }
  sumline($c, $locname, $locdrsum, $locprsum, $balc->{"max"}) if ( abs($locdrsum -$daydrsum) > 0.1 ) ;
  sumline($c, $weekday, $daydrsum, $dayprsum, $balc->{"max"});
  print "<hr/>";

}

################################################################################
# mainlist itself
################################################################################

sub mainlist {
  my $c = shift;
  startlist($c);
  oneday($c);
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

