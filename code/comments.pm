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
# Get CSS class for rating color coding
################################################################################
sub get_rating_class {
  my $rating = shift;
  $rating = int($rating + 0.5); # round to nearest integer
  if ($rating <= 3) { return 'rating-rubbish'; }
  elsif ($rating <= 5) { return 'rating-bronze'; }
  elsif ($rating <= 7) { return 'rating-silver'; }
  else { return 'rating-gold'; }
}

################################################################################
# Display a comment on a single line
################################################################################
sub commentline {
  my $c = shift;
  my $cr = shift; # The comment to display, from sql like one in listcomments
  my $glid = $cr->{Glass};
  my $s = "";
  
  # Preserve date parameter if present for list positioning
  my $date = util::param($c, "date");
  my $date_param = $date ? "&date=$date" : "";
  
  $s .= "<a href='$c->{url}?o=Full&e=$glid&ec=$cr->{Id}$date_param'>" .
          "<span style='font-size: xx-small'>[$cr->{Id}]</span></a>\n"
        if ( $cr->{Id} );
  $s .= "<b>($cr->{Rating})</b> \n" if ( $cr->{Rating} );
  my $people = $cr->{PeopleNames} || $cr->{PersName} || "";
  $s .= "<b>$people:</b>\n" if $people;
  my $ctype = $cr->{CommentType} || '';
  $s .= "<span style='font-size:xx-small; color:#bbb'>[$ctype]</span> \n"
    if $ctype && $ctype ne 'brew';
  $s .= "<i>$cr->{Comment} </i>\n" if ( $cr->{Comment} );
  $s .= photos::thumbnails_html($c, 'Comment', $cr->{Id}) if $cr->{Id};

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
      $s .= sprintf("<b class='%s'>%2.1f</b>", get_rating_class($avg), $avg);
      $s .= "<span style='font-size: xx-small;'>";
      $s .= "/$cnt" . "</span>" ;
    } else {
      $avg = int($avg);
      $s .= sprintf("<b class='%s'>%d</b>", get_rating_class($avg), $avg);
    }
    $s .= ") ";
  }
  if ( $com ) { # TODO - Maybe a log scale would be better
    my $n = $com;
    $n = 5 if ( $n > 5 );
    while ( $n-- ) {
      $s .= "•";
    }
  }
  return $s;
}

################################################################################
# List of all comments
################################################################################
sub listallcomments {
  my $c = shift; # context

  print "<b>Comments by $c->{username}</b> ";
  #print "&nbsp;<a href=\"$c->{url}?o=$c->{op}&e=new\"><span>(New)</span></a>";
  print "<br/>\n";
  print listrecords::listrecords($c, "COMMENTS_LIST", "Last-", "Xusername=?", $c->{username} );
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
    group_concat(cp_persons.Name, ', ') as PeopleNames
    from comments
    left join comment_persons cp on cp.Comment = comments.Id
    left join persons cp_persons on cp_persons.Id = cp.Person
    where glass = ?
    group by comments.Id
    order by comments.Id"; # To keep the order consistent
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
  $s .= photos::photo_form($c, glass => $glassid) . "\n";
  $s .= "<div  id='commentform' $hidden>\n";
  $s .= "<form method='post' action='$c->{url}' enctype='multipart/form-data'>\n";
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

  # CommentType selector
  my @ctypes = qw(brew night meal location person glass);
  my $curtype = $com->{CommentType} || 'brew';
  $s .= "<select name='commenttype' id='commenttype'>\n";
  for my $ct (@ctypes) {
    my $sel = ($curtype eq $ct) ? ' selected' : '';
    $s .= "<option value='$ct'$sel>$ct</option>\n";
  }
  $s .= "</select>\n";
  $s .= "<script>replaceSelectWithCustom(document.getElementById('commenttype'));</script>\n";

  # Privacy toggle removed - all comments are private by default

  # Person involved in the comment — pre-populate chips for existing persons
  my $prechips = '';
  if ( $com && $com->{Id} ) {
    my $psth = $c->{dbh}->prepare(
      "SELECT p.Id, p.Name FROM comment_persons cp
       JOIN persons p ON p.Id = cp.Person
       WHERE cp.Comment = ? ORDER BY p.Name");
    $psth->execute($com->{Id});
    while ( my ($pid, $pname) = $psth->fetchrow_array ) {
      $prechips .= "<span class='chip-wrapper'>" .
        "<span class='dropdown-chip'>" . util::htmlesc($pname) .
        " <a class='chip-remove' href='#'>&times;</a></span>" .
        "<input type='hidden' name='person_id' value='$pid'/>" .
        "</span>\n";
    }
  }
  $s .= persons::selectperson($c, 'person', undef, '', '', '', 'multi', $prechips);


  # Rating dropdown
  $s .= "<select name='rating' id='rating'>\n";
  $s .= "<option value=''>Rating</option>\n";
  my $r = $com->{Rating} || 0;
  for my $i (1 .. $#ratings) {  # Skip "Zero"
    my $selected = ($r == $i) ? " selected" : "";
    my $class = get_rating_class($i);
    $s .= "<option class='$class' value='$i'$selected>$i: $ratings[$i]</option>\n";
  }
  $s .= "</select>\n";
  $s .= "<script>replaceSelectWithCustom(document.getElementById('rating'));</script>\n";

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
  my $c = shift;

  my $glass      = util::param($c, "glass");
  my $comment_id = util::param($c, "comment_id");
  my $rating     = util::param($c, "rating")    || undef;
  my $comment    = util::param($c, "comment")   || undef;
  my $commenttype= util::param($c, "commenttype") || undef;
  my $private    = util::param($c, "private")   || "";
  my $person     = util::param($c, "person")    || undef; # legacy / new-person sentinel

  # Collect chip person IDs (multi-value)
  my @person_ids = $c->{cgi}->multi_param('person_id');
  @person_ids = grep { $_ && $_ =~ /^\d+$/ } @person_ids; # only plain integers

  # All comments are private (owned by this user)
  my $username = $c->{username};

  # Infer timestamp: use glass timestamp when available, else now
  my $ts = undef;
  if ( $glass ) {
    ($ts) = $c->{dbh}->selectrow_array(
      "SELECT Timestamp FROM glasses WHERE Id = ?", undef, $glass);
  }
  $ts //= util::datestr("%Y-%m-%d %H:%M:%S", 0, 1);

  if ( $person && $person eq "new" ) {  # Adding a new person via dropdown-new form
    my $newname = util::param($c,"newpersonName") || undef;
    my $newfull = util::param($c,"newpersonFullName") || undef;
    my $newdesc = util::param($c,"newpersonDescription") || undef;
    my $newcont = util::param($c,"newpersonContact") || undef;
    util::error("A Person must have a name") unless $newname;
    db::execute($c, "INSERT INTO persons (Name, FullName, Description, Contact) VALUES (?, ?, ?, ?)",
      $newname, $newfull, $newdesc, $newcont);
    my $newid = $c->{dbh}->last_insert_id(undef, undef, "PERSONS", undef);
    print { $c->{log} } "Inserted person '$newid' for comment '$comment_id' \n";
    push @person_ids, $newid;  # treat the new person as a chip
    $person = undef;
  }

  if ($comment_id) { # Update existing comment
    if ( util::param($c,"submit") =~ /Delete Comment/i ) {
      db::execute($c, "DELETE FROM comments WHERE Id = ?", $comment_id);
      print { $c->{log} } "Deleted comment id '$comment_id' \n";
    } else { # real update
      db::execute($c,
        "UPDATE comments SET Rating=?, Comment=?, CommentType=?, Username=?, Ts=?
         WHERE Id=? AND Glass IS NOT DISTINCT FROM ?",
        $rating, $comment, $commenttype, $username, $ts, $comment_id, $glass || undef);
      print { $c->{log} } "Updated comment '$comment_id' for glass '$glass' \n";
      # Rewrite comment_persons for this comment
      db::execute($c, "DELETE FROM comment_persons WHERE Comment = ?", $comment_id);
      for my $pid (@person_ids) {
        db::execute($c, "INSERT OR IGNORE INTO comment_persons (Comment, Person) VALUES (?,?)",
          $comment_id, $pid);
      }
    }
  } else { # Insert new comment
    db::execute($c,
      "INSERT INTO comments (Glass, Rating, Comment, CommentType, Username, Ts)
       VALUES (?, ?, ?, ?, ?, ?)",
      $glass || undef, $rating, $comment, $commenttype, $username, $ts);
    $comment_id = $c->{dbh}->last_insert_id(undef, undef, "COMMENTS", undef);
    print { $c->{log} } "Inserted comment '$comment_id' for glass '$glass' \n";
    for my $pid (@person_ids) {
      db::execute($c, "INSERT OR IGNORE INTO comment_persons (Comment, Person) VALUES (?,?)",
        $comment_id, $pid);
    }
  }

  # Preserve date parameter in redirect to maintain list position
  my $date_from_url = util::param($c, "date");
  if ($date_from_url) {
    $c->{redirect_url} = "$c->{url}?o=$c->{op}&date=$date_from_url";
  }

  return "";
} # postcomment


################################################################################
# Report module loaded ok
1;

