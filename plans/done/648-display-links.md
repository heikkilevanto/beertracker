# Plan for Issue #648: Display links in brews and locations

## Summary

The schema already has the link fields (from migration 019 / issue #647):
- `locations.Website` — existing
- `locations.UntappdLink` — new
- `locations.SearchLink` — new (producer search link, e.g. dryandbitter.com)
- `brews.DetailsLink` — new

This issue is about *displaying* those links in appropriate places.

---

## 1. util.pm — add link helpers

Add two helpers near the bottom of util.pm:

```perl
# extlink($url, $text) — returns an <a> that opens in _blank, or "" if no url
# All external links should go via this helper.
sub extlink {
  my $url  = shift // "";
  my $text = shift;
  return "" unless $url;
  return "<a href='" . htmlesc($url) . "' target='_blank'><span>$text</span></a>";
}

# brewlinks($brew_record) — returns short link badges for a brew
# Returns "Ut", "www", or "uts" (untappd search fallback)
# $name is used for the fallback search
sub brewlinks {
  my $c    = shift;
  my $link = shift // "";   # DetailsLink from brews table
  my $name = shift // "";   # brew name, for fallback search
  if ($link =~ /untappd/i) {
    return extlink($link, "Ut");
  } elsif ($link) {
    return extlink($link, "www");
  } else {
    my $q = uri_escape_utf8($name);
    return extlink("https://untappd.com/search?q=$q", "uts");
  }
}

# locationlinks($loc_record) — returns short link badges for a location
# Prefers Website ("www"), then UntappdLink ("Ut"), then untappd venue search ("uts")
sub locationlinks {
  my $c       = shift;
  my $website = shift // "";   # Website field
  my $utlink  = shift // "";   # UntappdLink field
  my $name    = shift // "";   # location name, for fallback search
  my $s = "";
  if ($website) {
    $s .= extlink($website, "www");
  }
  if ($utlink) {
    $s .= extlink($utlink, "Ut");
  } elsif (!$website) {
    my $q = uri_escape_utf8($name);
    $s .= extlink("https://untappd.com/search?q=$q&type=venues&sort=", "uts");
  }
  return $s;
}
```

Note: `util.pm` needs `use URI::Escape qw(uri_escape_utf8);` added at the top.

---

## 2. mainlist.pm — locationhead

**Change**: fetch `gloc.UntappdLink` in the SQL query (`glassquery`), and use `locationlinks()` in `locationhead`.

### 2a. SQL in glassquery
Add `gloc.UntappdLink as locutlink` alongside `gloc.Website as locwebsite`.

### 2b. locationhead
Replace the current `www` link block:
```perl
$html .= "<a href='$locwebsite' target='_blank'><span style='font-size: x-small;'>www</span></a>"
  if ( $locwebsite );
```
With:
```perl
$html .= util::locationlinks($c, $locwebsite, $rec->{locutlink}, $locname);
```
(The helper already wraps each in `<span>` via extlink, but we may want `font-size: x-small` too — handle that inside the helper or with a CSS class.)

---

## 3. mainlist.pm — nameline (brew link after brew id)

**Change**: fetch `brews.DetailsLink as brewlink` in `glassquery`, pass it via `$rec`, display after the id badge.

### 3a. SQL
Add `brews.DetailsLink as brewlink` to the main SELECT.

### 3b. nameline
After:
```perl
$html .= "<span style='font-size: x-small;'> [$rec->{brewid}]</span>" if($rec->{brewid});
```
Add:
```perl
$html .= util::brewlinks($c, $rec->{brewlink}, $rec->{brewname}) if ($rec->{brewid});
```

---

## 4. inputs.pm — inputform, link fields shown as clickable links

When not in edit mode (`$disabled eq "disabled"`), for fields that look like URL fields (`Website`, `UntappdLink`, `SearchLink`, `DetailsLink`), show the field label as a clickable link AND the URL itself as a small link, rather than just a disabled text input.

Add a special case in the regular-input branch of `inputform`:

```perl
} elsif ( $f =~ /Website|UntappdLink|SearchLink|DetailsLink/i ) {
  my $curval = ($rec && defined($rec->{$f})) ? $rec->{$f} : "";
  my $esc    = util::htmlesc($curval);
  $form .= "<td>\n";
  if ($disabled) {
    # Show as a link (if url present) or as plain text placeholder
    if ($curval) {
      $form .= "<a href='$esc' target='_blank'><span>$pl</span></a>\n";
    } else {
      $form .= "<span style='color:#888'>$pl</span>\n";
    }
  } else {
    # Editing: normal input + onchange updates a preview <a> next to it
    $form .= "<input name='$inpname' value='$esc' $clr $disabled " .
             "onchange=\"var a=document.getElementById('lnk-$inpname');" .
             " a.href=this.value; a.style.display=this.value?'':'none';\"/>\n";
    my $display = $curval ? "inline" : "none";
    $form .= "<a id='lnk-$inpname' href='$esc' target='_blank' style='display:$display'>" .
             "<span>&#x1F517;</span></a>\n";
  }
}
```

---

## 5. brews.pm — editbrew, search line

After the form (after `<hr/>`), for existing brews, add a search-links line:

```perl
# Search links for the brew
my $search_html = "";
my $prodname = $p->{ProducerName} // "";  # need to fetch from location join
my $prodlink = "";
# fetch producer searchlink
if ($p->{ProducerLocation}) {
  my $prod = db::getrecord($c, "LOCATIONS", $p->{ProducerLocation});
  if ($prod && $prod->{SearchLink}) {
    my $q = uri_escape_utf8($p->{Name});
    my $url = $prod->{SearchLink};
    $url =~ s/\{\{q\}\}/$q/g;  # allow template marker, else:
    # If no placeholder, just show the producer's search page
    $search_html .= util::extlink($url, "producer") . " ";
  }
}
my $qbrew  = uri_escape_utf8(($p->{Producer} ? "$p->{Producer} " : "") . $p->{Name});
$search_html .= util::extlink("https://untappd.com/search?q=$qbrew", "untappd") . " ";
my $qg = uri_escape_utf8(($p->{Producer} ? "$p->{Producer} " : "") . $p->{Name} . " beer");
$search_html .= util::extlink("https://www.google.com/search?q=$qg", "google");
print "Search: $search_html<br/>\n";
```

**Note**: The `editbrew` function currently gets the record with `db::getrecord($c, "BREWS", $c->{edit})` which returns raw fields. We need `ProducerLocation` to look up the producer. That field is already in the BREWS table. We'll fetch the producer record separately.

---

## 6. locations.pm — editlocation, search line

Similarly after the form, for existing locations:

```perl
if ($p->{Id} ne "new") {
  my $qname = uri_escape_utf8($p->{Name});
  my $search_html = "";
  $search_html .= util::extlink("https://untappd.com/search?q=$qname&type=venues&sort=", "untappd") . " ";
  $search_html .= util::extlink("https://www.google.com/search?q=$qname", "google");
  print "Search: $search_html<br/>\n";
}
```

---

## 7. listrecords.pm — handle link columns as clickable links

In the field-rendering loop, add a case for fields that contain URLs (Website, UntappdLink, SearchLink, DetailsLink):

```perl
} elsif ( $fn =~ /^(Website|UntappdLink|SearchLink|DetailsLink)$/i ) {
  if ($v) {
    my $label = ($fn =~ /Untappd/i) ? "Ut" :
                ($fn =~ /Search/i)  ? "search" : "www";
    $v = "<a href='" . util::htmlesc($v) . "' target='_blank'><span>$label</span></a>";
  }
}
```

---

## Implementation order

1. `util.pm` — add helpers (`extlink`, `brewlinks`, `locationlinks`)
2. `mainlist.pm` — extend SQL + locationhead + nameline
3. `inputs.pm` — URL field display in inputform
4. `brews.pm` — search line in editbrew
5. `locations.pm` — search line in editlocation
6. `listrecords.pm` — link column rendering

## Notes / Questions

- The `locationlinks` helper currently shows `uts` only if there's no website AND no UntappdLink. The issue says: "If the location has the website link, use that as 'www'. Otherwise if it has untappd link, show that as 'Ut'. If not, make a link to search in untappd, 'uts'." So the logic should be: if website → www; else if UntappdLink → Ut; else → uts. Only one link shown. But showing both www AND Ut (when both exist) might also be useful. Clarify with user.
- For the producer SearchLink in brew edit: should it be a template like `https://dryandbitter.com/search?q={name}`, or always append the brew name? The current `SearchLink` column doesn't define a template convention. A simple approach: if SearchLink is set, just show it as a "producer search" link and let the user add the query manually. Or we can append ?q=NAME. Clarify.
- For `inputs.pm` URL field handling: the field order in `inputform` is driven by `db::tablefields`. This means `Website`, `UntappdLink`, `SearchLink`, `DetailsLink` will appear automatically in the right sections. The special display only kicks in for those named fields.
