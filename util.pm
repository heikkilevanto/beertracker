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
  my $stamp = shift || return ( "(never)", "", "" );
  my ($date, $wd, $time ) = split (' ', $stamp);
  if (defined($wd)) {
    my @weekdays = ( "Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun" );
    $wd = $weekdays[$wd];
  }
  return ( $date, $wd || "", $time || "" );
}

# helper to make a unit displayed in smaller font
sub unit {
  my $v = shift;
  my $u = shift || "XXX";  # Indicate missing units so I see something is wrong
  return "" unless $v;
  return "$v<span style='font-size: xx-small'>$u</span> ";
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
} # datestr


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
  print "$msg <br/>\n";
  print STDERR "ERROR: $msg\n";
  my $i = 0;
  while (my($pkg,$fname,$lineno,$subroutine) = caller($i++)) {
    my $s = "  [$i]: $pkg:$lineno: $subroutine";
    print "$s  <br/>\n";
    print STDERR "$s \n";
  }
  exit();
}

# Helper to get version info
# Takes a relative dir path, defaults to the current one
# A bit tricky code, but seems to work
sub getversioninfo {
    my ($file, $namespace) = @_;
    $file = "$file/VERSION.pm";
    $namespace ||= 'VersionTemp' . int(rand(1000000));

    my $code = do {
        open my $fh, '<', $file or die "Can't open $file: $!";
        local $/;
        <$fh>;
    };

    # Replace package name with unique one
    $code =~ s/\bpackage\s+Version\b/package $namespace/;

    my $full = "package main; no warnings; eval q{$code};";
    my $ok = eval $full;
    die "Error loading $file: $@" if $@;

    no strict 'refs';
    my $func = "${namespace}::version_info";
    return $func->();
}

################################################################################
# Drop-down menus for the Show menu and for selecting a list
################################################################################

# The top bar, on every page
sub topline {
  my $c = shift; # context;
  my $s = "";
  $s .= "Beertracker";
  if ( $c->{devversion} ) {
    $s .= "-DEV";
  }
  my $v = Version::version_info();
  $s .= "&nbsp;\n";
  $s .= "$v->{tag}+$v->{commits}";
  $s .= "+" if ($v->{dirty});
  $s .= "&nbsp;\n";
  $s .= showmenu($c);
  $s .= "<hr>\n";
} # topline

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
  $s .= "<option value='o=Brew' >Brews</option>\n";
  $s .= "<option value='o=Location' >Locations</option>\n";
  $s .= "<option value='o=Comment' >Comments</option>\n";
#  $s .= "<option value='o=Style' >Styles</option>\n";  # Disabled, see #417
  $s .= "<option value='o=Person' >Persons</option>\n";
  $s .= "<option value='o=About' >About</option>\n";
  if ( $c->{devversion} ) {
    $s .= "<option value='o=copyproddata'>Get Production Data</option>\n";
  }
  $s .= "</select>\n";
#  $s .=  " &nbsp; &nbsp; &nbsp;";
#  if ( $c->{op} && $c->{op} !~ /graph/i ) {
#    $s .= "<a href='$c->{url}'><b>G</b></a>\n";
#  } else {
#    $s .= "<a href='$c->{url}?o=board'><b>B</b></a>\n";
#  }

  return $s;
}



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
                const inputs = newdiv$inputname.querySelectorAll('[data-required="1"]');
                for (let i = 0; i < inputs.length; i++) {
                  inputs[i].setAttribute('required', 'required');
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
  my $skipfields = shift || "Id"; # regexp. "Id|HiddenField|AlsoThis"  "all" for showing all

  my $form = "";
  if ( $inputprefix ) { # Subheader for included records
    my $hdr = $inputprefix;
    $hdr =~ s/^(new)(.)(.*)/"New " . uc($2). "$3:"/ge; # "newloc" -> "New Loc:"
    $form .= "<b>$hdr</b> $separatortag \n";
  }
  $form .= "<table>\n";
  foreach my $f ( tablefields($c,$table,$skipfields) ) {
    $form .= "<tr>\n";
    my $special = $1 if ( $f =~ s/^(\W)// );
    my $pl = $f;
    $pl =~ s/([A-Z])/ $1/g; # Break words GeoCoord -> Geo Coord
    $pl = trim($placeholderprefix .$pl);
    $pl =~ s/^([A-z])[a-z]+/$1/ if ( length($pl) > 20 );
    while ( length($pl) > 20 && $pl =~ s/([A-Z])([a-z]+)/$1/ ) { } ;  # Shorten pl
    $pl .= $special if ($special) ;
    my $inpname = $inputprefix . $f;
    my $val = "";
    $val = "value='$rec->{$f}'" if ( $rec && $rec->{$f} );
    if ( $special ) {
      $form .= "<td colspan=2>\n";
    } else {
      $form .= "<td>$pl</td>\n";
    }
    if ( $special && $f =~ /producerlocation/i ) {
      $form .= locations::selectlocation($c, $inputprefix.$f, $rec->{$f}, "prodloc", "prod");
    } elsif ( $special && $f =~ /location/i ) {
      if ( $inputprefix !~ /newperson/ ) {
        # Do no allow a relatedperson to have a location, comflicts with the persons own location
        $form .= locations::selectlocation($c, $inputprefix.$f, $rec->{$f}, "loc");
      }
    } elsif ($special && $f =~ /person/i ) {
      if ( $inputprefix !~ /newperson/ ) {
        # Allow editing of RelatedPerson, but only on top level
        $form .= persons::selectperson($c, $inputprefix.$f, $rec->{$f}, "pers");
        # Avoids endless recursion
      }
    } elsif ( $special ) {
      util::error ( "inputform: Special field '$f' not handled yet");  # Sould not happen
    } else {  # Regular input field
      my $pass = "";
      if ( $f =~ /Alc/ ) {  # Alc field, but not in the glass itself
        # (that is lowercase 'alc'). Pass it to glass.alc
        $pass = "onInput=\"var a=document.getElementById('alc'); if(a) a.value=this.value; \"";
      }
      my $required = "";
      if ( $f =~ /Name|BrewType|SubType|LocType/i && $f !~ /OfficialName/i) {
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
# TODO - The recursion does not yet handle all possible types
sub insertrecord {
  my $c = shift;
  my $table = shift;
  my $inputprefix = shift || "";  # "newloc" means inputs are "newlocName" etc
  my $defaults = shift || {};

  my @sqlfields; # field names in sql
  my @values; # values to insert, in the same order
  for my $f ( tablefields($c, $table,undef,1)) {  # 1 indicates no -prefix
    my $val = param($c, $inputprefix.$f );
    print STDERR "insertrecord: '$inputprefix' '$f' got value '$val' \n";
    if ( !$val ) {
      $val =  $defaults->{$f} || "";
      print STDERR "insertrecord: '$f' defaults to '$val' \n" if ($val);
    }
    if ( $val eq "new" ) {
      if ( $f eq "ProducerLocation" ) {
        print STDERR "Recursing to ProducerLocation ($inputprefix) \n";
        my $def = {};
        $def->{LocType} = "Producer";
        $def->{LocSubType} = util::param($c, "selbrewtype") || "Beer";
        $val = insertrecord($c, "LOCATIONS", "newprod", $def );
        print STDERR "Returned from ProducerLocation, id='$val'  \n";
      } elsif ( $f eq "Location" ) {
        print STDERR "Recursing to Location ($inputprefix) \n";
        my $def = {};
        $val = insertrecord($c, "LOCATIONS", "newloc", $def );
        print STDERR "Returned from Location, id='$val'  \n";
      } elsif ( $f eq "RelatedPerson" ) {
        print STDERR "Recursing to RelatedPerson ($inputprefix) \n";
        my $def = {};
        $val = insertrecord($c, "PERSONS", "newperson", $def );
        print STDERR "Returned from NewPerson, id='$val'  \n";
      }
      else {
        error ("insertrecord can not yet handle recursion to this type. p='$inputprefix' f='$f' ");
      }
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
  error("insertrecord: Nothing to insert into $table") unless @values;
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

  error ( "Can not update a $table record without id ") unless ($id) ;
  error ( "Bad id '$id' for updating a $table record ") unless ( $id =~ /^\d+$/ );
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

################### Delete a record
sub deleterecord {
  my $c = shift;
  my $table = shift;
  my $id = shift;
  my $sql = "delete from $table " .
    " where id = ?";
  print STDERR "deleterecord: $sql '$id' \n";
  my $sth = $c->{dbh}->prepare($sql);
  $sth->execute( $id );
   print STDERR "Deleted " . $sth->rows .
      " $table records for id '$id' \n";
} # deleterecord


############################## post a record.
#Looks at the submit parameter to decide to insert, update, or
# delete a record. The submit label must start with the operation name
# Assumes $c->{edit} has a proper id for ops that need one
sub postrecord {
  my $c = shift;
  my $table = shift;
  my $inputprefix = shift || "";  # "newloc" means inputs are "newlocName" etc
  my $defaults = shift || {};

  my $sub = param($c,"submit");
  if ($sub =~ /^Update/i || $c->{edit} =~ /^New/i ) {
    updaterecord( $c, $table, $c->{edit}, $inputprefix);
  } elsif ( $sub =~ /^Create|^Insert/i ) {
    $c->{edit} = insertrecord( $c, $table, $inputprefix, $defaults);
  } elsif ($sub =~ /Delete/i ) {
    deleterecord( $c, $table, $c->{edit});
    $c->{edit} = "";
  }
}


############ Get a single record by Id
sub getrecord {
  my $c = shift;
  my $table = shift;
  my $id = shift;
  return undef unless ($id);
  my $sql = "select * from $table where id = ? ";
  my $sth = $c->{dbh}->prepare($sql);
  $sth->execute($id);
  my $rec = $sth->fetchrow_hashref;
  $sth->finish;
  my $name = $rec->{Name} || "";
  print STDERR "getrecord: $sql '$id' -> '$name'\n";
  return $rec;
} # getrecord

############ Find a single record by a given field
sub findrecord {
  my $c = shift;
  my $table = shift;
  my $field = shift;
  my $val = shift;
  my $collate = shift || "";
  return undef unless ($val);
  my $sql = "select * from $table where $field = ? $collate";
  my $sth = $c->{dbh}->prepare($sql);
  $sth->execute($val);
  my $rec = $sth->fetchrow_hashref;
  $sth->finish;
  return $rec;
} # getrecord

############ Get given fields from (first) record that matches the where clause
# Or undef if not found
sub getfieldswhere {
  my $c = shift;
  my $table = shift;
  my $fields = shift;
  my $where = shift;
  my $order = shift || "";
  my $sql = "select $fields from $table $where $order";
  print STDERR "getfieldswhere: $sql \n";
  my $sth = $c->{dbh}->prepare($sql);
  $sth->execute();
  my $rec = $sth->fetchrow_hashref;
  $sth->finish;
  return $rec;
} # getrecord

############ Produce a list of records
# Has some heuristics for adjusting the display for some selected fields
# Tune these here or in the view definition
sub listrecords {
  my $c = shift;
  my $table = shift;
  my $sort = shift;
  my $where = shift || "";

  my @fields = tablefields($c, $table, "", 1);
  my $order = "";
  for my $f ( @fields ) {
    $order = "Order by $f" if ( $sort =~ /$f(-?)/ );
    $order .= " DESC" if ($1);
    # Note, no user-provided data goes into $order, only field names and DESC
    # (It is possible to give a bad sort parameter, but it won't match a field,
    # so we never use it here!)
  }

  $where = "where $where" if ($where);

  my $sql = "select * from $table $where $order";
  print STDERR "listrecords: $sql \n";
  my $list_sth = $c->{dbh}->prepare($sql);
  $list_sth->execute();

  my $url = $c->{url};
  my $op = $c->{op};

  my $s = "";
  #$s .= "<div style='overflow-x: auto;'>";
  #$s .= "<table style='white-space: nowrap;'>\n";
  $s .= "<table>\n";


  my @styles;  # One for each column
  # Table headers
  $s .= "<thead>";
  $s .= "<tr>\n";
  my $chkfield = -1;  # index of the checkmark field, if any
  my $dofilters = 0;
  for ( my $i=0; $i < scalar( @fields ); $i++ ) {
    my $f = $fields[$i];
    $f =~ s/^-//;
    if ( $f =~ /Name|Last|Location|Type|Producer/ ) {
      $dofilters = 1;
    }
    my $sty = "style='max-width:200px; min-width:0'"; # default
    if ( $f eq "Id" ) {
      $sty = "style='font-size: xx-small' text-align='right'";
    } elsif ( $f =~ /^(Com|Alc|Count)$/ ) {
      $sty = "style='text-align:right'";
    } elsif ( $f =~ /Rate/) {
      $sty = "style='text-align:center'";
    } elsif ( $f =~ /Chk/) { # Pseudo-field for a checkbox
      $sty = "style='text-align:center'";
      $chkfield = $i; # Remember where it is
    } elsif ( $f =~ /Comment/ ) {
      $sty = "style='max-width:400px; min-width:0'";
    } elsif ( $f =~ /^X/ ) {
      $sty = "style='display:none'";
    }
    $styles[$i] = $sty;
    my $click = "onclick='sortTable(this,$i)'";
    my $sf = $f;
    $sf .= "-" if ( $f eq $sort );
    $s .= "<td $sty $click data-label='$f'>$f</td>\n";
  }
  $s .= "</tr>\n";

  # Filter inputs
  if ( $dofilters ) {
    $s .= "<tr>\n";
    $s .= "<td onclick='clearfilters(this);'>Clr</td>\n";
    for ( my $i=1; $i < scalar( @fields ); $i++ ) {
      $s .= "<td $styles[$i] >";
      my $f = $fields[$i];
      $f =~ s/^-//;
      if ( $f =~ /Name|Last|Location|Type|Producer/ ) {
        $s .= "<input type=text name=filter$i oninput='changefilter(this);' $styles[$i] />";
        # Tried also with box-sizing: border-box; display: block;. Still extends the cell
      } else {
        $s .= "&nbsp;"
      }
      $s .= "</td>\n";
    }
    $s .= "</tr>\n";
  }
  $s .= "</thead><tbody>\n";

  while ( my @rec = $list_sth->fetchrow_array ) {
    my $tds = "";
    my $fv = "";
    my $id = $rec[0]; # Id has to be first if using the Check pseudofield
    for ( my $i=0; $i < scalar( @rec ); $i++ ) {
      my $v = $rec[$i] || "";
      my $fn = $fields[$i];
      my $sty = "style='max-width:200px'"; # default
      my $onclick = "onclick='fieldclick(this,$i);'";
      if ( $fn eq "Name" ) {
        $v = "<a href='$url?o=$op&e=$rec[0]'><b>$v</b></a>";
        $onclick = "";
      } elsif ( $fn eq "Sub" ) {
        $v = "[$v]" if ($v);
      } elsif ( $fn eq "Type" ) {
        $v =~ s/[ ,]*$//; # trailing commas from db join if no subtype
        $v = "[$v]" if ($v);
      } elsif ( $fn eq "Alc" ) {
        $v = sprintf("%5.1f", $v)  if ($v);
      } elsif ( $fn eq "Chk" ) {
        $v = "<input type=checkbox name=Chk$id />";
        $onclick = "";
      } elsif ( $fn eq "Last" ) {
        my ($date, $wd, $time) = splitdate($v);
        $v = "$wd $date $time";
        # TODO - "Sun 21:15" or "Sun 2023-05-25", depending on how recent
        # Will save a few chars on the phone
      }
      $tds .= "<td $styles[$i] $onclick>$v</td>\n";
    }

    $s .= "<tr $fv>\n";
    $s .= "$tds</tr>\n";
  }
  $s .= "</tbody></table>\n";
  $s .= "</div>\n";
  $list_sth->finish;

  # JS to do the filtering
  # TODO - Never filter records that have the Chk box checked
  # TODO - Do the sorting in JS as well, so we can keep the checked rows at top
  $s .= <<"SCRIPTEND";
  <script>
  let filterTimeout;

  function changefilter (inputElement) {
    clearTimeout(filterTimeout); // Cancel previous timeout
    filterTimeout = setTimeout(() => {
      dochangefilter(inputElement);
    }, 150); // Adjust delay as needed}
  }

  function dochangefilter (inputElement) {
    // Find the table from the input's ancestor
    const table = inputElement.closest('table');
    if (!table) return; // should not happen

    // Get the filters
    const rows = table.querySelectorAll('tr');
    const filtertds = rows[1].querySelectorAll('td');
    let filters = [];
    for ( let i=0; i<filtertds.length; i++) {
      let filterinp = filtertds[i].querySelector('input');
      if ( filterinp ) {
        filters[i] = new RegExp(filterinp.value, 'i')
      } else {
        filters[i] = '';
      }
    }

    for (let r = 2; r < rows.length; r++) { // 0 is col headers, 1 is filters
      var disp = ""; // default to showing the row
      const row = rows[r];
      const cols = rows[r].querySelectorAll('td');
      for (let c = 0; c < cols.length; c++) {
        if ( filters[c] )  {
          //console.log ( "Have filter for r=" + r + " c=" + c );
          if ( !filters[c].test( cols[c].textContent ) )
            disp = "none";
        }
      }
      row.style.display = disp;
    }
  }

  function fieldclick(el,index) {
    var filtertext = el.textContent;
    filtertext = filtertext.replace( /\\[|\\]/g , ""); // Remove brackets [Beer,IPA]
    filtertext = filtertext.replace( /^.*(20[0-9-]+) .*\$/ , "\$1"); // Just the date
      // Note the double escapes, since this is still a perl string
    //console.log("Click on element " + el + ": '" + el.textContent + "' i=" + index + " f='" + filtertext + "'" );

    // Get the filters
    const table = el.closest('table');
    const rows = table.querySelectorAll('tr');
    const filtertds = rows[1].querySelectorAll('td');
    const filterinp = filtertds[index].querySelector('input');
    if ( filterinp ) {
      filterinp.value = filtertext;
      dochangefilter(el);
    }
  }

  function clearfilters(el) {
    // Get the filters
    const table = el.closest('table');
    const rows = table.querySelectorAll('tr');
    const filtertds = rows[1].querySelectorAll('td');
    for ( let i=0; i<filtertds.length; i++) {
      let filterinp = filtertds[i].querySelector('input');
      if ( filterinp ) {
        filterinp.value = '';
      }
    }
    dochangefilter(el);
  }

  function sortTable(el, col) {
    const table = el.closest('table');
    const tbody = table.tBodies[0];
    const rows = Array.from(tbody.querySelectorAll("tr"));
    const isAscending = table.dataset.sortCol == col && table.dataset.sortDir !== "desc";
    const dir = isAscending ? -1 : 1;
    const decorated = rows.map(row => {
      const text = row.children[col].textContent.trim() || "";
      const match = text.match(/20[0-9: -]+/);
      let value;
      value = (match || isNaN(text)) ? text.toLowerCase() : parseFloat(text);
      return { row, value };
    });
    decorated.sort((a, b) => {
      if (a.value < b.value) return -1 * dir;
      if (a.value > b.value) return 1 * dir;
      return 0;
    });

    decorated.forEach(({ row }) => tbody.appendChild(row));
    const headers = table.tHead.rows[0].cells;
    for (let th of headers) {  // Clear arrows
      const label = th.dataset.label;
      if (label) {
        th.textContent = label;
      }
    }

    const headerCell = table.tHead.rows[0].cells[col];
    headerCell.textContent = headerCell.textContent.trim() + (dir === 1 ? " ▲" : " ▼");

    table.dataset.sortCol = col;
    table.dataset.sortDir = isAscending ? "desc" : "asc";
  }
  </script>
SCRIPTEND
  return $s;
}

################################################################################
# Report module loaded ok
1;
