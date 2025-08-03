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

# TODO SOON - Move the CSS away from here
# TODO - Refactor so that the javascript will not need variable named functions
# TODO - Move the javascript into its own routine

sub dropdown {
  my $c = shift;
  my $inputname = shift;   # Name of the input field, f.ex. 'loc'
  my $selectedid = shift,  # Id of the initially  selected item, '6'
  my $selectedname= shift; # Name of the initially selected item, 'Ølbaren'
  my $options = shift; # List of DIVs to select from
                #    "<div class='dropdown-item' id='4'>Home</div>\n".
                #    "<div class='dropdown-item' id='6'>Ølbaren</div>\n" ...
  my $tablename = shift;  # Table to grab input fields for new records. Empty if not
  my $newfieldprefix = shift; # Prefix for new input fields, f.ex. newloc
  my $skipnewfields = shift || "" ; # regexp. "Id|HiddenField|AlsoThis"

  my $s = "input='$inputname' sel='$selectedid' " .
     "seln='$selectedname' table='$tablename' newpref='$newfieldprefix' skip='$skipnewfields'";
  print STDERR "dropdown: $s \n";
  $s = "<!-- DROPDOWN START: $s -->\n";

  my $newdiv = "";
  if ($tablename) { # We want a way to add new records
    # Add an option to do so
    $options = "<div class='dropdown-item' id='new'>(new)</div>\n" . $options;
    $newdiv = "<div id='newdiv-$inputname' style='padding-left:10px;' hidden>\n";
    $newdiv .= inputform($c, $tablename, {}, $newfieldprefix, $inputname,"",$skipnewfields);
    $newdiv .= "</div>";
  }

  $s .= <<JSEND;
  <style>
        .dropdown-list {
            position: absolute;
            width: 100%;
            max-height: 300px;
            overflow-y: auto;
            border: 1px solid #ccc;
            z-index: 1000;
            background-color: $c->{bgcolor};
            display: none; /* Hidden by default */
        }
        .dropdown-item {
            cursor: pointer;
            padding: 3px;
        }
        .dropdown-item:hover {
            background-color: $c->{altbgcolor};
        }
    </style>
        $newdiv
        <div id="dropdown-$inputname" style="position:relative;width:100%;max-width:300px;">
        <input type="text" id="dropdown-filter-$inputname" autocomplete="off"
          style="width:100%" placeholder='$inputname' value='$selectedname' />
        <input type="hidden" id='$inputname' name='$inputname' value='$selectedid' >
        <div id="dropdown-list-$inputname" class="dropdown-list">
            $options
        </div>
    </div>

    <script>
        const filterinput$inputname = document.getElementById('dropdown-filter-$inputname');
        const hidinput$inputname = document.getElementById('$inputname');
        const dropdownList$inputname = document.getElementById('dropdown-list-$inputname');
        const wholedropdown$inputname = document.getElementById('dropdown-$inputname');
        const newdiv$inputname = document.getElementById('newdiv-$inputname');

        // Handle selection of a dropdown item
        dropdownList$inputname.addEventListener('click', event => {
            if (event.target.classList.contains('dropdown-item')) {
              filterinput$inputname.value = event.target.textContent;
              filterinput$inputname.oldvalue = "";
              hidinput$inputname.value = event.target.getAttribute("id");
              dropdownList$inputname .style.display = 'none';
              if (event.target.getAttribute("id") == "new" ) {
                wholedropdown$inputname.hidden = true;
                newdiv$inputname.hidden = false;
                const inputs = newdiv$inputname.querySelectorAll('[data-required="1"]');
                for (let i = 0; i < inputs.length; i++) {
                //if (inputs[i].offsetWidth || inputs[i].offsetHeight || inputs[i].getClientRects().length) {
                if (inputs[i].offsetParent != null ) {
                    // A trick to see if a field is visible
                    inputs[i].setAttribute('required', 'required');
                  } else {
                    inputs[i].removeAttribute("required");
                  }
                }
                document.querySelector('#newdiv-$inputname input')?.focus();
              } else { // update alc and brewtype if selected a brew
                const alcinp = document.getElementById("alc");
                const selalc = event.target.getAttribute("alc");
                if ( alcinp && selalc ) {
                  alcinp.value = selalc;
                  // console.log("Set alc " + selalc + " from brew ");
                }
              }
            }
        });

        // Show/hide dropdown based on filter focus
        filterinput$inputname.addEventListener('focus', () => {
            dropdownList$inputname .style.display = 'block';
            filterinput$inputname.oldvalue = filterinput$inputname.value;
            filterinput$inputname.value = "";
            filter$inputname();
        });

        filterinput$inputname.addEventListener('blur', () => {
            if ( filterinput$inputname.oldvalue ) {
              filterinput$inputname.value = filterinput$inputname.oldvalue;
            }
            // Delay hiding to allow click events on dropdown items
            setTimeout(() => {
                dropdownList$inputname .style.display = 'none';
            }, 200);
        });

        // Filter dropdown items
        function filter$inputname() {
            const selbrewtype = document.getElementById("selbrewtype");
            const filter = filterinput$inputname.value.toLowerCase();
            Array.from(dropdownList$inputname .children).forEach(item => {
                var brewtype = item.getAttribute("brewtype");
                var disp = ''; // default to showing it
                if ( selbrewtype && brewtype ) {
                  if ( selbrewtype.value != brewtype ) {
                    disp = 'none';
                    //console.log( "HIDE '" + item.textContent + "' type '" + brewtype + "' != '" + selbrewtype.value + "'" );
                  }
                }
                if (! item.textContent.toLowerCase().includes(filter) ) {
                  disp = 'none';
                  //console.log( "HIDE '" + item.textContent + "' filt '" + filter + "'" );
                }
                item.style.display = disp ;

            });
        };

        // Filter dropdown items as the user types
        filterinput$inputname.addEventListener('input', () => {
          filter$inputname();
        });

        // Handle Esc to close the dropdown
        filterinput$inputname.addEventListener("keydown", function(event) {
          if (event.key === "Escape" || event.keyCode === 27) {
          this.blur();
          }
        });

    </script>
JSEND
  $s .= "<!-- DROPDOWN END : input='$inputname' -->\n";

  return $s;
} # dropdown


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
        $form .= locations::selectlocation($c, $inputprefix.$f, $rec->{$f}, "prodloc", "prod");
      } elsif ( $f =~ /location/i ) {
        if ( $inputprefix !~ /newperson/ ) {
          # Do no allow a relatedperson to have a location, conflicts with the persons own location
          $form .= locations::selectlocation($c, $inputprefix.$f, $rec->{$f}, "loc");
        }
      } elsif ( $f =~ /person/i ) {
        if ( $inputprefix !~ /newperson/ ) {
          # Allow editing of RelatedPerson, but only on top level
          $form .= persons::selectperson($c, $inputprefix.$f, $rec->{$f}, "pers");
          # Avoids endless recursion
        }
      } elsif ( $f =~ /Lat/i ) {
        $form .= geo::geoInput($c, $inputprefix, $rec->{Lat}, $rec->{Lon} );
      } elsif ( $f =~ /Lon/i ) {
        # Both handled under Lat
      } elsif ( $f =~ /IsGeneric/i ) {
        $form .= "<td>\n";
        my $checked = "";
        $checked = "checked" if ($rec && $rec->{$f});
        $form .= "<input type=checkbox name='$f' $checked value='1'/>";
      } else  {
        util::error ( "inputform: Special field '$f' not handled yet");  # Sould not happen
      }
    } else {  # Regular input field
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
      $form .= "<input name='$inpname' $val $clr $pass $required/>\n";
      $form .= $separatortag;
    }
    $form .= "</td></tr>\n";
  }
  $form .= "</table>\n";

  return $form;
} # inputform

