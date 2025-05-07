
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
# List glasses for one day
################################################################################

sub locationhead {
  my $c = shift;
  my $rec = peekrec($c);
  my $loc = util::getrecord($c,"LOCATIONS", $rec->{loc});
  my ( $date, $wd ) = util::splitdate($rec->{effdate} );
  #print STDERR "Loc head: d='$rec->{effdate}' l='$rec->{loc}'='$loc->{Name}' \n";
  print "<b>$wd $date $loc->{Name} </b><br/>";
  return ( $rec->{effdate}, $rec->{loc}, $loc->{Name}, "$wd $date" );
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
  print "<span style='font-size: x-small;'>[$rec->{id}] </span>";
  print "<b>".util::unit($rec->{vol},"c")."</b>";
  print util::unit($rec->{price},",-");
  print util::unit($rec->{alc},"%");
  print util::unit($rec->{drinks},"d");
  #TODO Blood alc
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
  print "<form method='POST' style='display: inline;' class='no-print' >\n";
  # Edit link
  print "<a href='$c->{url}?o=$c->{op}&e=$rec->{id}'><span>edit</span></a>";

  # Hidden fields to post
  my $brewid = $rec->{brewid} || "";
  my $locid = $rec->{loc} || "";
  print "<input type='hidden' name='Location'  value='$locid' />\n";
  print "<input type='hidden' name='Brew'  value='$brewid' />\n";
  print "<input type='hidden' name='selbrewtype'  value='$rec->{brewtype}' />\n";
  print "<input type='hidden' name='o' value='$c->{op}' />\n";  # Stay on page
  print "<input type='hidden' name='q' value='$c->{qry}' />\n";

  # Actual copy buttons
  foreach my $volx (sort {no warnings; $a <=> $b || $a cmp $b} keys(%vols) ){
    # The sort order defaults to numerical, but if that fails, takes
    # alphabetical ('R' for restaurant). Note the "no warnings".
    print "<input type='submit' name='submit' value='Copy $volx'
                style='display: inline; font-size: small' />\n";
  }
  print "</form>\n";
  print "<br/>\n";
} # buttonline

sub sumline {
  my $c = shift;
  my $txt = shift;
  my $drinksum = shift;
  my $prsum = shift;
  print "<table border=0 style='table-layout: fixed' > <tr>";
  print "<td>===</td>";
  my $attr = "align='right' width='50px' ";
  print "<td $attr><b>" . util::unit($prsum,"kr") . "</b></td>\n";
  print "<td $attr><b>" . util::unit($drinksum, "d") . "</b></td>\n";
  print "<td> Total for <b>$txt</b></td>";
  print "</tr></table>";
}

sub oneday {
  my $c = shift;
  my ($effdate, $loc, $locname,$weekday ) = locationhead($c);
  my $rec;
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
    if ( $rec->{loc} != $loc ) {
      sumline($c, $locname, $locdrsum, $locprsum);
      ($effdate, $loc, $locname, $weekday) = locationhead($c);
      $locdrsum = 0;
      $locprsum = 0;
    }
    $dayprsum += abs($rec->{price});
    $daydrsum += $rec->{drinks};
    $locprsum += abs($rec->{price});
    $locdrsum += $rec->{drinks};
    print "<p>";
    nameline($c,$rec);
    numbersline($c,$rec);
    commentlines($c,$rec);
    buttonline($c,$rec);
    print "</p>\n";
  }
  sumline($c, $locname, $locdrsum, $locprsum) if ( abs($locdrsum -$daydrsum) > 0.1 ) ;
  sumline($c, $weekday, $daydrsum, $dayprsum);
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

