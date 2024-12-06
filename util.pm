# Part of my beertracker
# Small helper routines

package util;
use strict;
use warnings;

use feature 'unicode_strings';
use utf8;  # Source code and string literals are utf-8

use POSIX qw(strftime localtime locale_h);

################################################################################
# Table of contents
# Helpers for normalizing strings
# Helpers for date and timestamps
# Helpers for cgi parameters
# Error handling and debug logging
# Drop-down menus for the Show menu and for selecting a list
# Drop-downs for selecting a value from a list (location, brew, etc)
# Helpers for input forms
# Database helpers


# Small stuff for input fields
my $clr = "Onfocus='value=value.trim();select();' autocapitalize='words'";



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
  if (defined($wd)) {
    my @weekdays = ( "Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun" );
    $wd = $weekdays[$wd];
  }
  return ( $date, $wd || "" );
}


################################################################################
# Helpers for date and timestamps
################################################################################

# Helper to get a date string, with optional delta (in days)
sub datestr {
  my $form = shift || "%F %T";  # "YYYY-MM-DD hh:mm:ss"
  my $delta = shift || 0;  # in days, may be fractional. Negative for ealier
  my $exact = shift || 0;  # Pass non-zero to use the actual clock, not starttime
  my $starttime = time();
  my $clockhours = strftime("%H", localtime($starttime));
  $starttime = $starttime - $clockhours*3600 + 12 * 3600;
    # Adjust time to the noon of the same date
    # This is to fix dates jumping when script running close to miodnight,
    # when we switch between DST and normal time. See issue #153
  my $usetime = $starttime;
  if ( $form =~ /%T/ || $exact ) { # If we want the time (when making a timestamp),
    $usetime = time();   # base it on unmodified time
  }
  my $dstr = strftime ($form, localtime($usetime + $delta *60*60*24));
  return $dstr;
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
# Drop-down menus for the Show menu and for selecting a list
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

# TODO - Reset the filter when blurring the field
# Otherwise it gets remembered, but not displayed when opening again

# TODO SOON - Move the CSS away from here

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


  my $newdiv = "";
  if ($tablename) { # We want a way to add new records
    # Add an option to do so
    $options = "<div class='dropdown-item' id='new'>(new)</div>\n" . $options;
    $newdiv = "<div id='newdiv-$inputname' hidden>\n";
    $newdiv .= inputform($c, $tablename, {}, $newfieldprefix, $inputname);
    $newdiv .= "</div>";
  }

  my $s = "";
  $s .= <<JSEND;
  <style>
        .dropdown-list {
            position: absolute;
            width: 100%;
            max-height: 300px;
            overflow-y: auto;
            border: 1px solid #ccc;
            z-index: 1000;
            display: none; /* Hidden by default */
        }
        .dropdown-item {
            cursor: pointer;
            padding: 3px;
        }
        .dropdown-item:hover {
            background-color: #005000;
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
              } else { // update alc if selected a brew
                const alcinp = document.getElementById("alc");
                const selalc = event.target.getAttribute("alc");
                if ( alcinp && selalc ) {
                  alcinp.value = selalc;
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
                if (item.textContent.toLowerCase().includes(filter) &&
                    (selbrewtype && brewtype && brewtype == selbrewtype.value ) ) {
                    item.style.display = '';
                } else {
                    item.style.display = 'none';
                }
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
  return $s;
}


################################################################################
# Helpers for input forms
################################################################################

####### Make a simple input form for a given table
# Makes a list of input fields
sub inputform {
  my $c = shift;
  my $table = shift;
  my $rec = shift; # Current values
  my $inputprefix = shift || "";
  my $placeholderprefix = shift || "";
  my $separatortag = shift || "<br/>";
  my $skipfields = shift || "";
  my $form = "";
  foreach my $f ( tablefields($c,$table) ) {
    my $special = $1 if ( $f =~ s/^(\W)// );
    my $pl = $f;
    $pl =~ s/([A-Z])/ $1/g; # Break words GeoCoord -> Geo Coord
    $pl = trim($placeholderprefix .$pl);
    $pl .= $special if ($special) ;
    my $inpname = $inputprefix . $f;
    my $val = "";
    $val = "value='$rec->{$f}'" if ( $rec && $rec->{$f} );
    if ( $special ) {  # Special field, needs a dropdown
      if ( $f =~ /location/i ) {
        $form .= locations::selectlocation($c, $f, $rec->{$f}, "loc");
      } elsif ( $f =~ /person/i ) {
        if ( $inputprefix !~ /newperson/ ) {
          # Allow editing of RelatedPerson, but only on top level
          $form .= persons::selectperson($c, $f, $rec->{$f}, "pers");
        }
      } elsif ( $f =~ /brewtype/i ) {
        $val = $val || param($c, "selbrewtype") || "Cider" ;
        $val = "value='$val'";
        print STDERR "inputform: brew type '$f' is now '$val' \n";
        # TODO - That Cider is just a placeholder for missing types
        # They would crash otherwise. Seems not to work
      } else {
        $form .= "$f not handled yet";
      }
    } else {  # Regular input field
      my $pass = "";
      if ( $f =~ /Alc/ ) {  # Alc field, but not in the glass itself
        # (that is lowercase 'alc'). Pass it to glass.alc
        $pass = "onInput=\"var a=document.getElementById('alc'); if(a) a.value=this.value; \"";
      }
      $form .= "<input name='$inpname' $val placeholder='$pl' $clr $pass />\n";
      $form .= $separatortag;
    }
  }
  return $form;
} # inputform

################################################################################
# Database helpers
################################################################################

########## Get all field names for a table
sub tablefields {
  my $c = shift;
  my $table = shift;
  my $skips = shift; # Regexp for fields to skip. "Id|UnWanted|Field"
  my $nomark = shift || ""; # 1 to skip marking integer fields
  $skips = "Id" unless defined($skips);

  my $sql = "PRAGMA table_info($table)";
  my $list_sth = $c->{dbh}->prepare($sql);
  $list_sth->execute();
  my @fields;
  while ( my ($cid, $name, $type, $notnull, $def, $pk )  = $list_sth->fetchrow_array ) {
    next if ( $skips && $name =~ /^$skips$/ );
    $name = "-$name" if ( $type eq "INTEGER" && !$nomark );  # Mark those that point to other tables
    push @fields, $name ;
  }
  return @fields;
}

######### Insert a record directly from CGI parameters
# Takes the field names from the table.
# Expects cgi inputs with same names with a prefix
sub insertrecord {
  my $c = shift;
  my $table = shift;
  my $inputprefix = shift || "";  # "newloc" means inputs are "newlocName" etc
  my $defaults = shift || {};

  my @sqlfields; # field names in sql
  my @values; # values to insert, in the same order
  for my $f ( tablefields($c, $table)) {
    my $val = param($c, $inputprefix.$f );
    if ( !$val ) {
      $val =  $defaults->{$f} || "";
      print STDERR "insertrecord: '$f' defaults to '$val' \n";
    }
    if ( $val ) {
      push @sqlfields, $f;
      push @values, $val;
    }
  }
  my $fieldlist = "(" . join( ", ", @sqlfields ) . " )";
  my $qlist = $fieldlist;
  $qlist =~ s/\w+/?/g; # Make a list like ( ?, ?, ?)
  my $sql = "insert into $table $fieldlist values $qlist";
  print STDERR "insertrecord: $sql \n";
  print STDERR "insertrecord: " . join (", ", @values ) . "\n";
  my $sth = $c->{dbh}->prepare($sql);
  $sth->execute( @values );
  my $id = $c->{dbh}->last_insert_id(undef, undef, $table, undef) || undef;
  print STDERR "Inserted $table id '$id' ". join (", ", @values ). " \n";
  return $id;
} # insertrecord

########## Update a record directly from CGI parameters
sub updaterecord {
  my $c = shift;
  my $table = shift;
  my $id = shift;
  my $inputprefix = shift || "";  # "newloc" means inputs are "newlocName" etc

  my @sets;
  my @values;
  for my $f ( tablefields($c, $table)) {
    my $special = $1 if ( $f =~ s/^(-)// );
    my $val = param($c, $inputprefix.$f );
    print STDERR "updaterecord: '$f' = '$val' \n";
    if ( $special ) {
      print STDERR "updaterecord: Met a special field '$f' \n";
      if ( $val eq "new" ) {
        print STDERR "updaterecord: Should insert a new $f \n";
        if ( $f =~ /location/i ) {
          $val = insertrecord($c, "LOCATIONS", "newloc");
        } elsif ( $f =~ /location/i ) {
          $val = insertrecord($c, "BREWS", "newbrew");
        } elsif ( $f =~ /person/i ) {
          $val = insertrecord($c, "PERSONS", "newperson");
        } else {
          print STDERR "updaterecord: Don't know how to insert a '$f' \n";
          $val = "TODO";
        }
      }
    }
    if ( $val ) {
      push @sets , "$f = ?";
      push @values, $val;
      print STDERR "updaterecord: $f = '$val' \n";
    }
  }
  my $sql = "update $table set " .
    join( ", ", @sets) .
    " where id = ?";
  print STDERR "updaterecord: $sql \n";
  print STDERR "updaterecord: " . join(", ", @values) . " \n";
  my $sth = $c->{dbh}->prepare($sql);
  $sth->execute( @values, $id );
   print STDERR "Updated " . $sth->rows .
      " $table records for id '$id' : " . join(", ", @values) ." \n";
} # updaterecord

############ Produce a list of records
# Has some heuristics for adjusting the display for some selected fields
# Tune these here or in the view definition
sub listrecords {
  my $c = shift;
  my $table = shift;
  my $sort = shift;

  my @fields = tablefields($c, $table, "", 1);
  my $order = "";
  for my $f ( @fields ) {
    $order = "Order by $f" if ( $sort =~ /$f(-?)/ );
    $order .= " DESC" if ($1);
    # Note, no user-provided data goes into $order, only field names and DESC
  }

  my $sql = "select * from $table $order";
  print STDERR "listrecords: $sql \n";
  my $list_sth = $c->{dbh}->prepare($sql);
  $list_sth->execute();

  my $url = $c->{url};
  my $op = $c->{op};

  my $s = "";
  # Table headers
  $s .= "<table><tr>\n";
  for my $f ( @fields ) {
    $f =~ s/^-//;
    my $sf = $f;
    $sf .= "-" if ( $f eq $sort );
    $s .= "<td><a href='$url?o=$op&s=$sf'><i>$f</i></a></td>";
  }
  $s .= "</tr>";

  while ( my @rec = $list_sth->fetchrow_array ) {
    $s .= "<tr>\n";
    for ( my $i=0; $i < scalar( @rec ); $i++ ) {
      my $v = $rec[$i] || "";
      my $fn = $fields[$i];
      my $sty = "style='max-width:200px'"; # default
      if ( $fn eq "Id" ) {
        $sty = "style='font-size: xx-small' align='right'";
      } elsif ( $fn eq "Name" ) {
        $v = "<a href='$url?o=$op&e=$rec[0]'><b>$v</b></a>";
      } elsif ( $fn eq "Sub" ) {
        $v = "[$v]" if ($v);
      } elsif ( $fn eq "Type" ) {
        $v =~ s/[ ,]*$//;
        $v = "[$v]" if ($v);
      } elsif ( $fn eq "Last" ) {
        my ($date, $wd) = util::splitdate($v);
        $v = "$date $wd";
      }
      $s .= "<td $sty>$v</td>\n";
    }
    $s .= "</tr>";
  }
  $s .= "</table>\n";

}

################################################################################
# Report module loaded ok
1;
