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
  max-width: 600px;   /* maximum width */
  max-height: 600px;  /* maximum height */
  width: 100%;        /* scale down responsively */
  height: auto;       /* keep aspect ratio */
  display: flex;
  flex-wrap: wrap;
  gap: 1rem;
  background-color: $c->{bgcolor};
}
.chart-item {
  flex: 1 1 45%;
  min-height: 300px
}
\@media (max-width: 600px) {
  .chart-item {
    flex: 1 1 100%;
  }
}
</style>
CSS

    $html .= qq{<div class="chart-container">};
    $html .= qq{<div class="chart-item">} . chart_chartjs($rows, { include_cdn => 1 }) . qq{</div>};
    $html .= qq{</div>};

    my $allrows = histogram_data($c, {});
    $html .= data_table($c, $filter, $rows, $allrows);

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
<hr>
<form method="GET">
  <table>
    <tr>
      <td>Year:</td>
      <td><input type="text" name="year" value="$year" placeholder='(all)' ></td>
    </tr><tr>
      <td>Brew type:</td>
      <td><input type="text" name="brew_type" value="$brew_type" placeholder='(all)' ></td>
    </tr><tr>
      <td>Location type:</td>
      <td><input type="text" name="loc_type" value="$loc_type" placeholder='(all)' ></td>
    </tr><tr>
      <td><input type="hidden" name="o" value="$c->{op}"></td>
      <td>
        <input type="submit" value="Filter"> &nbsp;
        <input type="button" value="Clear" onclick="window.location.href='$c->{url}?o=$c->{op}'">
      </td>
    </tr>
  </table>
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

    my @labels;
    for my $i (0..9) {
      my $lbl = $comments::ratings[$i];
      $labels[$i] = " $i: '$lbl ($i)'";
    }
    my $labelstr = join(',', @labels);
    my $html = '';
    #$html .= qq{<script src="https://cdn.jsdelivr.net/npm/chart.js"></script>\n} if $include_cdn;
    $html .= qq{<script src="chart.umd.min.js"></script>\n} if $include_cdn;
    $html .= qq{<canvas id="$canvas_id"></canvas>\n};
    my $data_str = join(',', @$rows[1..9]);
    $html .= qq"<script>
        const ctx = document.getElementById('$canvas_id').getContext('2d');
        new Chart(ctx, {
            type: 'bar',
            data: {
                labels: [1,2,3,4,5,6,7,8,9],
                datasets: [{
                    label: '',
                    data: [$data_str],
                    backgroundColor: 'rgba(75, 192, 192, 0.5)'
                }]
            },
            options: {
              indexAxis: 'y',
              responsive: true,
              maintainAspectRatio: false,
              scales: {
                x: {
                  beginAtZero: true,
                  grid: { color: 'white' },
                  ticks: { color: 'white' },
                } ,
                y: {
                  type: 'linear',      // so we can set min/max numerically
                  reverse: true,
                  min: 1,
                  max: 9,
                  grid: { color: 'white' },
                  ticks: {
                    stepSize: 1,
                    color: 'white',
                    font: { size: 16 },
                    autoSkip: false,
                    callback: function(value) {
                      const labels = { $labelstr };
                      return labels[value] || value;
                      }

                  }
                }
              },
               plugins: {
                  legend: {
                    labels: {
                      filter: (legendItem) => legendItem.text !== ''
                    }
                  }
                }
            }
        });
    </script>";
    return $html;
} # chart_chartjs


############################################################
# Print the data in a numerical table
############################################################
sub data_table {
  my $c = shift;
  my $filter = shift;
  my $filtered_rows = shift;
  my $all_rows = shift;
  my $filtering = 0;
  if ( $filter->{year} ne "" || $filter->{brew_type} ne "" || $filter->{loc_type} ne "" ) {
    $filtering = 1;
  }

  my $html = "";
  $html .= "<hr>\n";
  $html .= '<table border="1" cellpadding="5" cellspacing="0">
  <thead>
    <tr>
      <th>Rating</th>
      <th>Total </th>';
  $html .= "<th>Filtered</th>" if ( $filtering);
  $html .= "</tr>
     </thead> <tbody>";
  for my $i ( 1..9) {
    my $lbl = $comments::ratings[$i];

    $html .= "<tr><td align=right> $lbl ($i)</td>";
    my $ar = $all_rows->[$i] || "";
    $html .= "<td align=right>$ar</td>";
    my $fr = $filtered_rows->[$i] || "";
    $html .= "<td align=right>$fr</td>" if ($filtering);
    $html .= "</tr>\n";
  }

  $html .= "</table>\n";
  return $html;

} # data_table


############################################################
# Tell perl the module loaded OK
1;
