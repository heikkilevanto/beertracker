# Part of my beertracker
# The main form for inputting a glass record, with all its extras
# And the routine to save it in the database

package glasses;
use strict;
use warnings;

use feature 'unicode_strings';
use utf8;  # Source code and string literals are utf-8

use POSIX qw(strftime localtime locale_h);

our %volumes = ( # Comment is displayed on the About page
  'T' => " 2 Taster, sizes vary, always small",
  'G' => "16 Glass of wine - 12 in places, at home 16 is more realistic",
  'S' => "25 Small, usually 25",
  'M' => "33 Medium, typically a bottle beer",
  'L' => "40 Large, 40cl in most places I frequent",
  'C' => "44 A can of 44 cl",
  'W' => "75 Bottle of wine",
  'B' => "75 Bottle of wine",
);

################################################################################
# Helper to decide if a glass is "empty"
################################################################################
sub isemptyglass {
  my $type = shift;
  return $type =~ /Restaurant|Night|Bar|Feedback/;
}

################################################################################
# Helper to select a brew type
################################################################################
# Selecting from glasses, not brews, so that we get 'empty' glasses as well,
# f.ex. "Restaurant"
sub selectbrewtype {
  my $c = shift;
  my $selected = shift || "";
  my $sql = "select distinct BrewType from Glasses";
  my $sth = $c->{dbh}->prepare($sql);
  $sth->execute( );
  my $opts = "";
  while ( my $bt = $sth->fetchrow_array ) {
    my $se = "";
    $se = "selected" if ( $bt eq $selected );
    my $em = "data-isempty=1";
    $em = "" if ( ! isemptyglass($bt) );
    $opts .= "<option value='$bt' $em $se>$bt</option>\n";
  }
  util::error ("No brew types in the database. Insert some dummy glasses")
    unless ($opts);
  my $s = "<select name='selbrewtype' id='selbrewtype' onChange='selbrewchange(this);' style='max-width:100px; width:100px; text-overflow:ellipsis; overflow:hidden; white-space:nowrap;'>\n" .
    $opts . "</select>\n";
  my $script = <<'SCRIPT';
    <script>
      replaceSelectWithCustom(document.getElementById("selbrewtype"));

      function selbrewchange(el) {
        const selbrew = document.getElementById("selbrewtype");
        const val = selbrew.value;
        const selected = el.options[el.selectedIndex];
        const isempty = selected.getAttribute("data-isempty");
        const table = el.closest('table');
        for ( const td of table.querySelectorAll("[data-empty]") ) {
          const te = td.getAttribute("data-empty");
          if ( te == 1 ) {
            if ( isempty )
              td.style.display = 'none';
            else
              td.style.display = '';
          } else if ( te == 2 ) {
              if ( isempty )
                td.style.display = '';
              else
                td.style.display = 'none';
            }
          else if ( te ) {
            if ( te == val )
                td.style.display = '';
              else
                td.style.display = 'none';
          }
        }
      }
    </script>
SCRIPT
  $s .= $script;
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
    WHERE BrewType in ("Restaurant","Night", "Bar","Feedback")
    GROUP BY brewtype,SubType
    ORDER BY last_time DESC ';
  my $sth = $c->{dbh}->prepare($sql);
  $sth->execute( );
  my $s = "";
  while ( my $bt = $sth->fetchrow_hashref ) {
    next unless ( $bt->{SubType} );
    my $sel = "";
    $sel = "selected" if ( $rec->{SubType} && $rec->{SubType} eq $bt->{SubType} );
    my $em = "data-empty=\"$bt->{BrewType}\" ";
    $s .= "<option value='$bt->{SubType}' $em $sel>$bt->{SubType}</option>\n";
  }
  $s = "<select name='selbrewsubtype' id='selbrewsubtype'>\n" .
    $s . "</select>\n";
  return $s;
} # selectbrewsubtype

################################################################################
# The input form
################################################################################
# This is a fairly small, but rather complex form. For now it is hard coded,
# without using the util::inputform helper, as almost every field has some
# special considerations.
sub inputform {
  my $c = shift;
  my $rec = findrec($c); # Get defaults, or the record we are editing

  # Formatting magic
  my $clr = "Onfocus='value=value.trim();select();' autocapitalize='words'";
  my $sz4 = "size='4' style='text-align:right' $clr";
  my $sz8 = "size='8'  $clr";
  my $sz20 = "size='20' $clr";

  print "\n<form method='POST' accept-charset='UTF-8' class='no-print' " .
        "onClick='setdate();' " .
        "enctype='multipart/form-data'>\n";
  print "<table>\n";

  print "<tr><td width='100px'>Id $rec->{Id}</td>\n";
  my $stamp = util::datestr("%F %T");
  print "<td>" ; # <input name='stamp' value='$stamp' size=25 $clr/>";
  my ($date,$time) = ( "", "");
  ($date,$time) = split ( ' ',$rec->{Timestamp} ) if ($rec->{Timestamp} );
  if ( !$c->{edit} ) {
    $date =" $date";  # Mark the time as speculative
    $time =" $time";
  }
  print "<input name='date' id='date' value='$date' " .
        "pattern=' ?([LlYy])?(\\d\\d\\d\\d-\\d\\d-\\d\\d)?' " .
        "placeholder='YYYY-MM-DD' $sz8 /> &nbsp;\n";
        # Could not make alternative pattern work, so I use a sequence of L/Y
        # and a valid date. Note also the leading space
  print "<input name='time' id='time' value='$time' " .
        "pattern=' ?\\d\\d(:?\\d\\d)?(:?\\d\\d)?' ".
        "placeholder='HH:MM' $sz8/> &nbsp;\n";
  my $onclick = "onclick='selectNearest(\"#dropdown-Location\")'";
  print "<tr><td $onclick>Location</td>\n";
  print "<td>" . locations::selectlocation($c, "Location", $rec->{Location}, "newlocname", "non") .
    "</td></tr>\n";

  # Brew style
  print "<tr><td width='100px' style='vertical-align:top; max-width:100px;'>" . selectbrewtype($c,$rec->{BrewType}) ."</td>\n";
  print "<td>\n";

  # Brew, or  subtype
  my $hidesub = "";
  my $hidebrew = "";
  if (isemptyglass($rec->{BrewType}) ) {
    $hidebrew = "style=display:none";
  } else {
    $hidesub = "style=display:none";
  }
  print "<span $hidesub data-empty=2>". selectbrewsubtype($c,$rec). "</span>";
  print "<span $hidebrew data-empty=1>". brews::selectbrew($c,$rec->{Brew},$rec->{BrewType}). "</span>";
  print "</td>\n";

  print "</tr>\n";

  # Note for the glass
  my $hidenote = "hidden";
  $rec->{Note} = "" unless ( $c->{edit} );  # Do not inherit from previous
  if ( $c->{edit} ) {
    $hidenote = "";
  }
  my $tap = $rec->{Tap} || "";
  if ( !$c->{edit} ) {
    $tap = " $tap";
  }
  print STDERR "Glass input form: hidenote='$hidenote' Note='$rec->{Note}' Tap='$tap'\n";
  print "<tr id='noteline' $hidenote><td>Tap <input name='tap' value='$tap' size='2' $clr/></td><td>\n";
  print "<input name='note' placeholder='note' value='$rec->{Note}' $sz20/>\n";
  print "</td></tr>\n";

  # (note toggle),  Vol, Alc, and Price
  print "<tr>";
  my $notetxt = "(more)";
  $notetxt = "" if ( !$hidenote);
  print "<td id='leftcol'><div id='notetag' onclick='shownote();'>$notetxt</div></td>";
  print "<td id='avp' >\n";
  my $vol = $rec->{Volume} || "";
  $vol .= "c" if ($vol);
  print "<input name='vol' id='vol' placeholder='vol' $sz4 value='$vol' data-empty=1 />\n";
  my $alc = $rec->{Alc} || "";
  $alc .= "%" if ($alc);
  print "<input name='alc' id='alc' placeholder='alc' $sz4 value='$alc' data-empty=1 />\n";
  my $pr = $rec->{Price} || "0";
  $pr .= ".-" if ($pr);
  print "<input name='pr' id='pr' placeholder='pr' $sz4 value='$pr' required />\n";
  print "</td></tr>\n";

  # Buttons
  print "<tr><td>\n";
  print " <input type='hidden' name='o' value='$c->{op}' />\n";
  if ($c->{edit}) {
    print " <input type='hidden' name='e' value='$rec->{Id}' />\n";
    print " <input type='submit' name='submit' value='Save' id='save' />\n";
    print "</td><td>\n";
    print " <input type='submit' name='submit' value='Del' formnovalidate />\n";
    print "<a href='$c->{url}?o=$c->{op}' ><span>cancel</span></a>";
  } else { # New glass
    print "<input type='submit' name='submit' value='Record'/>\n";
    print "</td><td>\n";
    print " <input type='button' value='Clr' onclick='clearinputs()'/>\n";
  }
  print "&nbsp;" ;
  print "</td></tr>\n";
  print "</table>\n";
  print "</form>\n";
  print comments::listcomments($c, $rec->{Id});
  print "<hr/>";

  # Javascript trickery
  my $script = <<'SCRIPTEND';

    function clearinputs() {  // Clear all inputs, used by the 'clear' button
      var inputs = document.getElementsByTagName('input');  // all regular input fields
      for (var i = 0; i < inputs.length; i++ ) {
        if ( inputs[i].type == "text" )
          inputs[i].value = "";
      }
    }

    function setdate() {  // Set date and time, if not already set by the user
      const dis = document.getElementsByName("date");
      const tis = document.getElementsByName("time");
      const now = new Date();
      for ( const di of dis ) {
        if ( di.value && di.value.startsWith(" ") ) {
          const year = now.getFullYear();
          const month = String(now.getMonth() + 1).padStart(2, '0'); // Zero-padded month
          const day = String(now.getDate()).padStart(2, '0'); // Zero-padded day
          const dat = `${year}-${month}-${day}`;
          di.value = " " + dat;
        }
      }
      for ( const ti of tis ) {
        if ( ti.value && ti.value.startsWith(" ") ) {
          const hh = String(now.getHours()).padStart(2, '0');
          const mm = String(now.getMinutes()).padStart(2, '0');
          const tim = `${hh}:${mm}`;
          ti.value = " " + tim;
        }
      }
    }
    setdate();

    // If noteline is already shown (editing with note), set the labels
    if (!document.getElementById("noteline").hidden) {
      document.getElementById("leftcol").innerHTML = '<input type="checkbox" name="setdef" />Def';
    }

    function shownote() {
      const noteline = document.getElementById("noteline");
      noteline.hidden = false;
      const toggle = document.getElementById("notetag");
      toggle.hidden = true;
      const leftcol = document.getElementById("leftcol");
      leftcol.innerHTML = '<input type="checkbox" name="setdef" />Def';
    }

    // hide newBrewType, we use SelBrewType always
    var nbt = document.getElementsByName("newbrewBrewType");
    if ( nbt.length > 0 ) {
      nbt[0].hidden = true;
      var br = nbt[0].nextElementSibling;
      br.hidden = true;
    }
SCRIPTEND
  print "<script defer>$script</script>\n";
} # inputform


################################################################################
# Helper to get the latest glasss record for editing or defaults
################################################################################
sub findrec {
  my $c = shift;
  my $id = $c->{edit};
  if ( ! $id ) {  # Not editing, just get the latest
    my $sql = "select id from glasses " .
              "where username = ? " .
              "order by timestamp desc ".
              "limit 1";
    my $sth = $c->{dbh}->prepare($sql);
    $sth->execute( $c->{username} );
    $id = $sth->fetchrow_array;
  }
  my $sql = "select * from glasses " .
            "where id = ? and username = ? ";
  my $sth = $c->{dbh}->prepare($sql);
  $sth->execute( $id, $c->{username} );
  my $rec = $sth->fetchrow_hashref;
  return $rec;
}

################################################################################
# Report module loaded ok
1;
