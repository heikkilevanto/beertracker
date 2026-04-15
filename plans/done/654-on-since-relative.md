# Plan: "On since" relative duration display (issue #654)

## Decisions

- Replace "On since YYYY-MM-DD" with a relative duration: "On for Xm", "On for Xh", or "On for X day(s)".
- Thresholds: < 1h → minutes only ("On for 47m"); 1h–4h → hours and minutes ("On for 2h50m"); < 48h → hours only ("On for 11h"); ≥ 48h → days ("On for 3 days").
- Singular/plural: "1 day", "3 days".
- On click, a hidden sibling `<span>` with the absolute date/time ("since 12-Apr 14:28") is revealed inline; clicking again hides it. This is the same behaviour on both desktop and mobile — no hover tooltip.
- Only shown in the expanded row (unchanged from current behaviour).
- The existing 24h new-beer background highlight (`$is_new`, `$bg`) is unchanged.
- `format_date_relative` is kept as-is for now; its use in `render_beer_row` is replaced by the new helpers.
- Out of scope: changing the "new beer" background-color threshold.

## Database changes

None.

## Phases

### Phase 1 — New helper: `format_duration_relative`

**File:** `code/beerboard.pm`

Add a new function below `format_date_relative` (around line 167):

```perl
sub format_duration_relative {
  my ($first_seen_ts) = @_;
  return "" unless $first_seen_ts;
  my $age = time() - $first_seen_ts;
  if ($age < 3600) {
    my $minutes = int($age / 60);
    return $minutes <= 0 ? "less than 1m" : "${minutes}m";
  } elsif ($age < 4 * 3600) {
    my $hours = int($age / 3600);
    my $mins = int(($age % 3600) / 60);
    return "${hours}h${mins}m";
  } elsif ($age < 48 * 3600) {
    my $hours = int($age / 3600);
    return "${hours}h";
  } else {
    my $days = int($age / 86400);
    my $unit = $days == 1 ? "day" : "days";
    return "$days $unit";
  }
} # format_duration_relative
```

### Phase 2 — New helper: `format_date_absolute`

**File:** `code/beerboard.pm`

Add a companion function that formats the absolute date/time as "12-Apr 14:28":

```perl
sub format_date_absolute {
  my ($date_str, $time_str) = @_;
  return "" unless $date_str;
  my @months = qw(Jan Feb Mar Apr May Jun Jul Aug Sep Oct Nov Dec);
  my ($y, $m, $d) = split /-/, $date_str;
  my $mon = $months[$m - 1];
  my $result = "$d-$mon";
  $result .= " $time_str" if $time_str;
  return $result;
} # format_date_absolute
```

### Phase 3 — Add new fields to `process_beer_entry` return hash

**File:** `code/beerboard.pm`, in the `return { ... }` block around line 353.

Add two new keys alongside the existing `first_seen_*` fields:

```perl
first_seen_relative => format_duration_relative($e->{first_seen_ts}),
first_seen_absolute => format_date_absolute($e->{first_seen_date}, $e->{first_seen_time}),
```

### Phase 4 — Update `render_beer_row` display

**File:** `code/beerboard.pm`, in `render_beer_row`, around line 475.

Replace the current print block:

```perl
if ($processed_data->{first_seen_date_formatted}) {
  print " <span style='font-size: x-small;'>On since $processed_data->{first_seen_date_formatted}.</span>";
}
```

With new markup that shows relative text and a click-to-reveal absolute span:

```perl
if ($processed_data->{first_seen_relative}) {
  my $rel = $processed_data->{first_seen_relative};
  my $abs = $processed_data->{first_seen_absolute};
  print " <span style='font-size: x-small; cursor: pointer;'"
      . " onclick=\"var s=this.nextElementSibling; s.style.display=(s.style.display==='none'?'inline':'none');\">"
      . "On for $rel</span>"
      . "<span style='font-size: x-small; display:none;'>, since $abs</span>";
}
```

## Open questions

None — all questions resolved.
