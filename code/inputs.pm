# Routines for input forms
package inputs;
use strict;
use warnings;

use feature 'unicode_strings';
use utf8;  # Source code and string literals are utf-8

use POSIX qw(strftime localtime locale_h);

my $clr = "Onfocus='value=value.trim();select();' autocapitalize='words'";

################################################################################
# Drop-down selection with filtering
################################################################################
# example:
#  dropdown( "location", $current_location_id, $current_location_name,
#    "<div class='dropdown-item' id='new'>(new)</div>\n" .
#    "<div class='dropdown-item' id='6'>Ølbaren</div>\n" .
#    ... );
# Omit the "new" line if you don't want it
# Returns a string ready to be printed in a form


sub dropdown {
  my $c             = shift;
  my $inputname     = shift;   # Name of the input field, e.g. 'loc'
  my $selectedid    = shift;   # Id of initially selected item
  my $selectedname  = shift;   # Name of initially selected item
  my $options       = shift;   # List of DIVs to select from
  my $tablename     = shift;   # Table for new record form
  my $newfieldprefix= shift;   # Prefix for new input fields
  my $skipnewfields = shift || "";
  my $disabled      = shift || "";   # "disabled" or ""
  my $enablescan    = shift || "";   # "scan" to enable barcode scanning
  my $multi         = shift || "";   # "multi" to enable chip multi-select
  my $prechips      = shift || "";   # pre-rendered chip HTML for multi-select edit

  my $newdiv = "";
  my $actions = "";
  
  # Build combined actions line if scan or new enabled
  if ($enablescan eq "scan") {
    $actions .= "<span class='action-link' data-action='scan' style='cursor: pointer;'>(scan)</span>";
  }
  if ($tablename) {
    $actions .= "<span class='action-link' data-action='new' style='cursor: pointer;'>(new)</span>";
    $newdiv  = "<div class='dropdown-new' id='newdiv-$inputname' hidden>\n";
    $newdiv .= inputform($c, $tablename, {}, $newfieldprefix, $inputname, "", $skipnewfields);
    $newdiv .= "</div>";
  }
  
  if ($actions) {
    $options = "<div class='dropdown-item' id='actions'>$actions</div>\n$options";
  }

  my $multiattr = $multi eq 'multi' ? " data-multi='1'" : "";
  my $chipsdiv  = $multi eq 'multi' ? "<div class='dropdown-chips'>$prechips</div>\n  " : "";
  my $s = <<"HTML";
<!-- DROPDOWN START: input='$inputname' -->
<div id="dropdown-$inputname" class="dropdown"$multiattr>
  $chipsdiv<div class="dropdown-main">
    <input type="text"
           class="dropdown-filter"
           autocomplete="off"
           placeholder="$inputname"
           value="$selectedname"
           $disabled />
    <input type="hidden"
           id="$inputname"
           name="$inputname"
           value="$selectedid" />
    <div class="dropdown-list">
      $options
    </div>
  </div>
  $newdiv
</div>
<script>initDropdown(document.getElementById('dropdown-$inputname'));</script>
<!-- DROPDOWN END: input='$inputname' -->
HTML

  return $s;
}


################################################################################
# Make a simple input form for a given table
################################################################################

sub inputform {
  my $c = shift;
  my $table = shift;
  my $rec = shift; # Current values
  my $inputprefix = shift || "";
  my $placeholderprefix = shift || "";
  my $separatortag = shift || "<br/>";
  my $skipfields = shift || "Id"; # regexp. "Id|HiddenField|AlsoThis"  "all" for showing all
  my $available_tags_ref = shift; # Optional: arrayref of all known tag strings for chip UI

  # Determine if we should disable fields (editing existing, not new)
  my $disabled = "";
  if ( $rec && $rec->{Id} && $rec->{Id} ne "new" && !$inputprefix ) {
    $disabled = "disabled";
  }

  my $form = "";
  if ( $inputprefix ) { # Subheader for included records
    my $hdr = $inputprefix;
    $hdr =~ s/^(new)(.)(.*)/"New " . uc($2). "$3:"/ge; # "newloc" -> "New Loc:"
    $form .= "<b>$hdr</b> $separatortag \n";
  }
  $form .= "<table>\n";
  foreach my $f ( db::tablefields($c,$table,$skipfields) ) {
    $form .= "<tr>\n";
    my $special = $1 if ( $f =~ s/^(\W)// );
    my $pl = $f;
    $pl =~ s/([A-Z])/ $1/g; # Break words GeoCoord -> Geo Coord
    $pl = util::trim($placeholderprefix .$pl);
    $pl =~ s/^([A-z])[a-z]+/$1/ if ( length($pl) > 20 );
    while ( length($pl) > 20 && $pl =~ s/([A-Z])([a-z]+)/$1/ ) { } ;  # Shorten pl
    #$pl .= $special if ($special) ;
    my $inpname = $inputprefix . $f;
    my $val = "";
    $val = "value='$rec->{$f}'" if ( $rec && defined($rec->{$f}) );
    if ( $special && $f ne "IsGeneric") {
      if ( $f =~ /Lat/ ) {
        $form .= geo::geolabel($c, $inputprefix);
      } else {
        $form .= "<td colspan=2>\n";
      }
    } else {
      $form .= "<td>$pl</td>\n";
    }
    if ( $special ) {
      if ( $f =~ /producerlocation/i ) {
        $form .= locations::selectlocation($c, $inputprefix.$f, $rec->{$f}, "prodloc", "prod", $disabled);
      } elsif ( $f =~ /location/i ) {
        if ( $inputprefix !~ /newperson/ ) {
          # Do no allow a relatedperson to have a location, conflicts with the persons own location
          $form .= locations::selectlocation($c, $inputprefix.$f, $rec->{$f}, "loc", "", $disabled);
        }
      } elsif ( $f =~ /person/i ) {
        if ( $inputprefix !~ /newperson/ ) {
          # Allow editing of RelatedPerson, but only on top level
          $form .= persons::selectperson($c, $inputprefix.$f, $rec->{$f}, "pers", "", $disabled);
          # Avoids endless recursion
        }
      } elsif ( $f =~ /Lat/i ) {
        $form .= geo::geoInput($c, $inputprefix, $rec->{Lat}, $rec->{Lon}, $disabled );
      } elsif ( $f =~ /Lon/i ) {
        # Both handled under Lat
      } elsif ( $f =~ /IsGeneric/i ) {
        $form .= "<td>\n";
        my $checked = "";
        $checked = "checked" if ($rec && $rec->{$f});
        $form .= "<input type=checkbox name='$f' $checked value='1' $disabled/>";
      } else  {
        util::error ( "inputform: Special field '$f' not handled yet");  # Sould not happen
      }
    } else {  # Regular input field
      if ( $f =~ /Barcode/i ) {
        # Special handling for barcode field - add scan link
        $form .= barcodeInput($c, $inpname, $rec->{$f}, $disabled );
      } elsif ( $f =~ /^Tags$/i && $available_tags_ref ) {
        my $tag_val = ($rec && defined($rec->{$f})) ? $rec->{$f} : "";
        $form .= tagsinput($c, $tag_val, $available_tags_ref, $disabled);
      } else {
        my $pass = "";
        if ( $f =~ /Alc/ ) {  # Alc field, but not in the glass itself
          # (that is lowercase 'alc'). Pass it to glass.alc
          $pass = "onInput=\"var a=document.getElementById('alc'); if(a) a.value=this.value; \"";
        }
        my $required = "";
        if ( $f =~ /Name|BrewType|SubType|LocType/i && $f !~ /OfficialName|FullName/i) {
          if ( $inputprefix ) {
            $required = "data-required='1'";
          } else {
            $required = "required";
          }
        }
        $form .= "<td>\n";
        $form .= "<input name='$inpname' $val $clr $pass $required $disabled/>\n";
        $form .= $separatortag;
      }
    }
    $form .= "</td></tr>\n";
  }
  $form .= "</table>\n";

  return $form;
} # inputform

################################################################################
# Tags chip input widget
################################################################################
# Renders current tags as removable chips, and all known tags as addable chips.
# $current   - space-separated string of current tag values (may be undef/"")
# $available - sorted arrayref of all distinct tag strings from the DB
# $disabled  - "disabled" or "" (controls initial locked state)
# Returns a <td>...</td> block (without closing </td> — parent adds it).
sub tagsinput {
  my $c         = shift;
  my $current   = shift // "";
  my $available = shift;   # arrayref
  my $disabled  = shift || "";

  my @current_tags   = grep { $_ } split /\s+/, $current;
  my $remove_hidden  = $disabled ? " hidden" : "";
  my $avail_hidden   = $disabled ? " hidden" : "";

  # Render current tags as chips
  my $chips = "";
  my $chip_count = 0;
  foreach my $tag (@current_tags) {
    my $esc = util::htmlesc($tag);
    $chips .= "<span class='chip-wrapper'>"
           .  "<span class='dropdown-chip'>"
           .  "<span class='chip-label'>$esc</span>"
           .  " <a class='chip-remove' href='#'$remove_hidden>&times;</a>"
           .  "</span>"
           .  "</span>\n";
    $chip_count++;
    $chips .= "<span class='tag-line-break'></span>\n" if ($chip_count % 5 == 0);
  }

  # Render available tags as addable chips
  my $avail_html = "";
  if ($available) {
    my %current_set = map { lc($_) => 1 } @current_tags;
    my $avail_count = 0;
    foreach my $tag (@$available) {
      my $esc  = util::htmlesc($tag);
      my $used = $current_set{lc($tag)} ? " used" : "";
      $avail_html .= "<span class='tag-available-chip$used' data-tag='$esc'>$esc</span>\n";
      $avail_count++;
      $avail_html .= "<span class='tag-line-break'></span>\n" if ($avail_count % 5 == 0);
    }
    $avail_html .= "<span class='tag-available-chip tag-new-btn'>(New tag)</span>\n";
    $avail_html .= "<span class='tags-new-field' hidden>"
               .  "<input type='text' class='tags-new-input' placeholder='new tag' autocomplete='off'/>"
               .  "<button type='button' class='tags-add-btn'>Add</button>"
               .  "</span>\n";
  }

  my $s = "<td>\n";
  $s .= "<div class='tags-input' id='tags-input-Tags'>\n";
  $s .= "  <div class='tags-current'>$chips</div>\n";
  if ($available) {
    $s .= "  <div class='tags-available'$avail_hidden>$avail_html</div>\n";
  }
  $s .= "  <input type='hidden' name='Tags' id='Tags' value='" . util::htmlesc($current) . "'/>\n";
  $s .= "</div>\n";
  $s .= "<script>initTagsInput(document.getElementById('tags-input-Tags'));</script>\n";
  # No closing </td> — parent (inputform) adds it
  return $s;
} # tagsinput

################################################################################
# Barcode input field with scan button
################################################################################

sub barcodeInput {
  my $c = shift;
  my $fieldname = shift || "Barcode";
  my $value = shift || "";
  my $disabled = shift || "";  # "disabled" or ""

  my $s = "";
  $s .= "<td>\n";
  $s .= "<input name='$fieldname' id='$fieldname' value='$value' $clr $disabled />\n";
  $s .= "<br>";
  my $hiddenclass = $disabled ? "class='barcode-scan-link' hidden" : "class='barcode-scan-link'";
  $s .= "<span onclick='startBarcodeScanning(\"$fieldname\")' $hiddenclass>&nbsp; (Scan)</span>\n";
  return $s;
} # barcodeInput

