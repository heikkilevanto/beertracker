# Part of my beertracker
# The main form for inputting a glass record, with all its extras
# And the routine to save it in the database

package glasses;
use strict;
use warnings;

use feature 'unicode_strings';
use utf8;  # Source code and string literals are utf-8

use JSON;

our %volumes = ( # Comment is not used any more.
  'T' => " 2", # Taster, sizes vary, always small"
  'G' => "16", # Glass of wine - 12 in places, at home 16 is more realistic"
  'S' => "25", # Small, usually 25"
  'M' => "33", # Medium, typically a bottle beer"
  'L' => "40", # Large, 40cl in most places I frequent"
  'C' => "44", # A can of 44 cl"
  'W' => "75", # Bottle of wine"
  'B' => "75", # Bottle of wine"
);

################################################################################
# Helper to decide if a glass is "empty"
# Canonical list: all empty glass types live here
################################################################################
my @empty_types = qw(Night Meal Restaurant Adjustment);
  # Night first, as it is most likely to be used on main list day summary line.

sub isemptyglass {
  my $type = shift // "";
  return grep { $type eq $_ } @empty_types;
}

# Returns HTML <option> elements for all empty glass types
sub emptyglass_options {
  return join('', map { "        <option value='$_'>$_</option>\n" } @empty_types);
}

# Returns a SQL-ready quoted, comma-separated list: "Restaurant","Night",...
sub emptyglass_sql_list {
  return join(', ', map { qq{"$_"} } @empty_types);
}

################################################################################
# Helper to select a brew type
################################################################################
# Selecting from glasses, not brews, so that we get 'empty' glasses as well,
# f.ex. "Restaurant"
sub selectbrewtype {
  my $c = shift;
  my $selected = shift || "";
  my $sql = "SELECT DISTINCT BrewType FROM Glasses WHERE BrewType != 'Adjustment'";
  my $sth = db::query($c, $sql);
  my $opts = "";
  while ( my $bt = $sth->fetchrow_array ) {
    my $em = "";
    $em = " data-isempty='1'" if (glasses::isemptyglass($bt));
    $opts .= "<div class='dropdown-item' id='$bt'$em>$bt</div>\n";
  }
  # If editing an Adjustment glass, add it to dropdown
  if ( $selected eq 'Adjustment' ) {
    $opts .= "<div class='dropdown-item' id='Adjustment'>Adjustment</div>\n";
  }
  my $s = inputs::dropdown($c, "selbrewtype", $selected, $selected, $opts,
    { simplenew => 1, required => 1 });
   return $s;
} # selectbrewtype

################################################################################
# Select a glass subtype
################################################################################
sub selectbrewsubtype {
  my $c = shift;
  my $rec = shift;
  my $sql = 'SELECT BrewType, SubType, MAX(timestamp) AS last_time
    FROM glasses
    WHERE BrewType IN (' . emptyglass_sql_list() . ')
    GROUP BY brewtype,SubType
    ORDER BY last_time DESC ';
  my $sth = db::query($c, $sql );
  my $opts = "";
  while ( my $bt = $sth->fetchrow_hashref ) {
    next unless ( $bt->{SubType} );
    my $sub   = util::htmlesc($bt->{SubType});
    my $btype = util::htmlesc($bt->{BrewType});
    $opts .= "<div class='dropdown-item' id='$sub' brewtype='$btype'>$sub</div>\n";
  }
  my $subtype = $rec->{SubType} || "";
  return inputs::dropdown($c, "selbrewsubtype", $subtype, $subtype, $opts,
    { simplenew => 1 });
} # selectbrewsubtype

################################################################################
# The input form
################################################################################
# This is a fairly small, but rather complex form. For now it is hard coded,
# without using the util::inputform helper, as almost every field has some
# special considerations.
sub maininputform {
  my $c = shift;
  my $cache_key = "maininputform:$c->{username}:$c->{op}:" . ($c->{edit} || 0);
  my $cached = cache::get($c, $cache_key);
  if ($cached) {
    print { $c->{log} } "maininputform: cache hit\n" if $c->{devversion};
    print $cached;
    return;
  }
  my $rec = findrec($c); # Get defaults, or the record we are editing
  $rec->{Id} = "" unless ( $rec->{Id} );

  # Formatting magic
  my $clr = "Onfocus='value=value.trim();select();' autocapitalize='words'";
  my $sz4 = "size='4' style='text-align:right' $clr";
  my $sz6 = "size='6'  $clr";
  my $sz8 = "size='8'  $clr";
  my $sz20 = "size='20' $clr";

  my $html = "\n<form method='POST' accept-charset='UTF-8' class='no-print' id='mainform' " .
             "onClick='setdate();' " .
             "enctype='multipart/form-data'>\n";
  $html .= "<table>\n";

  $html .= "<tr><td width='100px'>Id $rec->{Id}</td>\n";
  $html .= "<td>" ;
  my ($date,$time) = ( "", "");
  ($date,$time) = split ( ' ',$rec->{Timestamp} ) if ($rec->{Timestamp} );
  my ($rawdate, $rawtime) = ($date, $time);  # Save real values before leading-space marker
  if ( !$c->{edit} ) {
    $date =" $date";  # Mark the time as speculative
    $time =" $time";
  }
  $html .= "<input name='date' id='date' value='$date' data-rawval='$rawdate' " .
           "pattern=' ?([LlYy])?(\\d{4}-(0[1-9]|1[0-2])-(0[1-9]|[12]\\d|3[01]))?' " .
           "placeholder='YYYY-MM-DD' $sz8 /> &nbsp;\n";
           # Could not make alternative pattern work, so I use a sequence of L/Y
           # and a valid date. Note also the leading space
   $html .= "<input name='time' id='time' value='$time' data-rawval='$rawtime' " .
            "pattern='(?: ?(?:0[0-9]|1[0-9]|2[0-3])(?::?[0-5][0-9])?(?::?[0-5][0-9])?|-[0-9]+(?::[0-5][0-9])?)' ".
            "placeholder='HH:MM' $sz6/> &nbsp;\n";
   $html .= "<span id='help-trigger' class='help-link' title='Help for focused field'>?</span>\n";
  my $onclick = "onclick='selectNearest(\"#dropdown-Location\")'";
  $html .= "<tr><td $onclick>Location</td>\n";
  $html .= "<td>" . locations::selectlocation($c, "Location", $rec->{Location}, "newlocname", "non") .
    "</td></tr>\n";

  # Brew style
  $html .= "<tr><td width='100px' style='vertical-align:top; max-width:100px;'>" . selectbrewtype($c,$rec->{BrewType}) ."</td>\n";
  $html .= "<td>\n";

  # Brew, or  subtype
  my $hidesub = "";
  my $hidebrew = "";
  if (isemptyglass($rec->{BrewType}) ) {
    $hidebrew = "style=display:none";
  } else {
    $hidesub = "style=display:none";
  }
  $html .= "<span $hidesub data-empty=2>". selectbrewsubtype($c,$rec). "</span>";
  $html .= "<span $hidebrew data-empty=1>". brews::selectbrew($c,$rec->{Brew},$rec->{BrewType}). "</span>";
  $html .= "</td>\n";

  $html .= "</tr>\n";

  # Note for the glass
  my $hidenote = "hidden";
  my $rawnote = $rec->{Note} || "";  # Save before zeroing for non-edit mode
  $rec->{Note} = "" unless ( $c->{edit} );  # Do not inherit from previous
  $rec->{Barcode} = "" unless ( $c->{edit} );  # Do not inherit from previous
  my $barcode = $rec->{Barcode} || "";  # Barcode may be NULL in the DB
  if ( $c->{edit} ) {
    $hidenote = "";
  }
  my $tap = $rec->{Tap} || "";
  my $rawtap = $tap;  # Save before leading-space marker
  if ( !$c->{edit} ) {
    $tap = " $tap";
  }
   $html .= "<tr id='noteline' $hidenote><td>Tap <input name='tap' value='$tap' data-rawval='$rawtap' size='2' $clr/></td><td>\n";
   $html .= "<input name='note' placeholder='note' value='$rec->{Note}' data-note='$rawnote' size='20' onfocus='value=value.trim();select();' autocapitalize='sentences'/>\n";
   $html .= "</td></tr>\n";

   # Barcode for this glass, plus the override-checkbox for the brew code.
   # Hidden (behind "(more)") on new glasses, like note/geo.
   $html .= "<tr id='barcodeline' $hidenote><td>\n";
   $html .= "<label><input type='checkbox' name='setbrewcode' id='setbrewcode' /> Upd Br</label>\n";
   $html .= "</td><td>\n";
   $html .= "<input id='barcode' name='barcode' value='$barcode' " .
            "placeholder='Barcode' size='12' $clr/>\n";
   $html .= " <button type='button' onclick='startBarcodeScanning(\"barcode\")'>Scan</button>\n";
   $html .= "</td></tr>\n";

   my $hidedgeo = "hidden";
   if ( $c->{edit} ) {
     $hidedgeo = "";
   }
   $html .= "<tr id='georow' $hidedgeo><td>\n";
   $html .= "<label><input type='checkbox' name='updateGeo' id='updateGeo' /> Upd Geo</label>\n";
   $html .= "</td><td>\n";
   $html .= "<input name='geoLat' id='geoLat' placeholder='Lat' size='7' $clr />\n";
   $html .= "<input name='geoLon' id='geoLon' placeholder='Lon' size='7' $clr />\n";
   $html .= "</td></tr>\n";

   # (note toggle),  Vol, Alc, and Price
  $html .= "<tr>";
  my $notetxt = "(more)";
  $notetxt = "" if ( !$hidenote);
  $html .= "<td id='leftcol'><div id='notetag' onclick='shownote();'>$notetxt</div></td>";
  $html .= "<td id='avp' >\n";
  my $vol = $rec->{Volume} || "";
  $vol .= "c" if ($vol);
  $html .= "<input name='vol' id='vol' placeholder='vol' $sz4 value='$vol' data-empty=1 />\n";
  my $alc = $rec->{Alc} || "";
  $alc .= "%" if ($alc);
  $html .= "<input name='alc' id='alc' placeholder='alc' $sz4 value='$alc' data-empty=1 />\n";
  my $pr = $rec->{Price} // "";
  $pr .= ".-" if ($pr && $pr > 0);
   $html .= "<input name='pr' id='pr' placeholder='pr' $sz4 value='$pr' />\n";
   $html .= "</td></tr>\n";

  # Buttons
  $html .= "<tr style='white-space:nowrap'><td>\n";
  $html .= " <input type='hidden' name='o' value='$c->{op}' />\n";
  if ($c->{edit}) {
    $html .= " <input type='hidden' name='e' value='$rec->{Id}' />\n";
    $html .= " <input type='submit' name='submit' value='Save' id='save' />\n";
    $html .= "</td><td>\n";
    $html .= " <input type='submit' name='submit' value='Del' formnovalidate />\n";
    $html .= "<a href='$c->{url}?o=$c->{op}' ><span>cancel</span></a>";
  } else { # New glass
    $html .= " <input type='hidden' name='e' id='edit-e' value='$rec->{Id}' disabled/>\n";
    $html .= "<span id='new-buttons'><input type='submit' name='submit' value='Record'/></span>\n";
    $html .= "<span id='edit-buttons' style='display:none'><input type='submit' name='submit' value='Save' id='save'/></span>\n";
    $html .= "</td><td>\n";
    $html .= "<span id='new-buttons-right'>\n";
    $html .= " <input type='button' value='Clr' onclick='clearinputs()'/>\n";
    $html .= " <input type='button' value='Edit' onclick='editrecord()'/>\n";
    $html .= "</span>\n";
    $html .= "<span id='edit-buttons-right' style='display:none'>\n";
    $html .= " <input type='submit' name='submit' value='Del' formnovalidate/>\n";
    $html .= " <a href='$c->{url}?o=$c->{op}'><span>cancel</span></a>\n";
    $html .= "</span>\n";
  }
  $html .= "<label data-empty=2 style='font-size:small; margin-left:0.5em;'><input type='checkbox' name='addcomment' id='addcomment' /> comment</label>\n";
  $html .= "&nbsp;" ;
  $html .= "</td></tr>\n";
  $html .= "</table>\n";
  $html .= "</form>\n";
  if ($c->{edit}) {
    $html .= photos::photo_form($c, glass => $rec->{Id},
        return_url => "$c->{url}?o=$c->{op}&e=$rec->{Id}") . "\n";
  }
  $html .= comments::listcomments($c, $rec->{Id}, $rec->{Brew}, $rec->{Location}, $rec->{BrewType});
  $html .= "<hr/>";

  # Javascript trickery
  # The barcode map drives scanning: barcode -> {brew, vol, price, alc, def}.
  $html .= "<script id='barcode-map' type='application/json'>" . barcodemap($c) . "</script>\n";
  $html .= "<script defer>initGlassForm();</script>\n";
  cache::set($c, $cache_key, $html);
  print $html;
} # maininputform


################################################################################
# Helper to get the latest glasss record for editing or defaults
################################################################################
sub findrec {
  my $c = shift;
  my $id = $c->{edit};
  if ( ! $id ) {  # Not editing, just get the latest
    my $sql = "SELECT id FROM glasses " .
              "WHERE username = ? " .
              "ORDER BY timestamp DESC ".
              "LIMIT 1";
    ($id) = db::queryarray($c, $sql, $c->{username});
  }
  my $sql = "SELECT * FROM glasses " .
            "WHERE id = ? AND username = ? ";
  my $rec = db::queryrecord($c, $sql, $id, $c->{username});
  return $rec;
}

################################################################################
# Embedded barcode map for the main input form
# barcode -> {brew, vol, price, alc, def} where def is the brew's current
# default Barcode ("" if none). Built per render from the latest own glass per
# (Brew, Barcode), plus every brews.Barcode fallback. Per user: glasses are
# per-user; brews are shared.
################################################################################
sub barcodemap {
  my $c = shift;
  my %map;
  # Latest own glass per (Brew, Barcode) gives the vol/price/alc per code,
  # plus the brew's current default code (def) via LEFT JOIN — a glass whose
  # brew has no default code stays in the map with def="".
  my $sql = "SELECT g.Brew, g.Barcode, g.Volume, g.Price, g.Alc, " .
            "b.Barcode AS DefBarcode FROM glasses g " .
            "LEFT JOIN brews b ON b.Id = g.Brew " .
            "WHERE g.Username = ? AND g.Barcode IS NOT NULL AND g.Barcode != '' " .
            "ORDER BY g.Timestamp DESC";
  my $sth = db::query($c, $sql, $c->{username});
  while ( my $row = $sth->fetchrow_hashref ) {
    my $key = $row->{Barcode};
    next if ( exists $map{$key} );  # First (latest) row per (Brew, Barcode)
    $map{$key} = {
      brew  => $row->{Brew},
      vol   => $row->{Volume},
      price => $row->{Price},
      alc   => $row->{Alc},
      def   => $row->{DefBarcode} // "",
    };
  }
  # Brew fallbacks: each brew's code is the seed/fallback, plus its defaults.
  my $sql2 = "SELECT Id, Barcode, DefVol, DefPrice, Alc FROM brews " .
             "WHERE Barcode IS NOT NULL AND Barcode != ''";
  my $sth2 = db::query($c, $sql2);
  while ( my $brew = $sth2->fetchrow_hashref ) {
    # Add a fallback entry for the brew's own code, unless already in the map
    if ( !exists $map{$brew->{Barcode}} ) {
      $map{$brew->{Barcode}} = {
        brew  => $brew->{Id},
        vol   => $brew->{DefVol},
        price => $brew->{DefPrice},
        alc   => $brew->{Alc},
        def   => $brew->{Barcode},
      };
    }
  }
  return JSON->new->pretty->encode(\%map);
} # barcodemap

################################################################################
# Report module loaded ok
1;
