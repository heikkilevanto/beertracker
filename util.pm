# Part of my beertracker
# Small helper routines

package util;
use strict;
use warnings;

################################################################################
# Table of contents
#  - Helpers for normalizing strings
#  - Helpers for cgi parameters
#  - Error handling and debug logging
#  - Pull-down menus for the Show menu and for selecting a list


################################################################################
# Helpers for normalizing strings
################################################################################


# Helper to trim leading and trailing spaces
sub trim {
  my $val = shift || "";
  $val =~ s/^ +//; # Trim leading spaces
  $val =~ s/ +$//; # and trailing
  $val =~ s/\s+/ /g; # and repeated spaces in the middle
  return $val;
}

# Helper to sanitize numbers
sub number {
  my $v = shift || "";
  $v =~ s/,/./g;  # occasionally I type a decimal comma
  $v =~ s/[^0-9.-]//g; # Remove all non-numeric chars
  $v =~ s/[-.]*$//; # No trailing '.' or '-', as in price 45.-
  $v = 0 unless $v;
  return $v;
}

# Sanitize prices to whole ints
sub price {
  my $v = shift || "";
  $v = number($v);
  $v =~ s/[^0-9-]//g; # Remove also decimal points etc
  return $v;
}

# Split date and weekday, convert weekday to text
# Get the date from Sqlite with a format like '%Y-%m-%d %w'
# The %w returns the number of the weekday.
sub splitdate {
  my $stamp = shift || return ( "(never)", "" );
  my ($date, $wd ) = split (' ', $stamp);
  my @weekdays = ( "Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun" );
  $wd = $weekdays[$wd];
  return ( $date, $wd );
}

################################################################################
# Helpers for cgi parameters
################################################################################

# Get a cgi parameter
sub param {
  my $c = shift;
  my $tag = shift;
  my $def = shift || "";
  my $val = $c->{cgi}->param($tag) || $def;
  $val =~ s/[^a-zA-ZñÑåÅæÆøØÅöÖäÄéÉáÁāĀ\/ 0-9.,&:\(\)\[\]?%-]/_/g;
  return $val;
}

sub paramnumber {
  my $c = shift;
  my $tag = shift;
  my $def = shift || "";
  my $val = param($c, $tag, $def);
  $val = number($val);
  return $val;
}

################################################################################
# Error handling and debug logging
################################################################################

# Helper to make an error message
sub error {
  my $msg = shift;
  print "\n\n";  # Works if have sent headers or not
  print "<hr/>\n";
  print "ERROR   <br/>\n";
  print $msg;
  print STDERR "ERROR: $msg\n";
  exit();
}

################################################################################
# Pull-down menus for the Show menu and for selecting a list
################################################################################


# The main "Show" menu
sub showmenu {
  my $c = shift; # context;
  my $s = "";
  $s .= " <select  style='width:4.5em;' " .
              "onchange='document.location=\"$c->{url}?\"+this.value;' >";
  $s .= "<option value='' >Show</option>\n";
  $s .= "<option value='o=full&' >Full List</option>\n";
  $s .= "<option value='o=Graph' >Graph</option>\n";
  $s .= "<option value='o=board' >Beer Board</option>\n";
  $s .= "<option value='o=Months' >Stats</option>\n";
  $s .= "<option value='o=Beer' >Lists</option>\n";
  $s .= "<option value='o=About' >About</option>\n";
  $s .= "</select>\n";
  $s .=  " &nbsp; &nbsp; &nbsp;";
  if ( $c->{op} && $c->{op} !~ /graph/i ) {
    $s .= "<a href='$c->{url}'><b>G</b></a>\n";
  } else {
    $s .= "<a href='$c->{url}?o=board'><b>B</b></a>\n";
  }
  return $s;
}

########## Menu for the various lists we have
sub listsmenu {
  my $c = shift or die ("No context for listsmenubar" );
  my $s = "";
  $s .= " <select  style='width:7em;' " .
              "onchange='document.location=\"$c->{url}?\"+this.value;' >";
  my @ops = ( "Beer",  "Brewery", "Wine", "Booze", "Location", "Restaurant", "Style", "Persons");
  for my $l ( @ops ) {
    my $sel = "";
    $sel = "selected" if ($l eq $c->{op});
    $s .= "<option value='o=$l' $sel >$l</option>\n"
  }
  $s .= "</select>\n";
  $s .= "<a href='$c->{url}?o=$c->{op}'><span>List</span></a> ";
  $s .= "&nbsp; &nbsp; &nbsp;";
  return $s;
} # listsmenubar


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
  my $inputname = shift;   # Name of the input field, f.ex. 'loc'
  my $selectedid = shift,  # Id of the initially  selected item, '6'
  my $selectedname= shift; # Name of the initially selected item, 'Ølbaren'
  my $options = shift; # List of DIVs to select from
                #    "<div class='dropdown-item' id='4'>Home</div>\n".
                #    "<div class='dropdown-item' id='6'>Ølbaren</div>\n" ...
  my $newfields = shift || ""; # List of input fields for the "new" option
                # ( "Name", "Address" );  Skip if not wanted

  my $clr = "Onfocus='value=value.trim();select();' autocapitalize='words'";

  my $newdiv = "";
  if ($newfields) { # We want a way to add new records
    # Add an option to do so
    $options = "<div class='dropdown-item' id='new'>(new)</div>\n" . $options;
    $newdiv = "<div id='newdiv-$inputname' hidden>\n";
    foreach my $newfield ( @{$newfields} ) {
      my $pl = $newfield;
      $pl =~ s/^[a-z]+//; # Skip any prefix line 'new' until uppercase letter
      $pl =~ s/([A-Z])/ $1/g; # Break words GeoCoord -> Geo Coord
      $newdiv .= "<input name='$newfield' placeholder='New $pl' $clr /><br/>\n";
    }
    $newdiv .= "</div>";
  }

  my $s = "";
  $s .= <<JSEND;
  <style>
        .dropdown-list {
            position: absolute;
            width: 100%;
            max-height: 200px;
            overflow-y: auto;
            border: 1px solid #ccc;
            z-index: 1000;
            display: none; /* Hidden by default */
        }
        .dropdown-item {
            cursor: pointer;
        }
        .dropdown-item:hover {
            background-color: #005000;
        }
    </style>
        $newdiv
        <div id="dropdown-$inputname" style="position:relative;width:100%;max-width:300px;">
        <input type="text" id="dropdown-input" autocomplete="off"
          style="width:100%" placeholder='(filter)' value='$selectedname' />
        <input type="hidden" id='$inputname' name='$inputname' value='$selectedid' >
        <div id="dropdown-list" class="dropdown-list">
            $options
        </div>
    </div>

    <script>
        const input = document.getElementById('dropdown-input');
        const hidinput = document.getElementById('$inputname');
        const dropdownList = document.getElementById('dropdown-list');
        const wholedropdown = document.getElementById('dropdown-$inputname');
        const newdiv = document.getElementById('newdiv-$inputname');

        // Handle selection of a dropdown item
        dropdownList.addEventListener('click', event => {
            if (event.target.classList.contains('dropdown-item')) {
              input.value = event.target.textContent;
              input.oldvalue = "";
              hidinput.value = event.target.getAttribute("id");
              dropdownList.style.display = 'none';
              if (event.target.getAttribute("id") == "new" ) {
                console.log("Opening the NEW input");
                wholedropdown.hidden = true;
                newdiv.hidden = false;
              }
            }
        });

        // Show/hide dropdown based on input focus
        input.addEventListener('focus', () => {
            dropdownList.style.display = 'block';
            input.oldvalue = input.value;
            input.value = "";
        });
        input.addEventListener('blur', () => {
            if ( input.oldvalue ) {
              input.value = input.oldvalue;
            }
            // Delay hiding to allow click events on dropdown items
            setTimeout(() => {
                dropdownList.style.display = 'none';
            }, 200);
        });

        // Filter dropdown items as the user types
        input.addEventListener('input', () => {
            const filter = input.value.toLowerCase();
            Array.from(dropdownList.children).forEach(item => {
                if (item.textContent.toLowerCase().includes(filter)) {
                    item.style.display = '';
                } else {
                    item.style.display = 'none';
                }
            });
        });

        // Handle Esc to close the dropdown
        input.addEventListener("keydown", function(event) {
          if (event.key === "Escape" || event.keyCode === 27) {
          this.blur();
          }
        });

    </script>

JSEND
  return $s;
}


################################################################################
# Report module loaded ok
1;
