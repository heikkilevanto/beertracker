# Part of my beertracker
# Routines for displaying the beer list (board) for the current bar
# and buttons for quickly marking a beer has been drunk

# TODO - Rethink the whole beer board system, keep them all in the database,
# etc. See #390
# Basically, when scraping a list
#  - create missing brews and producers
#  - Rewrite the list to use brew and producer records,
#  - Use helpers from util.pm and brews.pm for short names, colors, etc
# Later
#  - Add tap records showing when we have seen said beer at which tap

package beerboard;
use strict;
use warnings;
use feature 'unicode_strings';
use utf8;  # Source code and string literals are utf-8
use URI::Escape;

# Beerlist scraping scrips
my %scrapers;
$scrapers{"Ølbaren"} = "oelbaren.pl";
$scrapers{"Taphouse"} = "taphouse.pl";
$scrapers{"Fermentoren"} = "fermentoren.pl";
#$scrapers{"Ølsnedkeren"} = "oelsnedkeren.pl";
# Ølsnedkerens web site is broken, does not show a beer list at all
# See #368

# Links to beer lists at the most common locations and breweries
my %links; # TODO - Kill this, get them from the database
$links{"Ølbaren"} = "http://oelbaren.dk/oel/";
$links{"Ølsnedkeren"} = "https://www.olsnedkeren.dk/";
$links{"Fermentoren"} = "http://fermentoren.com/index";
$links{"Dry and Bitter"} = "https://www.dryandbitter.com/collections/beer/";
#$links{"Dudes"} = "http://www.dudes.bar"; # R.I.P Dec 2018
$links{"Taphouse"} = "http://www.taphouse.dk/";
$links{"Slowburn"} = "https://slowburn.coop/";
$links{"Brewpub"} = "https://brewpub.dk/vores-l";
$links{"Penyllan"} = "https://penyllan.com/";



################################################################################
# Beer board (list) for the location.
# Scraped from their website
################################################################################
# TODO - This is one long routine. Refactor it to something manageable
# Split into two modules, as well!

sub beerboard {
  my $c = shift;

  my $qrylim = util::param($c,"f");

  my $extraboard = -1; # Which of the entries to open, or -1 current, -2 for all, -3 for none
  if ( $c->{op} =~ /board(-?\d+)/i ) {
    $extraboard = $1;
  }
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
  # Pull-down for choosing the bar
  print "\n<form method='POST' accept-charset='UTF-8' style='display:inline;' class='no-print' >\n";
  print "Beer list \n";
  print "<select onchange='document.location=\"$c->{url}?o=board&loc=\" + this.value;' style='width:5.5em;'>\n";
  if (!$scrapers{$locparam}) { #Include the current location, even if no scraper
    $scrapers{$locparam} = ""; #that way, the pulldown looks reasonable
  }
  for my $l ( sort(keys(%scrapers)) ) {
    my $sel = "";
    $sel = "selected" if ( $l eq $locparam);
    print "<option value='$l' $sel>$l</option>\n";
  }
  print "</select>\n";
  print "</form>\n";
  if ($links{$locparam} ) {
    print loclink($c, $locparam,"www"," ");
  }
  print "&nbsp; (<a href='$c->{url}?o=$c->{op}&loc=$locparam&q=PA'><span>PA</span></a>) "
    if ($c->{qry} ne "PA" );

  print "<a href='$c->{url}?o=board&loc=$locparam&f=f'><i>(Reload)</i></a>\n";
  print "<a href='$c->{url}?o=board-2&loc=$locparam'><i>(all)</i></a>\n";

  print "<p>\n";
  if (!$scrapers{$locparam}) {
    print "Sorry, no  beer list for '$locparam' - showing 'Ølbaren' instead<br/>\n";
    $locparam="Ølbaren"; # A good default
  }

  my $script = $c->{scriptdir} . $scrapers{$locparam};
  my $cachefile = $c->{datadir} . $scrapers{$locparam};
  $cachefile =~ s/\.pl/.cache/;
  my $json = "";
  my $loaded = 0;
  if ( -f $cachefile
       && (-M $cachefile) * 24 * 60 < 20    # age in minutes
       && -s $cachefile > 256    # looks like a real file
       && $qrylim ne "f" ) {
    open CF, $cachefile or util::error ("Could not open $cachefile for reading");
    while ( <CF> ) {
      $json .= $_ ;
    }
    close CF;
    print "<!-- Loaded cached board from '$cachefile' -->\n";
  }
  if ( !$json ){
    $json = `perl $script`;
    $loaded = 1;
    print "<!-- run scraper script '$script' -->\n";
  }
  if (! $json) {
    print "Sorry, could not get the list from $locparam<br/>\n";
    print "<!-- Error running " . $scrapers{$locparam} . ". \n";
    print "Result: '$json'\n -->\n";
  }else {
    if ($loaded) {
      open CF, ">$cachefile" or util::error( "Could not open $cachefile for writing");
      print CF $json;
      close CF;
    }
    chomp($json);
    #print "<!--\nPage:\n$json\n-->\n";  # for debugging
    my $beerlist = JSON->new->utf8->decode($json)
      or util::error("Json decode failed for $scrapers{$locparam} <pre>$json</pre>");
    my $nbeers = 0;
    if ($c->{qry}) {
    print "Filter:<b>$c->{qry}</b> " .
      "(<a href='$c->{url}?o=$c->{op}&loc=$locparam'><span>Clear</span></a>) " .
      "<p>\n";
    }
    my $oldbeer = "$foundrec->{maker} : $foundrec->{name}";  # Remember current beer for opening
    $oldbeer =~ s/&[a-z]+;//g;  # Drop things like &amp;
    $oldbeer =~ s/[^a-z0-9]//ig; # and all non-ascii characters

    print "<table border=0 style='white-space: nowrap;'>\n";
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
      if ( $c->{qry} ) {
        next unless ( "$sty $mak $beer" =~ /$c->{qry}/ );
      }

      if ( $id != $previd +1 ) {
        print "<tr><td align=right>&nbsp;</td><td align=right>. . .</td></tr>\n";
      }
      my $thisbeer = "$mak : $beer";  # Remember current beer for opening
      $thisbeer =~ s/&[a-z]+;//g;  # Drop things like &amp;
      $thisbeer =~ s/[^a-z0-9]//gi; # and all non-ascii characters
      if ( $extraboard == -1 && $thisbeer eq $oldbeer ) {
        $extraboard = $id; # Default to expanding the beer currently in the input fields
      }
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
        $dispmak = filt($c, $mak, "i", $dispmak,"board&loc=$locparam","maker");
      }
      $beer =~ s/(Warsteiner).*/$1/;  # Shorten some long beer names
      $beer =~ s/.*(Hopfenweisse).*/$1/;
      $beer =~ s/.*(Ungespundet).*/$1/;
      if ( $beer =~ s/Aecht Schlenkerla Rauchbier[ -]*// ) {
        $mak = "Schlenkerla";
        $dispmak = filt($c, $mak, "i", $mak,"board&loc=$locparam");
      }
      my $dispbeer .= filt($c, $beer, "b", $beer, "board&loc=$loc");

      $mak =~ s/'//g; # Apostrophes break the input form below
      $beer =~ s/'//g; # So just drop them
      $sty =~ s/'//g;
      my $origsty = $sty ;
      $sty = shortbeerstyle($sty);
      print "<!-- sty='$origsty' -> '$sty'\n'$e->{'beer'}' -> '$beer'\n'$e->{'maker'}' -> '$mak' -->\n";
      # Add a comment to show the simplifying process.
      # If there are strange beers, take a 'view source' and look
      my $country = $e->{'country'} || "";
      my $sizes = $e->{"sizePrice"};
      my $locrec = db::findrecord($c,"LOCATIONS","Name",$locparam, "collate nocase");
      my $locid = $locrec->{Id};
      my $hiddenbuttons = "";
      if ( $sty =~ /Cider/i ) {
        $hiddenbuttons .= "<input type='hidden' name='type' value='Cider' />\n" ;
      } else {
        $hiddenbuttons .= "<input type='hidden' name='type' value='Beer' />\n" ;
      }
      $hiddenbuttons .= "<input type='hidden' name='country' value='$country' />\n"
        if ($country) ;
      $hiddenbuttons .= "<input type='hidden' name='maker' value='$mak' />\n" ;
      $hiddenbuttons .= "<input type='hidden' name='name' value='$beer' />\n" ;
      $hiddenbuttons .= "<input type='hidden' name='style' value='$origsty' />\n" ;
      $hiddenbuttons .= "<input type='hidden' name='subtype' value='$sty' />\n" ;
      $hiddenbuttons .= "<input type='hidden' name='alc' value='$alc' />\n" ;
      $hiddenbuttons .= "<input type='hidden' name='loc' value='$loc' />\n" ;
      $hiddenbuttons .= "<input type='hidden' name='Location' value='$locid' />\n" ;
      $hiddenbuttons .= "<input type='hidden' name='tap' value='$id#' />\n" ; # Signalss this comes from a beer board
      $hiddenbuttons .= "<input type='hidden' name='o' value='board' />\n" ;  # come back to the board display
      my $buttons="";
      #foreach my $sp ( sort( {($a->{"vol"} <=> $b->{"vol"}) || ($a->{"vol"} cmp $b->{"vol"}) } @$sizes) ) {
      while ( scalar(@$sizes) < 2 ) {
        push @$sizes, { "vol" => "", "price" => "" };
      }
      foreach my $sp ( @$sizes ) {
        my $vol = $sp->{"vol"} || "";
        my $pr = $sp->{"price"} || "";
        my $lbl;
        if ($extraboard == $id || $extraboard == -2) {
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
            $lbl = " ";
          }
          $buttons .= "<td>";
        }
        $buttons .= "<form method='POST' accept-charset='UTF-8' style='display: inline;' class='no-print' >\n";
        $buttons .= $hiddenbuttons;
        $buttons .= "<input type='hidden' name='vol' value='$vol' />\n" ;
        $buttons .= "<input type='hidden' name='pr' value='$pr' />\n" ;
        $buttons .= "<input type='submit' name='submit' value='$lbl'/> \n";
        $buttons .= "</form>\n";
        $buttons .= "</td>\n" if ($extraboard != $id && $extraboard != -2);
      }
      my $beerstyle = beercolorstyle($c, $origsty, "Board:$e->{'id'}", "[$e->{'type'}] $e->{'maker'} : $e->{'beer'}" );

      my $dispid = $id;
      $dispid = "&nbsp;&nbsp;$id"  if ( length($dispid) < 2);
      if ($extraboard == $id  || $extraboard == -2) { # More detailed view
        print "<tr><td colspan=5><hr></td></tr>\n";
        print "<tr><td align=right $beerstyle>";
        my $linkid = $id;
        if ($extraboard == $id) {
          $linkid = "-3";  # Force no expansion
        }
        print "<a href='$c->{url}?o=board$linkid&loc=$locparam'><span width=100% $beerstyle id='here'>$dispid</span></a> ";
        print "</td>\n";

        print "<td colspan=4 >";
        print "<span style='white-space:nowrap;overflow:hidden;text-overflow:clip;max-width=100px'>\n";
        print "$mak: $dispbeer ";
        print "<span style='font-size: x-small;'>($country)</span>" if ($country);
        print "</span></td></tr>\n";
        print "<tr><td>&nbsp;</td><td colspan=4> $buttons &nbsp;\n";
        print "<form method='POST' accept-charset='UTF-8' style='display: inline;' class='no-print' >\n";
        print "$hiddenbuttons";
        print "<input type='hidden' name='vol' value='T' />\n" ;  # taster
        print "<input type='hidden' name='pr' value='X' />\n" ;  # at no cost
        print "<input type='submit' name='submit' value='Taster ' /> \n";
        print "</form>\n";
        print "</td></tr>\n";
        print "<tr><td>&nbsp;</td><td colspan=4>$origsty <span style='font-size: x-small;'>$alc%</span></td></tr> \n";
        my $seenline = seenline ($c, $mak, $beer);
        if ($seenline) {
          print "<tr><td>&nbsp;</td><td colspan=4> $seenline";
          print "</td></tr>\n";
        }
          # TODO - Get rate counts from the database somehow
#         if ($ratecount{$seenkey}) {
#           my $avgrate = sprintf("%3.1f", $ratesum{$seenkey}/$ratecount{$seenkey});
#           print "<tr><td>&nbsp;</td><td colspan=4>";
#           my $rating = "rating";
#           $rating .= "s" if ($ratecount{$seenkey} > 1 );
#           print "$ratecount{$seenkey} $rating <b>$avgrate</b>: ";
#           print $ratings[$avgrate];
#         print "</td></tr>\n";
#         }
        print "<tr><td colspan=5><hr></td></tr>\n" if ($extraboard != -2) ;
      } else { # Plain view
        print "<tr><td align=right $beerstyle>";
        print "<a href='$c->{url}?o=board$id&loc=$locparam#here'><span width=100% $beerstyle>$dispid</span></a> ";
        print "</td>\n";
        print "$buttons\n";
        print "<td style='font-size: x-small;' align=right>$alc</td>\n";
        print "<td>$dispbeer $dispmak ";
        print "<span style='font-size: x-small;'>($country)</span> " if ($country);
        print "$sty</td>\n";
        print "</tr>\n";
      }
      $previd = $id;
    } # beer loop
    print "</table>\n";
    if (! $nbeers ) {
      print "Sorry, got no beers from $locparam\n";
      print "<!-- Error running " . $scrapers{$locparam} . ". \n";
      print "Result: '$json'\n -->\n";
    }
  }
  # Keep $c->{qry}, so we filter the big list too
  $c->{qry} = "" if ($c->{qry} =~ /PA/i );   # But not 'PA', it is only for the board
  print "<hr/>\n";
} # beerboard


################################################################################
# Small helpers
################################################################################

# Helper to make a link to a bar of brewery web page and/or scraped beer menu
sub loclink {
  my $c = shift;
  my $loc = shift;
  my $www = shift || "www";
  my $scrape = shift || "List";
  my $lnk = "";
  if (defined($scrapers{$loc}) && $scrape ne " ") {
    $lnk .= " &nbsp; <i><a href='$c->{url}?o=board&loc=$loc'><span>$scrape</span></a></i>" ;
  }
  if (defined($links{$loc}) && $www ne " ") {
    $lnk .= " &nbsp; <i><a href='" . $links{$loc} . "' target='_blank' ><span>$www</span></a></i>" ;
  }
  return $lnk
}

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
sub beercolor {
  my $rec = shift; # Can also be type
  my $prefix = shift || "0x";
  my $line = shift;
  my $type;
  if ( ref($rec) ) {
    $type = "$rec->{type},$rec->{subtype}: $rec->{style} $rec->{maker}";  # something we can match
    $line = $rec->{rawline};
  } else {
    $type = $rec;
  }
  my @drinkcolors = (   # color, pattern. First match counts, so order matters
      "003000", "restaurant", # regular bg color, no highlight
      "eac4a6", "wine[, ]+white",
      "801414", "wine[, ]+red",
      "4f1717", "wine[, ]+port",
      "aa7e7e", "wine",
      "f2f21f", "Pils|Lager|Keller|Bock|Helles|IPL",
      "e5bc27", "Classic|dunkel|shcwarz|vienna",
      "adaa9d", "smoke|rauch|sc?h?lenkerla",
      "350f07", "stout|port",  # imp comes later
      "1a8d8d", "sour|kriek|lambie?c?k?|gueuze|gueze|geuze|berliner",
      "8cf2ed", "booze|sc?h?nap+s|whisky",
      "e07e1d", "cider",
      "eaeac7", "weiss|wit|wheat|weizen",
      "66592c", "Black IPA|BIPA",
      "9ec91e", "NEIPA|New England",
      "c9d613", "IPA|NE|WC",  # pretty late, NE matches pilsNEr
      "d8d80f", "Pale Ale|PA",
      "b7930e", "Old|Brown|Red|Dark|Ale|Belgian||Tripel|Dubbel|IDA",   # Any kind of ales (after Pale Ale)
      "350f07", "Imp",
      "dbb83b", "misc|mix|random",
      );
      for ( my $i = 0; $i < scalar(@drinkcolors); $i+=2) {
        my $pat = $drinkcolors[$i+1];
        if ( $type =~ /$pat/i ) {
          return $prefix.$drinkcolors[$i] ;
        }
      }
      print STDERR "No color for '$line' \n";
      return $prefix."9400d3" ;   # dark-violet, aggressive pink
}

# Helper to return a style attribute with suitable colors for (beer) style
sub beercolorstyle {
  my $c = shift;
  my $rec = shift;  # Can also be style as text, see below
  my $line = shift; # for error logging
  my $type = "";
  my $bkg;
  if (ref($rec)) {
    $bkg= beercolor($rec,"#");
  } else {
    $type = $rec;
    $bkg= beercolor($type,"#",$line);
  }
  my $col = $c->{bgcolor};
  my $lum = ( hex($1) + hex($2) + hex($3) ) /3  if ($bkg =~ /^#?(..)(..)(..)/i );
  if ($lum < 64) {  # If a fairly dark color
    $col = "#ffffff"; # put white text on it
  }
  return "style='background-color:$bkg;color:$col;'";
} # beercolorstyle




################################################################################
# Tell Perl the module loaded fine
1;
