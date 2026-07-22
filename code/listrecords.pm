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
  if ( $field =~ /^TR/i ) {
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
  return 0 if $lt < 0;
  my $gt;
  while ($lt >= 0) {
    $gt = index($$tds_ref, ">", $lt);
    return 0 if $gt <= $lt;
    my $tag = substr($$tds_ref, $lt, $gt - $lt);
    last if $tag !~ /display\s*:\s*none/i;
    $lt = $lt > 0 ? rindex($$tds_ref, "<td", $lt - 1) : -1;
  }
  return 0 if $lt < 0;
  return 0 if substr($$tds_ref, $lt, $gt - $lt) =~ /colspan/i;
  substr($$tds_ref, $gt, 0) = " colspan='2'";
  return 1;
}

################################################################################
# listrecords itself
################################################################################

sub listrecords {
  my $c = shift;
  my $sql_param = shift;
  my $sort = shift;
  my $opt = shift || {};
  my $where          = $opt->{where}          || "";
  my $params         = $opt->{params};
  my $extraparams    = $opt->{extraparams};
  my $maxrecords     = $opt->{maxrecords}     || 20;
  my $browsersortcol = $opt->{browsersortcol};
  my $title          = $opt->{title}          || "";
  my $initial_filter = $opt->{initial_filter} || {};
  my $no_new_link    = $opt->{no_new_link}    || 0;
  my $show_rating_summary = $opt->{show_rating_summary} || 0;
  my $hide_headers_default = $opt->{hide_headers_default} || 0;
  my $gap_column = $opt->{gap_column};

  my $cache_key = join("\x1e", "listrecords", $c->{username}, $sql_param, $where,
    $params ? (ref $params eq 'ARRAY' ? @$params : $params) : ());
  my $cached = cache::get($c, $cache_key);
  if ( defined $cached ) {
    print { $c->{log} } "listrecords: cache hit for $sql_param\n";
    return $cached;
  }

  my @fields;
  my $intro_sth = db::query($c, "$sql_param LIMIT 0");
  @fields = @{$intro_sth->{NAME}};
  $intro_sth->finish;
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
            } elsif ($field =~ s/_as=([^_]+)$//) {
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
              } elsif ($field =~ s/_link=([A-Z][a-zA-Z]+)$//) {
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
                print { $c->{log} } "WARNING: listrecords: Unrecognized suffix '_$1' in column '$orig_field' (sql: $sql_param)\n";
           }
      } while ($changed);
      $fields[$i] = $field;
      $suffix_info[$i] = $suf;
  }
  my ($rate_col, $comment_col) = (-1, -1);
  if ($show_rating_summary) {
    for (my $i = 0; $i < scalar(@fields); $i++) {
      my $fn = $suffix_info[$i]{as_name} || $fields[$i];
      $rate_col    = $i if $fn eq "Rate";
      $comment_col = $i if $fn eq "Comment";
    }
  }

  my $order = "";
  if ( defined $sort ) {
      for (my $i = 0; $i < scalar(@fields); $i++) {
          my $f = $fields[$i];
          if ( $sort =~ /$f(-?)/ ) {
              $order = "Order by $orig_fields[$i]" . ($1 ? " DESC" : "");
          }
      }
  }

  my $gap_col_idx = -1;
  if ($gap_column) {
    for (my $i = 0; $i < scalar(@fields); $i++) {
      if ($fields[$i] eq $gap_column) {
        $gap_col_idx = $i;
        last;
      }
    }
  }

  $where = "where $where" if ($where);

  my $sql = "select * from ($sql_param) $where $order";
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
    .lr-wrapper { overflow-x: auto; }
    table[data-page-size] { border-collapse: separate; border-spacing: 0; }
    .top-border td { border-top: 2px solid white; }
    .null-value { color: #999; font-style: italic; }
    .filtering-active { filter: brightness(1.3); }
    tbody[data-lr-fs] > tr[data-first] > td { white-space: nowrap; }
    .lr-compact thead > tr { display: none; }
    .lr-compact .lr-page-nav-div { display: none !important; }
    .lr-help-popup {
      position: fixed; z-index: 2000; left: 50%; top: 50%;
      transform: translate(-50%, -50%);
      background: var(--altbgcolor, #2a3a4a);
      border: 1px solid #888; border-radius: 8px;
      padding: 16px 20px; max-width: 400px; width: 90%;
      box-shadow: 4px 4px 16px rgba(0,0,0,0.6);
      font-size: 0.9em; line-height: 1.6; color: #fff;
      display: none;
    }
    .lr-help-popup-close {
      float: right; cursor: pointer; font-weight: bold;
      color: #999; font-size: 1.2em; margin-left: 8px;
    }
    .lr-help-popup-close:hover { color: #fff; }
    .lr-help-popup h3 { margin: 0 0 8px 0; }
    .lr-help-popup ul { margin: 4px 0; padding-left: 1.5em; }
    .lr-help-popup kbd {
      background: #444; border: 1px solid #666; border-radius: 3px;
      padding: 0 4px; font-family: inherit;
    }
    </style>\n";

  # Header bar — always rendered, two lines
  $s .= "<div class='lr-wrapper' data-lr-wrapper>\n";
  $s .= "<div class='lr-bar' style='display:flex; flex-direction:column; gap:2px;'>\n";
  $s .= "  <div style='display:flex; align-items:center; gap:4px;'>\n";
  $s .= "    <span class='lr-count'>0</span>&nbsp;<b>$title</b>\n";
  if ( $title !~ /^Photos/i && !$no_new_link ) {
    $s .= "    <a href=\"$url?o=$op&e=new\"\n";
    $s .= "       style='cursor:pointer; border:1px solid #888; border-radius:4px; padding:0 5px; font-size:small; text-decoration:none; color:inherit'><span>New</span></a>\n";
  }
  $s .= "    <span class='lr-clr' onclick='lr_clearfilters(this)'\n";
  $s .= "          style='cursor:pointer; border:1px solid #888; border-radius:4px; padding:0 5px; font-size:small; margin-left:8px'>Clr</span>\n";
  $s .= "    <span class='lr-hdr' onclick='lr_toggleheaders(this)'\n";
  $s .= "          style='cursor:pointer; border:1px solid #888; border-radius:4px; padding:0 5px; font-size:small'>Hdr</span>\n";
  $s .= "    <span class='lr-help' onclick='lr_showhelp()'\n";
  $s .= "          style='cursor:pointer; border:1px solid #888; border-radius:4px; padding:0 5px; font-size:small; display:inline-block; width:1.6em; text-align:center'>?</span>\n";
  $s .= "  </div>\n";
  $s .= "  <div class='lr-page-nav-div' style='display:flex; align-items:center; flex-wrap:wrap; gap:8px;'>\n";
  $s .= "    Showing <select class='lr-size-select' onchange='lr_changesize(this)'>\n";
  my $found = 0;
  foreach my $so (10, 20, 50, 100, 200) {
    my $sel = $so == $maxrecords ? " selected" : "";
    $s .= "      <option value='$so'$sel>$so</option>\n";
    $found = 1 if $so == $maxrecords;
  }
  if (!$found) {
    $s .= "      <option value='$maxrecords' selected>$maxrecords</option>\n";
  }
  $s .= "      <option value='0'>All</option>\n";
  $s .= "    </select>\n";
  $s .= "    <a href='#' class='lr-prev' onclick='return lr_page(this,-1)'><span>Prev</span></a>\n";
  $s .= "    <select class='lr-page-select' onchange='lr_gopage(this)'>\n";
  $s .= "      <option value='1'>1-100</option>\n";
  $s .= "    </select>\n";
  $s .= "    <a href='#' class='lr-next' onclick='return lr_page(this,1)'><span>Next</span></a>\n";
  $s .= "  </div>\n";
  $s .= "</div>\n";
  $s .= "<div class='lr-help-popup' id='lr-help-popup'>\n";
  $s .= "  <span class='lr-help-popup-close' onclick='lr_hidehelp()'>&times;</span>\n";
  $s .= "  <h3>Sorting &amp; Filtering</h3>\n";
  $s .= "  <ul>\n";
  $s .= "    <li><b>Sort</b>: click a column header input to sort ascending, click again for descending. The sort arrow (▲/▼) appears in the input.</li>\n";
  $s .= "    <li><b>Filter</b>: type text in any column header input. Multiple words are AND, comma-separated words are OR. Prefix with <kbd>-</kbd> to exclude, <kbd>=</kbd> for exact match.</li>\n";
  $s .= "    <li><b>Click to filter</b>: click on almost any word in the list to trigger a filter for that word.</li>\n";
  $s .= "    <li><b>Clear</b>: the <kbd>Clr</kbd> button clears all filters at once.</li>\n";
  $s .= "    <li><b>Headers</b>: the <kbd>Hdr</kbd> button shows or hides the column headers and navigation.</li>\n";
  $s .= "    <li><b>Navigate</b>: use the page size selector, <b>Prev</b>/<b>Next</b>, or the page dropdown to move between pages.</li>\n";
  $s .= "  </ul>\n";
  $s .= "</div>\n";
  if ($hide_headers_default) {
    $s .= "<script>(function(w){w.classList.add('lr-compact');})(document.querySelector('[data-lr-wrapper]'));<\/script>\n";
  }

  my $geotable = "";
  if ( $extraparams && (($extraparams->{lat} // '') eq '?') && (($extraparams->{lon} // '') eq '?') ) {
    $geotable = "id='geotable'";
  }
  my $tableid = "";
  if ( $browsersortcol ) {
    $tableid = " id='autosort-table'";
  }
  my $autofilter_attr = ($initial_filter && scalar(keys %$initial_filter)) ? " data-autofilter" : "";
  my $summary_attrs = "";
  if ($show_rating_summary && $rate_col >= 0) {
    $summary_attrs .= " data-col-rate='$rate_col'";
    $summary_attrs .= " data-col-comment='$comment_col'" if $comment_col >= 0;
  }
  my $tableattrs = "$geotable$tableid$autofilter_attr$summary_attrs data-page-size='$maxrecords' data-current-page='1'";

  $s .= "<table class='listrecords' $tableattrs>\n";
  my @styles;  # One for each column

  # Table headers
  $s .=  "<!-- listrecords: table headers -->\n";

  $s .= "<thead>";
  # Filter inputs also work as column headers, and sort buttons on dbl-click
  $s .= "<tr class='top-border lr-filter-row'>\n";
  my $hdr_cont_active = 0;
  my $hdr_contline_rest = 0;
  my $hdr_photo_rs_rem = 0;
  my @hidden_filters;
  for ( my $i=0; $i < scalar( @fields ); $i++ ) {
    my $f = $fields[$i];
    my $filter_events = "oninput='changefilter(this);' ondblclick='event.preventDefault(); sortTable(this,$i); return false;'";
    my $break = linebreak($c,$f);
    if ( $break ) {
      if ($hdr_cont_active) {
        $s .= "</td>\n";
        $hdr_cont_active = 0;
      }
      $hdr_contline_rest = 0;
      if ($hdr_photo_rs_rem > 1) {
        _colspan_last_td(\$s);
      }
      if ($hdr_photo_rs_rem) {
        $hdr_photo_rs_rem--;
      }
      $s .= $break;
      $styles[$i] = "";
      next;
    }
    my $sty = "style='max-width:200px; min-width:0'"; # default
    $sty = "style='max-width:90px; min-width:0'" if ( $c->{mobile} );
    if ( $f =~ /^X/i ) {
      $sty = "style='display:none'";
    } elsif ( $f eq "Id" || $f eq "IdClr" ) {
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
    } elsif ( $f =~ /^(Com|Count|d)$/ ) {
      $sty = "style='text-align:right; max-width:50px'";
    } elsif ( $f =~ /^Pr$/ ) {
      $sty = "style='text-align:right; max-width:35px'";
    } elsif ( $f =~ /^Photo$/ ) {
      $sty = "style='width:96px; text-align:center; padding:1px'";
    } elsif ( $f =~ /^Photos$/ ) {
      $sty = "style='text-align:left; max-width:250px; padding:1px'";
    } elsif ( $f =~ /Rate|Rating/ ) {
      $sty = "style='text-align:center; font-weight:bold; max-width:50px'";
    } elsif ( $f =~ /Chk/) { # Pseudo-field for a checkbox
      $sty = "style='text-align:center;max-width:50px'";
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
            if ($hdr_contline_rest) {
                # contline chain active — keep cell open for next column
            } else {
                $s .= "</td>\n";
                $hdr_cont_active = 0;
            }
        }
        if ( !$suffix_info[$i]{nofilter} ) {
            push @hidden_filters, "<input type=text style='display:none' data-col='$i' $filter_events/>\n";
        }
        if ($hdr_contline_rest) {
            # contline chain active — skip empty td (for multi-row header layouts)
        } elsif ( $f =~ /^Photos?$/ ) {
            _colspan_last_td(\$s);
            $hdr_photo_rs_rem = $suffix_info[$i]{rowspan} || 0;
        } elsif ( $suffix_info[$i]{cont} ) {
            # noheader + cont: start empty td but keep open for next column
            $s .= "<td $styles[$i] $extra_attr[$i]>\n";
            $hdr_cont_active = 1;
        } else {
            $s .= "<td $styles[$i] $extra_attr[$i]></td>\n";
        }
        next;
    }

    my $val_attr = "";
    if ($initial_filter && exists $initial_filter->{$f}) {
        $val_attr = " value='" . util::htmlesc($initial_filter->{$f}) . "'";
    }
    my $hdr_input;
    if ( $suffix_info[$i]{nofilter} ) {
        $hdr_input = $f;
    } elsif ( $f eq "Id" || $f eq "IdClr" ) {
      $hdr_input = "<input type=text data-col='$i' $sty $filter_events placeholder='Id'$val_attr/>";
    } elsif ( $f eq "Name" ) {
      $hdr_input = "<input type=text data-col='$i' $sty $filter_events placeholder='Name'$val_attr/>";
    } elsif ( $f  ) {
      my $on = $f=~/Chk/ ? "" : $filter_events;
      $hdr_input = "<input type=text data-col='$i' $sty $on placeholder='$f'$val_attr/>";
    } else {
      $hdr_input = "&nbsp;"
    }
    if ($hdr_cont_active) {
        $s .= $hdr_input;
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
  if ($hdr_photo_rs_rem > 0) {
    _colspan_last_td(\$s);
  }
  $s .= "</tr>\n";
  $s .= join('', @hidden_filters);
  $s .= "</thead>\n";
  $s .=  "<!-- listrecords: table headers done, now the body -->\n";

  my $cutoff = util::datestr("%F", -7);  # a week ago, display full date

  my ($ratesum, $ratecount, $comcount) = (0, 0, 0);

  my ($rowcount, $prev_gap) = (0, 0);
  while ( my @rec = $list_sth->fetchrow_array ) {
    if ($gap_col_idx >= 0 && defined $rec[$gap_col_idx] && $rec[$gap_col_idx] ne '') {
      my $curr_gap = $rec[$gap_col_idx];
      my $daydiff = $prev_gap - $curr_gap;
      $prev_gap = $curr_gap;
      if ($daydiff > 1) {
        $daydiff--;
        my $gap_text = $daydiff > 1 ? "... $daydiff days ..." : "...";
        my $colspan = scalar(@fields);
        $s .= "<tbody data-gap='1' data-lr-fs='1'><tr data-first=1 class='top-border'><td colspan='$colspan' style='text-align:center;color:#888'>$gap_text</td></tr></tbody>\n";
      }
    }
    $rowcount++;
    my $tds = "";
    my $id = $rec[0]; # Id has to be first if using the Check pseudofield
    my $cont_active = 0;
    my $contline_rest = 0;
    my $photo_skipped = 0;
    for ( my $i=0; $i < scalar( @rec ); $i++ ) {
      my $v = $rec[$i];
      if ($show_rating_summary) {
        if ($rate_col >= 0 && $i == $rate_col && defined $v) {
          $ratesum += $v;
          $ratecount++;
        }
        if ($comment_col >= 0 && $i == $comment_col && defined $v && $v ne '') {
          $comcount++;
        }
      }
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
          my $pfx = uc(substr($entity, 0, 1));
          $v = "<a href='$url?o=$entity&e=$v'"
             . " style='cursor:pointer; border:1px solid #888; border-radius:4px; padding:0 5px; font-size:small; text-decoration:none; color:inherit'"
             . "><span>${pfx}:$v</span></a>";
        }
        $word_split = 0;
      } elsif ( $fn eq "Id" ) {
        if ($v) {
          my $op2 = "Brew";
          my $pfx = "B";
          if ($c->{op} =~ /Photo/i) { $op2 = "Photos"; $pfx = "P"; }
          elsif ($c->{op} =~ /Location/i) { $op2 = "Location"; $pfx = "L"; }
          if ( $op2 eq $c->{op} ) {
            $v = "<a href='$url?o=$op2&e=$v'"
               . " style='cursor:pointer; border:1px solid #888; border-radius:4px; padding:0 5px; font-size:small; text-decoration:none; color:inherit'"
               . "><span>$v</span></a>";
          } else {
            $v = "<a href='$url?o=$op2&e=$v'><span>${pfx}[$v]</span></a>: ";
          }
        }
        $word_split = 0;
      } elsif ( $fn eq "Sub" ) {
        if ($v) {
          $v = "[$v]";
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
          my $hidden = ($brewtype eq 'Beer' && $subtype) ? "<span style='display:none'>Beer </span>" : "";
          $v = $hidden . "<span $dispstyle>$v</span>";
          $word_split = 0;
        }
      } elsif ( $fn eq "Alc" ) {
        if ($v) {
          $data_attrs .= " data-sort-key='$v'";
          my $display = util::unit($v,"%");
          $v = "<span data-col='$i' data-filter='$v' onclick='fieldclick(event,this)'>$display</span>";
        }
      } elsif ( $fn eq "LocName" ) {
        # bare location name — no @ prefix, link prefix handles identification
      } elsif ( $fn eq "CountryRegion" ) {
        my ($country, $region) = split(/;/, $v, 2);
        $v = util::locdesc($c, $country, $region);
        $v .= "&nbsp;&nbsp;" if $v;
        $word_split = 0;
      } elsif ( $fn eq "PersonName" ) {
        if ($v) {
          my @persons = split(/; /, $v);
          my @out;
          foreach my $entry (@persons) {
            my ($name, $pid) = split(/\|/, $entry, 2);
            my $escname = util::htmlesc($name);
            if ($pid) {
              push @out, "<a href='$url?o=Person&e=$pid'"
                . " style='cursor:pointer; border:1px solid #888; border-radius:4px; padding:0 5px; font-size:small; text-decoration:none; color:inherit'"
                . "><span>P:$pid</span></a>"
                . " <span data-filter='\"" . $escname . "\"' onclick='fieldclick(event,this,$i)'>"
                . $escname . "</span>";
            } else {
              push @out, "<span data-filter='\"" . $escname . "\"' onclick='fieldclick(event,this,$i)'>"
                . $escname . "</span>";
            }
          }
          $v = join("; ", @out);
        }
        $word_split = 0;
      } elsif ( $fn eq "Prod" ) {
        if ($v) {
          $v = _word_spans($v, $i);
          $v = "<i>$v</i>";
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
          if ( $extraparams->{lat} eq '?' ) {
            $data_attrs .= " lat=$lat lon=$lon";
            $v = '?';
          } else {
            $v = geo::geodist( $extraparams->{lat}, $extraparams->{lon}, $lat, $lon );
          }
        } elsif ( $v ) {
          # no reference lat/lon, show raw coordinates
          my ( $lat, $lon ) = split(' ', $v);
          $v = "$lat, $lon" if $lat;
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
          _colspan_last_td(\$tds);  # Best-effort: may fail if last td already has colspan
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
          if (_colspan_last_td(\$tds)) {
            $photo_skipped = 1;
            next;
          }
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
      } elsif ( $fn eq "Day" ) {
        if ($v) {
          my ($date, $wd) = util::splitdate($v);
          $wd =~ s/Sun/<b>Sun<\/b>/;
          $v = "<a href='$url?o=Graph&date=$date&ndays=1'><span>$date $wd</span></a>";
        }
        $word_split = 0;
      } elsif ( $fn eq "d" ) {
        if (defined $v && $v ne '') {
          $data_attrs .= " data-sort-key='$v'";
          $v = sprintf('%.1f', $v) . "<span style='font-size: xx-small'>d</span> ";
        } else {
          $v = "";
        }
      } elsif ( $fn eq "Pr" ) {
        if ($v) {
          $data_attrs .= " data-sort-key='$v'";
          $v = util::unit($v, ".-");
        } else {
          $v = "";
        }
      } elsif ( $fn eq "Locations" ) {
        if ($v) {
          my %seen;
          my @parts;
          foreach my $entry (split(/,/, $v)) {
            $entry =~ s/^\s+|\s+$//g;
            my ($id, $name) = split(/::/, $entry, 2);
            next unless $id && !$seen{$id}++;
            my $link = "<a href='$url?o=Location&e=$id'"
              . " style='cursor:pointer; border:1px solid #888; border-radius:4px; padding:0 5px; font-size:small; text-decoration:none; color:inherit'"
              . "><span>L:$id</span></a>";
            if ($name) {
              $link .= " " . _word_spans($name, $i);
            }
            push @parts, $link;
          }
          $v = join(", ", @parts);
        }
        $word_split = 0;
      }
      if ( $was_null_field && $fn =~ /^(Type|Sub|LocType|LocSubType|BrewType)$/i && !$v ) {
        $v = "<span class='null-value'>NULL</span>";
      }
      if ( $suffix_info[$i]{filter} ) {
          $word_split = 0;
          if ($v ne '' && $v !~ /</) {
              my $escaped = util::htmlesc($v);
              if ($v !~ /"/) {
                  $v = "<span data-col='$i' data-filter='&quot;$escaped&quot;' onclick='fieldclick(event,this)'>$escaped</span>";
              } else {
                  $v = "<span data-col='$i' data-filter='$escaped' onclick='fieldclick(event,this)'>$escaped</span>";
              }
          }
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
        $tds .= $cell;
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

    my $hidden_style = ($maxrecords > 0 && $rowcount > $maxrecords) ? " style='display:none'" : "";
    $s .= "<tbody data-lr-fs='1'$hidden_style>\n";
    $s .= "<tr data-first=1 class='top-border'>\n";
    $s .= "$tds</tr>\n";
    $s .= "</tbody>\n";
  }
  if ($rowcount == 0) {
    $s .= "<tbody data-lr-fs='1'></tbody>\n";
  }
  $s .= "</table>\n";
  $s .= "</div>\n";
  if ($show_rating_summary && $rowcount > 0) {
    $s .= "<div class='lr-summary'>";
    if ($ratecount == 1) {
      $s .= "One rating: <b>" . comments::ratingline($ratesum) . "</b>. ";
    } elsif ($ratecount > 0) {
      my $avg = sprintf("%3.1f", $ratesum / $ratecount);
      $s .= "$ratecount Ratings averaging <b>" . comments::ratingline($avg) . "</b>. ";
    } elsif ($comcount > 0) {
      $s .= "Comments: $comcount. ";
    }
    $s .= "</div>\n";
  }
  $s .= "<!-- listrecords: table body done -->\n";

  if ($geotable) {
    $s .= "<script>geotabledist();</script>\n";
  }
  if ( $browsersortcol ) {
    my $sort_idx;
    for (my $i = 0; $i < scalar(@fields); $i++) {
      if ( $fields[$i] eq $browsersortcol ) {
        $sort_idx = $i;
        last;
      }
    }
    if ( defined $sort_idx ) {
      $s .= "<script>autoSortTable('autosort-table', $sort_idx, true);</script>\n";
    }
  }
  $s .= "<script>document.querySelectorAll('[data-lr-wrapper]').forEach(function(w){var p=w.parentNode,s=w.nextSibling;p.removeChild(w);Array.from(w.querySelectorAll('table')).forEach(function(t){lr_paginate(t);});p.insertBefore(w,s);});<\/script>\n";
  if ($initial_filter) {
    for my $i (0..$#fields) {
      if (exists $initial_filter->{$fields[$i]}) {
        my $v = util::htmlesc($initial_filter->{$fields[$i]});
        $s .= "<script>autoFilterTable($i, '$v');<\/script>\n";
        last;
      }
    }
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
