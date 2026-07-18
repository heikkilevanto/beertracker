# Part of my beertracker
# Stuff for comment records and photos (TODO)

# TODO - This too big for a module. Split it somehow.

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
# $flags: 0/undef = no extra info
#   letter string: d=date, t=time, l=location, b=brew, p=persons(no-op), y=type badge
################################################################################
sub commentline {
  my $c = shift;
  my $cr = shift; # The comment to display, from sql like one in listcomments
  my $flags = shift || 0;
  my $glid = $cr->{Glass};
  my $s = "";
  $s .= "<a href='$c->{url}?o=Comment&e=$cr->{Id}'>" .
          "<span style='font-size: xx-small'>[$cr->{Id}]</span></a>\n"
        if ( $cr->{Id} );
  $s .= "<b>($cr->{Rating})</b> \n" if ( $cr->{Rating} );
  my $people_data = $cr->{PeopleData} || "";
  if ($people_data) {
    my @items = split(/, /, $people_data);
    for (my $i = 0; $i < @items; $i++) {
      my ($name, $pid) = split(/\|/, $items[$i]);
      if ($pid) {
        $s .= "<a href='$c->{url}?o=Person&e=$pid'>" .
              "<span style='font-weight:bold;'>" . util::htmlesc($name) . "</span></a>";
      } else {
        $s .= "<span style='font-weight:bold;'>" . util::htmlesc($name) . "</span>";
      }
      $s .= ", " if $i < $#items;
    }
    $s .= ":\n";
  }
  my $ctype = $cr->{CommentType} || '';
  # Type badge: shown when no flags or when 'y' flag present
  if ($ctype && $ctype ne 'brew') {
    if (!$flags || index($flags, 'y') >= 0) {
      $s .= "<span style='font-size:xx-small; color:#bbb'>[$ctype]</span> \n";
    }
  }
  if ($flags) {
    # Letter-based flags: build extra info line
    my $extra = "";
    if (index($flags, 'd') >= 0 && $cr->{effdate}) {
      my $date = substr($cr->{effdate}, 0, 10);
      $extra .= "<span style='font-size:xx-small; color:#bbb'>$date</span>";
    }
    if (index($flags, 't') >= 0 && $cr->{time}) {
      $extra .= " " if $extra;
      $extra .= "<span style='font-size:xx-small; color:#bbb'>$cr->{time}</span>";
    }
    if (index($flags, 'l') >= 0 && $cr->{loc} && $cr->{locname}) {
      $extra .= " " if $extra;
      $extra .= "<a href='$c->{url}?o=Location&e=$cr->{loc}'>" .
                "<span style='font-size:xx-small'>\@$cr->{locname}</span></a>";
    }
    if (index($flags, 'b') >= 0 && $cr->{brewname}) {
      $extra .= " " if $extra;
      if ($cr->{Brew}) {
        $extra .= "<a href='$c->{url}?o=Brew&e=$cr->{Brew}'>" .
                  "<span style='font-size:xx-small'>$cr->{brewname}</span></a>";
      } else {
        $extra .= "<span style='font-size:xx-small; color:#bbb'>$cr->{brewname}</span>";
      }
    }
    if ($extra) {
      $s .= $extra;
      $s .= "<br/>\n" if $cr->{Comment};
    }
  }
  $s .= "&nbsp;&nbsp;<i>$cr->{Comment} </i>\n" if ( $cr->{Comment} );
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

  if ( $c->{edit} ) {
    editcomment($c);
    return;
  }

  print listrecords::listrecords($c, "COMMENTS_LIST", "Last-",
      { where => "xUsername=?", params => $c->{username},
        title => "Comments by $c->{username}" });
  return;
} # listallcomments

################################################################################
# List of comments for a given glass record
################################################################################
sub listcomments {
  my $c = shift; # context
  my $glassid = shift || "";
  my $brew     = shift || "";
  my $location = shift || "";
  my $brewtype = shift || "";

  # Derive the default comment type from the glass type
  my $commenttype;
  if ( $brewtype eq 'Night' ) {
    $commenttype = 'night';
  } elsif ( $brewtype =~ /^(Restaurant|Meal|Bar)$/ ) {
    $commenttype = 'location';
  } else {
    $commenttype = 'brew';
  }

  my $s = "";

  my $sql = "select COMMENTS.*,
    group_concat(cp_persons.Name || '|' || cp.Person, ', ') as PeopleData
    from comments
    left join comment_persons cp on cp.Comment = comments.Id
    left join persons cp_persons on cp_persons.Id = cp.Person
    where glass = ?
    group by comments.Id
    order by comments.Id"; # To keep the order consistent
  my $sth = db::query($c, $sql, $glassid);

  $s .= "&nbsp;<br/>\n";
  $s .= "<ul style='margin:0; padding-left:1.2em;'>\n";
  while ( my $cr = $sth->fetchrow_hashref ) {
    $s .= "<li>" . commentline($c,$cr) . "</li>\n";
  }
  $s .= "</ul>\n";
  my $newurl = "$c->{url}?o=Comment&e=new&glass=$glassid&commenttype=$commenttype";
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

  my $lcol = "vertical-align:top; padding:0.2em 0.5em 0 0; white-space:nowrap; color:#999; font-size:small; text-align:right";
  my $s="";
  $s .= "<!-- Comment editing form -->\n";
  $s .= "<form method='post' action='$c->{url}' enctype='multipart/form-data'>\n";
  $s .= "<input type='hidden' name='commentedit' value='1'>\n"; # To distinguish from glass submit
  $s .= "<input type='hidden' name='o' value='$c->{op}'>\n";
  $s .= "<input type='hidden' name='e' value='$c->{edit}'>\n";
  $s .= "<input type='hidden' name='glass' value='$glassid'>\n";
  $s .= "<input type='hidden' name='returnto' value='$returnto'>\n" if $returnto;
  if ($com->{Id}) {
    $s .= "<input type='hidden' name='comment_id' value='$com->{Id}'>\n";
  }

  $s .= "<table style='border-collapse:collapse'>\n";

  my @ctypes = qw(brew night meal location person glass);
  my $curtype = $com->{CommentType} || 'brew';
  my $loctext  = util::htmlesc($com->{locname}  || $com->{_glass_locname}  || "");
  my $brewtext = util::htmlesc($com->{brewname} || $com->{_glass_brewname} || "");
  my $ts_display = $com->{Ts} || $com->{_glass_ts} || "";
  $ts_display =~ s/:\d+$//;  # remove seconds

  # Type row
  my $ctopts = join("", map { "<div class='dropdown-item' id='$_'>$_</div>\n" } @ctypes);
  $s .= "<tr>\n";
  $s .= "  <td style='$lcol'>Type</td>\n";
  $s .= "  <td>\n";
  $s .= inputs::dropdown($c, "commenttype", $curtype, $curtype, $ctopts);
  $s .= "  </td>\n";
  $s .= "</tr>\n";

  # Context row: read-only text for night (loc+ts) and glass (loc+brew) types
  $s .= "<tr id='row-context' hidden>\n";
  $s .= "  <td style='$lcol'>On</td>\n";
  $s .= "  <td>\n";
  $s .= "    <div id='night-display' hidden><span style='color:#aaa'>$loctext</span>";
  $s .= " &nbsp;<span style='color:#aaa'>$ts_display</span>" if $ts_display;
  $s .= "</div>\n";
  $s .= "    <div id='glass-display' hidden><span style='color:#aaa'>$loctext</span>";
  $s .= " &nbsp;<span style='color:#aaa'>$brewtext</span>" if $brewtext;
  $s .= "</div>\n";
  $s .= "  </td>\n";
  $s .= "</tr>\n";

  # Person row
  my $prechips = '';
  if ( $com->{Id} ) {
    my $psth = db::query($c,
      "SELECT p.Id, p.Name FROM comment_persons cp
       JOIN persons p ON p.Id = cp.Person
       WHERE cp.Comment = ? ORDER BY p.Name", $com->{Id});
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
  $s .= "<tr id='row-person'>\n";
  $s .= "  <td style='$lcol'>Person</td>\n";
  $s .= "  <td>\n";
  $s .= persons::selectperson($c, 'person', undef, '', '', '', 'multi', $prechips);
  $s .= "  </td>\n";
  $s .= "</tr>\n";

  # Brew row
  $s .= "<tr id='row-brew'>\n";
  $s .= "  <td style='$lcol'>Brew</td>\n";
  $s .= "  <td>\n";
  $s .= brews::selectbrew($c, $com->{Brew}||'');
  $s .= "  </td>\n";
  $s .= "</tr>\n";

  # Location row
  $s .= "<tr id='row-location'>\n";
  $s .= "  <td style='$lcol'>Location</td>\n";
  $s .= "  <td>\n";
  $s .= locations::selectlocation($c, 'Location', $com->{Location}||'', '', 'non');
  $s .= "  </td>\n";
  $s .= "</tr>\n";

  # Timestamp row (hidden by default, shown with "show all")
  my $ts_val = $com->{Ts} || "";
  $ts_val =~ s/ /T/;    # datetime-local format
  $ts_val =~ s/:\d+$//; # remove seconds
  $s .= "<tr id='row-ts' hidden>\n";
  $s .= "  <td style='$lcol'>Timestamp</td>\n";
  $s .= "  <td><input type='datetime-local' name='ts' value='$ts_val'></td>\n";
  $s .= "</tr>\n";

  # Public row (hidden by default)
  my $is_public = ($com->{Id} && !$com->{Username}) ? " checked" : "";
  $s .= "<tr id='row-public' hidden>\n";
  $s .= "  <td></td>\n";
  $s .= "  <td><label><input type='checkbox' name='public' value='1'$is_public>" .
        " <span style='color:#aaa; font-size:small'>Public comment</span></label></td>\n";
  $s .= "</tr>\n";

  # Comment row
  my $comment = $com->{Comment} || "";
  my $pl = "Add a new comment";
  $s .= "<tr>\n";
  $s .= "  <td style='$lcol'>Comment</td>\n";
  $s .= "  <td><textarea name='comment' rows='3' cols='40' placeholder='$pl'>$comment</textarea></td>\n";
  $s .= "</tr>\n";

  # Rating row
  my $r = $com->{Rating} || 0;
  my $ratopts = "<div class='dropdown-item' id=''>Rating</div>\n";
  for my $i (1 .. $#ratings) {  # Skip "Zero"
    my $rclass = get_rating_class($i);
    $ratopts .= "<div class='dropdown-item $rclass' id='$i'>$i: $ratings[$i]</div>\n";
  }
  my $rat_id   = $r || "";
  my $rat_name = $r ? "$r: $ratings[$r]" : "Rating";
  my $rat_class = $r ? get_rating_class($r) : "";
  $s .= "<tr>\n";
  $s .= "  <td style='$lcol'>Rating</td>\n";
  $s .= "  <td>\n";
  $s .= inputs::dropdown($c, "rating", $rat_id, $rat_name, $ratopts);
  $s .= qq{  <script>
(function(){
  var dd = document.getElementById('dropdown-rating');
  if (!dd) return;
  var hidden = dd.querySelector('input[type=hidden]');
  var filter = dd.querySelector('.dropdown-filter');
  var ratingClasses = ['rating-rubbish','rating-bronze','rating-silver','rating-gold'];
  function syncClass() {
    ratingClasses.forEach(function(c){filter.classList.remove(c);});
    if (!hidden.value) return;
    var item = dd.querySelector('.dropdown-item[id="'+hidden.value+'"]');
    if (item) {
      var cls = Array.from(item.classList).find(function(c){return c.startsWith('rating-');});
      if (cls) filter.classList.add(cls);
    }
  }
  hidden.addEventListener('input', syncClass);
  syncClass();
})();
  </script>\n};
  $s .= "  </td>\n";
  $s .= "</tr>\n";

  # Buttons row
  my $button_text = $com->{Id} ? "Upd" : "Add";
  $s .= "<tr>\n";
  $s .= "  <td colspan='2'>\n";
  $s .= "    <input type='submit' name='submit' value='$button_text'>\n";
  $s .= "    &nbsp;<a href='$cancel_url'><span>Cancel</span></a>\n";
  $s .= "    &nbsp;<input type='submit' name='submit' value='Del'>\n" if $com->{Id};
  $s .= "    &nbsp;<a href='#' id='show-all-link'><span>(Show all fields)</span></a>\n";
  $s .= "  </td>\n";
  $s .= "</tr>\n";
  $s .= "</table>\n";
  $s .= "</form>\n";

  # Photos attached to this comment
  if ($com->{Id}) {
    my $thumbs = photos::thumbnails_html($c, 'Comment', $com->{Id});
    $s .= $thumbs if $thumbs;
  }

  # Photo upload link — only for saved comments
  if ($com->{Id}) {
    $s .= photos::photo_form($c, comment => $com->{Id},
        return_url => "$c->{url}?o=Comment&e=$com->{Id}") . "\n";
  }

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

  # Other comments on the same item (via listrecords)
  my $context_brew = $com->{Brew};
  my $context_loc  = $com->{Location};
  if ($glassid && !$context_brew && !$context_loc) {
    ($context_brew, $context_loc) = db::queryarray($c,
        "SELECT Brew, Location FROM glasses WHERE Id = ?", $glassid);
  }
  my $sibling_html = "";
  if ($context_brew) {
    my ($cnt) = db::queryarray($c, q{SELECT COUNT(*) FROM COMMENTS_LIST WHERE
        EXISTS (SELECT 1 FROM comments c2 LEFT JOIN glasses g2 ON g2.Id = c2.Glass
                WHERE c2.Id = "Id_A_link:Comment" AND (c2.Brew = ? OR g2.Brew = ?))
        AND xUsername = ? AND "Id_A_link:Comment" != ?},
        $context_brew, $context_brew, $c->{username}, $com->{Id});
    if ($cnt && $cnt > 0) {
      $sibling_html = listrecords::listrecords($c, "COMMENTS_LIST", "Last-", {
          where => q{EXISTS (SELECT 1 FROM comments c2
                     LEFT JOIN glasses g2 ON g2.Id = c2.Glass
                     WHERE c2.Id = "Id_A_link:Comment"
                       AND (c2.Brew = ? OR g2.Brew = ?))
                     AND xUsername = ? AND "Id_A_link:Comment" != ?},
          params => [$context_brew, $context_brew, $c->{username}, $com->{Id}],
          title => "Other comments on this brew",
          initial_filter => { CommentType => "brew" },
          show_rating_summary => 1,
          compact_on_small => 1,
          no_new_link => 1,
          maxrecords => 10,
      });
    }
  } elsif ($context_loc) {
    my ($cnt) = db::queryarray($c, q{SELECT COUNT(*) FROM COMMENTS_LIST WHERE
        CAST("LocId_A_link:Location" AS INTEGER) = ? AND xUsername = ? AND "Id_A_link:Comment" != ?},
        $context_loc, $c->{username}, $com->{Id});
    if ($cnt && $cnt > 0) {
      $sibling_html = listrecords::listrecords($c, "COMMENTS_LIST", "Last-", {
          where => q{CAST("LocId_A_link:Location" AS INTEGER) = ? AND xUsername = ?
                     AND "Id_A_link:Comment" != ?},
          params => [$context_loc, $c->{username}, $com->{Id}],
          title => "Other comments at this location",
          initial_filter => { CommentType => "location" },
          show_rating_summary => 1,
          compact_on_small => 1,
          no_new_link => 1,
          maxrecords => 10,
      });
    }
  } elsif ($com->{Id} && $com->{CommentType} eq 'person') {
    my ($pid) = db::queryarray($c,
        "SELECT Person FROM comment_persons WHERE Comment = ?", $com->{Id});
    if ($pid) {
      my ($cnt) = db::queryarray($c, q{SELECT COUNT(*) FROM COMMENTS_LIST WHERE
          EXISTS (SELECT 1 FROM comment_persons cp
                  WHERE cp.Comment = "Id_A_link:Comment" AND cp.Person = ?)
          AND xUsername = ? AND "Id_A_link:Comment" != ?},
          $pid, $c->{username}, $com->{Id});
      if ($cnt && $cnt > 0) {
        $sibling_html = listrecords::listrecords($c, "COMMENTS_LIST", "Last-", {
            where => q{EXISTS (SELECT 1 FROM comment_persons cp
                       WHERE cp.Comment = "Id_A_link:Comment" AND cp.Person = ?)
                       AND xUsername = ? AND "Id_A_link:Comment" != ?},
            params => [$pid, $c->{username}, $com->{Id}],
            title => "Other comments mentioning this person",
            initial_filter => { CommentType => "person" },
            show_rating_summary => 1,
            compact_on_small => 1,
            no_new_link => 1,
            maxrecords => 10,
        });
      }
    }
  }
  if ($sibling_html) {
    $s .= "<hr style='border-color:#444; margin:0.5em 0'>\n";
    $s .= $sibling_html;
  }

  # JS: show/hide rows based on comment type, and "show all" toggle
  my $glass_is_empty = ($com->{glass_brewtype} && glasses::isemptyglass($com->{glass_brewtype})) ? 1 : 0;
  $s .= "<script>var glassIsEmpty = $glass_is_empty; initCommentForm();</script>\n";

  return $s;
} # commentform



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
        gloc.Name AS locname,   gloc.Id AS locid,
        g.BrewType AS glass_brewtype
      FROM comments c
      LEFT JOIN glasses   g    ON g.Id    = c.Glass
      LEFT JOIN brews     b    ON b.Id    = g.Brew
      LEFT JOIN locations gloc ON gloc.Id = g.Location
      LEFT JOIN locations ploc ON ploc.Id = b.ProducerLocation
      WHERE c.Id = ?
        AND ( (c.Glass IS NOT NULL AND g.Username = ?)
           OR (c.Glass IS NULL     AND c.Username = ?) )
    };
    $com = db::queryrecord($c, $sql, $ec, $c->{username}, $c->{username});
    util::error("Comment $ec not found") unless $com;
  }

  print "<b>" . ( $ec ? "Edit comment $ec" : "New comment" ) . "</b><br/>\n";

  my ($gloc, $gbrew, $gts, $gbrewtype);  # glass display data for commentform (set below if prefill_glass)

  # Context header, shows wha this comment refers to
  if ($com && $com->{Glass}) {
    my ($date, $wd) = util::splitdate($com->{effdate});
    my $glass_url = "$c->{url}?o=Full&e=$com->{Glass}&date=$date&ndays=1";
    print "On: <a href='$glass_url'><span>$wd $date $com->{effhm}";
    print " \@$com->{locname}" if $com->{locname};
    print "</span></a><br/>\n";  # newline after time and location
    if ($com->{brewname}) {
      my $sep = $com->{prodname} ? "<b>$com->{prodname}</b>: " : "";
      print "<a href='$c->{url}?o=Brew&e=$com->{brewid}'><span>${sep}<b>$com->{brewname}</b></span></a><br/>\n";
    }
  } elsif ($com && $com->{Location}) {
    my ($locname) = $c->{dbh}->selectrow_array(
      "SELECT Name FROM locations WHERE Id = ?", undef, $com->{Location});
    print "On location: <a href='$c->{url}?o=Location&e=$com->{Location}'>" .
          "<span>" . ($locname || $com->{Location}) . "</span></a><br/>\n";
  } elsif ($prefill_glass) {
    # New comment for a known glass — show context and fetch brew/location for prefill
    my ($gdate, $glocid, $gbrewid);
        ($gdate, $gloc, $glocid, $gbrew, $gbrewid, $gts, $gbrewtype) = db::queryarray($c, q{
          SELECT strftime('%Y-%m-%d %w %H:%M', g.Timestamp, '-06:00'),
            gloc.Name, g.Location, b.Name, g.Brew, g.Timestamp, g.BrewType
          FROM glasses g
          LEFT JOIN locations gloc ON gloc.Id = g.Location
          LEFT JOIN brews b ON b.Id = g.Brew
          WHERE g.Id = ? AND g.Username = ?}, $prefill_glass, $c->{username});
    if ($gdate) {
      my ($date, $wd) = util::splitdate($gdate);
      print "On: <a href='$c->{url}?o=Full&e=$prefill_glass&date=$date&ndays=1'>" .
            "<span>$wd $date";
      print " \@$gloc" if $gloc;
      print "</span></a><br/>\n";  # newline after time and location
      if ($gbrew && $gbrewid) {
        print "<a href='$c->{url}?o=Brew&e=$gbrewid'><span><b>$gbrew</b></span></a><br/>\n";
      } elsif ($gbrew) {
        print "<b>$gbrew</b><br/>\n";
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
      my ($pname) = db::queryarray($c,
        "SELECT Name FROM persons WHERE Id = ?", $prefill_pid);
      $com->{_prefill_person_id}   = $prefill_pid;
      $com->{_prefill_person_name} = $pname || $prefill_pid;
    }
    # Pass glass display data for night/glass text display in commentform
    $com->{_glass_locname}  = $gloc if $gloc;
    $com->{_glass_brewname} = $gbrew if $gbrew;
    $com->{Ts}              = $gts  if $gts && !$com->{Ts};
    $com->{glass_brewtype}  = $gbrewtype if $gbrewtype;
  }

  # Cancel: always back to the comments list
  my $returnto   = util::param($c, "returnto") || "";
  $returnto      =~ s/[^a-z]//g;  # Restrict to lowercase letters only (safe page names)
  my $cancel_url = $returnto ? "$c->{url}?o=$returnto" : "$c->{url}?o=Comment";
  my $glass_id   = $com->{Glass} || $prefill_glass || "";

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
  my $public     = util::param($c, "public")    || ""; # public=1 means no username stored
  my $person     = util::param($c, "person")    || undef; # legacy / new-person sentinel
  my $location   = util::param($c, "Location")  || undef;
  my $brew       = util::param($c, "Brew")      || undef;
  $location = undef unless ($location && $location =~ /^\d+$/);
  $brew     = undef unless ($brew     && $brew     =~ /^\d+$/);

  # Collect chip person IDs (multi-value)
  my @person_ids = $c->{cgi}->multi_param('person_id');
  @person_ids = grep { $_ && $_ =~ /^\d+$/ } @person_ids; # only plain integers

  # Username: private (default) uses current user; public comment stores no username
  my $username = $public ? undef : $c->{username};

  # Timestamp: user-supplied override takes priority, then glass timestamp, then now
  my $ts_override = util::param($c, "ts") || "";
  $ts_override =~ s/T/ /;           # datetime-local uses T as separator
  $ts_override .= ":00" if $ts_override =~ /^\d{4}-\d{2}-\d{2} \d{2}:\d{2}$/;
  my $ts;
  if ($ts_override =~ /^\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}$/) {
    $ts = $ts_override;
  } elsif ( $glass ) {
    ($ts) = db::queryarray($c,
      "SELECT Timestamp FROM glasses WHERE Id = ?", $glass);
  }
  $ts //= util::datestr("%Y-%m-%d %H:%M:%S", 0, 1);

  if ( $person && $person eq "new" ) {  # Adding a new person via dropdown-new form
    my $newname = util::param($c,"newpersonName") || undef;
    my $newfull = util::param($c,"newpersonFullName") || undef;
    my $newdesc = util::param($c,"newpersonDescription") || undef;
    my $newcont = util::param($c,"newpersonContact") || undef;
    my $newtags = util::clean_tags(util::param($c,"newpersonTags")) || undef;
    util::error("A Person must have a name") unless $newname;
    db::execute($c, "INSERT INTO persons (Name, FullName, Description, Contact, Tags) VALUES (?, ?, ?, ?, ?)",
      $newname, $newfull, $newdesc, $newcont, $newtags);
    my $newid = $c->{dbh}->last_insert_id(undef, undef, "PERSONS", undef);
    print { $c->{log} } "Inserted person '$newid' for comment '$comment_id' \n";
    push @person_ids, $newid;  # treat the new person as a chip
    $person = undef;
  }

  if ($comment_id) { # Update existing comment
    if ( util::param($c,"submit") =~ /^Del/i ) {
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

