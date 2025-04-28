package stats;

################################################################################
# Variosu statistics of my beer database
################################################################################


use strict;
use warnings;

use feature 'unicode_strings';
use utf8;  # Source code and string literals are utf-8

################################################################################
# Sub-menu for the various statistics pages
################################################################################
sub statsmenu {
  my $c = shift;
  print "Other stats: \n";
  print "<a href='$c->{url}?o=short'><span>Days</span></a>&nbsp;\n";
  print "<a href='$c->{url}?o=Months'><span>Months</span></a>&nbsp;\n";
  print "<a href='$c->{url}?o=Years'><span>Years</span></a>&nbsp;\n";
  print "<a href='$c->{url}?o=DataStats'><b>Datafile</b></a>&nbsp;\n";
  print "<hr/>\n";
}



################################################################################
# Statistics of the data file
################################################################################
# TODO - Get stuff from the database
sub datastats {
  my $c = shift;
  statsmenu($c);

  print "<table>\n";
  print "<tr><td></td><td><b>Data file stats</b></td></tr>\n";

  print "<tr></tr>\n";
  print "<tr><td></td><td><b>General</b></td></tr>\n";
  my $dfsize = -s $c->{databasefile};
  $dfsize = int($dfsize / 1024);
  print "<tr><td align='right'>$dfsize</td><td>kb in $c->{databasefile}</td></tr>\n";

  print "<tr><td>&nbsp;</td></tr>\n";
  print "<tr><td></td><td><b>Users</b></td></tr>\n";
  my $sql = "select username as username, count(*) as recs from glasses group by username";
  my $sth = $c->{dbh}->prepare($sql);
  $sth->execute();
  while ( my $rec = $sth->fetchrow_hashref ) {
    #print STDERR "U: ", JSON->new->encode($rec), "\n";
    print "<tr>\n";
    print "<td><b>$rec->{username}</b> </td>\n";
    print "<td>$rec->{recs} glasses</td>\n";
    print "</tr>\n";
  }
  $sth->finish;

  print "<tr><td>&nbsp;</td></tr>\n";
  print "<tr><td></td><td><b>Glasses </b></td></tr>\n";
  $sql = "select brewtype, count(*) as count from glasses " .
         "group by brewtype order by count desc";
  $sth = $c->{dbh}->prepare($sql);
  $sth->execute();
  while ( my $rec = $sth->fetchrow_hashref ) {
    #print STDERR "U: ", JSON->new->encode($rec), "\n";
    print "<tr>\n";
    print "<td><b>$rec->{BrewType}</b> </td>\n";
    print "<td>$rec->{count} glasses</td>\n";
    print "</tr>\n";
  }
  $sth->finish;

  print "<tr><td>&nbsp;</td></tr>\n";
  print "<tr><td></td><td><b>Brews </b></td></tr>\n";
  $sql = "select brewtype, count(*) as count from brews " .
         "group by brewtype order by count desc";
  $sth = $c->{dbh}->prepare($sql);
  $sth->execute();
  while ( my $rec = $sth->fetchrow_hashref ) {
    #print STDERR "U: ", JSON->new->encode($rec), "\n";
    print "<tr>\n";
    print "<td><b>$rec->{BrewType}</b> </td>\n";
    print "<td>$rec->{count} brews</td>\n";
    print "</tr>\n";
  }
  $sth->finish;
  # TODO: Find brews that have one or no glasses associated with them

  print "<tr><td>&nbsp;</td></tr>\n";
  print "<tr><td></td><td><b>Producers</b></td></tr>\n";
  $sql = "select LocType, LocSubType, count(name) as count ".
         "from locations where LocType = 'Producer' " .
         "group by LocType, LocSubType " .
         "order by LocType, count desc,  LocSubType ";
  $sth = $c->{dbh}->prepare($sql);
  $sth->execute();
  while ( my $rec = $sth->fetchrow_hashref ) {
    #print STDERR "U: ", JSON->new->encode($rec), "\n";
    print "<tr>\n";
    print "<td><b>$rec->{LocSubType}</b> </td>\n";
    print "<td>$rec->{count} producers</td>\n";
    print "</tr>\n";
  }
  $sth->finish;

  print "<tr><td>&nbsp;</td></tr>\n";
  print "<tr><td></td><td><b>Locations</b></td></tr>\n";
  $sql = "select LocType, LocSubType, count(name) as count ".
         "from locations where LocType <> 'Producer' " .
         "group by LocType, LocSubType " .
         "order by LocType, count desc,  LocSubType ";
  $sth = $c->{dbh}->prepare($sql);
  $sth->execute();
  while ( my $rec = $sth->fetchrow_hashref ) {
    #print STDERR "U: ", JSON->new->encode($rec), "\n";
    print "<tr>\n";
    print "<td><b>$rec->{LocType}, $rec->{LocSubType}</b> </td>\n";
    print "<td>$rec->{count} locations</td>\n";
    print "</tr>\n";
  }
  $sth->finish;

  # TODO: Comments, ratings, photos
  # TODO: Comments, on brew type, night, restaurant
  # TODO: Ratings, min/max/avg/count, on brewtype
  # TODO: Photos, on brewtype (night/rest) or person
  # TODO: Persons - what to say of them? Have no categories.


  print "</table>\n";
  return;  # The rest is old style lines array stuff, kept here just
  # for reference while rewriting
my $OLDCODE = <<'EOF'

  my $datarecords = scalar(@records);
  # The following have been calculated when reading the file, without parsing it
  my $totallines = $datarecords + $commentlines + $commentedrecords;
  print "<tr><td align='right'>$totallines</td><td> lines</td></tr>\n";
  print "<tr><td align='right'>$commentlines</td><td> lines of comments</td></tr>\n";
  print "<tr><td align='right'>$commentedrecords</td><td> record lines commented out</td></tr>\n";
  print "<tr><td align='right'>$datarecords</td><td> real data records</td></tr>\n";

  my %rectypes;
  my %distinct;
  my %seen;
  my $oldrecs = 0;
  my $badrecs = 0;
  my $comments = 0;
  my @rates = ( 0,0,0,0,0,0,0,0,0,0 );
  my $ratesum = 0;
  my $ratecount = 0;

  for ( my $i = 0 ; $i < scalar(@lines); $i++) {
    my $rec = getrecord($i);
    next if filtered ( $rec );
    if ( ! $rec ) {
      $badrecs++;
      next;
    }
    my $rt = $rec->{type};
    $rectypes{$rt} ++;
    $oldrecs ++ if ($rec->{rawline} && $rec->{rawline} !~ /; *$rt *;/ );
    $comments++ if ( $rec->{com} );
    if (defined($rec->{rate}) && $rec->{rate} =~ /\d/ ) {
      $rates[ $rec->{rate} ] ++;
      $ratesum += $rec->{rate};
      $ratecount++;
    }
    if ( ! $seen{$rec->{seenkey}} ) {
      $seen{$rec->{seenkey}} = 1;
      $distinct{$rec->{type}}++;
    }
  }
  print "<tr><td align='right'>$oldrecs</td><td> old type lines</td></tr>\n";
  print "<tr><td>&nbsp;</td></tr>\n";
  print "<tr><td>&nbsp;</td><td><b>Record types</b></td></tr>\n";
  foreach my $rt ( sort  { $rectypes{$b} <=> $rectypes{$a} } keys(%rectypes) )  {
    print "<tr><td align='right'>$rectypes{$rt}</td>" .
    "<td> $rt ($distinct{$rt} different)</td></tr>\n";
  }
  if ( $badrecs ) {
    print "<tr><td align='right'>$badrecs</td><td>Bad</td></tr>\n";
  }
  print "<tr><td>&nbsp;</td></tr>\n";
  print "<tr><td>&nbsp;</td><td><b>Ratings</b></td></tr>\n";
  my $i = 1;
  while ( $ratings[$i] ){
    print "<tr><td align='right'>$rates[$i]</td><td>'$ratings[$i]' ($i)</td></tr>\n";
    $i++;
  }
  print "<tr><td align='right'>$ratecount</td><td>Records with ratings</td></tr>\n";
  if ( $ratecount ) {
    my $avg = sprintf("%3.1f", $ratesum / $ratecount);
    print "<tr><td align='right'>$avg</td><td>Average rating</td></tr>\n";
  }
  print "<tr><td align='right'>$comments</td><td>Records with comments</td></tr>\n";

  print "</table>\n";
EOF
}


################################################################################
1;  # Module loaded ok
