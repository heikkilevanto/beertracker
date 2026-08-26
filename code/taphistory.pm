# Part of my beertracker
# Tap Timeline - location tap history visualization (plan 750)
#
# Renders a per-day, per-tap timeline of what beer was on each tap at a
# location. Daily granularity only: each (tap, day) cell shows the single
# most-recent beer that was on that tap that day. Consecutive same-beer days
# are merged with colspan for a Gantt-like look.
#
# Entry points:
#   o=Taps&loc=<name>              location timeline (default: first scraper loc)
#   o=Taps&loc=<name>&tap=<N>      single-tap chronological detail
#   o=Taps&loc=<name>&days=14|30|60|90   number of daily columns (default 30)

package taphistory;

use strict;
use warnings;
use feature 'unicode_strings';
use utf8;
use open ':encoding(UTF-8)';
use Time::Local qw(timelocal);
use POSIX qw(strftime);
use JSON;
use URI::Escape qw(uri_escape_utf8);

# styles.pm is loaded by index.fcgi via require; call styles::* directly.

################################################################################
# Helpers
################################################################################

# Effective day of a local timestamp, shifted by the app's -6h day convention
# so late-night drinking counts as the previous day. Returns "YYYY-MM-DD".
sub eff_day_of {
    my ($ts) = @_;
    return "" unless $ts;
    $ts =~ /^(\d{4})-(\d{2})-(\d{2})[ T](\d{2}):(\d{2}):(\d{2})/;
    return "" unless $1;
    my $epoch = timelocal($6, $5, $4, $3, $2 - 1, $1 - 1900);  # local
    $epoch -= 6 * 3600;
    my ($Y, $M, $D) = (localtime($epoch))[5, 4, 3];
    return sprintf("%04d-%02d-%02d", $Y + 1900, $M + 1, $D);
} # eff_day_of

# Add (or subtract) a number of calendar days to a "YYYY-MM-DD" string.
# Uses local noon so DST transitions do not shift the derived date.
sub date_plus_days {
    my ($datestr, $k) = @_;
    $datestr =~ /^(\d{4})-(\d{2})-(\d{2})/;
    my $epoch = timelocal(0, 0, 12, $3, $2 - 1, $1 - 1900) + $k * 86400;
    my ($Y, $M, $D) = (localtime($epoch))[5, 4, 3];
    return sprintf("%04d-%02d-%02d", $Y + 1900, $M + 1, $D);
} # date_plus_days

# Foreground color for a hex background, matching styles::brewtextstyle.
sub fg_for {
    my ($c, $hex) = @_;
    $hex =~ s/^#//;
    my ($r, $g, $b) = ($hex =~ /(..)(..)(..)/);
    return "#ffffff" unless $r;
    my $lum = (hex($r) + hex($g) + hex($b)) / 3;
    return $lum < 64 ? "#ffffff" : $c->{bgcolor};
} # fg_for

# Parse a local "YYYY-MM-DD HH:MM:SS" into an epoch (local).
sub ts_epoch {
    my ($ts) = @_;
    return undef unless $ts;
    $ts =~ /^(\d{4})-(\d{2})-(\d{2})[ T](\d{2}):(\d{2}):(\d{2})/;
    return undef unless $1;
    return timelocal($6, $5, $4, $3, $2 - 1, $1 - 1900);
} # ts_epoch

my @MON_ABBR = qw(Jan Feb Mar Apr May Jun Jul Aug Sep Oct Nov Dec);

################################################################################
# Main entry
################################################################################

sub taphistory {
    my $c = shift;

    # Resolve location
    my $locparam = util::param($c, "loc");
    if (!$locparam) {
        my @scraper = scrapeboard::get_scraper_locations($c);
        $locparam = $scraper[0] if @scraper;
    }
    my $locrec = db::findrecord($c, "LOCATIONS", "Name", $locparam, "collate nocase");

    # Days parameter (whitelist)
    my $days = util::param($c, "days") || 30;
    $days = 30 unless $days =~ /^(14|30|60|90)$/;

    if (!$locrec) {
        render_selector_only($c, $locparam);
        return;
    }

    my $loc_id = $locrec->{Id};
    my $locname = $locrec->{Name};

    # Single-tap detail view
    my $tap = util::param($c, "tap");
    if (defined $tap && $tap =~ /^\d+$/) {
        render_single_tap($c, $loc_id, $locname, $tap, $days);
        return;
    }

    render_timeline($c, $loc_id, $locname, $days);
} # taphistory

################################################################################
# Timeline view
################################################################################

sub render_timeline {
    my ($c, $loc_id, $locname, $days) = @_;

    # Reference "now" = latest LastSeen for the location
    my ($ref) = db::queryarray($c,
        "SELECT max(LastSeen) FROM tap_beers WHERE Location = ?", $loc_id);
    my $end_ref = $ref;  # fall back to now if no scrape data at all
    if (!$end_ref) {
        my @t = localtime(time());
        $end_ref = strftime("%Y-%m-%d %H:%M:%S", @t);
    }
    $end_ref =~ s/T/ / if $end_ref;

    my $end_epoch = ts_epoch($end_ref) // time();
    my $end_day = eff_day_of($end_ref);
    my $start_day = date_plus_days($end_day, -($days - 1));

    # Day buckets (effective day D -> local half-open [D 06:00, (D+1) 06:00))
    my @buckets;
    for my $k (0 .. $days - 1) {
        my $D = date_plus_days($start_day, $k);
        push @buckets, {
            day   => $D,
            bs    => $D . " 06:00:00",
            be    => date_plus_days($D, 1) . " 06:00:00",
        };
    }
    my $env_start = $start_day . " 06:00:00";
    my $env_end   = date_plus_days($end_day, 1) . " 06:00:00";

    # Fetch overlapping tap periods
    my $sth = $c->{dbh}->prepare(q{
        SELECT tb.Id, tb.Tap, tb.Brew, b.Name AS BrewName, b.ShortName,
               b.BrewType, b.SubType, b.BrewStyle,
               tb.FirstSeen, tb.Gone,
               pl.Name AS ProducerName, pl.Id AS ProducerId,
               tb.SizeS, tb.PriceS, tb.SizeM, tb.PriceM, tb.SizeL, tb.PriceL
        FROM tap_beers tb
        LEFT JOIN brews b ON tb.Brew = b.Id
        LEFT JOIN locations pl ON b.ProducerLocation = pl.Id
        WHERE tb.Location = ? AND tb.Tap IS NOT NULL AND tb.Brew IS NOT NULL
          AND tb.FirstSeen <= ?
          AND (tb.Gone IS NULL OR tb.Gone >= ?)
        ORDER BY tb.Tap, tb.FirstSeen
    });
    $sth->execute($loc_id, $env_end, $env_start);

    my %tap_days;     # tap -> [ rec-or-undef ] x N (chronological)
    my %details;      # bid -> info
    my %seen_bid;

    while (my $r = $sth->fetchrow_hashref) {
        my $bid = $r->{Brew};
        my $type = $r->{BrewType} || "";
        my $sub = $r->{SubType} || "";
        my $bg = styles::brewcolor($c, "$type,$sub");
        my $fg = fg_for($c, $bg);

        unless ($seen_bid{$bid}) {
            $seen_bid{$bid} = 1;
            $details{$bid} = {
                name  => $r->{BrewName} || "?",
                sub   => $sub || $type || "Unknown",
                style => $r->{BrewStyle} || "",
                prod  => $r->{ProducerName} || "",
                prodid=> $r->{ProducerId} || "",
                color => "#$bg",
                fg    => $fg,
            };
        }

        my $ge = $r->{Gone};
        my $fs_epoch = ts_epoch($r->{FirstSeen}) // 0;
        my $ge_epoch = $ge ? (ts_epoch($ge) // $end_epoch) : $end_epoch;
        my $dur = int(($ge_epoch - $fs_epoch) / 86400);

        my $rec = {
            bid    => $bid,
            name   => $r->{BrewName} || "?",
            sub    => $sub || $type || "Unknown",
            type   => $type,
            style  => $r->{BrewStyle} || "",
            prod   => $r->{ProducerName} || "",
            prodid => $r->{ProducerId} || "",
            bg     => "#$bg",
            fg     => $fg,
            fs     => $r->{FirstSeen},
            since  => substr($r->{FirstSeen}, 0, 10),
            gone   => $ge ? substr($ge, 0, 10) : "still on tap",
            days   => $dur,
            price  => "",
        };
        if ($r->{PriceS})      { $rec->{price} = "$r->{SizeS} cl / $r->{PriceS}"; }
        elsif ($r->{PriceM})   { $rec->{price} = "$r->{SizeM} cl / $r->{PriceM}"; }
        elsif ($r->{PriceL})   { $rec->{price} = "$r->{SizeL} cl / $r->{PriceL}"; }

        my $tap = int($r->{Tap});
        $tap_days{$tap} = [ (undef) x scalar(@buckets) ] unless exists $tap_days{$tap};
        for my $i (0 .. $#buckets) {
            my $bk = $buckets[$i];
            next unless day_overlap($r->{FirstSeen}, $ge, $bk->{bs}, $bk->{be}, $end_ref);
            my $cur = $tap_days{$tap}->[$i];
            if (!defined($cur) || $r->{FirstSeen} gt $cur->{fs}) {
                $tap_days{$tap}->[$i] = $rec;
            }
        }
    }
    $sth->finish;

    # Scrape markers
    my ($marker_str) = db::queryarray($c, q{
        SELECT group_concat(SUBSTR(FirstSeen,1,10), ', ')
        FROM (SELECT FirstSeen FROM tap_beers
              WHERE Location = ? AND Tap IS NULL AND Brew IS NULL
              ORDER BY FirstSeen DESC LIMIT 5)
    }, $loc_id);
    $marker_str ||= "none";

    print render_controls($c, $locname, $days);
    print "<div id='details'><span class='close' onclick='closeDetails()'>&#10005;</span>"
        . "<div id='details-body'></div></div>";

    my $N = scalar(@buckets);
    my $table_w = 40 + $N * 22 + ($N + 1) * 2;  # + border-spacing
    print "<div class='overflow-auto'>\n"
        . "<table class='timeline' style='width:" . $table_w . "px'>\n";
    print "<colgroup><col width='40'><col width='22' span='$N'></colgroup>\n";
    print "<thead><tr><th class='tapcol'>Tap</th>\n";
    for my $bk (reverse @buckets) {
        my ($yyyy, $mm, $dd) = $bk->{day} =~ /^(\d\d\d\d)-(\d\d)-(\d\d)$/;
        print "<th class='daycol'><span class='mon'>" . $MON_ABBR[$mm - 1]
            . "</span><span class='day'>$dd</span></th>\n";
    }
    print "</tr></thead>\n<tbody>\n";

    for my $tap (sort { $a <=> $b } keys %tap_days) {
        my @cells = build_cells($tap_days{$tap});
        print "<tr>\n";
        print "<td class='tapcol'><a href='$c->{url}?o=Taps&loc="
            . uri_escape_utf8($locname) . "&amp;tap=$tap'><span>#$tap</span></a></td>\n";
        for my $cell (@cells) {
            my ($rec, $span) = @$cell;
            if (!defined $rec) {
                print "<td colspan='$span'></td>\n";
            } else {
                my $title = util::htmlesc($rec->{name})
                    . ($rec->{style} ? " — " . util::htmlesc($rec->{style}) : "")
                    . ($rec->{prod} ? " (" . util::htmlesc($rec->{prod}) . ")" : "")
                    . " | " . util::htmlesc($rec->{since});
                my $ds = util::htmlesc($rec->{since});
                my $dg = util::htmlesc($rec->{gone});
                my $dp = util::htmlesc($rec->{price});
                print "<td colspan='$span' style='background-color:" . $rec->{bg} . "'>"
                    . "<span class='tap-cell' style='color:" . $rec->{fg} . "' "
                    . "title='" . $title . "' "
                    . "data-brewid='" . util::htmlesc($rec->{bid}) . "' "
                    . "data-tap='$tap' data-since='$ds' data-gone='$dg' "
                    . "data-days='" . $rec->{days} . "' data-price='$dp' "
                    . "onclick='showDetails(this)'>"
                    . util::htmlesc($rec->{name}) . "</span></td>\n";
            }
        }
        print "</tr>\n";
    }
    print "</tbody></table>\n</div>\n";
    print "<div class='footer'>Last scraped: " . util::htmlesc($marker_str) . "</div>\n";

    my $det = JSON->new->encode(\%details);
    print "<script>\n"
        . "var TAP_LOC = '" . util::htmlesc($locname) . "';\n"
        . "var TAP_DETAILS = $det;\n"
        . "</script>\n";
} # render_timeline

# Half-open overlap test: period covers bucket [bs, be) iff
#   FirstSeen < be  AND  bs < coalesce(Gone, end_ref)
sub day_overlap {
    my ($fs, $ge, $bs, $be, $end_ref) = @_;
    $ge = $end_ref unless $ge;
    return ($fs lt $be) && ($bs lt $ge);
} # day_overlap

# Merge consecutive same-brew (or empty) cells, in display order (most recent first)
sub build_cells {
    my ($daylist) = @_;
    my @disp = reverse(@$daylist);
    my @cells;
    my $i = 0;
    while ($i < @disp) {
        my $rec = $disp[$i];
        my $j = $i;
        while ($j < @disp) {
            my $o = $disp[$j];
            my $same = (!defined($o) && !defined($rec))
                || (defined($o) && defined($rec) && $o->{bid} eq $rec->{bid});
            last unless $same;
            $j++;
        }
        push @cells, [ $rec, $j - $i ];
        $i = $j;
    }
    return @cells;
} # build_cells

################################################################################
# Single-tap detail view
################################################################################

sub render_single_tap {
    my ($c, $loc_id, $locname, $tap, $days) = @_;

    my $end_ref = undef;
    my ($ref) = db::queryarray($c,
        "SELECT max(LastSeen) FROM tap_beers WHERE Location = ?", $loc_id);
    $end_ref = $ref if $ref;
    $end_ref =~ s/T/ / if $end_ref;
    my $end_epoch = ts_epoch($end_ref) // time();
    my $env_start = date_plus_days(eff_day_of($end_ref), -($days - 1)) . " 06:00:00";
    my $env_end   = date_plus_days(eff_day_of($end_ref), 1) . " 06:00:00";

    my $sth = $c->{dbh}->prepare(q{
        SELECT tb.Id, tb.Tap, tb.Brew, b.Name AS BrewName,
               b.BrewType, b.SubType, b.BrewStyle,
               tb.FirstSeen, tb.Gone,
               pl.Name AS ProducerName, pl.Id AS ProducerId,
               tb.SizeS, tb.PriceS, tb.SizeM, tb.PriceM, tb.SizeL, tb.PriceL
        FROM tap_beers tb
        LEFT JOIN brews b ON tb.Brew = b.Id
        LEFT JOIN locations pl ON b.ProducerLocation = pl.Id
        WHERE tb.Location = ? AND tb.Tap = ? AND tb.Brew IS NOT NULL
          AND tb.FirstSeen <= ?
          AND (tb.Gone IS NULL OR tb.Gone >= ?)
        ORDER BY tb.FirstSeen DESC
    });
    $sth->execute($loc_id, $tap, $env_end, $env_start);

    print "<h1>Tap #$tap at " . util::htmlesc($locname) . "</h1>\n";
    print "<p><a href='$c->{url}?o=Taps&loc=" . uri_escape_utf8($locname)
        . "&amp;days=$days'><span>&laquo; Back to timeline</span></a></p>\n";

    print "<table class='tap-detail'>\n";
    print "<thead><tr><th>Beer</th><th>On since</th>"
        . "<th>Gone</th><th>Days</th><th>Volume / Price</th></tr></thead>\n<tbody>\n";
    while (my $r = $sth->fetchrow_hashref) {
        my $ge = $r->{Gone};
        my $fs_epoch = ts_epoch($r->{FirstSeen}) // 0;
        my $ge_epoch = $ge ? (ts_epoch($ge) // $end_epoch) : $end_epoch;
        my $dur = int(($ge_epoch - $fs_epoch) / 86400);
        my $gone_disp = $ge ? substr($ge, 0, 10) : "<b>still on tap</b>";
        my @prices;
        if ($r->{PriceS}) { push @prices, "$r->{SizeS} cl / $r->{PriceS}"; }
        if ($r->{PriceM}) { push @prices, "$r->{SizeM} cl / $r->{PriceM}"; }
        if ($r->{PriceL}) { push @prices, "$r->{SizeL} cl / $r->{PriceL}"; }
        my $price = @prices ? join("<br/>", map { util::htmlesc($_) } @prices) : "";

        my $style_str = $r->{SubType} || $r->{BrewType} || "Beer";
        my $style_url = uri_escape_utf8($style_str);
        my $style_disp = styles::brewstyledisplay($c, $r->{BrewType}, $r->{SubType},
            "tap:$tap '" . ($r->{BrewName} // "") . "'");
        my $prod = $r->{ProducerName}
            ? " <a href='$c->{url}?o=Location&e=" . util::htmlesc($r->{ProducerId})
              . "'><span><i>" . util::htmlesc($r->{ProducerName}) . ":</i></span></a>"
            : "";
        my $brew = "<a href='$c->{url}?o=Brew&e=" . util::htmlesc($r->{Brew})
            . "'><span><b>" . util::htmlesc($r->{BrewName} || "?") . "</b></span></a>";
        my $bidspan = " <span style='font-size:x-small;'>[" . util::htmlesc($r->{Brew}) . "]</span>";
        my $beer = "<a href='$c->{url}?o=$c->{op}&q=$style_url'>$style_disp</a> "
            . "$prod $brew$bidspan";

        print "<tr>";
        print "<td>$beer</td>";
        print "<td>" . util::htmlesc(substr($r->{FirstSeen}, 0, 10)) . "</td>";
        print "<td>$gone_disp</td>";
        print "<td>$dur</td>";
        print "<td>$price</td>";
        print "</tr>\n";
    }
    print "</tbody></table>\n";
    $sth->finish;
} # render_single_tap

################################################################################
# Controls / selector-only fallback
################################################################################

sub render_controls {
    my ($c, $locname, $days) = @_;
    my @locs = scrapeboard::get_scraper_locations($c);
    my $sel = "<label>Location: <select id='tap-loc' onchange='tapGoto()'>\n";
    for my $l (@locs) {
        my $s = ($l eq $locname) ? " selected" : "";
        $sel .= "<option value='" . util::htmlesc($l) . "'$s>" . util::htmlesc($l) . "</option>\n";
    }
    $sel .= "</select></label>\n";
    my $day = "<label>Days: <select id='tap-days' onchange='tapGoto()'>\n";
    for my $v (14, 30, 60, 90) {
        my $s = ($v == $days) ? " selected" : "";
        $day .= "<option value='$v'$s>$v days</option>\n";
    }
    $day .= "</select></label>\n";
    return "<div class='controls'>$sel$day</div>\n";
} # render_controls

sub render_selector_only {
    my ($c, $locparam) = @_;
    print "<h1>Tap Timeline</h1>\n";
    print "<p>No scraper location found. Choose a location:</p>\n";
    print render_controls($c, $locparam || "", 30);
} # render_selector_only

1; # Return true for require
