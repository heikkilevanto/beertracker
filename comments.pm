# Part of my beertracker
# Stuff for comment records and photos (TODO)


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

  my $sql = "select COMMENTS.*,
    PERSONS.Name as PersName,
    PERSONS.Id as PersId
    from comments
    left join PERSONS on persons.id = comments.person
    where glass = ?
    order by Id"; # To keep the order consistent
  my $sth = $c->{dbh}->prepare($sql);
  $sth->execute($glass);

  $s .= "&nbsp;<br/>\n";
  my $editcommentid = util::param($c, "ec", 0);
  my $editcommentrec;
  while ( my $cr = $sth->fetchrow_hashref ) {
    $s .= "Rating: <b>$cr->{Rating}</b>: $ratings[$cr->{Rating}]\n" if ( $cr->{Rating} );
    $s .= "With <b>$cr->{PersName}</b>\n" if ( $cr->{Person} );
    $s .= "<br/><i>$cr->{Comment} </i><br/>\n" if ( $cr->{Comment} );
    $s .= "Photo $cr->{Photo} <br/>\n" if ( $cr->{Photo} );  # TODO - Show the photo itself
      # TODO - Move the image file name routines here from index.cgi:929 or so.
    $s .= "<span style='font-size: x-small'> Comment id: $cr->{Id} </span>" .
          "<a href='$c->{url}?o=$c->{op}&e=$glass&ec=$cr->{Id}'><span font-size: x-small>Edit</span></a><br/>\n";
    if ( $editcommentid && $cr->{Id} == $editcommentid ) {
      $editcommentrec = $cr;
    }
  }
  $s .= commentform($c, $editcommentrec, $glass);

  return $s;
} # listcomments

################################################################################
# Form to enter or edit a comment
################################################################################

sub commentform {
  my $c = shift;
  my $com = shift;
  my $glass = shift;

  my $s="";
  $s .= "<hr><br>\n";
  $s .= "<form method='post' action='$c->{url}'>\n";
  $s .= "<input type='hidden' name='commentedit' value='1'>\n"; # To distinguish from glass submit
  $s .= "<input type='hidden' name='o' value='$c->{op}'>\n";
  $s .= "<input type='hidden' name='e' value='$c->{edit}'>\n";
  $s .= "<input type='hidden' name='ce' value='$com->{Id}'>\n" if ( $com->{Id} );
  $s .= "<input type='hidden' name='glass' value='$glass'>\n";

  # If editing, include the comment ID
  if ($com && $com->{Id}) {
    $s .= "<input type='hidden' name='comment_id' value='$com->{Id}'>\n";
    $s .= "Editing comment $com->{Id} ";
    $s .= "<a href=$c->{url}?o=$c->{op}&e=$c->{edit}><span>Cancel</span></a><br/>\n";
  }

  # Comment text area
  my $comment = $com->{Comment} || "";
  my $pl = "Add a new comment" ;
  $s .= "<textarea name='comment' rows='3' cols='40' placeholder='$pl' $clr>$comment</textarea><br/>\n";

  # Person involved in the comment
  #print STDERR "cform: pn='$com->{PersName}' pi=$com->{PersId} \n";
  $s .= persons::selectperson($c, 'person', $com->{PersId} );

  # TODO - Photo button

  # Submit button
  my $button_text = $com->{Id} ? "Update Comment" : "Add Comment";
  $s .= "<input type='submit' value='$button_text'>\n";

  # Rating dropdown
  $s .= "<select name='rating'>\n";
  $s .= "<option value=''>Rating</option>\n";
  my $r = $com->{Rating} || 0;
  for my $i (1 .. $#ratings) {  # Skip "Zero"
    my $selected = ($r == $i) ? " selected" : "";
    $s .= "<option value='$i'$selected>$i: $ratings[$i]</option>\n";
  }
  $s .= "</select>\n";


  $s .= "</form>\n";
  return $s;
}

################################################################################
# Handle submitted comment form
################################################################################
sub postcomment {
  my $c = shift;

  my $glass = util::param($c, "glass");
  my $comment_id = util::param($c, "comment_id");
  my $rating = util::param($c, "rating") || 0;
  my $comment = util::param($c, "comment") || "";
  my $person = util::param($c, "person") || "";

  if ( $person eq "new" ) {  # Adding a new person
    my $newname = util::param($c,"newpersonName");
    my $newfull = util::param($c,"newpersonFullName");
    my $newdesc = util::param($c,"newpersonDescription");
    my $newcont = util::param($c,"newpersonContact");
    error ("A Person must have a name" )
       unless $newname;
    my $sql = "INSERT INTO persons (Name, FullName, Description, Contact) VALUES (?, ?, ?, ?)";
    my $sth = $c->{dbh}->prepare($sql);
    $sth->execute($newname, $newfull, $newdesc, $newcont);
    my $newid = $c->{dbh}->last_insert_id(undef, undef, "PERSONS", undef) || undef;
    print STDERR "Inserted person '$newid' for comment '$comment_id' \n";
    $person = $newid;
  }

  if ($comment_id) { # Update existing comment
    my $sql = "UPDATE comments SET Rating = ?, Comment = ?, Person = ?
               WHERE Id = ? AND Glass = ?";
    my $sth = $c->{dbh}->prepare($sql);
    $sth->execute($rating, $comment, $person, $comment_id, $glass );
    print STDERR "Updated comment '$comment_id' for glass  '$glass' \n";
  } else { # Insert new comment
    my $sql = "INSERT INTO comments (Glass, Rating, Comment, Person) VALUES (?, ?, ?, ?)";
    my $sth = $c->{dbh}->prepare($sql);
    $sth->execute($glass, $rating, $comment, $person);
    $comment_id = $c->{dbh}->last_insert_id(undef, undef, "COMMENTS", undef) || undef;
    print STDERR "Inserted comment '$comment_id' for glass '$glass' \n";
  }

  # Redirect to avoid duplicate form submission on refresh
  $c->{redirect} = "$c->{url}?o=$c->{op}&e=$c->{edit}&glass=$glass";
  return "";
}


################################################################################
# Report module loaded ok
1;

