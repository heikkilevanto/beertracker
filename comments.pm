# Part of my beertracker
# Stuff for comment records


package comments;

use strict;
use warnings;
use feature 'unicode_strings';
use utf8;  # Source code and string literals are utf-8

# Formatting magic
my $clr = "Onfocus='value=value.trim();select();' autocapitalize='words'";

my @ratings = ( "Zero", "Undrinkable", "Unpleasant", "Could be better",  # zero should not be used!
"Ok", "Goes down well", "Nice", "Pretty good", "Excellent", "Perfect");  # 9 is the top

################################################################################
# List of comments for a given glass record
################################################################################
sub listcomments {
  my $c = shift; # context
  my $glass = shift;

  my $s = "";

  my $sql = "select COMMENTS.*, PERSONS.Name as Person
    from comments
    left join PERSONS on persons.id = comments.person
    where glass = ?
    order by Id"; # To keep the order consistent
  my $sth = $c->{dbh}->prepare($sql);
  $sth->execute($glass);

  $s .= "&nbsp;<br/>\n";
  while ( my $cr = $sth->fetchrow_hashref ) {
    $s .= "Rating: $cr->{Rating}: $ratings[$cr->{Rating}]\n" if ( $cr->{Rating} );
    $s .= "$cr->{Person}\n" if ( $cr->{Person} );
    $s .= "<br/>\n" if ( $s );
    $s .= "<i>$cr->{Comment} </i><br/>\n" if ( $cr->{Comment} );
    $s .= "Photo $cr->{Photo} <br/>\n" if ( $cr->{Photo} );  # TODO - Show the photo itself
    $s .= commentform($c, $cr);
  }

  return $s;
} # listcomments

################################################################################
# Form to enter or edit a comment
################################################################################
sub commentform {
  my $c = shift;
  my $com = shift;

  my $s = "";
  my $rating = $com->{Rating} || "";
  my $comment = $com->{Comment} || "";
  my $person = $com->{Person} || "";
  my $photo = $com->{Photo} || "";

  # TODO - Build an input form
  # Either with util::inputform (with ratings pulldown from here, and photo),
  # or directly here
}


################################################################################
# Report module loaded ok
1;

