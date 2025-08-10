# ratestats.pm
# Simple procedural Perl module for producing a ratings histogram
# Fits the BeerTracker style (required from index.cgi and used as ratestats::FUNC)

package ratestats;
use strict;
use warnings;
use DBI;

############################################################
# Main entry point: Display histogram graphs and filter form
############################################################
sub ratings_histogram {
    my ($c) = @_;

    my $filter = {
        year      => util::param($c, 'year'),
        brew_type => util::param($c, 'brew_type'),
        loc_type  => util::param($c, 'loc_type'),
    };

    my $rows = histogram_data($c, $filter);
    my $html = '';

    # Minimal responsive CSS
    $html .= <<"CSS";
<style>
.chart-container {
  display: flex;
  flex-wrap: wrap;
  gap: 1rem;
  background-color: $c->{bgcolor};
}
.chart-item {
  flex: 1 1 45%;
}
\@media (max-width: 600px) {
  .chart-item {
    flex: 1 1 100%;
  }
}
</style>
CSS

    $html .= qq{<div class="chart-container">};
    $html .= qq{<div class="chart-item">} . chart_gnuplot($c, $rows, {}) . qq{</div>};
    $html .= qq{<div class="chart-item">} . chart_chartjs($rows, { include_cdn => 1 }) . qq{</div>};
    $html .= qq{</div>};
    $html .= histogram_form($c, $filter);

    print $html;
} # ratings_histogram

############################################################
# Print HTML form for filters
############################################################
sub histogram_form {
    my ($c, $opts) = @_;
    my $year      = $opts->{year}      // '';
    my $brew_type = $opts->{brew_type} // '';
    my $loc_type  = $opts->{loc_type}  // '';

    return qq{
<form method="GET">
  <input type="hidden" name="o" value="$c->{op}">
  <label for="year">Year:</label>
  <input type="text" name="year" value="$year">
  <label for="brew_type">Brew type:</label>
  <input type="text" name="brew_type" value="$brew_type">
  <label for="loc_type">Location type:</label>
  <input type="text" name="loc_type" value="$loc_type">
  <input type="submit" value="Filter">
</form>
};
} # histogram_form

############################################################
# Run SQL query returning counts for ratings 1..10, with filter
############################################################
sub histogram_data {
    my ($c, $filter) = @_;

    my $sql = qq{
      SELECT comments.Rating as rating, COUNT(*) AS cnt
      FROM comments
      JOIN glasses ON comments.Glass = glasses.Id
      JOIN brews ON glasses.Brew = brews.Id
      LEFT JOIN locations ON glasses.Location = locations.Id
    };

    my @where = ('glasses.Username = ?');
    my @bind  = ($c->{username});

    if (defined $filter->{year} && length $filter->{year}) {
      push @where, "strftime('%Y', glasses.Timestamp) = ?";
      push @bind, $filter->{year};
    }

    if (defined $filter->{brew_type} && length $filter->{brew_type}) {
      push @where, "brews.BrewType = ?";
      push @bind, $filter->{brew_type};
    }

    if (defined $filter->{loc_type} && length $filter->{loc_type}) {
      push @where, "locations.LocType = ?";
      push @bind, $filter->{loc_type};
    }

    $sql .= ' WHERE ' . join(' AND ', @where);
    $sql .= ' GROUP BY comments.Rating ORDER BY comments.Rating';

    my $sth = $c->{dbh}->prepare($sql);
    $sth->execute(@bind);

    my $rows = $sth->fetchall_arrayref({});

    my @counts = (0) x 10;
    for my $row (@$rows) {
      my $r = $row->{rating} // 0;
      next if $r < 1 || $r > 10;
      $counts[$r] = $row->{cnt} || 0;
    }

    return \@counts;
} # histogram_data

############################################################
# Emit <canvas> and Chart.js instantiation script
############################################################
sub chart_chartjs {
    my ($rows, $opts) = @_;
    my $canvas_id = $opts->{canvas_id} // 'histogramChart';
    my $include_cdn = $opts->{include_cdn} // 1;

    my $html = '';
    #$html .= qq{<script src="https://cdn.jsdelivr.net/npm/chart.js"></script>\n} if $include_cdn;
    $html .= qq{<script src="chart.js"></script>\n} if $include_cdn;
    $html .= qq{<canvas id="$canvas_id"></canvas>\n};
    my $data_str = join(',', @$rows[1..9]);
    $html .= qq{<script>
        const ctx = document.getElementById('$canvas_id').getContext('2d');
        new Chart(ctx, {
            type: 'bar',
            data: {
                labels: [1,2,3,4,5,6,7,8,9,10],
                datasets: [{
                    label: 'Ratings',
                    data: [$data_str],
                    backgroundColor: 'rgba(75, 192, 192, 0.5)'
                }]
            },
            options: { scales: { y: { beginAtZero: true } } }
        });
    </script>};
    return $html;
} # chart_chartjs

############################################################
# Write histogram data & gnuplot script, run gnuplot, return <img> HTML
############################################################
sub chart_gnuplot {
  my ($c, $rows, $opts) = @_;

  my ($width, $height) = $c->{mobile} ? (300, 200) : (600, 400);
  open my $dfh, '>', $c->{plotfile} or die "Cannot write $c->{plotfile}: $!";
  for my $rating (1..10) {
      my $count = $rows->[$rating] // 0;
      print $dfh "$rating $count\n";
  }
  close $dfh;

  my $pngfile = "$c->{datadir}/$c->{username}-ratings.png";

  open my $gfh, '>', $c->{cmdfile} or die "Cannot write $c->{cmdfile}: $!";
  print $gfh <<"GNUPLOT";
    set terminal png size $width,$height
    set output '$pngfile'
    set border lc rgb "white"
    set tics textcolor rgb "white"
    set xlabel textcolor rgb "white"
    set ylabel textcolor rgb "white"
    set title textcolor rgb "white"
    set key textcolor rgb "white"

    set object 1 rect from screen 0,0 to screen 1,1 fc rgb "$c->{bgcolor}" behind
    set xlabel 'Rating'
    set ylabel 'Count'
    set boxwidth 0.5
    set style fill solid
    plot '$c->{plotfile}' using 1:2 with boxes title 'Ratings'
GNUPLOT
  close $gfh;

  system('gnuplot', $c->{cmdfile}) == 0 or warn "gnuplot failed: $?";

  my $png_url = "$c->{datadir}/$c->{username}-ratings.png";
  return qq{<img src="$png_url" width="$width" height="$height" alt="Ratings Histogram">};
} # chart_gnuplot

############################################################
# Tell perl the module loaded OK
1;
