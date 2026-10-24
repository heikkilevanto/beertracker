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
# Field definitions. An ordered rule list; first match wins. Styles are
# verbatim from the old header if/elsif chain (including the trailing-space
# quirks on some rules — they reach the HTML as-is, so keep them verbatim
# when editing this table). Header lookup keys on the RAW post-suffix-strip
# column name; body lookup keys on the as= alias when present.
#
# Ordering constraints (keep the old chain's order):
#   - ^X first: it wins over everything for hidden columns.
#   - Exact Id/IdClr/Alc rules before the Id|Alc family rule.
#   - Exact Rate before the Rate|Rating family (CommentRating stays identity
#     in the body), and Rate|Rating before Comment|Description (CommentRating
#     must get the Rate style).
#   - Id|Alc family before Comment|Description (CommentId).
#   - Exact PersonName before the LocName|PersonName family (LocName and
#     GlassLocName stay identity in the body); LocName|PersonName before
#     Comment|Description (no live collision, but keep the old order).
#   - Body-only rules (Name, CountryRegion, Prod, BrewName, Day, Locations)
#     go last: they have no header style of their own and must not shadow
#     the style families above.
################################################################################
# Body value formatters. One sub per format code-ref in @FIELD_DEFS; each gets
# the $ctx hashref (see _render_body_row) and returns the new cell value, or
# sets $ctx->{skip} to drop the cell (empty Photo). Referenced from the rules
# as \&_fmt_x. Subs appear in the same order as the rules below.
################################################################################

sub _fmt_id {
  my ($ctx) = @_;
  my $v = $ctx->{v};
  if ($v) {
    my $op2 = "Brew";
    my $pfx = "B";
    if ($ctx->{c}{op} =~ /Photo/i) { $op2 = "Photos"; $pfx = "P"; }
    elsif ($ctx->{c}{op} =~ /Location/i) { $op2 = "Location"; $pfx = "L"; }
    if ( $op2 eq $ctx->{c}{op} ) {
      $v = "<a href='$ctx->{url}?o=$op2&e=$v'"
         . " class='lr-btn'"
         . "><span>$v</span></a>";
    } else {
      $v = "<a href='$ctx->{url}?o=$op2&e=$v'><span>${pfx}[$v]</span></a>: ";
    }
  }
  return $v;
} # _fmt_id

sub _fmt_alc {
  my ($ctx) = @_;
  my $v = $ctx->{v};
  if ($v) {
    ${$ctx->{data_attrs}} .= " data-sort-key='$v'";
    my $display = util::unit($v,"%");
    $v = "<span data-col='$ctx->{i}' data-filter='$v' onclick='fieldclick(event,this)'>$display</span>";
  }
  return $v;
} # _fmt_alc

sub _fmt_stats {
  my ($ctx) = @_;
  my $v = $ctx->{v};
  my ( $cnt, $avg, $com ) = split (";", $v);
  ${$ctx->{data_attrs}} .= " data-sort-key='$avg'" if ($avg);
  $v = comments::avgratings($ctx->{c}, $cnt, $avg, $com);
  if ($v) {
    if ($avg) {
      my $favg = sprintf("%.1f", $avg);
      $v = "<span data-col='$ctx->{i}' data-filter='$favg' onclick='fieldclick(event,this)'>$v</span>";
    }
  }
  return $v;
} # _fmt_stats

# Shared by the Last and LastProd rules; branches on $ctx->{fn}.
sub _fmt_last {
  my ($ctx) = @_;
  my $v = $ctx->{v};
  if ( $v ne '' ) {
    my ($date, $wd, $time) = dateutil::splitdate($v);
    my $disp = "$time $wd";
    $disp = "$date" if ( $date lt $ctx->{cutoff} );
    ${$ctx->{data_attrs}} .= " data-sort-key='$date $time'";
    ${$ctx->{data_attrs}} .= " title='$date $time $wd'" if ( $ctx->{fn} eq "Last" );
    $disp = "[$disp]" if ( $ctx->{fn} eq "LastProd" );
    $v = "<span data-col='$ctx->{i}' data-filter='$date' onclick='fieldclick(event,this)'>"
       . "<span style='position:absolute;left:-9999px'>$date </span>$disp</span>";
  } else {
    $v = "";
  }
  return $v;
} # _fmt_last

sub _fmt_ts {
  my ($ctx) = @_;
  my $v = $ctx->{v};
  if ($v) {
    my ($date, $time) = split(' ', $v);
    if ($date && $time) {
      my ($y, $m, $d) = split('-', $date);
      my $epoch = POSIX::mktime(0, 0, 0, $d, $m-1, $y-1900);
      my @weekdays = ( "Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat" );
      my $wd = $weekdays[(localtime($epoch))[6]];
      my $disp = "$time $wd";
      $disp = "$date" if ( $date lt $ctx->{cutoff} );
      ${$ctx->{data_attrs}} .= " data-sort-key='$date $time' title='$date $time $wd'";
      $v = "<span data-col='$ctx->{i}' data-filter='$date' onclick='fieldclick(event,this)'>"
         . "<span style='position:absolute;left:-9999px'>$date </span>$disp</span>";
    }
  }
  return $v;
} # _fmt_ts

sub _fmt_type {
  my ($ctx) = @_;
  my $v = $ctx->{v};
  my $c = $ctx->{c};
  my $rec = $ctx->{rec};
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
    my $dispstyle = styles::brewtextstyle($c, $style_str, "$c->{op}:$rec->[0] $brewtype/" . ($subtype // ""));
    (my $filter_str = $style_str) =~ s/,/ /g;
    $v = _word_spans($filter_str);
    my $hidden = "";
    $hidden = "<span style='display:none'>Beer </span>" if ($brewtype eq 'Beer' && $subtype);
    $v = $hidden . "<span $dispstyle>$v</span>";
  }
  return $v;
} # _fmt_type

sub _fmt_d {
  my ($ctx) = @_;
  my $v = $ctx->{v};
  if (defined $v && $v ne '') {
    ${$ctx->{data_attrs}} .= " data-sort-key='$v'";
    ${$ctx->{data_attrs}} .= " data-col='$ctx->{i}' data-filter='$v' onclick='fieldclick(event,this)'";
    $v = sprintf('%.1f', $v) . "<span style='font-size: xx-small'>d</span> ";
  } else {
    $v = "";
  }
  return $v;
} # _fmt_d

sub _fmt_pr {
  my ($ctx) = @_;
  my $v = $ctx->{v};
  if ($v) {
    ${$ctx->{data_attrs}} .= " data-sort-key='$v'";
    ${$ctx->{data_attrs}} .= " data-col='$ctx->{i}' data-filter='$v' onclick='fieldclick(event,this)'";
    $v = util::unit($v, ".-");
  } else {
    $v = "";
  }
  return $v;
} # _fmt_pr

sub _fmt_vol {
  my ($ctx) = @_;
  my $v = $ctx->{v};
  if ($v) {
    ${$ctx->{data_attrs}} .= " data-sort-key='$v'";
    ${$ctx->{data_attrs}} .= " data-col='$ctx->{i}' data-filter='$v' onclick='fieldclick(event,this)'";
    $v = util::unit($v, "c");
  } else {
    $v = "";
  }
  return $v;
} # _fmt_vol

sub _fmt_photo {
  my ($ctx) = @_;
  my $v = $ctx->{v};
  my $c = $ctx->{c};
  my $rec = $ctx->{rec};
  my $fields = $ctx->{fields};
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
      for (my $j = 0; $j < scalar(@$fields); $j++) {
          if ($fields->[$j] eq 'Id' || $fields->[$j] eq 'IdClr') {
              $id_idx = $j;
              last;
          }
      }
      $editurl = "$c->{url}?o=Photos&e=$rec->[$id_idx]";
  }
  $v = photos::imagetag($c, $v, "thumb", $editurl);
  ${$ctx->{word_split}} = 0;
  if (!$v) {
    $ctx->{skip} = 1;
  }
  return $v;
} # _fmt_photo

sub _fmt_rate {
  my ($ctx) = @_;
  my $v = $ctx->{v};
  if ($v) {
    ${$ctx->{data_attrs}} .= " data-sort-key='$v'";
    my $rclass = comments::get_rating_class($v);
    $v = "<b class='$rclass'>($v)</b>";
  }
  return $v;
} # _fmt_rate

sub _fmt_chk {
  my ($ctx) = @_;
  return "<input type=checkbox name=Chk$ctx->{id} />";
} # _fmt_chk

sub _fmt_personname {
  my ($ctx) = @_;
  my $v = $ctx->{v};
  if ($v) {
    my @persons = split(/; /, $v);
    my @out;
    foreach my $entry (@persons) {
      my ($name, $pid) = split(/\|/, $entry, 2);
      my $escname = util::htmlesc($name);
      if ($pid) {
        push @out, "<a href='$ctx->{url}?o=Person&e=$pid'"
          . " class='lr-btn'"
          . "><span>P:$pid</span></a>"
          . " <span data-filter='\"" . $escname . "\"' onclick='fieldclick(event,this,$ctx->{i})'>"
          . $escname . "</span>";
      } else {
        push @out, "<span data-filter='\"" . $escname . "\"' onclick='fieldclick(event,this,$ctx->{i})'>"
          . $escname . "</span>";
      }
    }
    $v = join("; ", @out);
  }
  return $v;
} # _fmt_personname

sub _fmt_sim {
  my ($ctx) = @_;
  my $v = $ctx->{v};
  my $fields = $ctx->{fields};
  my $rec = $ctx->{rec};
  if ( $v && $ctx->{extraparams} && $ctx->{extraparams}{refname} ) {
    my $name_idx;
    for (my $j = 0; $j < scalar(@$fields); $j++) {
      if ($fields->[$j] eq 'Name') {
        $name_idx = $j;
        last;
      }
    }
    if (defined $name_idx) {
      my $thisname = $rec->[$name_idx];
      $v = util::namesimilarity($ctx->{extraparams}{refname}, $thisname);
    } else {
      $v = "";
    }
  } else {
    $v = "";
  }
  return $v;
} # _fmt_sim

sub _fmt_geo {
  my ($ctx) = @_;
  my $v = $ctx->{v};
  if ( $v && $ctx->{extraparams} && $ctx->{extraparams}{lat} && $ctx->{extraparams}{lon} ) {
    my ( $lat, $lon ) = split(' ', $v);
    if ( $ctx->{extraparams}{lat} eq '?' ) {
      ${$ctx->{data_attrs}} .= " lat=$lat lon=$lon";
      $v = '?';
    } else {
      my $dist = geo::geodist( $ctx->{extraparams}{lat}, $ctx->{extraparams}{lon}, $lat, $lon );
      $v = "<span data-col='$ctx->{i}' data-filter='$dist' onclick='fieldclick(event,this)'>$dist</span>";
    }
  } elsif ( $v ) {
    # no reference lat/lon, show raw coordinates
    my ( $lat, $lon ) = split(' ', $v);
    $v = "$lat, $lon" if $lat;
  } else {
    $v = "";
  }
  return $v;
} # _fmt_geo

sub _fmt_name {
  my ($ctx) = @_;
  my $v = _word_spans($ctx->{v});
  $v = "<b>$v</b>";
  return $v;
} # _fmt_name

sub _fmt_countryregion {
  my ($ctx) = @_;
  my $v = $ctx->{v};
  my $i = $ctx->{i};
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
  return $v;
} # _fmt_countryregion

sub _fmt_prod {
  my ($ctx) = @_;
  my $v = $ctx->{v};
  if ($v) {
    $v = _word_spans($v);
    $v = "<i>$v</i>";
  }
  return $v;
} # _fmt_prod

sub _fmt_brewname {
  my ($ctx) = @_;
  my $v = $ctx->{v};
  if ($v) {
    $v = _word_spans($v);
    $v = "<b>$v</b>";
  }
  return $v;
} # _fmt_brewname

sub _fmt_day {
  my ($ctx) = @_;
  my $v = $ctx->{v};
  if ($v) {
    my ($date, $wd) = dateutil::splitdate($v);
    $wd =~ s/Sun/<b>Sun<\/b>/;
    $v = "<a href='$ctx->{url}?o=Graph&date=$date&ndays=1'><span>$date $wd</span></a>";
  }
  return $v;
} # _fmt_day

sub _fmt_locations {
  my ($ctx) = @_;
  my $v = $ctx->{v};
  if ($v) {
    my %seen;
    my @parts;
    foreach my $entry (split(/,/, $v)) {
      $entry =~ s/^\s+|\s+$//;
      my ($id, $name) = split(/::/, $entry, 2);
      next unless $id && !$seen{$id}++;
      my $link = "<a href='$ctx->{url}?o=Location&e=$id'"
        . " class='lr-btn'"
        . "><span>L:$id</span></a>";
      if ($name) {
        $link .= " " . _word_spans($name);
      }
      push @parts, $link;
    }
    $v = join(", ", @parts);
  }
  return $v;
} # _fmt_locations

my @FIELD_DEFS = (
  { re   => qr/^X/i,            style => "style='display:none'", hidden => 1 },
  { name => "Id",               style => "style='max-width:40px; text-align:center'",
    word_split => 0, format => \&_fmt_id },
  { name => "IdClr",            style => "style='max-width:40px; text-align:center'",
    placeholder => "Id" },
  { name => "Alc",              style => "style='max-width:55px; text-align:center'",
    format => \&_fmt_alc },
  { re   => qr/Id|Alc/,         style => "style='max-width:55px; text-align:center'" },
  { name => "Stats",            style => "style='max-width:100px; text-align:center'",
    format => \&_fmt_stats },
  # Last and LastProd share _fmt_last; it branches on $ctx->{fn}
  { name => "Last",             style => "style='max-width:100px'",
    format => \&_fmt_last },
  { name => "LastProd",         style => "style='max-width:100px'",
    format => \&_fmt_last },
  { name => "Ts",               style => "style='max-width:100px'",
    format => \&_fmt_ts },
  { name => "Type",             style => "style='max-width:200px; text-align:center'",
    mobile_style => "style='max-width:100px; text-align:center'",
    word_split => 0, format => \&_fmt_type },
  { re   => qr/^(Com|Count)$/,  style => "style='text-align:right; max-width:50px'" },
  { name => "d",                style => "style='text-align:right; max-width:50px'",
    format => \&_fmt_d },
  { name => "Pr",               style => "style='text-align:right; max-width:35px'",
    format => \&_fmt_pr },
  { name => "Vol",              style => "style='text-align:right; max-width:35px'",
    format => \&_fmt_vol },
  { name => "Photo",            style => "style='width:96px; text-align:center; padding:1px'",
    word_split => 0, format => \&_fmt_photo },
  # Exact Rate before the Rate|Rating family: the family style serves
  # CommentRating etc., but only fn="Rate" gets the body format.
  { name => "Rate",             style => "style='text-align:center; font-weight:bold; max-width:50px'",
    format => \&_fmt_rate },
  { re   => qr/Rate|Rating/,    # MUST stay before the Comment rule
    style => "style='text-align:center; font-weight:bold; max-width:50px'" },
  { name => "Chk",              style => "style='text-align:center;max-width:50px'",
    no_events => 1, word_split => 0, format => \&_fmt_chk },
  # Exact PersonName before the LocName|PersonName family: LocName and
  # GlassLocName stay identity in the body (old no-op handler).
  { name => "PersonName",       style => "style='font-weight: bold; max-width:200px;' ",
    word_split => 0, format => \&_fmt_personname },
  { re   => qr/LocName|PersonName/,
    style => "style='font-weight: bold; max-width:200px;' " },
  { re   => qr/Comment|Description/i,
    style => "style='max-width:200px; min-width:0; font-style: italic' " },
  { name => "Sim",              style => "style='max-width:55px; min-width:0; text-align:right' ",
    format => \&_fmt_sim },
  { name => "Geo",              # label and style depend on $c->{mobile}
    style => "style='max-width:100px; min-width:0; text-align:right' ",
    mobile_style => "style='max-width:55px; min-width:0; text-align:right' ",
    label => "Dist (km)", mobile_label => "km",
    format => \&_fmt_geo },
  # Body-only rules (no header style of their own; placed at the end so the
  # style families above win the header lookup). Formats reproduce the old
  # body if/elsif handlers verbatim.
  { name => "Name",             word_split => 0, format => \&_fmt_name },
  { name => "CountryRegion",    word_split => 0, format => \&_fmt_countryregion },
  { name => "Prod",             word_split => 0, format => \&_fmt_prod },
  { name => "BrewName",         word_split => 0, format => \&_fmt_brewname },
  { name => "Day",              word_split => 0, format => \&_fmt_day },
  { name => "Locations",        word_split => 0, format => \&_fmt_locations },
);
# Fall-through (no match): default style, word_split => 1, identity format.
my $FIELD_DEFAULT = {
  style        => "style='max-width:200px; min-width:0'",
  mobile_style => "style='max-width:90px; min-width:0'",
  word_split   => 1,
};

# Pure: no $c, no dbh. Returns a fresh hashref for the first matching rule,
# with the mobile style/label already resolved and word_split defaulted.
# The optional format code-ref is the body value handler (see _render_body_row).
sub field_def {
  my ($name, $mobile) = @_;
  my $rule;
  foreach my $cand (@FIELD_DEFS) {
    if ( defined $cand->{name} ) {
      if ( $name eq $cand->{name} ) { $rule = $cand; last; }
    } elsif ( $name =~ $cand->{re} ) {
      $rule = $cand;
      last;
    }
  }
  my %def = $rule ? %$rule : ();
  my $style = $def{style};
  my $mobile_style = $def{mobile_style};
  if ( !defined $style ) {
    $style = $FIELD_DEFAULT->{style};
    $mobile_style = $FIELD_DEFAULT->{mobile_style};
  }
  $def{style} = ( $mobile && defined $mobile_style ) ? $mobile_style : $style;
  delete $def{mobile_style};
  if ( defined $def{mobile_label} ) {
    $def{label} = $mobile ? $def{mobile_label} : $def{label};
  }
  delete $def{mobile_label};
  $def{word_split} = 1 unless exists $def{word_split};
  return \%def;
} # field_def

################################################################################
# _render_header - the <thead> block. Filter inputs double as column headers.
# Fills @{$st->{styles}} with one style string per column for the body <td>s.
# The field-def lookup is keyed on the raw post-suffix-strip name (the body
# keys on the as= alias when present) — the caller passes the memoized
# lookups as $st->{hdr_def}. The display label comes from the rule (Geo is
# renamed to "km"/"Dist (km)"), with the leading-dash strip applied on top,
# matching the old chain's rename-then-strip order.
sub _render_header {
  my ($c, $st) = @_;
  my $fields         = $st->{fields};         # base names, suffixes stripped
  my $suffix         = $st->{suffix};         # per-column suffix info hashrefs
  my $extra_attr     = $st->{extra_attr};     # rowspan/colspan attrs
  my $hdr_def        = $st->{hdr_def};        # field_def() result per column
  my $px             = $st->{px};             # _Npx width overrides
  my $auto           = $st->{auto};           # _A auto-width flags
  my $initial_filter = $st->{initial_filter};
  my $styles         = $st->{styles};         # OUT: per-column body style

  my $s = "";
  $s .=  "<!-- listrecords: table headers -->\n";
  $s .= "<thead>";
  # Filter inputs also work as column headers, and sort buttons on dbl-click
  $s .= "<tr class='top-border lr-filter-row'>\n";
  my $hdr_cont_active = 0;
  my $hdr_contline_rest = 0;
  my $hdr_photo_rs_rem = 0;
  my @hidden_filters;
  for ( my $i=0; $i < scalar( @$fields ); $i++ ) {
    my $def = $hdr_def->[$i];
    my $label = $def->{label};
    $label = $fields->[$i] unless defined $label;
    my $filter_events = "oninput='changefilter(this);' ondblclick='event.preventDefault(); sortTable(this,$i); return false;'";
    my $break = linebreak($c, $fields->[$i]);
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
      $styles->[$i] = "";
      next;
    }
    my $sty = $def->{style};
    $styles->[$i] = $sty;
    if ( $auto->{$i} ) {
        $styles->[$i] = "";
        $sty = " size='" . (length($label) + 2) . "'";
        $sty .= " style='max-width:70px'" if ( $c->{mobile} );
    } elsif ( $px->{$i} ) {
        $styles->[$i] = "style='max-width:$px->{$i}; min-width:0'";
        $sty = " size='6' style='max-width:$px->{$i}; min-width:0'";
    }
    my $f = $label;
    $f =~ s/^-//;

    if ( $suffix->[$i]{contline} ) {
        _close_cont(\$s, \$hdr_cont_active);
        $hdr_contline_rest = 1;
    }
    if ( $suffix->[$i]{noheader} ) {
        # contline chain active — keep cell open for next column
        if ( !$hdr_contline_rest ) {
            _close_cont(\$s, \$hdr_cont_active);
        }
        if ( !$suffix->[$i]{nofilter} ) {
            push @hidden_filters, "<input type=text style='display:none' data-col='$i' $filter_events/>\n";
        }
        if ($hdr_contline_rest) {
            # contline chain active — skip empty td (for multi-row header layouts)
        } elsif ( $f =~ /^Photos?$/ ) {
            _colspan_last_td(\$s);
            $hdr_photo_rs_rem = $suffix->[$i]{rowspan} || 0;
        } elsif ( $suffix->[$i]{cont} ) {
            # noheader + cont: start empty td but keep open for next column
            $s .= "<td $styles->[$i] $extra_attr->[$i]>\n";
            $hdr_cont_active = 1;
        } else {
            $s .= "<td $styles->[$i] $extra_attr->[$i]></td>\n";
        }
        next;
    }

    # Initial filter value: keyed on the raw name on both header and footer
    # (the footer already uses it; the old header used the renamed name).
    my $val_attr = "";
    if ($initial_filter && exists $initial_filter->{$fields->[$i]}) {
        $val_attr = " value='" . util::htmlesc($initial_filter->{$fields->[$i]}) . "'";
    }
    my $hdr_input;
    if ( $suffix->[$i]{nofilter} ) {
        $hdr_input = $f;
    } elsif ( $f ) {
      my $on = $filter_events;
      $on = "" if ($def->{no_events});
      my $ph = $def->{placeholder};
      $ph = $f unless defined $ph;
      $hdr_input = "<input type=text data-col='$i' $sty $on placeholder='" . util::htmlesc($ph) . "'$val_attr/>";
    } else {
      $hdr_input = "&nbsp;"
    }
    if ($hdr_cont_active) {
        $s .= $hdr_input;
    } else {
        $s .= "<td $sty $extra_attr->[$i]>$hdr_input";
    }
    if ($suffix->[$i]{cont} || $hdr_contline_rest) {
        $hdr_cont_active = 1;
    } else {
        $s .= "</td>\n";
        $hdr_cont_active = 0;
    }
  }
  _close_cont(\$s, \$hdr_cont_active);
  foreach my $i (keys %$px) {
      $styles->[$i] = "style='max-width:$px->{$i}; min-width:0'";
  }
  foreach my $i (keys %$auto) {
      $styles->[$i] = "";
  }
  if ($hdr_photo_rs_rem > 0) {
    _colspan_last_td(\$s);
  }
  $s .= "</tr>\n";
  $s .= join('', @hidden_filters);
  $s .= "</thead>\n";
  $s .=  "<!-- listrecords: table headers done, now the body -->\n";
  return $s;
} # _render_header

################################################################################
# _render_body_row - one <tr> of body cells for @rec. Per-row cont/contline/
# photo state lives here; $st carries the column config and the memoized
# @body_def lookups (keyed on the as= alias when present). Each rule's
# format code-ref gets a $ctx hashref (v, fn, i, rec, fields, c, url,
# extraparams, cutoff, id, and refs to data_attrs / word_split); it returns
# the new value, or sets $ctx->{skip} to drop the cell (empty Photo).
sub _render_body_row {
  my ($c, $st, $rec) = @_;
  my $fields      = $st->{fields};        # base names, suffixes stripped
  my $suffix      = $st->{suffix};        # per-column suffix info hashrefs
  my $extra_attr  = $st->{extra_attr};    # rowspan/colspan attrs
  my $styles      = $st->{styles};        # per-column body style (from header)
  my $body_def    = $st->{body_def};      # field_def() result per column
  my $url         = $st->{url};
  my $extraparams = $st->{extraparams};
  my $cutoff      = $st->{cutoff};

  my $tds = "";
  my $id = $rec->[0]; # Id has to be first if using the Check pseudofield
  my $cont_active = 0;
  my $contline_rest = 0;
  my $photo_skipped = 0;
  for ( my $i=0; $i < scalar( @$rec ); $i++ ) {
    my $v = $rec->[$i];
    my $was_null_field = !defined $v;
    $v //= "";

    my $fn = $fields->[$i];
    my $linebreak = linebreak($c,$fn);
    if ( $linebreak ) {
      _close_cont(\$tds, \$cont_active);
      $contline_rest = 0;
      _maybe_photo_colspan(\$tds, \$photo_skipped);
      $tds .= $linebreak;
      next;
    }
    if ( $suffix->[$i]{contline} ) {
      _close_cont(\$tds, \$cont_active);
      $contline_rest = 1;
    }
    $fn = $suffix->[$i]{as_name} if $suffix->[$i]{as_name};
    my $data_attrs = "data-col='$i'";
    if ( my $ag = $suffix->[$i]{aggregate} ) {
        my $raw = $rec->[$i];
        if (defined $raw && !ref $raw && $raw =~ /^[+-]?\d+\.?\d*$/) {
            $data_attrs .= " data-agg-val='$raw'";
        }
    }
    my $def = $body_def->[$i];
    my $word_split = $def->{word_split};
    # Old chain order: the Name handler wins over a _link= suffix; the
    # suffix case wins over the name rules (Id_A_link=Brew gets the link
    # markup, not the Id handler).
    if ( $suffix->[$i]{link} && !( $fn eq "Name" && $def->{format} ) ) {
      if ($v) {
        $data_attrs .= " data-sort-key='$v'";
        my $entity = $suffix->[$i]{link};
        my $pfx = uc(substr($entity, 0, 1));
        $v = "<a href='$url?o=$entity&e=$v'"
           . " class='lr-btn'"
           . "><span>${pfx}:$v</span></a>";
      }
      $word_split = 0;
    } elsif ( $def->{format} ) {
      my $ctx = {
        v           => $v,
        fn          => $fn,
        i           => $i,
        rec         => $rec,
        fields      => $fields,
        c           => $c,
        url         => $url,
        extraparams => $extraparams,
        cutoff      => $cutoff,
        id          => $id,
        data_attrs  => \$data_attrs,
        word_split  => \$word_split,
      };
      $v = $def->{format}->($ctx);
      if ( $ctx->{skip} ) {
        _close_cont(\$tds, \$cont_active);
        _colspan_last_td(\$tds);  # Best-effort: may fail if last td already has colspan
        $photo_skipped = 1;
        next;
      }
    }
    if ( $was_null_field && $fn =~ /^(Type|Sub|LocType|LocSubType|BrewType)$/i && !$v ) {
      $v = "<span class='null-value'>NULL</span>";
    }
    if ( $suffix->[$i]{filter} ) {
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
    if ( $suffix->[$i]{nofilter} ) {
      if ( $v !~ /</ ) {
          $v = util::htmlesc($v);
      }
      $word_split = 0;
    }
    if ( $word_split && $v !~ /</ ) {
      $v = _word_spans($v);
    }
    my $cell_events = " ondblclick='fieldclick_cell(event,this,$i)'";
    $cell_events = "" if ($suffix->[$i]{nofilter});
    my $cell;
    if (length $v) {
        $cell = "<span ${data_attrs}${cell_events}>$v</span>\n";
    } else {
        $cell = "";
    }
    if ($cont_active) {
      $tds .= $cell;
    } else {
      $tds .= "<td $styles->[$i] $extra_attr->[$i]>$cell";
    }
    if ($suffix->[$i]{cont} || $contline_rest) {
      $cont_active = 1;
    } else {
      $tds .= "</td>\n";
      $cont_active = 0;
    }
  }
  _close_cont(\$tds, \$cont_active);
  _maybe_photo_colspan(\$tds, \$photo_skipped);
  my $tr = "<tr data-first=1 class='top-border'>\n";
  $tr .= "$tds</tr>\n";
  return $tr;
} # _render_body_row

################################################################################
# listrecords - thin dispatcher. The rendering body lives in _render().
################################################################################

sub listrecords {
  my $c = shift;
  my $sql_param = shift;
  my $opt = shift || {};

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

  # Memoized field-def lookups for the header, keyed on the raw
  # post-suffix-strip name (the body keys on the as= alias when present).
  my @hdr_def;
  for (my $i = 0; $i < scalar(@fields); $i++) {
    $hdr_def[$i] = field_def($fields[$i], $c->{mobile});
  }

  # The body lookup is keyed on the as= alias when present (the header keys
  # on the raw name) — this encodes the old chain's quirk in one place.
  my @body_def;
  for (my $i = 0; $i < scalar(@fields); $i++) {
    my $name = $suffix_info[$i]{as_name} || $fields[$i];
    $body_def[$i] = field_def($name, $c->{mobile});
  }

  $s .= _render_header($c, {
    fields         => \@fields,
    suffix         => \@suffix_info,
    extra_attr     => \@extra_attr,
    hdr_def        => \@hdr_def,
    px             => \%px_override,
    auto           => \%auto_override,
    initial_filter => $initial_filter,
    styles         => \@styles,
  });

  my $cutoff = dateutil::datestr("%F", -7);  # a week ago, display full date

  my $body_st = {
    fields      => \@fields,
    suffix      => \@suffix_info,
    extra_attr  => \@extra_attr,
    styles      => \@styles,
    body_def    => \@body_def,
    url         => $url,
    extraparams => $extraparams,
    cutoff      => $cutoff,
  };

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
    my $tr = _render_body_row($c, $body_st, \@rec);

    my $hidden_style = "";
    $hidden_style = " style='display:none'" if ($maxrecords > 0 && $rowcount > $maxrecords);
    $s .= "<tbody data-lr-fs='1'$hidden_style>\n";
    $s .= $tr;
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
