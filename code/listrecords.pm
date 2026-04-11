# A complex routine to list records from the database
# Can do browser-side filtering and sorting
# Runs directly from the database, most often used
# with specially crafted views.
# makes use of sorting and filtering routines in listrecords.js

package listrecords;
use strict;
use warnings;

use feature 'unicode_strings';
use utf8;  # Source code and string literals are utf-8

use POSIX qw(strftime localtime locale_h);

# TODO - Should probably html-escale values from the db
# TODO - This is basically one too-long function.

################################################################################
# A helper to decide to make a line break in the display format
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
  my $params = shift || undef ;  # params for the sql
  my $extraparams = shift || undef;  # params for special fields, like lat/long to measure from
  my $maxrecords = shift || 20;  # show this many records initially, rest hidden

  # Build cache key from all inputs that affect the rendered HTML.
  my $params_str = "";
  if ( $params ) {
    my @pa = ref $params eq 'ARRAY' ? @$params : ($params);
    $params_str = join("\x1f", @pa);
  }
  my $extraparams_str = "";
  if ( $extraparams ) {
    $extraparams_str = join("\x1f", map { "$_=" . ($extraparams->{$_} // "") } sort keys %$extraparams);
  }
  my $mobile = $c->{mobile} ? 1 : 0;
  my $cache_key = join("\x1e", "listrecords", $c->{username}, $c->{op},
                       $table, $sort, $where, $params_str, $extraparams_str,
                       $maxrecords, $mobile);
  my $cached = cache::get($c, $cache_key);
  if ( defined $cached ) {
    print { $c->{log} } "listrecords: cache hit for $table\n";
    return $cached;
  }

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
  my @paramarr = ();
  if ( $params ) {
    @paramarr = ref $params eq 'ARRAY' ? @$params : ($params);
  }
  my $list_sth = @paramarr ? db::query($c, $sql, @paramarr) : db::query($c, $sql);

  my $url = $c->{url};
  my $op = $c->{op};

  my $s = "";
  $s .= "<!-- listrecords: $sql -->\n"; 
  $s .= "<style>
    .top-border td { border-top: 2px solid white; }
    </style>\n";
  my $geotable = "";
  if ( $extraparams && (($extraparams->{lat} // '') eq '?') && (($extraparams->{lon} // '') eq '?') ) {
    $geotable = "id='geotable'";
  }
  my $tableattrs = "$geotable data-maxrecords='$maxrecords'";

  $s .= "<table $tableattrs>\n";
  my @styles;  # One for each column

  # Table headers
  $s .=  "<!-- listrecords: table headers -->\n"; 

  $s .= "<thead>";

  # Filter inputs also work as column headers, and sort buttons on dbl-click
  $s .= "<tr class='top-border'>\n";
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
    $sty = "style='max-width:90px; min-width:0'" if ( $c->{mobile} );
    if ( $f =~ /^X/i ) {
      $sty = "style='display:none'";
    } elsif ( $f =~ /Id|Alc/ ) {
      $sty = "style='max-width:55px; text-align:center'";
    } elsif ( $f =~ /^(Stats)$/ ) {
      $sty = "style='max-width:100px; text-align:center'";
    } elsif ( $f =~ /^(Last)$/ ) {
      $sty = "style='max-width:100px; text-align:center'" if ($c->{mobile});
    } elsif ( $f =~ /^(Type)$/ ) {
      my $w = "100px";
      $w = "200px" unless $c->{mobile};
      $sty = "style='max-width:$w; text-align:center'";
    } elsif ( $f =~ /^(Sub)$/ ) {
      $sty = "style='max-width:70px; text-align:center'";
    } elsif ( $f =~ /^(Com|Count)$/ ) {
      $sty = "style='text-align:right; max-width:50px'";
    } elsif ( $f =~ /^Photo$/ ) {
      $sty = "style='text-align:center; max-width:50px; padding:1px'";
    } elsif ( $f =~ /^Photos$/ ) {
      $sty = "style='text-align:left; max-width:250px; padding:1px'";
    } elsif ( $f =~ /Rate|Rating|Clr/) {
      $sty = "style='text-align:center; font-weight:bold; max-width:50px'";
    } elsif ( $f =~ /Chk/) { # Pseudo-field for a checkbox
      $sty = "style='text-align:center;max-width:50px'";
      $chkfield = $i; # Remember where it is
    } elsif ( $f =~ /LocName|PersonName/ ) {
      $sty = "style='font-weight: bold; max-width:200px;' ";
    } elsif ( $f =~ /isGeneric/i ) {
      $sty = "style='font-weight: bold; max-width:100px;' ";
      $f = "Generic";
    } elsif ( $f =~ /Comment|Description/i ) {
      $sty = "style='max-width:200px; min-width:0; font-style: italic' ";
    } elsif ( $f =~ /Sim/ ) {  # name similarity
      $sty = "style='max-width:55px; min-width:0; text-align:right' ";
      $f = "Sim";
    } elsif ( $f =~ /Geo/ ) {  # geo distance
      if ( $c->{mobile} ) {
        $sty = "style='max-width:55px; min-width:0; text-align:right' ";
        $f = "km";
      } else {
        $sty = "style='max-width:100px; min-width:0; text-align:right' ";
        $f = "Dist (km)";
      }
    } elsif ( $f =~ /^None/i ) {
      $f = "";
    }
    #print { $c->{log} } "i=$i f='$f' s='$sty' \n";
    $styles[$i] = $sty;
    $f =~ s/^-//;
    $f =~ s/'//g;

    $s .= "<td $sty >";
    if ( $f =~ /Clr/i ) { # Clear filters button
      $s .= "<span $sty onclick='clearfilters(this);' >Clr</span>";
    } elsif ( $f  ) {
      my $on = "oninput='changefilter(this);' ondblclick='event.preventDefault(); sortTable(this,$i); return false;'";
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
  $s .=  "<!-- listrecords: table headers done, now the body -->\n"; 

  my $cutoff = util::datestr("%F", -7);  # a week ago, display full date

  my $first = 1;
  my $rowcount = 0;
  my $hashidden = 0;  # Flag to track if we have hidden rows
  while ( my @rec = $list_sth->fetchrow_array ) {
    $rowcount++;
    my $hidden = "";
    if ( $rowcount > $maxrecords ) {
      $hidden = " hidden";
      $hashidden = 1;
    }
    my $tds = "";
    my $id = $rec[0]; # Id has to be first if using the Check pseudofield
    for ( my $i=0; $i < scalar( @rec ); $i++ ) {
      my $v = $rec[$i] || "";
      my $fn = $fields[$i];
      my $linebreak = linebreak($c,$fn);
      if ( $linebreak ) {
        $linebreak =~ s/<tr>/<tr$hidden>/ if $hidden;  # Apply hidden to linebreak TRs
        $tds .= $linebreak;
        $first = 0;
        next;
      }
      my $sty = "style='max-width:200px'"; # default
      my $onclick = "onclick='fieldclick(this,$i);'";
      my $data = "data-col=$i";
      if ( $fn eq "Name" ) {
        $v = "<a href='$url?o=$op&e=$rec[0]'><span><b>$v</b></span></a>";
        $onclick = "";
      } elsif ( $fn =~ /Clr/ ) {
        $v="&nbsp;";
      } elsif ( $fn =~ /Sub|Id/ ) {
        if ($v) {
          if ($c->{op} =~ /Comment/i) {
            $v = "<a href='$url?o=Comment&e=$v'><span>[$v]</span></a>";
          } else {
            $v = "[$v]";
          }
        }
      } elsif ( $fn eq "Type" ) {
        $v =~ s/[ ,]*$//; # trailing commas from db join if no subtype
        if ($v) {
          my ($brewtype, $subtype) = split(/,\s*/, $v, 2);  # Split on comma
          $v = styles::brewstyledisplay($c, $brewtype, $subtype);
        }
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
        my $disp = "$date $time $wd"; # wday last, for alignment
        if ( $c->{mobile} ) {
          $disp = "$time $wd";
          $disp = "$date" if ( $date lt $cutoff );
        }
        $v = "<a href='$c->{url}?o=Full&date=$date'><span>$disp</span></a>";
      } elsif ( $fn eq "Sim" ) { # Name similarity
        if ( $v && $extraparams && $extraparams->{refname} ) {
          # Find the Name field in this row
          my $name_idx;
          for (my $j = 0; $j < scalar(@fields); $j++) {
            if ($fields[$j] eq 'Name') {
              $name_idx = $j;
              last;
            }
          }
          if (defined $name_idx) {
            my $thisname = $rec[$name_idx];
            $v = util::namesimilarity($extraparams->{refname}, $thisname);
          } else {
            $v = "";
          }
        } else {
          $v = "";
        }
      } elsif ( $fn eq "Geo" ) { # Geo dist
        if ( $v && $extraparams && $extraparams->{lat} && $extraparams->{lon} ) {
          my ( $lat, $lon ) = split(' ', $v);
          if (  $extraparams->{lat} eq '?' ) {  # Need to recalc in js
            $data .= " lat=$lat lon=$lon";
            $v = '?';
          } else {
            $v = geo::geodist( $extraparams->{lat}, $extraparams->{lon}, $lat, $lon );
          }
        } else {
          $v = "";
        }
      } elsif ( $fn eq "Comment" ) {
        $v = "$v";
      } elsif ( $fn eq "Photo" ) {
        $v = photos::imagetag($c, $v, $c->{mobile} ? "small" : "thumb");
      } elsif ( $fn eq "Photos" ) {
        if ($v) {
          my @fns = split(/\|/, $v);
          $v = join('', map { photos::imagetag($c, $_, $c->{mobile} ? "small" : "thumb") } @fns);
        }
      } elsif ( $fn eq "IsGeneric" ) {
        $v = "Gen" if ($v);
      }
      $tds .= "<td $styles[$i] $data $onclick>$v</td>\n";
    }

    $s .= "<tr data-first=1 class='top-border'$hidden>\n"; # in-between TRs don't have data_first
    $s .= "$tds</tr>\n";
  }
  $s .= "</tbody></table>\n";
  $s .= "<!-- listrecords: table body done -->\n"; 

  if ($hashidden) {
    $s .= "<!-- listrecords: more link -->\n"; 
    $s .= "<div style='text-align: left; margin-top: 10px;'>";
    $s .= "<a href='javascript:void(0);' onclick='showMoreRecords(this);'><span>More...</span></a>";
    $s .= "</div>\n";
  }
  if ($geotable) {
    $s .= "<script>geotabledist();</script>\n";
  }
  $s .= "<!-- listrecords: all done for $sql -->\n"; 

  $list_sth->finish;

  cache::set($c, $cache_key, $s);
  return $s;
}

################################################################################
1; # Tell perl that the module loaded fine
