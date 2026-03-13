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
  $s .= "<a href='$c->{url}?o=Comment&e=$cr->{Id}'>" .
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
  print "&nbsp;<a href='$c->{url}?o=Comment&e=new&returnto=comments'><span>(New)</span></a>";
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
  my $brew     = shift || "";
  my $location = shift || "";

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
  $s .= "<ul style='margin:0; padding-left:1.2em;'>\n";
  while ( my $cr = $sth->fetchrow_hashref ) {
    $s .= "<li>" . commentline($c,$cr) . "</li>\n";
  }
  $s .= "</ul>\n";
  my $newurl = "$c->{url}?o=Comment&e=new&glass=$glassid&commenttype=brew";
  $newurl .= "&brew=$brew"         if $brew;
  $newurl .= "&location=$location" if $location;
  $s .= "<a href='$newurl'><span>(New comment)</span></a>\n";
  return $s;
} # listcomments

################################################################################
# Form to enter or edit a comment
################################################################################

sub commentform {
  my $c          = shift;
  my $com        = shift // {};
  my $glassid    = shift || "";
  my $cancel_url = shift || "$c->{url}?o=Comment";
  my $returnto   = shift || "";

  my $s="";
  $s .= "<!-- Comment editing form -->\n";
  # Photo link is placed below the form (see end of this function)
  $s .= "<form method='post' action='$c->{url}' enctype='multipart/form-data'>\n";
  $s .= "<input type='hidden' name='commentedit' value='1'>\n"; # To distinguish from glass submit
  $s .= "<input type='hidden' name='o' value='$c->{op}'>\n";
  $s .= "<input type='hidden' name='e' value='$c->{edit}'>\n";
  $s .= "<input type='hidden' name='glass' value='$glassid'>\n";
  $s .= "<input type='hidden' name='returnto' value='$returnto'>\n" if $returnto;
  if ($com->{Id}) {
    $s .= "<input type='hidden' name='comment_id' value='$com->{Id}'>\n";
  }

  # Comment text area (always shown)
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

  # Person involved in the comment — pre-populate chips for existing persons or prefill
  my $prechips = '';
  if ( $com->{Id} ) {
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
  } elsif ($com->{_prefill_person_id}) {
    my $pid   = $com->{_prefill_person_id};
    my $pname = $com->{_prefill_person_name} || $pid;
    $prechips .= "<span class='chip-wrapper'>" .
      "<span class='dropdown-chip'>" . util::htmlesc($pname) .
      " <a class='chip-remove' href='#'>&times;</a></span>" .
      "<input type='hidden' name='person_id' value='$pid'/>" .
      "</span>\n";
  }
  # Person selector (conditionally shown based on commenttype; always shown if pre-populated)
  $s .= "<div id='commentfield-person'>\n";
  $s .= persons::selectperson($c, 'person', undef, '', '', '', 'multi', $prechips);
  $s .= "</div>\n";

  # Location selector (conditionally shown)
  $s .= "<div id='commentfield-location'>\n";
  $s .= locations::selectlocation($c, 'Location', $com->{Location}||'', '', 'non');
  $s .= "</div>\n";

  # Brew selector (conditionally shown)
  $s .= "<div id='commentfield-brew'>\n";
  $s .= brews::selectbrew($c, $com->{Brew}||'');
  $s .= "</div>\n";

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
  $s .= "<a href='$cancel_url'><span>Cancel</span></a>\n";
  $s .= "<input type='submit' name='submit' value='Delete Comment'>\n" if ( $com->{Id} );
  $s .= "</form>\n";

  # Photo upload link (moved below the form)
  $s .= photos::photo_form($c, glass => $glassid) . "\n" if $glassid;

  # "Add another comment on the same item" link
  if ($glassid) {
    my $another_url = "$c->{url}?o=Comment&e=new&glass=$glassid&commenttype=$curtype";
    $s .= "<a href='$another_url'><span>(Add another comment)</span></a><br/>\n";
  } elsif ($com->{Brew}) {
    my $another_url = "$c->{url}?o=Comment&e=new&brew=$com->{Brew}&commenttype=brew";
    $s .= "<a href='$another_url'><span>(Add another comment)</span></a><br/>\n";
  } elsif ($com->{Location}) {
    my $another_url = "$c->{url}?o=Comment&e=new&location=$com->{Location}&commenttype=location";
    $s .= "<a href='$another_url'><span>(Add another comment)</span></a><br/>\n";
  }

  # "Show all fields" link and JS for field visibility based on commenttype
  $s .= "<a href='#' onclick='showAllCommentFields(); return false;'><span>(Show all fields)</span></a>\n";
  $s .= <<'JSEND';
<script>
function updateCommentFields() {
  var typeEl = document.getElementById('commenttype');
  var type = typeEl ? typeEl.value : 'brew';
  var brewDiv     = document.getElementById('commentfield-brew');
  var personDiv   = document.getElementById('commentfield-person');
  var locationDiv = document.getElementById('commentfield-location');

  function hasValue(div) {
    if (!div) return false;
    var hidden = div.querySelector('input[type=hidden][name=Brew], input[type=hidden][name=Location]');
    if (hidden && hidden.value) return true;
    var personInputs = div.querySelectorAll('input[name=person_id]');
    return personInputs.length > 0;
  }

  var showBrew     = (type === 'brew' || type === 'meal' || type === 'glass') || hasValue(brewDiv);
  var showPerson   = (type === 'person') || hasValue(personDiv);
  var showLocation = (type !== 'glass') || hasValue(locationDiv);

  if (brewDiv)     brewDiv.hidden     = !showBrew;
  if (personDiv)   personDiv.hidden   = !showPerson;
  if (locationDiv) locationDiv.hidden = !showLocation;
}

function showAllCommentFields() {
  ['commentfield-brew', 'commentfield-person', 'commentfield-location'].forEach(function(id) {
    var el = document.getElementById(id);
    if (el) el.hidden = false;
  });
}

var commenttypeEl = document.getElementById('commenttype');
if (commenttypeEl) {
  commenttypeEl.addEventListener('change', updateCommentFields);
  updateCommentFields();
}
</script>
JSEND

  return $s;
}

################################################################################
# Standalone comment edit/create page  (o=Comment&e=<id> or with prefill params)
################################################################################

sub editcomment {
  my $c = shift;
  my $ec = $c->{edit};
  $ec = undef unless ($ec && $ec =~ /^\d+$/);  # only numeric ids are real comments
  my $com = undef;

  # Prefill from GET params (used when creating a new comment)
  my $prefill_glass= util::param($c, "glass")       || "";
  my $prefill_type = util::param($c, "commenttype") || "";
  my $prefill_pid  = util::param($c, "person")      || "";
  my $prefill_loc  = util::param($c, "location")    || "";
  my $prefill_brew = util::param($c, "brew")        || "";

  if ($ec) {
    my $sql = q{
      SELECT c.*,
        strftime('%Y-%m-%d %w', COALESCE(g.Timestamp, c.Ts), '-06:00') AS effdate,
        strftime('%H:%M',       COALESCE(g.Timestamp, c.Ts))           AS effhm,
        b.Name    AS brewname,  b.Id    AS brewid,
        ploc.Name AS prodname,
        gloc.Name AS locname,   gloc.Id AS locid
      FROM comments c
      LEFT JOIN glasses   g    ON g.Id    = c.Glass
      LEFT JOIN brews     b    ON b.Id    = g.Brew
      LEFT JOIN locations gloc ON gloc.Id = g.Location
      LEFT JOIN locations ploc ON ploc.Id = b.ProducerLocation
      WHERE c.Id = ?
        AND ( (c.Glass IS NOT NULL AND g.Username = ?)
           OR (c.Glass IS NULL     AND c.Username = ?) )
    };
    $com = $c->{dbh}->selectrow_hashref($sql, undef, $ec, $c->{username}, $c->{username});
    util::error("Comment $ec not found") unless $com;
  }

  print "<b>" . ( $ec ? "Edit comment $ec" : "New comment" ) . "</b><br/>\n";

  # Context header
  if ($com && $com->{Glass}) {
    my ($date, $wd) = util::splitdate($com->{effdate});
    my $glass_url = "$c->{url}?o=Full&e=$com->{Glass}&date=$date&ndays=1";
    print "On: <a href='$glass_url'><span>$wd $date $com->{effhm}";
    print " \@$com->{locname}" if $com->{locname};
    print "</span></a><br/>\n";  # newline after time and location
    if ($com->{brewname}) {
      my $sep = $com->{prodname} ? "$com->{prodname}: " : "";
      print "<a href='$c->{url}?o=Brew&e=$com->{brewid}'><span>$sep$com->{brewname}</span></a><br/>\n";
    }
  } elsif ($com && $com->{Location}) {
    my ($locname) = $c->{dbh}->selectrow_array(
      "SELECT Name FROM locations WHERE Id = ?", undef, $com->{Location});
    print "On location: <a href='$c->{url}?o=Location&e=$com->{Location}'>" .
          "<span>" . ($locname || $com->{Location}) . "</span></a><br/>\n";
  } elsif ($prefill_glass) {
    # New comment for a known glass — show context and fetch brew/location for prefill
    my ($gdate, $gloc, $glocid, $gbrew, $gbrewid) = $c->{dbh}->selectrow_array(q{
      SELECT strftime('%Y-%m-%d %w %H:%M', g.Timestamp, '-06:00'),
             gloc.Name, g.Location, b.Name, g.Brew
      FROM glasses g
      LEFT JOIN locations gloc ON gloc.Id = g.Location
      LEFT JOIN brews b ON b.Id = g.Brew
      WHERE g.Id = ? AND g.Username = ?}, undef, $prefill_glass, $c->{username});
    if ($gdate) {
      my ($date, $wd) = util::splitdate($gdate);
      print "On: <a href='$c->{url}?o=Full&e=$prefill_glass&date=$date&ndays=1'>" .
            "<span>$wd $date";
      print " \@$gloc" if $gloc;
      print "</span></a><br/>\n";  # newline after time and location
      if ($gbrew && $gbrewid) {
        print "<a href='$c->{url}?o=Brew&e=$gbrewid'><span>$gbrew</span></a><br/>\n";
      } elsif ($gbrew) {
        print "$gbrew<br/>\n";
      }
      # Prefill brew/location from the glass unless already specified in GET params
      $prefill_loc  ||= $glocid  if $glocid;
      $prefill_brew ||= $gbrewid if $gbrewid;
    }
  }

  # For new comment: seed $com with prefill values so commentform uses them
  unless ($com) {
    $com = { CommentType => $prefill_type || 'brew' };
    $com->{Location} = $prefill_loc if $prefill_loc && $prefill_loc =~ /^\d+$/;
    $com->{Brew}     = $prefill_brew if $prefill_brew && $prefill_brew =~ /^\d+$/;
    if ($prefill_pid) {
      my ($pname) = $c->{dbh}->selectrow_array(
        "SELECT Name FROM persons WHERE Id = ?", undef, $prefill_pid);
      $com->{_prefill_person_id}   = $prefill_pid;
      $com->{_prefill_person_name} = $pname || $prefill_pid;
    }
  }

  # Cancel: back to that day in mainlist if we know the glass, or to returnto page
  my $returnto   = util::param($c, "returnto") || "";
  $returnto      =~ s/[^a-z]//g;  # Restrict to lowercase letters only (safe page names)
  my $cancel_url = $returnto ? "$c->{url}?o=$returnto" : "$c->{url}?o=Comment";
  my $glass_id   = $com->{Glass} || $prefill_glass || "";
  if ($glass_id) {
    my ($effdate) = $c->{dbh}->selectrow_array(
      "SELECT strftime('%Y-%m-%d', Timestamp, '-06:00') FROM glasses WHERE Id = ? AND Username = ?",
      undef, $glass_id, $c->{username});
    $cancel_url = "$c->{url}?o=Full&date=$effdate&ndays=1" if $effdate;
  }

  print commentform($c, $com, $glass_id, $cancel_url, $returnto);
} # editcomment

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
  my $location   = util::param($c, "Location")  || undef;
  my $brew       = util::param($c, "Brew")      || undef;
  $location = undef unless ($location && $location =~ /^\d+$/);
  $brew     = undef unless ($brew     && $brew     =~ /^\d+$/);

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
        "UPDATE comments SET Rating=?, Comment=?, CommentType=?, Username=?, Ts=?,
         Location=?, Brew=?
         WHERE Id=? AND Glass IS NOT DISTINCT FROM ?",
        $rating, $comment, $commenttype, $username, $ts,
        $location, $brew, $comment_id, $glass || undef);
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
      "INSERT INTO comments (Glass, Rating, Comment, CommentType, Username, Ts, Location, Brew)
       VALUES (?, ?, ?, ?, ?, ?, ?, ?)",
      $glass || undef, $rating, $comment, $commenttype, $username, $ts, $location, $brew);
    $comment_id = $c->{dbh}->last_insert_id(undef, undef, "COMMENTS", undef);
    print { $c->{log} } "Inserted comment '$comment_id' for glass '$glass' \n";
    for my $pid (@person_ids) {
      db::execute($c, "INSERT OR IGNORE INTO comment_persons (Comment, Person) VALUES (?,?)",
        $comment_id, $pid);
    }
  }

  # Redirect to avoid duplicate form submission on refresh, back to the glass's date
  my $effdate;
  if ( $glass ) {
    ($effdate) = $c->{dbh}->selectrow_array(
      "SELECT strftime('%Y-%m-%d', Timestamp, '-06:00') FROM glasses WHERE Id = ? AND Username = ?",
      undef, $glass, $c->{username});
  }
  if ( $effdate ) {
    $c->{redirect_url} = "$c->{url}?o=Full&date=$effdate&ndays=1";
  } else {
    my $returnto = util::param($c, "returnto") || "";
    $returnto =~ s/[^a-z]//g;  # Restrict to lowercase letters only
    $c->{redirect_url} = $returnto ? "$c->{url}?o=$returnto" : "$c->{url}?o=comment";
  }
  return "";
} # postcomment


################################################################################
# Report module loaded ok
1;

