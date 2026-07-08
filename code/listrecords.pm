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
# Helper: add colspan='2' to the last <td> in $tds, if it doesn't already
# have a colspan attribute. Used when skipping an empty photo column.
sub _colspan_last_td {
  my $tds_ref = shift;
  my $lt = rindex($$tds_ref, "<td");
  return if $lt < 0;
  my $gt = index($$tds_ref, ">", $lt);
  return if $gt <= $lt;
  return if substr($$tds_ref, $lt, $gt - $lt) =~ /colspan/i;
  substr($$tds_ref, $gt, 0) = " colspan='2'";
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
  my $cache_key = join("\x1e", "listrecords_v2", $c->{username}, $c->{op},
                       $table, $sort, $where, $params_str, $extraparams_str,
                       $maxrecords, $mobile);
  my $cached = cache::get($c, $cache_key);
  if ( defined $cached ) {
    print { $c->{log} } "listrecords: cache hit for $table\n";
    return $cached;
  }

  my @fields = db::tablefields($c, $table, "", 1);
  my @orig_fields = @fields;  # Preserve for SQL ORDER BY (before suffix stripping)
  my @extra_attr = ("") x scalar(@fields);
  my %px_override;
  my %auto_override;
  my @suffix_info;  # array of hashrefs, one per column
  for (my $i = 0; $i < scalar(@fields); $i++) {
      my $suf = {};
      my $field = $fields[$i];
      my $orig_field = $field;
      my $changed;
      do {
          $changed = 0;
          if ($field =~ s/_R(\d+)$//) {
              $suf->{rowspan} = $1;
              $extra_attr[$i] = "rowspan='$1'";
              $changed = 1;
          } elsif ($field =~ s/_C(\d+)$//) {
              $suf->{colspan} = $1;
              $extra_attr[$i] = "colspan='$1'";
              $changed = 1;
          } elsif ($field =~ s/_as:([^_]+)$//) {
              $suf->{as_name} = $1;
              $changed = 1;
          } elsif ($field =~ s/_(\d+px)$//) {
              $suf->{width_px} = $1;
              $px_override{$i} = $1;
              $changed = 1;
           } elsif ($field =~ s/_A$//) {
               $suf->{auto_width} = 1;
               $auto_override{$i} = 1;
               $changed = 1;
           } elsif ($field =~ s/_filter$//) {
               $suf->{filter} = 1;
               $changed = 1;
           } elsif ($field =~ s/_nofilter$//) {
               $suf->{nofilter} = 1;
               $changed = 1;
           } elsif ($field =~ s/_noheader$//) {
               $suf->{noheader} = 1;
               $changed = 1;
            } elsif ($field =~ s/_link:([A-Z][a-zA-Z]+)$//) {
                 $suf->{link} = $1;
                 $suf->{nofilter} = 1;
                 $suf->{noheader} = 1;
                 $changed = 1;
            } elsif ($field =~ s/_contline$//) {
                $suf->{contline} = 1;
                $changed = 1;
            } elsif ($field =~ s/_cont$//) {
                $suf->{cont} = 1;
                $changed = 1;
           } elsif ($field =~ /_([a-z][a-zA-Z0-9]*)$/) {
               print { $c->{log} } "WARNING: listrecords: Unrecognized suffix '_$1' in column '$orig_field' (table: $table)\n";
           }
      } while ($changed);
      $fields[$i] = $field;
      $suffix_info[$i] = $suf;
  }
  my $order = "";
  for (my $i = 0; $i < scalar(@fields); $i++) {
      my $f = $fields[$i];
      if ( $sort =~ /$f(-?)/ ) {
          $order = "Order by $orig_fields[$i]" . ($1 ? " DESC" : "");
      }
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
    table[data-maxrecords] { border-collapse: separate; border-spacing: 0; }
    .top-border td { border-top: 2px solid white; }
    .null-value { color: #999; font-style: italic; }
    .filtering-active { filter: brightness(1.3); }
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
  my $hdr_cont_active = 0;
  my $hdr_cont_sep = "";
  my $hdr_contline_rest = 0;
  my @hidden_filters;
  for ( my $i=0; $i < scalar( @fields ); $i++ ) {
    my $f = $fields[$i];
    my $break = linebreak($c,$f);
    if ( $break ) {
      if ($hdr_cont_active) {
        $s .= "</td>\n";
        $hdr_cont_active = 0;
      }
      $hdr_contline_rest = 0;
      $s .= $break;
      $styles[$i] = "";
      next;
    }
    my $sty = "style='max-width:200px; min-width:0'"; # default
    $sty = "style='max-width:90px; min-width:0'" if ( $c->{mobile} );
    if ( $f =~ /^X/i ) {
      $sty = "style='display:none'";
    } elsif ( $f eq "Id" ) {
      $sty = "style='max-width:40px; text-align:center'";
    } elsif ( $f =~ /Id|Alc/ ) {
      $sty = "style='max-width:55px; text-align:center'";
    } elsif ( $f =~ /^(Stats)$/ ) {
      $sty = "style='max-width:100px; text-align:center'";
    } elsif ( $f =~ /^(Last|Ts)$/ ) {
      $sty = "style='max-width:100px'";
    } elsif ( $f =~ /^(Type)$/ ) {
      my $w = "100px";
      $w = "200px" unless $c->{mobile};
      $sty = "style='max-width:$w; text-align:center'";
    } elsif ( $f =~ /^(Sub)$/ ) {
      $sty = "style='max-width:70px; text-align:center'";
    } elsif ( $f =~ /^(Com|Count)$/ ) {
      $sty = "style='text-align:right; max-width:50px'";
    } elsif ( $f =~ /^Photo$/ ) {
      $sty = "style='width:96px; text-align:center; padding:1px'";
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
    if ( $auto_override{$i} ) {
        $styles[$i] = "";
        $sty = " size='" . (length($f) + 2) . "'";
        $sty .= " style='max-width:70px'" if ( $c->{mobile} );
    }
    $f =~ s/^-//;
    $f =~ s/'//g;

    if ( $suffix_info[$i]{contline} ) {
        if ($hdr_cont_active) {
            $s .= "</td>\n";
            $hdr_cont_active = 0;
        }
        $hdr_contline_rest = 1;
    }
    if ( $suffix_info[$i]{noheader} ) {
        if ($hdr_cont_active) {
            $s .= "</td>\n";
            $hdr_cont_active = 0;
        }
        if ( !$suffix_info[$i]{nofilter} ) {
            my $non = "oninput='changefilter(this);' ondblclick='event.preventDefault(); sortTable(this,$i); return false;'";
            push @hidden_filters, "<input type=text style='display:none' data-col='$i' $non/>\n";
        }
        $s .= "<td $styles[$i] $extra_attr[$i]></td>\n";
        next;
    }

    my $hdr_input;
    if ( $suffix_info[$i]{nofilter} ) {
        $hdr_input = $f;
    } elsif ( $f eq "Id" ) {
      my $on = "oninput='changefilter(this);' ondblclick='event.preventDefault(); sortTable(this,$i); return false;'";
      $hdr_input = "<input type=text data-col='$i' $sty $on placeholder='Id'/>";
    } elsif ( $f eq "Name" ) {
      my $on = "oninput='changefilter(this);' ondblclick='event.preventDefault(); sortTable(this,$i); return false;'";
      $hdr_input = "<input type=text data-col='$i' $sty $on placeholder='Name'/>";
    } elsif ( $f =~ /Clr/i ) { # Clear filters button
      $hdr_input = "<span style='cursor:pointer; border:1px solid #888; border-radius:4px; padding:0 5px; font-size:x-small' onclick='clearfilters(this);'>Clr</span>";
    } elsif ( $f  ) {
      my $on = "oninput='changefilter(this);' ondblclick='event.preventDefault(); sortTable(this,$i); return false;'";
      $on = "" if ($f=~/Chk/);
      $hdr_input = "<input type=text data-col='$i' $sty $on placeholder='$f'/>";
      # Tried also with box-sizing: border-box; display: block;. Still extends the cell
    } else {
      $hdr_input = "&nbsp;"
    }
    if ($hdr_cont_active) {
        $s .= $hdr_cont_sep . $hdr_input;
    } else {
        $s .= "<td $sty $extra_attr[$i]>$hdr_input";
    }
    if ($suffix_info[$i]{cont} || $hdr_contline_rest) {
        $hdr_cont_active = 1;
    } else {
        $s .= "</td>\n";
        $hdr_cont_active = 0;
    }
  }
  if ($hdr_cont_active) {
    $s .= "</td>\n";
  }
  foreach my $i (keys %px_override) {
      $styles[$i] = "style='max-width:$px_override{$i}; min-width:0'";
  }
  foreach my $i (keys %auto_override) {
      $styles[$i] = "";
  }
  $s .= "</tr>\n";
  $s .= join('', @hidden_filters);
  $s .= "</thead>\n";
  $s .=  "<!-- listrecords: table headers done, now the body -->\n";

  my $cutoff = util::datestr("%F", -7);  # a week ago, display full date

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
    my $cont_active = 0;
    my $cont_sep = "";
    my $contline_rest = 0;
    my $photo_skipped = 0;
    for ( my $i=0; $i < scalar( @rec ); $i++ ) {
      my $v = $rec[$i];
      my $was_null_field = !defined $v;
      $v //= "";

      my $fn = $fields[$i];
      my $linebreak = linebreak($c,$fn);
      if ( $linebreak ) {
        if ($cont_active) {
          $tds .= "</td>\n";
          $cont_active = 0;
        }
        $contline_rest = 0;
        if ($photo_skipped) {
          _colspan_last_td(\$tds);
        }
        $tds .= $linebreak;
        next;
      }
      if ( $suffix_info[$i]{contline} ) {
        if ($cont_active) {
          $tds .= "</td>\n";
          $cont_active = 0;
        }
        $contline_rest = 1;
      }
      $fn = $suffix_info[$i]{as_name} if $suffix_info[$i]{as_name};
      my $data_attrs = "data-col='$i'";
      my $word_split = 1;
      if ( $fn eq "Name" ) {
        $v = _word_spans($v, $i);
        $v = "<b>$v</b>";
        $word_split = 0;
      } elsif ( $suffix_info[$i]{link} ) {
        if ($v) {
          my $entity = $suffix_info[$i]{link};
          my $prefix = substr($entity, 0, 1);
          $v = "<a href='$url?o=$entity&e=$v'><span>${prefix}[$v]</span></a>: ";
        }
        $word_split = 0;
      } elsif ( $fn eq "IdClr" ) {
        if ($v) {
          $v = "<a href='$url?o=Brew&e=$v'><span>B[$v]</span></a>: ";
        }
        $word_split = 0;
      } elsif ( $fn =~ /Clr/ ) {
        $v="";
        $word_split = 0;
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
          my $style_str;
          if ($brewtype eq 'Beer') {
            $style_str = $subtype || 'Beer';
          } else {
            $style_str = $brewtype;
            $style_str .= ",$subtype" if $subtype;
          }
          my $dispstyle = styles::brewtextstyle($c, $style_str, "$c->{op}:$rec[0] $brewtype/" . ($subtype // ""));
          (my $filter_str = $style_str) =~ s/,/ /g;
          $v = _word_spans($filter_str, $i);
          $v = "<span $dispstyle>$v</span>";
          $word_split = 0;
        }
      } elsif ( $fn eq "Alc" ) {
        if ($v) {
          $data_attrs .= " data-sort-key='$v'";
          my $display = util::unit($v,"%");
          $v = "<span data-col='$i' data-filter='$v' onclick='fieldclick(event,this)'>$display</span>";
        }
      } elsif ( $fn eq "LocName" ) {
        $v = "@" . $v  if ($v);
      } elsif ( $fn eq "CountryRegion" ) {
        my ($country, $region) = split(/;/, $v, 2);
        $v = util::locdesc($c, $country, $region);
        $v .= "&nbsp;&nbsp;" if $v;
        $word_split = 0;
      } elsif ( $fn eq "PersonName" ) {
        $v .= ":" if ($v);
      } elsif ( $fn eq "Prod" ) {
        if ($v) {
          $v = _word_spans($v, $i);
          $v = "<i>$v</i>:";
        }
        $word_split = 0;
      } elsif ( $fn eq "BrewName" ) {
        if ($v) {
          $v = _word_spans($v, $i);
          $v = "<b>$v</b>";
        }
        $word_split = 0;
      } elsif ( $fn eq "Stats" ) {  # Combined ratings averages
        my ( $cnt, $avg, $com ) = split (";", $v);
        $data_attrs .= " data-sort-key='$avg'" if ($avg);
        $v = comments::avgratings($c, $cnt, $avg, $com);
        if ($v) {
          if ($avg) {
            my $favg = sprintf("%.1f", $avg);
            $v = "<span data-col='$i' data-filter='$favg' onclick='fieldclick(event,this)'>$v</span>";
          }
        }
      } elsif ( $fn eq "Rate" ) {
        if ($v) {
          $data_attrs .= " data-sort-key='$v'";
          $v = "($v)";
        }
      } elsif ( $fn eq "Chk" ) {
        $v = "<input type=checkbox name=Chk$id />";
        $word_split = 0;
      } elsif ( $fn eq "Ts" ) {
        if ($v) {
          my ($date, $time) = split(' ', $v);
          if ($date && $time) {
            my ($y, $m, $d) = split('-', $date);
            my $epoch = POSIX::mktime(0, 0, 0, $d, $m-1, $y-1900);
            my @weekdays = ( "Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat" );
            my $wd = $weekdays[(localtime($epoch))[6]];
            my $disp = "$time $wd";
            $disp = "$date" if ( $date lt $cutoff );
            $data_attrs .= " data-sort-key='$date $time' title='$date $time $wd'";
            $v = $disp;
          }
        }
      } elsif ( $fn eq "Last" ) {
        my ($date, $wd, $time) = util::splitdate($v);
        my $disp = "$time $wd";
        $disp = "$date" if ( $date lt $cutoff );
        $data_attrs .= " data-sort-key='$date $time' title='$date $time $wd'";
        $v = $disp;
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
            $data_attrs .= " lat=$lat lon=$lon";
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
        my $id_idx;
        for (my $j = 0; $j < scalar(@fields); $j++) {
            if ($fields[$j] eq 'Id' || $fields[$j] eq 'IdClr') {
                $id_idx = $j;
                last;
            }
        }
        my $editurl = "$c->{url}?o=Photos&e=$rec[$id_idx]";
        $v = photos::imagetag($c, $v, "thumb", $editurl);
        $word_split = 0;
        if (!$v) {
          if ($cont_active) {
            $tds .= "</td>\n";
            $cont_active = 0;
          }
          _colspan_last_td(\$tds);
          $photo_skipped = 1;
          next;
        }
      } elsif ( $fn eq "Photos" ) {
        if ($v) {
          my @fns = split(/\|/, $v);
          $v = join('', map { photos::imagetag($c, $_, "thumb") } @fns);
        }
        if (!$v) {
          if ($cont_active) {
            $tds .= "</td>\n";
            $cont_active = 0;
          }
          _colspan_last_td(\$tds);
          $photo_skipped = 1;
          next;
        }
      } elsif ( $fn eq "IsGeneric" ) {
        $v = "Gen" if ($v);
      } elsif ( $fn =~ /^(Website|UntappdLink|SearchLink|DetailsLink)$/i ) {
        if ($v) {
          my $label = ($fn =~ /Untappd/i) ? "Ut"     :
                      ($fn =~ /Search/i)  ? "search" : "www";
          $v = util::extlink($v, $label);
          $word_split = 0;
        }
      }
      if ( $was_null_field && $fn =~ /^(Type|Sub|LocType|LocSubType|BrewType)$/i && !$v ) {
        $v = "<span class='null-value'>NULL</span>";
      }
      if ( $suffix_info[$i]{nofilter} ) {
        if ( $v !~ /</ ) {
            $v = util::htmlesc($v);
        }
        $word_split = 0;
      }
      if ( $word_split && $v !~ /</ ) {
        $v = _word_spans($v, $i);
      }
      my $cell_events = $suffix_info[$i]{nofilter} ? "" : " ondblclick='fieldclick_cell(event,this,$i)'";
      my $cell;
      if (length $v) {
          $cell = "<span ${data_attrs}${cell_events}>$v</span>\n";
      } else {
          $cell = "";
      }
      if ($cont_active) {
        $tds .= $cont_sep . $cell;
      } else {
        $tds .= "<td $styles[$i] $extra_attr[$i]>$cell";
      }
      if ($suffix_info[$i]{cont} || $contline_rest) {
        $cont_active = 1;
      } else {
        $tds .= "</td>\n";
        $cont_active = 0;
      }
    }
    if ($cont_active) {
      $tds .= "</td>\n";
    }
    if ($photo_skipped) {
      _colspan_last_td(\$tds);
    }

    $s .= "<tbody$hidden>\n";
    $s .= "<tr data-first=1 class='top-border'>\n";
    $s .= "$tds</tr>\n";
    $s .= "</tbody>\n";
  }
  if ($rowcount == 0) {
    $s .= "<tbody></tbody>\n";
  }
  $s .= "</table>\n";
  $s .= "<!-- listrecords: table body done -->\n";

  if ($hashidden) {
    $s .= "<!-- listrecords: more link -->\n";
    $s .= "<div style='text-align: left; margin-top: 10px; margin-bottom: 20px;'>";
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
# Word-level filter tokenisation for list cell values.
# Parses «…» markers into single tokens (spaces preserved), splits remaining
# text by whitespace into individual words. Each word is rendered as a
# clickable <span>, preserving original special characters in the display.
# The JS fieldclick_word handler strips non-allowed characters on click.
sub _word_spans {
    my $v = shift;
    my $col_idx = shift;
    return $v if $v eq '';

    my @segments;
    while ($v =~ /(.*?)\x{ab}(.*?)\x{bb}/sg) {
        my ($before, $quoted) = ($1, $2);

        if (length $before) {
            foreach my $word (split /\s+/, $before) {
                push @segments, $word if length $word;
            }
        }

        push @segments, $quoted if length $quoted;
    }

    my $after = pos($v) ? substr($v, pos($v)) : $v;
    if (length $after) {
        foreach my $word (split /\s+/, $after) {
            push @segments, $word if length $word;
        }
    }

    return util::htmlesc($v) unless @segments;

    my @spans;
    foreach my $seg (@segments) {
        push @spans, "<span onclick='fieldclick_word(event,this,$col_idx)'>" . util::htmlesc($seg) . "</span>";
    }

    return join(" ", @spans);
}

################################################################################
1; # Tell perl that the module loaded fine
