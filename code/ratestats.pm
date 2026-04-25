# ratestats.pm
# Simple procedural Perl module for producing a ratings histogram
# Fits the BeerTracker style (required from index.fcgi and used as ratestats::FUNC)

package ratestats;
use strict;
use warnings;

use feature 'unicode_strings';
use utf8;  # Source code and string literals are utf-8

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

    $html .= histogram_form($c, $filter);
    $html .= chart_gnuplot($c, $rows);

    my $allrows = histogram_data($c, {});
    $html .= data_table($c, $filter, $rows, $allrows);


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

    # Get pulldown values for years
    my $sql = "select
      distinct strftime('%Y',Timestamp) as v
      from glasses
      where Username = ?
      order by v desc";
    my $yearsel = db::querydropdown( $c, "year", $year, "(all)", $sql, $c->{username});

    $sql = "select
      distinct BrewType as v
      from glasses where username = ?
      order by timestamp desc";
    my $brewsel = db::querydropdown( $c, "brew_type", $brew_type, "(all)", $sql, $c->{username});

    $sql = "select
      distinct LocType as v
      from glasses, Locations
      where username = ?
      and Locations.Id = glasses.location
      order by timestamp desc";
    my $locsel = db::querydropdown( $c, "loc_type", $loc_type, "(all)", $sql, $c->{username});

    return qq{
<form method="GET">
  <table>
    <tr><td colspan=3><b>Ratings statistics</b></td></tr>
    <tr>
      <td>Filter Year:</td>
      <td>
        $yearsel
      </td>
    </tr><tr>
      <td>Brew type:</td>
      <td>$brewsel</td>
    </tr><tr>
      <td>Location type:</td>
      <td>$locsel</td>
    </tr><tr>
      <td><input type="hidden" name="o" value="$c->{op}"></td>
      <td>
        <input type="submit" value="Filter"> &nbsp;
        <input type="button" value="Clear" onclick="window.location.href='$c->{url}?o=$c->{op}'">
      </td>
    </tr>
  </table>
</form>
<hr>
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
      LEFT JOIN locations ON glasses.Location = locations.Id
    };
#      JOIN brews ON glasses.Brew = brews.Id

    my @where = ('glasses.Username = ?');
    my @bind  = ($c->{username});

    if (defined $filter->{year} && length $filter->{year}) {
      push @where, "strftime('%Y', glasses.Timestamp) = ?";
      push @bind, $filter->{year};
    }

    if (defined $filter->{brew_type} && length $filter->{brew_type}) {
      push @where, "BrewType = ?";
      push @bind, $filter->{brew_type};
    }

    if (defined $filter->{loc_type} && length $filter->{loc_type}) {
      push @where, "locations.LocType = ?";
      push @bind, $filter->{loc_type};
    }

    $sql .= ' WHERE ' . join(' AND ', @where);
    $sql .= ' GROUP BY comments.Rating ORDER BY comments.Rating';

    my $sth = db::query($c, $sql, @bind);
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
# Emit a gnuplot-generated horizontal bar chart PNG
# Ratings 1-9 on Y axis, count on X axis
############################################################
sub chart_gnuplot {
    my ($c, $rows) = @_;

    my $datafile = $c->{plotfile};
    my $pngfile = $c->{plotfile};
    $pngfile =~ s/\.plot$/-ratings.png/;
    my $cmdfile = $c->{cmdfile};

    # Write data file: rating_number count (ratings 1-9)
    open my $fh, '>', $datafile
        or util::error("Could not open $datafile: $!");
    for my $i (1..9) {
        my $cnt = $rows->[$i] || 0;
        my $plotcnt = $cnt > 0 ? $cnt : 0.001;  # avoid degenerate zero-width box
        print $fh "$i $plotcnt\n";
    }
    close $fh;

    my $bgcolor = $c->{bgcolor};
    my $cmd = ""
        . "set term png small size 400,300\n"
        . "set out \"$pngfile\"\n"
        . "set xrange [0:]\n"
        . "set yrange [0.5:9.5]\n"
        . "set ytics 1 textcolor \"white\"\n"
        . "set xtics textcolor \"white\"\n"
        . "set border linecolor \"white\"\n"
        . "set grid xtics lc \"white\" lw 0.5\n"
        . "set object 1 rect noclip from screen 0, screen 0 to screen 1, screen 1 "
        . "behind fc \"$bgcolor\" fillstyle solid border\n"
        . "unset key\n"
        . "plot \"$datafile\" using (\$2/2):1:(\$2/2):(0.35) with boxxy fillstyle solid lc \"#4bc0c0\"\n";

    open my $cfh, '>', $cmdfile
        or util::error("Could not open $cmdfile: $!");
    print $cfh $cmd;
    close $cfh;

    system("gnuplot $cmdfile");

    return "<img src=\"$pngfile\" style='max-width:95vw' />\n";
} # chart_gnuplot


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
  my $fcount = 0;  # count of filtered ratings
  my $fsum = 0;    # And their sum for average
  my $acount = 0;  # Same for all ratings
  my $asum = 0;

  my $html = "";
  $html .= "<hr>\n";
  $html .= '<table border="1" cellpadding="5" cellspacing="0" class="data">
  <thead>
    <tr>
      <th>&nbsp;</th>
      <th>Rating</th>
      <th>Total </th>';
  if ( $filtering) {
    $html .= "<th>Filtered";
    $html .= "<br>$filter->{year}" if ($filter->{year});
    $html .= "<br>$filter->{brew_type}" if ($filter->{brew_type});
    $html .= "<br>$filter->{loc_type}" if ($filter->{loc_type});
    $html .= "</th>" ;
  }
  $html .= "</tr>
     </thead> <tbody>";
  for my $i ( 1..9) {
    no warnings 'once'; my $lbl = $comments::ratings[$i];
    $fcount += $filtered_rows->[$i] || 0;
    $fsum += ( $filtered_rows->[$i] || 0 ) * $i;
    $acount += $all_rows->[$i] || 0;
    $asum += ( $all_rows->[$i] || 0 ) * $i;
    $html .= "<tr><td align=right>($i)</td><td>$lbl</td>";
    my $ar = $all_rows->[$i] || "";
    $html .= "<td align=right>$ar</td>";
    my $fr = $filtered_rows->[$i] || "";
    $html .= "<td align=right>$fr</td>" if ($filtering);
    $html .= "</tr>\n";
  }

  $html .= "<tr><td align=right colspan=2>Total ratings</td>\n";
  $html .= "<td align=right>$acount</td>\n";
  $html .= "<td align=right>$fcount</td>\n" if ($filtering);
  $html .= "</tr><tr><td align=right colspan=2>Average rating</td>\n";
  $html .= "<td align=right> \n";
  $html .= sprintf("%0.1f", $asum / $acount ) if ($asum);
  $html .= "</td>\n";
  if ($filtering) {
    $html .= "<td align=right> \n";
    $html .= sprintf("%0.1f", $fsum / $fcount ) if ($fsum);
    $html .= "</td>\n";
  }
  $html .= "</table>\n";
  return $html;

} # data_table


############################################################
# Tell perl the module loaded OK
1;
