# A complex routine to list records from the database
# Can do browser-side filtering and sorting
# Runs directly from the database, most often used
# with specially crafted views.

package listrecords;
use strict;
use warnings;

use feature 'unicode_strings';
use utf8;  # Source code and string literals are utf-8

use POSIX qw(strftime localtime locale_h);



################################################################################
# A hlper to decide to make a line break in the display format
# Returns the string to do so, or nothing if not a TR field
sub linebreak {
  my $c = shift;
  my $field = shift;
  my $tags = "</tr>\n<tr>\n";  # Stop previous line and start a new one
  if ( $field =~ /^TRMOB/i ) {  # break for mobile display only
    if ( $c->{mobile} ) {
      return $tags;
    } else {
      return " "; # non-empty, but not a line break
    }
  } elsif ( $field =~ /^TR/i ) { # unconditional break
    return $tags;
  }
  return ""; # Not a line break at all
}


################################################################################
# listrecords itself
################################################################################

sub listrecords {
  my $c = shift;
  my $table = shift;
  my $sort = shift;
  my $where = shift || "";

  my @fields = db::tablefields($c, $table, "", 1);
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
  $s .= "<style>
    .top-border td { border-top: 2px solid white; }
    </style>\n";
  $s .= "<table>\n";
  my @styles;  # One for each column

  # Table headers
  $s .= "<thead>";

  # Filter inputs also work as column headers, and sort buttons on dbl-click
  $s .= "<tr class='top-border'>\n";
  #$s .= "<td onclick='clearfilters(this);'>Clr</td>\n";
  my $chkfield = "";
  for ( my $i=0; $i < scalar( @fields ); $i++ ) {
    my $f = $fields[$i];
    my $break = linebreak($c,$f);
    if ( $break ) {
      $s .= $break;
      $styles[$i] = "";
      next;
    }
    my $sty = "style='max-width:200px; min-width:0'"; # default
    if ( $f =~ /Id|Alc|Com|Count/ ) {
      $sty = "style='max-width:55px; text-align:center'";
    } elsif ( $f =~ /^(Stats)$/ ) {
      $sty = "style='max-width:100px; text-align:center'";
    } elsif ( $f =~ /^(Com|Alc|Count)$/ ) {
      $sty = "style='text-align:right'";
    } elsif ( $f =~ /Rate|Rating|Clr/) {
      $sty = "style='text-align:center; font-weight:bold; max-width:50px'";
    } elsif ( $f =~ /Chk/) { # Pseudo-field for a checkbox
      $sty = "style='text-align:center;max-width:50px'";
      $chkfield = $i; # Remember where it is
    } elsif ( $f =~ /LocName|PersonName/ ) {
      $sty = "style='font-weight: bold; max-width:200px;' ";
    } elsif ( $f =~ /Comment/ ) {
      $sty = "style='max-width:200px; min-width:0; font-style: italic' ";
    } elsif ( $f =~ /^X/ ) {
      $sty = "style='display:none'";
    }
    #print STDERR "i=$i f='$f' s='$sty' \n";
    $styles[$i] = $sty;
    $f =~ s/^-//;
    $f =~ s/'//g;

    $s .= "<td $sty >";
    if ( $f =~ /Clr/i ) { # Clear filters button
      $s .= "<span $sty onclick='clearfilters(this);' >Clr</span>";
    } elsif ( $f  ) {
      my $on = "oninput='changefilter(this);' ondblclick=sortTable(this,$i)";
      $on = "" if ($f=~/Chk/);
      $s .= "<input type=text data-col=$i $sty $on placeholder='$f'/>";
      # Tried also with box-sizing: border-box; display: block;. Still extends the cell
    } else {
      $s .= "&nbsp;"
    }
    $s .= "</td>\n";
  }
  $s .= "</tr>\n";
  $s .= "</thead><tbody>\n";

  my $first = 1;
  while ( my @rec = $list_sth->fetchrow_array ) {
    my $tds = "";
    my $id = $rec[0]; # Id has to be first if using the Check pseudofield
    for ( my $i=0; $i < scalar( @rec ); $i++ ) {
      my $v = $rec[$i] || "";
      my $fn = $fields[$i];
      my $linebreak = linebreak($c,$fn);
      if ( $linebreak ) {
        $tds .= $linebreak;
        $first = 0;
        next;
      }
      my $sty = "style='max-width:200px'"; # default
      my $onclick = "onclick='fieldclick(this,$i);'";
      my $data = "data-col=$i";
      if ( $fn eq "Name" ) {
        $v = "<a href='$url?o=$op&e=$rec[0]'><b>$v</b></a>";
        $onclick = "";
      } elsif ( $fn =~ /Sub|Id/ ) {
        $v = "[$v]" if ($v);
      } elsif ( $fn eq "Type" ) {
        $v =~ s/[ ,]*$//; # trailing commas from db join if no subtype
        $v = "[$v]" if ($v);
      } elsif ( $fn eq "Alc" ) {
        $v = util::unit($v,"%") if ($v);
      } elsif ( $fn eq "LocName" ) {
        $v = "@" . $v  if ($v);
      } elsif ( $fn eq "PersonName" ) {
        $v .= ":" if ($v);
      } elsif ( $fn eq "Stats" ) {  # Combined ratings averages
        my ( $cnt, $avg, $com ) = split (";", $v);
        $v = comments::avgratings($c, $cnt, $avg, $com);
      } elsif ( $fn eq "Rate" ) {
        $v = "($v)" if ($v);
      } elsif ( $fn eq "Chk" ) {
        $v = "<input type=checkbox name=Chk$id />";
        $onclick = "";
      } elsif ( $fn eq "Last" ) {
        my ($date, $wd, $time) = util::splitdate($v);
        $v = "<a href='$c->{url}?o=Full&date=$date'><span>$wd $date $time</span></a>";
        # TODO - "Sun 21:15" or "Sun 2023-05-25", depending on how recent
        # Will save a few chars on the phone
      } elsif ( $fn eq "Comment" ) {
        $v = "$v";
      }
      $tds .= "<td $styles[$i] $data $onclick>$v</td>\n";
    }

    $s .= "<tr data-first=1 class='top-border'>\n"; # in-between TRs don't have data_first
    $s .= "$tds</tr>\n";
  }
  $s .= "</tbody></table>\n";
  $s .= "</div>\n";
  $list_sth->finish;

  # JS to do the filtering
  # TODO - Never filter records that have the Chk box checked

  # TODO - I now have named inputs for filters, use them
  # TODO - How to handle row groups. Mark the first lines somehow, and
  # process all the following ones as if they were one.
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

    const filterinputs = table.querySelectorAll('thead input');

    // Get the filters
    let filters = [];
    for ( let i=0; i<filterinputs.length; i++) {
      let filterinp = filterinputs[i];
      if ( filterinp ) {
        const col = filterinp.getAttribute("data-col");
        filterinp.value = filterinp.value.replace(/[▲▼]/,"");
        filters[col] = new RegExp(filterinp.value, 'i')
      }
    }
    const firstrows = table.querySelectorAll('tbody tr[data-first]');
    for (let r = 0; r < firstrows.length; r++) {
      var disp = ""; // default to showing the row
      let row = firstrows[r];
      do {
        const cols = row.querySelectorAll('td');
        for (let c = 0; c < cols.length; c++) {
          const col = cols[c].getAttribute('data-col');
          if ( col ) {
            if ( filters[col] ) {
              const re = filters[col];
              if ( !re.test( cols[c].textContent, 'i' ) ) {
                disp = "none";
              }
            }
          }
        }
        row = row.nextElementSibling;
      } while ( row && ! row.hasAttribute("data-first") );
      let ro = firstrows[r];
      do {
        ro.style.display = disp;
        ro = ro.nextElementSibling;
      } while ( ro && ! ro.hasAttribute("data-first") );

    }
  }

  // Clicking on a data field sets the filter
  function fieldclick(el,index) {
    var filtertext = el.textContent;
    filtertext = filtertext.replace( /\\[|\\]/g , ""); // Remove brackets [Beer,IPA]
    filtertext = filtertext.replace( /^.*(20[0-9-]+) .*\$/ , "\$1"); // Just the date
      // Note the double escapes, since this is still a perl string

    // Get the filters
    const table = el.closest('table');
    const col = el.getAttribute("data-col");
    const filterinp = table.querySelector('input[data-col="'+col+'"]');
    if ( filterinp ) {
      filterinp.value = filtertext;
      dochangefilter(el);
    }
  }

  function clearfilters(el) {
    // Get the filters
    const table = el.closest('table');
    const filters = table.querySelectorAll('thead td input[data-col]');
    for ( let i=0; i<filters.length; i++) {
      const filterinp = filters[i];
      if ( filterinp ) {
        filterinp.value = '';
      }
    }
    dochangefilter(el);
  }


  function sortTable(el, col) {
    const table = el.closest('table');
    const tbody = table.tBodies[0];
    const ascending = ( el.value == " ▼" );
    const columnIndex = col;

    // Group rows into records
    const rows = Array.from(tbody.rows);
    const records = [];
    let currentRecord = [];

    for (const row of rows) {
        if (row.dataset.first === "1") {
            if (currentRecord.length) records.push(currentRecord);
            currentRecord = [row];
        } else {
            currentRecord.push(row);
        }
    }
    if (currentRecord.length) records.push(currentRecord);

    // Precompute sort keys
    const sortableRecords = records.map(record => {
      const key = extractSortKey(record, columnIndex);
      return { key, record };
    });


    // Sort the cached records
    sortableRecords.sort((a, b) => {
        if (a.key === "" ) return 1;
        if (b.key === "" ) return -1;
        if (a.key < b.key) return ascending ? -1 : 1;
        if (a.key > b.key) return ascending ? 1 : -1;
        return 0;
    });

    // Rebuild tbody
    tbody.innerHTML = "";
    for (const { record } of sortableRecords) {
        for (const row of record) {
            tbody.appendChild(row);
        }
    }

   // Clear arrows
   for (let th of table.querySelectorAll('thead input ') ) {
      th.value = th.value.replace(/[▲▼]/,"").trim();
    }

    el.value = ascending ? " ▲" : " ▼" ;

    table.dataset.sortCol = col;
    table.dataset.sortDir = ascending ? "desc" : "asc";

  }

  function extractSortKey(recordRows, columnIndex) {
    for (const row of recordRows) {
        const sel = "[data-col='" + columnIndex +"']";
        const cell = row.querySelector(sel);
        if (cell) {
          let text = cell.textContent;
          const match = text.match(/20[0-9][0-9]-[0-9 :-]+/);
          if ( match ) { text = match[0]; }
          text = text.replace( /^\\[/, "");
          text = text.replace( /\\]\$/, "");
          if ( isNaN(text) || ! text) {
            text = text.toLowerCase().trim();
          } else {
            text = parseFloat(text);
          }
          // console.log("sortkey for col " + columnIndex + " of '" + cell.textContent + "' is '" + text + "' m=" + match);
          return text;
        }
    }
    return ""; // fallback key
  }


  </script>
SCRIPTEND
  return $s;
}

################################################################################
1; # Tell perl that the module loaded fine
