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
    if ($lt > 0) {
      $lt = rindex($$tds_ref, "<td", $lt - 1);
    } else {
      $lt = -1;
    }
  }
  return 0 if $lt < 0;
  return 0 if substr($$tds_ref, $lt, $gt - $lt) =~ /colspan/i;
  substr($$tds_ref, $gt, 0) = " colspan='2'";
  return 1;
}

################################################################################
# Column-name suffix parsing. Each column name from the SQL can carry stacked
# suffixes (_R2_C3_A_90px_cont ...) that are stripped one per pass, repeatedly,
# until nothing recognizable is left. Order matters: one suffix per pass, first
# matching rule wins. Rules are [regex, key, fixed-value?]; a rule without a
# fixed value stores the first capture group. Aggregate stacking: the last
# one stripped wins (e.g. Rate_avg_cnt_A ends with aggregate => "avg").
my @SUFFIX_DEFS = (
  [qr/_R(\d+)$/,                  'rowspan'],
  [qr/_C(\d+)$/,                  'colspan'],
  [qr/_as=([^_]+)$/,              'as_name'],
  [qr/_(\d+px)$/,                 'width_px'],
  [qr/_A$/,                       'auto_width', 1],
  [qr/_filter$/,                  'filter', 1],
  [qr/_nofilter$/,                'nofilter', 1],
  [qr/_noheader$/,                'noheader', 1],
  [qr/_link=([A-Z][a-zA-Z]+)$/,   'link'],
  [qr/_contline$/,                'contline', 1],
  [qr/_cont$/,                    'cont', 1],
  [qr/_sum$/,                     'aggregate', 'sum'],
  [qr/_avg$/,                     'aggregate', 'avg'],
  [qr/_cnt$/,                     'aggregate', 'cnt'],
);

# Pure: no $c, no dbh. Returns a hashref with per-column arrays kept in
# alignment with the input list:
#   base       => \@base_names     fields with suffixes stripped
#   suffix     => \@suffix_info    per-column hashref (rowspan, cont, ...)
#   extra_attr => \@extra_attr     rowspan/colspan attrs for the <td>s
#   px         => \%px_override    _Npx width overrides, keyed by column index
#   auto       => \%auto_override  _A flags, keyed by column index
#   warnings   => \@warnings       unrecognized-suffix messages; the caller
#                                  writes them to $c->{log} with sql context
sub parse_field_suffixes {
  my ($raw_fields) = @_;
  my @base = @$raw_fields;
  my @suffix;
  my @extra_attr = ("") x scalar(@base);
  my %px;
  my %auto;
  my @warnings;
  for (my $i = 0; $i < scalar(@base); $i++) {
    my $suf = {};
    my $orig_field = $base[$i];
    my $changed;
    do {
      $changed = 0;
      foreach my $def (@SUFFIX_DEFS) {
        my ($re, $key, $fixed) = @$def;
        if ( $base[$i] =~ s/$re// ) {
          my $val = defined $fixed ? $fixed : $1;
          $suf->{$key} = $val;
          if ( $key eq 'rowspan' ) { $extra_attr[$i] = "rowspan='$val'"; }
          if ( $key eq 'colspan' ) { $extra_attr[$i] = "colspan='$val'"; }
          if ( $key eq 'width_px' ) { $px{$i} = $val; }
          if ( $key eq 'auto_width' ) { $auto{$i} = 1; }
          $changed = 1;
          last;
        }
      }
      # Unrecognized suffix: warn, do not strip, leave the name as-is.
      if ( !$changed && $base[$i] =~ /_([a-z][a-zA-Z0-9]*)$/ ) {
        push @warnings, "Unrecognized suffix '_$1' in column '$orig_field'";
      }
    } while ($changed);
    $suffix[$i] = $suf;
  }
  return {
    base       => \@base,
    suffix     => \@suffix,
    extra_attr => \@extra_attr,
    px         => \%px,
    auto       => \%auto,
    warnings   => \@warnings,
  };
} # parse_field_suffixes

################################################################################
# Close an open cont/contline td, if one is active. Used at linebreaks, at
# contline starts, and at end of header/row.
sub _close_cont {
  my ($s_ref, $active_ref) = @_;
  if ($$active_ref) {
    $$s_ref .= "</td>\n";
    $$active_ref = 0;
  }
} # _close_cont

# Apply the empty-photo colspan fixup to the last td, if one is owed.
# The flag is deliberately NOT reset here: in the body it stays set for the
# whole row, so every segment-ending td after a skipped photo gets the fixup
# (the photo column and its rowspan would otherwise leave each row segment
# one column short). Callers reset it per row.
sub _maybe_photo_colspan {
  my ($s_ref, $skipped_ref) = @_;
  if ($$skipped_ref) {
    _colspan_last_td($s_ref);
  }
} # _maybe_photo_colspan

################################################################################
# listrecords - thin dispatcher. The rendering body lives in _render().
################################################################################

sub listrecords {
  my $c = shift;
  my $sql_param = shift;
  my $opt = shift || {};

  # #769 scaffolding: render with the frozen reference and the current
  # implementation over the same rows, compare, and always serve the
  # current result. Inert without the lrcompare param. Deleted when the
  # refactor is done.
  if ( util::param($c, "lrcompare") ) {
    require "./code/listrecordsorig.pm";  # frozen pre-#769 module; only loaded here
    $c->{cache_disable} = 1;  # both renders share a cache key; bypass or the
                              # second render gets the first one's result
    my $old = listrecordsorig::listrecords($c, $sql_param, $opt);
    my $new = _render($c, $sql_param, $opt);
    if ( $old eq $new ) {
      $new .= "<!-- lr-compare: OK -->\n";
    } else {
      # Binary-search the common prefix length (= first differing offset).
      # A byte-by-byte scan is far too slow in Perl for MB-sized pages.
      my $minlen = length($old) < length($new) ? length($old) : length($new);
      my ($lo, $hi) = (0, $minlen);  # prefix of length $lo is equal
      while ( $lo < $hi ) {
        my $mid = int(($lo + $hi + 1) / 2);
        if ( substr($old, 0, $mid) eq substr($new, 0, $mid) ) { $lo = $mid; }
        else { $hi = $mid - 1; }
      }
      my $off = $lo;
      my $user = $c->{username} || "unknown";
      # Dump to the datadir, not /tmp: Apache's PrivateTmp hides /tmp from
      # the user, and the datadir is already per-user and writable.
      my $dumpbase = "$c->{datadir}lrcompare-$user";
      print { $c->{log} } "lrcompare: DIFF at offset $off (old " . length($old)
          . " bytes, new " . length($new) . " bytes, sql: $sql_param);\n"
          . "lrcompare: wrote $dumpbase-old.html and $dumpbase-new.html\n";
      if ( open my $fh, ">:encoding(UTF-8)", "$dumpbase-old.html" ) {
        print $fh $old;
        close $fh;
      }
      if ( open my $fh, ">:encoding(UTF-8)", "$dumpbase-new.html" ) {
        print $fh $new;
        close $fh;
      }
      $new .= "<!-- lr-compare: DIFF -->\n";
    }
    return $new;
  }

  return _render($c, $sql_param, $opt);
} # listrecords

################################################################################
# _render - the actual listrecords body
################################################################################

sub _render {
  my $c = shift;
  my $sql_param = shift;
  my $opt = shift || {};
  my $where          = $opt->{where}          || "";
  my $params         = $opt->{params};
  my $extraparams    = $opt->{extraparams};
  my $maxrecords     = $opt->{maxrecords}     || 20;
  my $browsersortcol = $opt->{browsersortcol};
  my $title          = $opt->{title}          || "";
  my $initial_filter = $opt->{initial_filter} || {};
  my $no_new_link    = $opt->{no_new_link}    || 0;
  my $hide_headers_default = $opt->{hide_headers_default} || 0;
  my $allbutton    = $opt->{allbutton}    || 0;
  my $gap_column = $opt->{gap_column};
  my $norecmessage = $opt->{norecmessage};
  my $sql_limit    = $opt->{sql_limit};

  my $showall = 0;
  if ($sql_limit) {
    $showall = util::param($c, "showall") ? 1 : 0;
  }

  my @cache_params = ();
  if ($params) {
    if (ref $params eq 'ARRAY') { @cache_params = @$params; }
    else { @cache_params = ($params); }
  }
  my $cache_key = join("\x1e", "listrecords", $c->{username}, $sql_param, $where, @cache_params, $c->{mobile},
                       "lim" . ($showall ? "all" : ($sql_limit || "")));
  my $cached = cache::get($c, $cache_key);
  if ( defined $cached ) {
    print { $c->{log} } "listrecords: cache hit for $sql_param\n";
    return $cached;
  }

  my @fields;
  my $intro_sth = db::query($c, "$sql_param LIMIT 0");
  @fields = @{$intro_sth->{NAME}};
  $intro_sth->finish;
  my $parsed = parse_field_suffixes(\@fields);
  @fields = @{$parsed->{base}};
  my @extra_attr = @{$parsed->{extra_attr}};
  my %px_override = %{$parsed->{px}};
  my %auto_override = %{$parsed->{auto}};
  my @suffix_info = @{$parsed->{suffix}};  # array of hashrefs, one per column
  foreach my $warnmsg (@{$parsed->{warnings}}) {
    print { $c->{log} } "WARNING: listrecords: $warnmsg (sql: $sql_param)\n";
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

  $where = "WHERE $where" if ($where);

  my $sql = "SELECT * FROM ($sql_param) $where";
  my $truncated = 0;
  if ($sql_limit && !$showall) {
    $sql_limit = int($sql_limit);
    # Fetch one extra row to detect truncation
    $sql .= " LIMIT " . ($sql_limit + 1);
  }
  my @paramarr = ();
  if ( $params ) {
    if (ref $params eq 'ARRAY') { @paramarr = @$params; }
    else { @paramarr = ($params); }
  }
  my $list_sth = db::query($c, $sql);
  $list_sth = db::query($c, $sql, @paramarr) if (@paramarr);
  if ( $norecmessage ) {
    my $peek = $list_sth->fetchrow_arrayref;
    if ( !$peek ) {
      $list_sth->finish;
      return "<i>" . util::htmlesc($norecmessage) . "</i>\n";
    }
    $list_sth->finish;
    $list_sth = db::query($c, $sql);
    $list_sth = db::query($c, $sql, @paramarr) if (@paramarr);
  }

  my $url = $c->{url};
  my $op = $c->{op};

  my $s = "";
  $s .= "<!-- listrecords: $sql -->\n";

  # Header bar — always rendered, two lines
  $s .= "<div class='lr-wrapper' data-lr-wrapper data-initial-pagesize='$maxrecords'>\n";
  $s .= "<div class='lr-bar' style='display:flex; flex-direction:column; gap:2px;'>\n";
  $s .= "  <div style='display:flex; align-items:center; gap:4px;'>\n";
  $s .= "    <span class='lr-count'>0</span>&nbsp;<b>$title</b>\n";
  if ( $title !~ /^Photos/i && !$no_new_link ) {
    $s .= "    <a href=\"$url?o=$op&e=new\"\n";
    $s .= "       class='lr-btn'><span>New</span></a>\n";
  }
  $s .= "    <span class='lr-btn lr-clr' onclick='lr_clearfilters(this)'\n";
  $s .= "          style='display:none; margin-left:8px'>Clr</span>\n";
  $s .= "    <span class='lr-btn lr-hdr' onclick='lr_toggleheaders(this)'>Hdr</span>\n";
  if ($allbutton) {
    $s .= "    <span class='lr-btn lr-all' onclick='lr_showall(this)'>All</span>\n";
  }
  $s .= "    <span class='lr-btn lr-help' onclick='lr_showhelp()'\n";
  $s .= "          style='display:inline-block; width:1.6em; text-align:center'>?</span>\n";
  $s .= "  </div>\n";
  $s .= "  <div class='lr-page-nav-div' style='display:flex; align-items:center; flex-wrap:wrap; gap:8px;'>\n";
  $s .= "    Showing <select class='lr-size-select' onchange='lr_changesize(this)'>\n";
  my $found = 0;
  foreach my $so (5, 10, 20, 50, 100, 200) {
    my $sel = "";
    $sel = " selected" if ($so == $maxrecords);
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
  $s .= "    <li><b>Filter</b>: type text in any column header input. Multiple words are AND, comma-separated words are OR. Prefix with <kbd>-</kbd> to exclude, <kbd>=</kbd> for exact match, <kbd>!=</kbd> for not-equals, <kbd>&gt;=</kbd> <kbd>&gt;</kbd> <kbd>&lt;=</kbd> <kbd>&lt;</kbd> for relational comparison.</li>\n";
  $s .= "    <li><b>Click to filter</b>: click on almost any word in the list to trigger a filter for that word.</li>\n";
  $s .= "    <li><b>Clear</b>: the <kbd>Clr</kbd> button clears all filters at once.</li>\n";
  $s .= "    <li><b>Headers</b>: the <kbd>Hdr</kbd> button shows or hides the column headers and navigation.</li>\n";
  $s .= "    <li><b>Navigate</b>: use the page size selector, <b>Prev</b>/<b>Next</b>, or the page dropdown to move between pages.</li>\n";
  $s .= "  </ul>\n";
  $s .= "</div>\n";
  if ($hide_headers_default || $allbutton) {
    $s .= "<script>(function(w){w.classList.add('lr-compact');})(document.currentScript.parentElement);<\/script>\n";
  }

  my $geotable = "";
  if ( $extraparams && (($extraparams->{lat} // '') eq '?') && (($extraparams->{lon} // '') eq '?') ) {
    $geotable = "id='geotable'";
  }
  my $tableid = "";
  if ( $browsersortcol ) {
    $tableid = " id='autosort-table'";
  }
  my $autofilter_attr = "";
  $autofilter_attr = " data-autofilter" if ($initial_filter && scalar(keys %$initial_filter));
  my $tableattrs = "$geotable$tableid$autofilter_attr data-page-size='$maxrecords' data-current-page='1'";

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
      _close_cont(\$s, \$hdr_cont_active);
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
    } elsif ( $f =~ /^(Last|LastProd|Ts)$/ ) {
      $sty = "style='max-width:100px'";
    } elsif ( $f =~ /^(Type)$/ ) {
      my $w = "100px";
      $w = "200px" unless $c->{mobile};
      $sty = "style='max-width:$w; text-align:center'";
    } elsif ( $f =~ /^(Sub)$/ ) {
      $sty = "style='max-width:70px; text-align:center'";
    } elsif ( $f =~ /^(Com|Count|d)$/ ) {
      $sty = "style='text-align:right; max-width:50px'";
    } elsif ( $f =~ /^(Pr|Vol)$/ ) {
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
    } elsif ( $px_override{$i} ) {
        $styles[$i] = "style='max-width:$px_override{$i}; min-width:0'";
        $sty = " size='6' style='max-width:$px_override{$i}; min-width:0'";
    }
    $f =~ s/^-//;

    if ( $suffix_info[$i]{contline} ) {
        _close_cont(\$s, \$hdr_cont_active);
        $hdr_contline_rest = 1;
    }
    if ( $suffix_info[$i]{noheader} ) {
        # contline chain active — keep cell open for next column
        if ( !$hdr_contline_rest ) {
            _close_cont(\$s, \$hdr_cont_active);
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
      my $on = $filter_events;
      $on = "" if ($f =~ /Chk/);
      $hdr_input = "<input type=text data-col='$i' $sty $on placeholder='" . util::htmlesc($f) . "'$val_attr/>";
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
  _close_cont(\$s, \$hdr_cont_active);
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

  my $cutoff = dateutil::datestr("%F", -7);  # a week ago, display full date

  my ($rowcount, $prev_gap) = (0, 0);
  while ( my @rec = $list_sth->fetchrow_array ) {
    if ($sql_limit && !$showall && $rowcount >= $sql_limit) {
      # We fetched one extra row beyond the limit — mark truncated and stop
      $truncated = 1;
      last;
    }
    if ($gap_col_idx >= 0 && defined $rec[$gap_col_idx] && $rec[$gap_col_idx] ne '') {
      my $curr_gap = $rec[$gap_col_idx];
      my $daydiff = $prev_gap - $curr_gap;
      $prev_gap = $curr_gap;
      if ($daydiff > 1) {
        $daydiff--;
        my $gap_text = "...";
        $gap_text = "... $daydiff days ..." if ($daydiff > 1);
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
      my $was_null_field = !defined $v;
      $v //= "";

      my $fn = $fields[$i];
      my $linebreak = linebreak($c,$fn);
      if ( $linebreak ) {
        _close_cont(\$tds, \$cont_active);
        $contline_rest = 0;
        _maybe_photo_colspan(\$tds, \$photo_skipped);
        $tds .= $linebreak;
        next;
      }
      if ( $suffix_info[$i]{contline} ) {
        _close_cont(\$tds, \$cont_active);
        $contline_rest = 1;
      }
      $fn = $suffix_info[$i]{as_name} if $suffix_info[$i]{as_name};
      my $data_attrs = "data-col='$i'";
      if ( my $ag = $suffix_info[$i]{aggregate} ) {
          my $raw = $rec[$i];
          if (defined $raw && !ref $raw && $raw =~ /^[+-]?\d+\.?\d*$/) {
              $data_attrs .= " data-agg-val='$raw'";
          }
      }
      my $word_split = 1;
      if ( $fn eq "Name" ) {
        $v = _word_spans($v);
        $v = "<b>$v</b>";
        $word_split = 0;
      } elsif ( $suffix_info[$i]{link} ) {
        if ($v) {
          $data_attrs .= " data-sort-key='$v'";
          my $entity = $suffix_info[$i]{link};
          my $pfx = uc(substr($entity, 0, 1));
          $v = "<a href='$url?o=$entity&e=$v'"
             . " class='lr-btn'"
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
               . " class='lr-btn'"
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
          $v = _word_spans($filter_str);
          my $hidden = "";
          $hidden = "<span style='display:none'>Beer </span>" if ($brewtype eq 'Beer' && $subtype);
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
        $country = '' unless defined $country;
        $region  = '' unless defined $region;
        $region =~ s/^\s+|\s+$//g;
        my @parts;
        if ($region ne '' && $country eq 'Denmark') {
            push @parts, "<span data-col='$i' data-filter='" . util::htmlesc($region) . "' onclick='fieldclick(event,this)'>" . util::htmlesc($region) . "</span>";
        } elsif ($country eq 'Denmark') {
            push @parts, "<span data-col='$i' data-filter='" . util::htmlesc($country) . "' onclick='fieldclick(event,this)'>DK</span>";
        } elsif ($region ne '') {
            my $code = $country;
            if (exists $util::COUNTRY_CODES{$country}) {
                $code = (split /,\s*/, $util::COUNTRY_CODES{$country})[0];
            }
            push @parts, "<span data-col='$i' data-filter='" . util::htmlesc($country) . "' onclick='fieldclick(event,this)'>" . util::htmlesc($code) . "</span>";
            push @parts, ", ";
            push @parts, "<span data-col='$i' data-filter='" . util::htmlesc($region) . "' onclick='fieldclick(event,this)'>" . util::htmlesc($region) . "</span>";
        } elsif ($country ne '') {
            push @parts, "<span data-col='$i' data-filter='" . util::htmlesc($country) . "' onclick='fieldclick(event,this)'>" . util::htmlesc($country) . "</span>";
        }
        $v = join("", @parts);
        $v .= "&nbsp;&nbsp;" if @parts;
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
                . " class='lr-btn'"
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
          $v = _word_spans($v);
          $v = "<i>$v</i>";
        }
        $word_split = 0;
      } elsif ( $fn eq "BrewName" ) {
        if ($v) {
          $v = _word_spans($v);
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
          my $rclass = comments::get_rating_class($v);
          $v = "<b class='$rclass'>($v)</b>";
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
            $v = "<span data-col='$i' data-filter='$date' onclick='fieldclick(event,this)'>"
               . "<span style='position:absolute;left:-9999px'>$date </span>$disp</span>";
          }
        }
      } elsif ( $fn eq "Last" || $fn eq "LastProd" ) {
        if ( $v ne '' ) {
          my ($date, $wd, $time) = dateutil::splitdate($v);
          my $disp = "$time $wd";
          $disp = "$date" if ( $date lt $cutoff );
          $data_attrs .= " data-sort-key='$date $time'";
          $data_attrs .= " title='$date $time $wd'" if ( $fn eq "Last" );
          $disp = "[$disp]" if ( $fn eq "LastProd" );
          $v = "<span data-col='$i' data-filter='$date' onclick='fieldclick(event,this)'>"
             . "<span style='position:absolute;left:-9999px'>$date </span>$disp</span>";
        } else {
          $v = "";
        }
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
            my $dist = geo::geodist( $extraparams->{lat}, $extraparams->{lon}, $lat, $lon );
            $v = "<span data-col='$i' data-filter='$dist' onclick='fieldclick(event,this)'>$dist</span>";
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
        my $photoid;
        if ($v =~ /^(\d+):(.*)$/) {
            $photoid = $1;
            $v = $2;
        }
        my $editurl;
        if (defined $photoid) {
            $editurl = "$c->{url}?o=Photos&e=$photoid";
        } else {
            my $id_idx;
            for (my $j = 0; $j < scalar(@fields); $j++) {
                if ($fields[$j] eq 'Id' || $fields[$j] eq 'IdClr') {
                    $id_idx = $j;
                    last;
                }
            }
            $editurl = "$c->{url}?o=Photos&e=$rec[$id_idx]";
        }
        $v = photos::imagetag($c, $v, "thumb", $editurl);
        $word_split = 0;
        if (!$v) {
          _close_cont(\$tds, \$cont_active);
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
          _close_cont(\$tds, \$cont_active);
          if (_colspan_last_td(\$tds)) {
            $photo_skipped = 1;
            next;
          }
        }
      } elsif ( $fn eq "IsGeneric" ) {
        $v = "Gen" if ($v);
      } elsif ( $fn =~ /^(Website|UntappdLink|SearchLink|DetailsLink)$/i ) {
        if ($v) {
          my $label = "www";
          $label = "Ut"     if ($fn =~ /Untappd/i);
          $label = "search" if ($fn =~ /Search/i);
          $v = util::extlink($v, $label);
          $word_split = 0;
        }
      } elsif ( $fn eq "Day" ) {
        if ($v) {
          my ($date, $wd) = dateutil::splitdate($v);
          $wd =~ s/Sun/<b>Sun<\/b>/;
          $v = "<a href='$url?o=Graph&date=$date&ndays=1'><span>$date $wd</span></a>";
        }
        $word_split = 0;
      } elsif ( $fn eq "d" ) {
        if (defined $v && $v ne '') {
          $data_attrs .= " data-sort-key='$v'";
          $data_attrs .= " data-col='$i' data-filter='$v' onclick='fieldclick(event,this)'";
          $v = sprintf('%.1f', $v) . "<span style='font-size: xx-small'>d</span> ";
        } else {
          $v = "";
        }
      } elsif ( $fn eq "Pr" ) {
        if ($v) {
          $data_attrs .= " data-sort-key='$v'";
          $data_attrs .= " data-col='$i' data-filter='$v' onclick='fieldclick(event,this)'";
          $v = util::unit($v, ".-");
        } else {
          $v = "";
        }
      } elsif ( $fn eq "Vol" ) {
        if ($v) {
          $data_attrs .= " data-sort-key='$v'";
          $data_attrs .= " data-col='$i' data-filter='$v' onclick='fieldclick(event,this)'";
          $v = util::unit($v, "c");
        } else {
          $v = "";
        }
      } elsif ( $fn eq "Locations" ) {
        if ($v) {
          my %seen;
          my @parts;
          foreach my $entry (split(/,/, $v)) {
            $entry =~ s/^\s+|\s+$//;
            my ($id, $name) = split(/::/, $entry, 2);
            next unless $id && !$seen{$id}++;
            my $link = "<a href='$url?o=Location&e=$id'"
              . " class='lr-btn'"
              . "><span>L:$id</span></a>";
            if ($name) {
              $link .= " " . _word_spans($name);
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
        $v = _word_spans($v);
      }
      my $cell_events = " ondblclick='fieldclick_cell(event,this,$i)'";
      $cell_events = "" if ($suffix_info[$i]{nofilter});
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
    _close_cont(\$tds, \$cont_active);
    _maybe_photo_colspan(\$tds, \$photo_skipped);

    my $hidden_style = "";
    $hidden_style = " style='display:none'" if ($maxrecords > 0 && $rowcount > $maxrecords);
    $s .= "<tbody data-lr-fs='1'$hidden_style>\n";
    $s .= "<tr data-first=1 class='top-border'>\n";
    $s .= "$tds</tr>\n";
    $s .= "</tbody>\n";
  }
  if ($rowcount == 0) {
    $s .= "<tbody data-lr-fs='1'></tbody>\n";
  }
  $s .= "</table>\n";
  if ($rowcount > 0) {
    my $has_footer;
    for my $i (0..$#fields) { $has_footer = 1 if $suffix_info[$i]{aggregate} }
    if ($has_footer) {
      $s .= "<div data-lr-agg style='display:flex;flex-wrap:wrap;gap:0.5em 1em;padding:2px 0'>\n";
      for my $i (0..$#fields) {
        my $ag = $suffix_info[$i]{aggregate} or next;
        my $fn = $suffix_info[$i]{as_name} || $fields[$i];
        my $rate_attr = "";
        $rate_attr = " data-rate='1'" if ($fn =~ /Rate|Rating/);
        $s .= "<span data-col='$i' data-aggregate='$ag'$rate_attr style='white-space:nowrap'>"
            . "<b>" . util::htmlesc($fn) . "</b>: </span>\n";
      }
      $s .= "</div>\n";
      $s .= "<script>(function(){ var d = document.currentScript.previousElementSibling;\n"
          . "document.addEventListener('DOMContentLoaded', function(){ lr_update_footer(d); });\n"
          . "})();<\/script>\n";
    }
  }
  if ($rowcount > 0) {
    $s .= "<script>var c=document.querySelector('[data-lr-wrapper] .lr-count');if(c)c.textContent='$rowcount ';<\/script>\n";
  }
  if ($truncated) {
    $s .= "<div class='lr-truncated' style='padding:4px 0; color:#888'>\n";
    $s .= "  Showing first $sql_limit records (most recent first).\n";
    $s .= "  <a href='$url?o=$op&showall=1'><span>Show all</span></a>\n";
    $s .= "</div>\n";
  }
  $s .= "</div>\n";
  $s .= "<!-- listrecords: table body done -->\n";

  if ($geotable) {
    $s .= "<script>document.addEventListener('DOMContentLoaded', function(){ geotabledist(); });</script>\n";
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
      $s .= "<script>document.addEventListener('DOMContentLoaded', function(){ autoSortTable('autosort-table', $sort_idx, true); });</script>\n";
    }
  }
  $s .= "<script>document.addEventListener('DOMContentLoaded', function(){ document.querySelectorAll('[data-lr-wrapper] table').forEach(function(t){lr_paginate(t);}); });<\/script>\n";
  if ($initial_filter) {
    for my $i (0..$#fields) {
      if (exists $initial_filter->{$fields[$i]}) {
        my $v = $initial_filter->{$fields[$i]};
        $v =~ s/\\/\\\\/g;
        $v =~ s/'/\\'/g;
        $s .= "<script>document.addEventListener('DOMContentLoaded', function(){ autoFilterTable($i, '$v'); });</script>\n";
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
# Split cell text by whitespace into individual clickable words.
# Each word is rendered as a <span class='fw'> for column filtering.
# A delegated click handler in listrecords.js picks these up and finds the
# column via the nearest data-col ancestor. The JS strips non-allowed
# characters on click.
sub _word_spans {
    my $v = shift;
    return $v if $v eq '';

    my @segments = grep { length } split /\s+/, $v;

    return util::htmlesc($v) unless @segments;

    my @spans;
    foreach my $seg (@segments) {
        push @spans, "<span class='fw'>" . util::htmlesc($seg) . "</span>";
    }

    return join(" ", @spans);
}

################################################################################
1; # Tell perl that the module loaded fine
