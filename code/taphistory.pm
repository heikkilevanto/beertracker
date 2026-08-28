# Part of my beertracker
# Tap Timeline - location tap history visualization (plan 750)
#
# Renders a per-day, per-tap timeline of what beer was on each tap at a
# location. Daily granularity only: each (tap, day) cell shows the single
# most-recent beer that was on that tap that day. Consecutive same-beer days
# are merged with colspan for a Gantt-like look.
#
# Entry points:
#   o=Taps&loc=<name>                            location timeline (default: first scraper loc)
#   o=Taps&loc=<name>&tap=<N>                    single-tap detail (full known history for that tap)
#   o=Taps&loc=<name>&days=14d|30d|3m|6m|1y       number of daily columns (default 30d; a bare number also works)
#   o=Taps&loc=<name>&from=YYYY-MM-DD            anchor day for the first (rightmost) column (default today)

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

# Period tokens -> number of daily columns
my %PERIOD = ( "14d" => 14, "30d" => 30, "3m" => 90, "6m" => 180, "1y" => 365 );

################################################################################
# Helpers
################################################################################

# Foreground color for a hex background, matching styles::brewtextstyle.
sub fg_for {
    my ($c, $hex) = @_;
    $hex =~ s/^#//;
    my ($r, $g, $b) = ($hex =~ /(..)(..)(..)/);
    return "#ffffff" unless $r;
    my $lum = (hex($r) + hex($g) + hex($b)) / 3;
    return $lum < 64 ? "#ffffff" : $c->{bgcolor};
} # fg_for

my @MON_ABBR = qw(Jan Feb Mar Apr May Jun Jul Aug Sep Oct Nov Dec);
my @WDAY_ABBR = qw(Sun Mon Tue Wed Thu Fri Sat);

# Format a price as Finnish euros: integer -> "54.-", fractional -> "54,50".
sub eurofmt {
    my ($p) = @_;
    return "" unless defined $p && $p ne "";
    $p =~ s/,/./;
    if ($p =~ /^(\d+)(?:\.0+)?$/) { return "$1.-"; }
    $p =~ s/\./,/;
    return $p;
} # eurofmt

# Collect the available prices of a tap_beers row, formatted via eurofmt.
sub keg_prices {
    my ($r) = @_;
    my @p;
    if ($r->{PriceS}) { push @p, eurofmt($r->{PriceS}); }
    if ($r->{PriceM}) { push @p, eurofmt($r->{PriceM}); }
    if ($r->{PriceL}) { push @p, eurofmt($r->{PriceL}); }
    return @p;
} # keg_prices

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

    # From parameter: anchor day for the first (rightmost) column, default today
    my $from = util::param($c, "from");
    if (!$from || $from !~ /^\d{4}-\d{2}-\d{2}$/) {
        if ($from && $from =~ /^(\d{1,2})$/) {
            # A bare 1-2 digit number is a month: use the previous occurrence,
            # anchored on the last day of that month.
            my $m = $1 + 0;
            my @t = localtime(time());
            my $cur_m = $t[4] + 1;
            my $y = $t[5] + 1900;
            $y-- if $m >= $cur_m;
            my $nm = ($m == 12) ? 1 : $m + 1;
            my $ny = ($m == 12) ? $y + 1 : $y;
            my $first_next = timelocal(0, 0, 12, 1, $nm - 1, $ny - 1900);
            $from = strftime("%Y-%m-%d", localtime($first_next - 86400));
        } else {
            my @t = localtime(time());
            $from = strftime("%Y-%m-%d", @t);
        }
    }

    # Days: accept either a period token (14d/30d/3m/6m/1y) or a bare number
    my $dp = util::param($c, "days") || "30d";
    my $days = $PERIOD{$dp};
    if (!defined $days && $dp =~ /^\d+$/) {
        $days = $dp + 0;
    }
    $days = 30 unless defined $days;

    if (!$locrec) {
        render_selector_only($c, $locparam, $days, $from);
        return;
    }

    my $loc_id = $locrec->{Id};
    my $locname = $locrec->{Name};

    # Single-tap detail view
    my $tap = util::param($c, "tap");
    if (defined $tap && $tap =~ /^\d+$/) {
        render_single_tap($c, $loc_id, $locname, $tap, $days, $from);
        return;
    }

    render_timeline($c, $loc_id, $locname, $days, $from);
} # taphistory

################################################################################
# Timeline view
################################################################################

sub render_timeline {
    my ($c, $loc_id, $locname, $days, $from) = @_;

    # Reference "now" anchored on the chosen From day (first/rightmost column)
    my $end_ref = "$from 12:00:00";
    my $end_day = dateutil::eff_day_of($end_ref);
    my $start_day = dateutil::date_plus_days($end_day, -($days - 1));

    # Day buckets (effective day D -> local half-open [D 06:00, (D+1) 06:00))
    my @buckets;
    for my $k (0 .. $days - 1) {
        my $D = dateutil::date_plus_days($start_day, $k);
        push @buckets, {
            day   => $D,
            bs    => $D . " 06:00:00",
            be    => dateutil::date_plus_days($D, 1) . " 06:00:00",
        };
    }
    my $env_start = $start_day . " 06:00:00";
    my $env_end   = dateutil::date_plus_days($end_day, 1) . " 06:00:00";

    # Fetch overlapping tap periods
    my $sth = $c->{dbh}->prepare(q{
               SELECT tb.Id, tb.Tap, tb.Brew, b.Name AS BrewName,
               b.ShortName AS brew_shortname,
               b.BrewType, b.SubType, b.BrewStyle, b.Alc,
               tb.FirstSeen, tb.Gone,
               pl.Name AS ProducerName, pl.ShortName AS prod_shortname,
               pl.Id AS ProducerId,
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
    my %kegs;         # bid -> [ keg history within the window ]
    my %seen_bid;

    while (my $r = $sth->fetchrow_hashref) {
        my $bid = $r->{Brew};
        my $type = $r->{BrewType} || "";
        my $sub = $r->{SubType} || "";

        unless ($seen_bid{$bid}) {
            $seen_bid{$bid} = 1;
            my $bg = styles::brewcolor($c, "$type,$sub");
            $details{$bid} = {
                name  => ($r->{brew_shortname} || $r->{BrewName}) || "?",
                sub   => $sub || $type || "Unknown",
                style => $r->{BrewStyle} || "",
                prod  => ($r->{prod_shortname} || $r->{ProducerName}) || "",
                prodid=> $r->{ProducerId} || "",
                alc   => $r->{Alc},
                color => "#$bg",
                fg    => fg_for($c, $bg),
            };
        }
        my $d = $details{$bid};

        my $ge = $r->{Gone};
        my $fs_day = substr($r->{FirstSeen}, 0, 10);
        my $ge_day = $ge ? substr($ge, 0, 10) : dateutil::eff_day_of($end_ref);
        my $dur = dateutil::day_diff($fs_day, $ge_day) + 1;  # inclusive of both ends

        my $rec = {
            bid    => $bid,
            kegid  => $r->{Id},
            name   => $d->{name},
            style  => $d->{style},
            prod   => $d->{prod},
            bg     => $d->{color},
            fg     => $d->{fg},
            since  => $fs_day,
            gone   => $ge ? $ge_day : "still on tap",
            days   => $dur,
            fs     => $r->{FirstSeen},
        };

        push @{$kegs{$bid}}, {
            id     => $r->{Id},
            tap    => int($r->{Tap}),
            first  => $fs_day,
            gone   => $ge ? $ge_day : "",
            days   => $dur,
            prices => [ keg_prices($r) ],
        };

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

    # Latest scrape timestamp (for staleness warning).
    # The NULL/NULL marker row stores the true last-scrape time in LastSeen
    # (FirstSeen is frozen at the row's creation), so read LastSeen; fall back
    # to actual beer activity if no marker exists.
    my ($latest_scrape) = db::queryarray($c, q{
        SELECT MAX(LastSeen) FROM tap_beers
        WHERE Location = ? AND Tap IS NULL AND Brew IS NULL
    }, $loc_id);
    if (!$latest_scrape) {
        ($latest_scrape) = db::queryarray($c, q{
            SELECT MAX(ts) FROM (
                SELECT FirstSeen AS ts FROM tap_beers WHERE Location = ?
                UNION SELECT Gone FROM tap_beers
                WHERE Location = ? AND Gone IS NOT NULL
            )
        }, $loc_id, $loc_id);
    }

    # Staleness warning (above the table)
    my $warn_html = "";
    if ($latest_scrape) {
        my $ep = dateutil::ts_epoch($latest_scrape);
        if ($ep && (time() - $ep) > 86400) {
            my $days = int((time() - $ep) / 86400);
            my $latest_day = substr($latest_scrape, 0, 10);
            $warn_html = "<div class='scrape-warn'>Warning: latest scrape was "
                . util::htmlesc($latest_day) . " &mdash; about "
                . $days . " day" . ($days == 1 ? "" : "s") . " ago.</div>\n";
        }
    }

    print render_controls($c, $locname, $days, $from);
    print "<div id='details'><span class='close' onclick='closeDetails()'>&#10005;</span>"
        . "<div id='details-body'></div></div>";

    print $warn_html if $warn_html;

    my $N = scalar(@buckets);
    my $table_w = 40 + $N * 22 + ($N + 1) * 2;  # + border-spacing
    print "<div class='overflow-auto'>\n"
        . "<table class='timeline' style='width:" . $table_w . "px'>\n";
    print "<colgroup><col width='40'><col width='22' span='$N'></colgroup>\n";
    my $today = strftime("%Y-%m-%d", localtime(time()));
    my $corner = ($from eq $today)
        ? "<th class='tapcol'><span>Tap</span></th>"
        : "<th class='tapcol'><a href='#' onclick='tapClearFrom(); return false;'>"
          . "<span>&laquo;&laquo;</span></a></th>";
    print "<thead><tr>$corner\n";
    my $i = 0;
    for my $bk (reverse @buckets) {
        my ($yyyy, $mm, $dd) = $bk->{day} =~ /^(\d\d\d\d)-(\d\d)-(\d\d)$/;
        my $epoch = timelocal(0, 0, 12, $dd, $mm - 1, $yyyy - 1900);
        my $wday = (localtime($epoch))[6];
        my $weekend = ($wday == 0 || $wday == 6);
        my $cls = "daycol" . ($weekend ? " weekend" : "");
        my $is_first = ($i == 0) || ($dd eq "01");
        my ($mon, $daytxt);
        if ($weekend) {
            $mon = "<span class='mon wd'>" . $WDAY_ABBR[$wday] . "</span>";
            $daytxt = "<span class='day'>$dd</span>";
        } elsif ($is_first) {
            $mon = "<span class='mon'>" . $MON_ABBR[$mm - 1] . "</span>";
            $daytxt = "<span class='day'>'" . substr($yyyy, 2) . "</span>";
        } else {
            $mon = "";
            $daytxt = "<span class='day'>$dd</span><span class='mon'>"
                . $MON_ABBR[$mm - 1] . "</span>";
        }
        my $dattr = util::htmlesc($bk->{day});
        print "<th class='$cls' style='cursor:pointer;' onclick='tapSetFrom(\"$dattr\")'>"
            . "$mon$daytxt</th>\n";
        $i++;
    }
    print "</tr></thead>\n<tbody>\n";

    for my $tap (sort { $a <=> $b } keys %tap_days) {
        my @cells = build_cells($tap_days{$tap});
        print "<tr>\n";
        print "<td class='tapcol'><a href='$c->{url}?o=Taps&loc="
            . uri_escape_utf8($locname) . "&amp;days=$days&amp;from="
            . util::htmlesc($from) . "&amp;tap=$tap'><span>#$tap</span></a></td>\n";
        for my $cell (@cells) {
            my ($rec, $span) = @$cell;
            if (!defined $rec) {
                print "<td colspan='$span'></td>\n";
            } else {
                my $title = util::htmlesc($rec->{name})
                    . ($rec->{style} ? " — " . util::htmlesc($rec->{style}) : "")
                    . ($rec->{prod} ? " (" . util::htmlesc($rec->{prod}) . ")" : "")
                    . " | " . util::htmlesc($rec->{since});
                print "<td colspan='$span' style='background-color:" . $rec->{bg} . "'>"
                    . "<span class='tap-cell' style='color:" . $rec->{fg} . "' "
                    . "title='" . $title . "' "
                    . "data-brewid='" . util::htmlesc($rec->{bid}) . "' "
                    . "data-kegid='" . util::htmlesc($rec->{kegid}) . "' "
                    . "onclick='showDetails(this)'>"
                    . util::htmlesc($rec->{name})
                    . ($rec->{prod} ? " <span class='tap-prod'>"
                        . util::htmlesc($rec->{prod}) . "</span>" : "")
                    . "</span></td>\n";
            }
        }
        print "</tr>\n";
    }
    print "</tbody></table>\n</div>\n";
    if ($latest_scrape) {
        my ($sc_day, $sc_time) = $latest_scrape
            =~ /^(\d{4}-\d{2}-\d{2})[ T](\d{2}:\d{2})/;
        print "<div class='footer'>Last scraped: "
            . util::htmlesc("$sc_day $sc_time") . "</div>\n";
    }

    my $det = JSON->new->encode(\%details);
    my $kegs_json = JSON->new->encode(\%kegs);
    print "<script>\n"
        . "var TAP_LOC = '" . util::htmlesc($locname) . "';\n"
        . "var TAP_DETAILS = $det;\n"
        . "var TAP_KEGS = $kegs_json;\n"
        . "</script>\n";
} # render_timeline

# Half-open overlap test: period covers bucket [bs, be) iff
#   FirstSeen < be  AND  bs < coalesce(Gone, end_ref)
# Timestamps are compared lexically; that is safe because the
# "YYYY-MM-DD HH:MM:SS" format sorts chronologically.
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
    my ($c, $loc_id, $locname, $tap, $days, $from) = @_;

    my $end_ref = "$from 12:00:00";

    my $sth = $c->{dbh}->prepare(q{
        SELECT tb.Id, tb.Tap, tb.Brew, b.Name AS BrewName,
               b.ShortName AS brew_shortname,
               b.BrewType, b.SubType, b.BrewStyle,
               tb.FirstSeen, tb.Gone,
               pl.Name AS ProducerName, pl.ShortName AS prod_shortname,
               pl.Id AS ProducerId,
               tb.SizeS, tb.PriceS, tb.SizeM, tb.PriceM, tb.SizeL, tb.PriceL
        FROM tap_beers tb
        LEFT JOIN brews b ON tb.Brew = b.Id
        LEFT JOIN locations pl ON b.ProducerLocation = pl.Id
        WHERE tb.Location = ? AND tb.Tap = ? AND tb.Brew IS NOT NULL
        ORDER BY tb.FirstSeen DESC
    });
    $sth->execute($loc_id, $tap);

    print "<h1>Tap #$tap at " . util::htmlesc($locname) . "</h1>\n";
    print "<p><a href='$c->{url}?o=Taps&loc=" . uri_escape_utf8($locname)
        . "&amp;days=$days&amp;from=" . util::htmlesc($from)
        . "'><span>&laquo; Back to timeline</span></a></p>\n";

    print "<table class='tap-detail'>\n";
    print "<thead><tr><th>Style</th><th>Beer</th><th>On &ndash; Off</th>"
        . "<th>Days</th><th>Price</th></tr></thead>\n<tbody>\n";
    while (my $r = $sth->fetchrow_hashref) {
        my $ge = $r->{Gone};
        my $fs_day = substr($r->{FirstSeen}, 0, 10);
        my $ge_day = $ge ? substr($ge, 0, 10) : dateutil::eff_day_of($end_ref);
        my $dur = dateutil::day_diff($fs_day, $ge_day) + 1;  # inclusive of both ends
        my $gone_disp = $ge ? substr($ge, 0, 10) : "still on";
        my @prices = keg_prices($r);
        my $price = @prices ? join(" ", map { util::htmlesc($_) } @prices) : "";

        my $style_disp = styles::brewstyledisplay($c, $r->{BrewType}, $r->{SubType},
            "tap:$tap '" . ($r->{BrewName} // "") . "'");
        my $prodname = $r->{prod_shortname} || $r->{ProducerName};
        my $brewname = $r->{brew_shortname} || $r->{BrewName};
        my $prod = $prodname
            ? " <a href='$c->{url}?o=Location&e=" . util::htmlesc($r->{ProducerId})
              . "'><span><i>" . util::htmlesc($prodname) . ":</i></span></a>"
            : "";
        my $brew = "<a href='$c->{url}?o=Brew&e=" . util::htmlesc($r->{Brew})
            . "'><span><b>" . util::htmlesc($brewname || "?") . "</b></span></a>";
        my $sep = $c->{mobile} ? "<br/>" : " ";
        my $beer = "$prod$sep$brew";

        print "<tr>";
        print "<td>$style_disp</td>";
        print "<td>$beer</td>";
        print "<td>" . util::htmlesc(substr($r->{FirstSeen}, 0, 10))
            . " &ndash; " . util::htmlesc($gone_disp) . "</td>";
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
    my ($c, $locname, $days, $from) = @_;
    my @locs = scrapeboard::get_scraper_locations($c);
    my $sel = "<label>Taps: <select id='tap-loc' onchange='tapGoto()' "
        . "style='width:5.5em;'>\n";
    for my $l (@locs) {
        my $s = ($l eq $locname) ? " selected" : "";
        $sel .= "<option value='" . util::htmlesc($l) . "'$s>" . util::htmlesc($l) . "</option>\n";
    }
    $sel .= "</select></label>\n";
    my $day = "<select id='tap-days' onchange='tapGoto()'>\n";
    for my $k (qw(14d 30d 3m 6m 1y)) {
        my $v = $PERIOD{$k};
        my $s = ($v == $days) ? " selected" : "";
        $day .= "<option value='$v'$s>$k</option>\n";
    }
    $day .= "</select>\n";
    my $fromf = "<label>From: <input type='text' id='tap-from' size='10' "
        . "value='" . util::htmlesc($from) . "' onfocus='this.select();' "
        . "onchange='tapGoto()' /></label>\n";
    return "<br/>\n<div class='controls'>$sel$day$fromf</div>\n";
} # render_controls

sub render_selector_only {
    my ($c, $locparam, $days, $from) = @_;
    print "<h1>Tap Timeline</h1>\n";
    print "<p>No scraper location found. Choose a location:</p>\n";
    print render_controls($c, $locparam || "", $days, $from);
} # render_selector_only

1; # Return true for require
