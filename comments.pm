# Part of my beertracker
# Stuff for comment records and photos (TODO)


package comments;

use strict;
use warnings;
use feature 'unicode_strings';
use utf8;  # Source code and string literals are utf-8


our @ratings = ( "Zero", "Undrinkable", "Unpleasant", "Could be better",  # zero should not be used!
"Ok", "Goes down well", "Nice", "Pretty good", "Excellent", "Perfect");  # 9 is the top

################################################################################
# Get a displayable line with a rating
################################################################################
sub ratingline {
  my $rating = shift;
  my $tag1 = shift || "nop";  # "b" to bold the number
  my $tag2 = shift || $tag1;  # "i" to get italic text
  return "" unless $rating;
  return "<$tag1>($rating)</$tag1> - <$tag2>$ratings[$rating]</$tag2>";
}

################################################################################
# Display a comment on a single line
################################################################################
sub commentline {
  my $c = shift;
  my $cr = shift; # The comment to display, from sql like one in listcomments
  my $glid = $cr->{Glass};
  my $s = "";
  $s .= "<a href='$c->{url}?o=full&e=$glid&ec=$cr->{Id}'>" .
          "<span style='font-size: xx-small'>[$cr->{Id}]</span></a>\n"
        if ( $cr->{Id} );
  $s .= "<b>($cr->{Rating})</b> \n" if ( $cr->{Rating} );
  $s .= "<b>$cr->{PersName}:</b>\n" if ( $cr->{PersName} );
  $s .= "<i>$cr->{Comment} </i>\n" if ( $cr->{Comment} );
  #$s .= "Photo $cr->{Photo} <br/>\n" if ( $cr->{Photo} );  # TODO - Show photo
    # Once I have a photo module

  return $s;
} # commentline


################################################################################
# Produce a simple string with average ratings. Something like (6.5/2) 3•
################################################################################

sub avgratings {
  my ($c, $cnt, $avg, $com) = @_ ;
  my $s = "";
  if ( $avg ) {
    $s .= "(" ;
    if ( $cnt > 1) {
      $s .= sprintf("<b>%2.1f</b>", $avg);
      $s .= "<span style='font-size: xx-small;'>";
      $s .= "/$cnt" . "</span>" ;
    } else {
      $avg = int($avg);
      $s .= "<b>$avg</b>";
    }
    $s .= ")";
  }
  if ( $com ) {
    $s .= " $cnt•";
  }
  return $s;
}

################################################################################
# List of all comments
################################################################################
sub listallcomments {
  my $c = shift; # context

  if ( $c->{edit} ) {
    editbrew($c);
    return;
  }
  print "<b>Comments</b> ";
  #print "&nbsp;<a href=\"$c->{url}?o=$c->{op}&e=new\"><span>(New)</span></a>";
  print "<br/>\n";
  print listrecords::listrecords($c, "COMMENTS_LIST", "Last-" );
  return;
} # listallcomments

################################################################################
# List of comments for a given glass record
################################################################################
sub listcomments {
  my $c = shift; # context
  my $glassid = shift;

  my $s = "";

  my $sql = "select COMMENTS.*,
    PERSONS.Name as PersName,
    PERSONS.Id as PersId
    from comments
    left join PERSONS on persons.id = comments.person
    where glass = ?
    order by Id"; # To keep the order consistent
  my $sth = $c->{dbh}->prepare($sql);
  $sth->execute($glassid);

  $s .= "&nbsp;<br/>\n";
  my $editcommentid = util::param($c, "ec", 0);
  my $editcommentrec;
  $s .= "<ul style='margin:0; padding-left:1.2em;'>\n";
  while ( my $cr = $sth->fetchrow_hashref ) {
    $s .= "<li>" . commentline($c,$cr,$glassid) . "</li>\n";
    if ( $editcommentid && $cr->{Id} == $editcommentid ) {
      $editcommentrec = $cr;
    }
  }
  $s .= "</ul>\n";
  $s .= commentform($c, $editcommentrec, $glassid);

  return $s;
} # listcomments

################################################################################
# Form to enter or edit a comment
################################################################################

sub commentform {
  my $c = shift;
  my $com = shift;
  my $glassid = shift;

  my $s="";
  $s .= "<!-- Comment editing form -->\n";

  my $hidden = "hidden";
  if ( $com ) {
    $hidden = "";
  }
  $s .= "<span onclick='document.getElementById(\"commentform\").hidden ^= true'>(Add comment)</span>\n";
  $s .= "<div  id='commentform' $hidden>\n";
  $s .= "<form method='post' action='$c->{url}'>\n";
  $s .= "<input type='hidden' name='commentedit' value='1'>\n"; # To distinguish from glass submit
  $s .= "<input type='hidden' name='o' value='$c->{op}'>\n";
  $s .= "<input type='hidden' name='e' value='$c->{edit}'>\n";
  $s .= "<input type='hidden' name='ce' value='$com->{Id}'>\n" if ( $com->{Id} );
  $s .= "<input type='hidden' name='glass' value='$glassid'>\n";

  # If editing, include the comment ID
  if ($com && $com->{Id}) {
    $s .= "<input type='hidden' name='comment_id' value='$com->{Id}'>\n";
    $s .= "<br/>Editing comment $com->{Id} <br/>";
  }

  # Comment text area
  my $comment = $com->{Comment} || "";
  my $pl = "Add a new comment" ;
  $s .= "<textarea name='comment' rows='3' cols='40' placeholder='$pl' >$comment</textarea><br/>\n";

  # Person involved in the comment
  #print STDERR "cform: pn='$com->{PersName}' pi=$com->{PersId} \n";
  $s .= persons::selectperson($c, 'person', $com->{PersId} );
  #$s .= "<br/>";

  # Rating dropdown
  $s .= "<select name='rating'>\n";
  $s .= "<option value=''>Rating</option>\n";
  my $r = $com->{Rating} || 0;
  for my $i (1 .. $#ratings) {  # Skip "Zero"
    my $selected = ($r == $i) ? " selected" : "";
    $s .= "<option value='$i'$selected>$i: $ratings[$i]</option>\n";
  }
  $s .= "</select>\n";
  $s .= "&nbsp; (photo) <br/>\n";
  # TODO - Photo button

  # Submit button
  my $button_text = $com->{Id} ? "Update Comment" : "Add Comment";
  $s .= "<input type='submit' name='submit' value='$button_text'>\n";
  $s .= "<a href='$c->{url}?o=$c->{op}&e=$c->{edit}'><span>Cancel</span></a>\n";
  $s .= "<input type='submit' name='submit' value='Delete Comment'>\n" if ( $com->{Id} );


  $s .= "</form>\n";
  $s .= "</div>\n";
  return $s;
}

################################################################################
# Handle submitted comment form
################################################################################
sub postcomment {
  # TODO - Use util helpers, to get recurstion right
  # New person -> New Location and New RelatedPerson ?
  my $c = shift;

  my $glass = util::param($c, "glass");
  my $comment_id = util::param($c, "comment_id");
  my $rating = util::param($c, "rating") || undef;
  my $comment = util::param($c, "comment") || undef;
  my $person = util::param($c, "person") || undef;

  if ( $person && $person eq "new" ) {  # Adding a new person
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
    if ( util::param($c,"submit") =~ /Delete Comment/i ) {
      my $rows = $c->{dbh}->do("DELETE FROM COMMENTS WHERE ID = ?", undef, $comment_id);
      print STDERR "Deleted comment id '$comment_id' (rows=$rows) \n";
    } else { # must be a real update
      my $sql = "UPDATE comments SET Rating = ?, Comment = ?, Person = ?
                WHERE Id = ? AND Glass = ?";
      my $sth = $c->{dbh}->prepare($sql);
      $sth->execute($rating, $comment, $person, $comment_id, $glass );
      print STDERR "Updated comment '$comment_id' for glass  '$glass' \n";
    }
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

