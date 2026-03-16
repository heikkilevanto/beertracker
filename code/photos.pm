# Part of my beertracker
# Routines for managing photos

package photos;
use strict;
use warnings;
use feature 'unicode_strings';
use utf8;  # Source code and string literals are utf-8

use POSIX qw(strftime);
my $q = CGI->new;
$q->charset( "UTF-8" );


# Default image sizes (width in pixels)
my %imagesizes;
$imagesizes{"thumb"} = 90;
$imagesizes{"small"} = 40;  # For compact list display
$imagesizes{"mob"} = 240;  # 320 is full width on my phone
$imagesizes{"pc"} = 640;


# TODO - Pass $c to all subs, etc
#

# TODO
#- Make a routine to scale to any given width. Check if already there.
#- Use that when displaying
#- When clearing the cache, delete scaled images over a month old, but not .orig





# Get image file name. Width can be in pixels, or special values like
# "orig" for the original image, "" for the plain name to be saved in the record,
# or "thumb", "mob", "pc" for default sizes
sub imagefilename {
  my $c = shift;
  my $fn = shift; # The raw file name
  my $width = shift; # How wide we want it, or "orig" or ""
  $fn =~ s/(\.?\+?orig)?\.jpe?g$//i; # drop extension if any
  return $fn if (!$width); # empty width for saving the clean filename in $rec
  $fn = "$c->{photodir}/$fn"; # a real filename
  if ( $width =~ /\.?orig/ ) {
    $fn .= "+orig.jpg";
    return $fn;
  }
  $width = $imagesizes{$width} || "";
  return "" unless $width;
  $width .= "w"; # for easier deleting *w.jpg
  $fn .= "+$width.jpg";
  return $fn;
} # imagefilename


# Produce the image tag
sub imagetag {
  my $c        = shift;
  my $photo    = shift;  # The name, as in the db
  my $width    = shift || "thumb"; # One of the keys in %imagesizes
  my $link_url = shift;  # Optional: override the link target (defaults to orig)
  return "" unless ( $photo );
  my $orig = imagefilename($c,$photo, "orig");
  if ( ! -r $orig ) {
    print { $c->{log} } "Photo file '$orig' not found \n";
    return "";
  }
  my $fn = imagefilename($c,$photo, $width);
  return "" unless $fn;
  if ( ! -r $fn ) { # Need to resize it
    my $size = $imagesizes{$width};
    $size = $size . "x". $size .">";
    print { $c->{log} } "convert $orig -resize '$size' $fn \n";
    my @cmd = ('/usr/bin/convert', $orig, '-resize', $size, $fn);
    print { $c->{log} } "Running: " . join(' ', @cmd) . "\n";
    my $rc = system(@cmd);
    if ($rc != 0) {
      my $exit = $rc >> 8;
      print { $c->{log} } "Resize failed rc=$rc exit=$exit for $orig -> $fn\n";
      return ""; # return empty tag when conversion fails
    }
  }
  my $w    = $imagesizes{$width};
  my $href = $link_url || $orig;
  my $tgt  = $link_url ? "" : " target='_blank'";
  my $itag = "<img src='$fn' width='$w' style='vertical-align:top' />";
  my $tag  = "<a href='$href'$tgt style='margin-right:6px; display:inline-block'>$itag</a>\n";
  return $tag;
} # imagetag


# Return a list of photo records for a given entity.
# Usage: get_photos($c, 'Comment', $comment_id)  -- $col is the photos table column name
sub get_photos {
  my $c   = shift;
  my $col = shift; # photos table column: Comment, Glass, Location, Person, Brew
  my $id  = shift;
  return () unless defined($id) && $id ne '';
  my $sql = "SELECT * FROM photos WHERE $col = ? ORDER BY Id";
  my $sth = db::query($c, $sql, $id);
  my @photos;
  while (my $row = $sth->fetchrow_hashref) {
    push @photos, $row;
  }
  return @photos;
} # get_photos

# Return thumbnail HTML for all photos attached to an entity.
# Each thumbnail links to the full-size original.
# Usage: thumbnails_html($c, 'Comment', $id)  -- $col is the photos table column name
sub thumbnails_html {
  my $c   = shift;
  my $col = shift; # photos table column: Comment, Glass, Location, Person, Brew
  my $id  = shift;
  return '' unless defined($id) && $id ne '';
  my @photos = get_photos($c, $col, $id);
  return '' unless @photos;
  my $s = '';
  for my $p (@photos) {
    my $editurl = "$c->{url}?o=Photos&e=$p->{Id}";
    $s .= imagetag($c, $p->{Filename}, 'thumb', $editurl);
  }
  return "<div style='margin-left:1.2em; margin-top:3px'>$s</div>\n";
} # thumbnails_html


# Save the uploaded image in a file.
# $prefix is the full filename base, e.g. "c-42" or "g-100-1700000000".
sub savefile {
  my $c      = shift;
  my $prefix = shift;

  my $storename = $prefix;
  my $dbname = imagefilename($c, $storename,"");  # To be saved in the db
  my $filename = imagefilename($c, $storename, "orig"); # file to save in
  print { $c->{log} } "Saving image '$dbname' into '$filename' \n";

  util::error("FIle '$dbname' already exists, will not overwrite")
    if ( -e $filename );
  my $filehandle = $c->{cgi}->upload('photo');
  if ( ! $filehandle ) {
    print { $c->{log} } "No upload filehandle in photos::savefile\n";
    return "";
  }
  my $tmpfilename = $c->{cgi}->tmpFileName( $filehandle );
  unless ( -r $tmpfilename ) {
    util::error("Upload temp file '$tmpfilename' not readable");
  }
  # Ensure destination directory exists
  use File::Basename;
  my $destdir = dirname($filename);
  unless ( -d $destdir ) {
    unless (mkdir $destdir) {
      util::error("Could not create photo directory '$destdir': $!");
    }
  }
  my @cmd = ('/usr/bin/convert', $tmpfilename, '-auto-orient', '-strip', $filename);
  print { $c->{log} } "Running: " . join(' ', @cmd) . "\n";
  my $rc = system(@cmd);
  if ($rc != 0) {
    my $exit = $rc >> 8;
    util::error("Image convert failed (exit=$exit) while creating $filename");
  }
  my $fsz = -s $filename;
  print { $c->{log} } "Uploaded $fsz bytes into '$filename' \n";
  return $dbname; # The name without width-specs
}# savefile


################################################################################
# Collapsible (photo) upload widget. Returns an HTML string.
# Clicking "(Photo)" immediately triggers the file picker / camera.
# Once a file is chosen the form auto-submits — no extra button needed.
# Options (as key=>value pairs):
#   glass|location|person|brew|comment => $id   (one required)
#   public_default => 0|1   (default 0)
#   return_url     => $url  (where to redirect after upload)
sub photo_form {
  my $c    = shift;
  my %opts = @_;

  # Find which entity type was supplied
  my ($entity_type, $entity_id);
  for my $t (qw(glass location person brew comment)) {
    if (defined $opts{$t} && $opts{$t} ne '') {
      $entity_type = $t;
      $entity_id   = $opts{$t};
      last;
    }
  }
  $entity_type //= 'glass';
  $entity_id   //= '';

  my $pub_default = $opts{public_default} // 0;
  my $return_url  = $opts{return_url}     // "$c->{url}?o=$c->{op}";
  my $fid         = "photoform_${entity_type}_${entity_id}";
  my $pub_val     = $pub_default ? '1' : '0';

  my $s = '';
  # The trigger link directly clicks the hidden file input.
  $s .= "<span onclick='document.getElementById(\"${fid}_file\").click()' "
      . "style='cursor:pointer'>(Photo)</span>\n";
  # The form is invisible in the layout but present in the DOM.
  $s .= "<form id='${fid}_form' method='post' action='$c->{url}' "
      . "enctype='multipart/form-data' style='display:none'>\n";
  $s .= "  <input type='hidden' name='o' value='Photos' />\n";
  $s .= "  <input type='hidden' name='$entity_type' value='$entity_id' />\n";
  $s .= "  <input type='hidden' name='public' value='$pub_val' />\n";
  $s .= "  <input type='hidden' name='return_url' value='$return_url' />\n";
  $s .= "  <input type='file' id='${fid}_file' name='photo' "
      . "accept='image/*' capture='environment' />\n";
  $s .= "</form>\n";
  # Auto-submit as soon as a file is picked.
  $s .= qq{<script>
document.getElementById('${fid}_file').addEventListener('change', function() {
  if (this.files.length) { document.getElementById('${fid}_form').submit(); }
});
</script>
};
  return $s;
} # photo_form

################################################################################
# POST handler: save uploaded photo OR update/delete metadata.
sub post_photo {
  my $c = shift;

  my $photo_id   = util::param($c, 'photo_id')   || undef;
  # return_url contains '=' so must bypass util::param's character filter
  my $return_url = $c->{cgi}->param('return_url') || "$c->{url}?o=Photos";

  # --- Metadata edit / delete path ---
  if ($photo_id) {
    my $submit = util::param($c, 'submit') || '';

    if ( $submit =~ /Add Attachment/i ) {
      # Create a new photos row pointing to the same image file, different entity
      my $attach_type = util::param($c, 'attach_type') || '';
      my $attach_id;
      if ($attach_type eq 'brew') {
        $attach_id = util::param($c, 'Brew') || undef;
      } elsif ($attach_type eq 'location') {
        $attach_id = util::param($c, 'attach_location_id') || undef;
      } else {
        $attach_id = util::param($c, 'attach_person_id') || undef;
      }
      util::error("No entity selected for attachment") unless $attach_id;
      my $src = db::queryrecord($c, "SELECT * FROM photos WHERE Id = ?", $photo_id);
      util::error("Source photo $photo_id not found") unless $src;
      my $col = ucfirst($attach_type);
      db::execute($c,
        "INSERT INTO photos (Filename, $col, Uploader, Caption, Public, Ts) VALUES (?, ?, ?, ?, ?, CURRENT_TIMESTAMP)",
        $src->{Filename}, $attach_id, $src->{Uploader}, $src->{Caption}, $src->{Public});
      my $new_id = $c->{dbh}->last_insert_id("","","","");
      print { $c->{log} } "Added attachment: photo $new_id (copy of $photo_id) for $attach_type $attach_id\n";
      $c->{redirect_url} = "$c->{url}?o=Photos&e=$new_id";
      return;
    }

    if ( $submit =~ /Delete/i ) {
      # Fetch filename before deleting so we can clean up files if last record
      my $fname_row = db::queryrecord($c, "SELECT Filename FROM photos WHERE Id = ?", $photo_id);
      db::execute($c, "DELETE FROM photos WHERE Id = ?", $photo_id);
      print { $c->{log} } "Deleted photo id=$photo_id\n";
      # Remove physical image files only when no other record references this filename
      if ($fname_row && $fname_row->{Filename}) {
        my ($remaining) = db::queryarray($c, "SELECT COUNT(*) FROM photos WHERE Filename = ?", $fname_row->{Filename});
        if ($remaining == 0) {
          my $orig = imagefilename($c, $fname_row->{Filename}, 'orig');
          (my $base = $orig) =~ s/\+orig\.jpg$//;
          unlink $orig;
          my @scaled = glob("${base}+*w.jpg");
          unlink @scaled if @scaled;
          print { $c->{log} } "Deleted image files for '$fname_row->{Filename}'\n";
        } else {
          print { $c->{log} } "Photo '$fname_row->{Filename}' still has $remaining record(s), keeping files\n";
        }
      }
    } else {
      my $caption  = util::param($c, 'caption')  || undef;
      my $ispublic = util::param($c, 'public') ? 1 : 0;
      db::execute($c,
        "UPDATE photos SET Caption = ?, Public = ? WHERE Id = ?",
        $caption, $ispublic, $photo_id);
      print { $c->{log} } "Updated photo id=$photo_id\n";
    }
    $c->{redirect_url} = $return_url;
    return;
  }

  # --- New upload path ---
  my $caption  = util::param($c, 'caption') || undef;
  my $ispublic = util::param($c, 'public') ? 1 : 0;
  $return_url  = $c->{cgi}->param('return_url') || "$c->{url}?o=$c->{op}";

  # Determine which entity type/id was submitted
  my %entity_prefix = (glass=>'g', location=>'l', person=>'p', brew=>'b', comment=>'c');
  my ($entity_type, $entity_id);
  for my $t (qw(glass location person brew comment)) {
    my $val = util::param($c, $t) || undef;
    if ($val) { $entity_type = $t; $entity_id = $val; last; }
  }
  util::error("No entity id provided for photo upload") unless $entity_id;

  my $col    = ucfirst($entity_type);
  my $pfx    = $entity_prefix{$entity_type};
  my $uploader = $c->{username};

  # Use a human-readable timestamp for the filename
  my $ts        = strftime("%Y-%m-%d+%H:%M:%S", localtime);
  my $prefix    = "${pfx}-${entity_id}-${ts}";
  my $photoname = savefile($c, $prefix);
  util::error("Photo upload failed or no file was selected") unless $photoname;

  db::execute($c,
    "INSERT INTO photos (Filename, $col, Uploader, Caption, Public, Ts) VALUES (?, ?, ?, ?, ?, CURRENT_TIMESTAMP)",
    $photoname, $entity_id, $uploader, $caption, $ispublic);

  print { $c->{log} } "Inserted photo '$photoname' for $entity_type '$entity_id' uploader='" . ($uploader//"NULL") . "'\n";
  $c->{redirect_url} = $return_url;
} # post_photo

################################################################################
# GET: list all photos for the current user, newest first.
sub listphotos {
  my $c = shift;

  if ( $c->{edit} ) {
    editphoto($c);
    return;
  }

  print "<b>Photos for $c->{username}</b><br/>\n";

  my $sql = q{
    SELECT p.*
      FROM photos p
     WHERE ( p.Glass   IN (SELECT Id FROM glasses WHERE Username = ?)
          OR p.Comment IN (SELECT c.Id FROM comments c
                             JOIN glasses g ON g.Id = c.Glass
                            WHERE g.Username = ?)
          OR lower(p.Uploader) = lower(?) )
       AND ( lower(p.Uploader) = lower(?) OR p.Public = 1 )
     ORDER BY p.Ts DESC
  };
  my $sth = db::query($c, $sql, $c->{username}, $c->{username}, $c->{username}, $c->{username});

  my $count    = 0;
  my $cur_date = '';
  my $in_table = 0;
  while (my $p = $sth->fetchrow_hashref) {
    my $editurl = "$c->{url}?o=Photos&e=$p->{Id}";
    my $thumb = imagetag($c, $p->{Filename}, 'thumb', $editurl);
    next unless $thumb;  # skip if file missing

    my ($date) = split(' ', $p->{Ts});
    $date //= 'Unknown date';

    if ($date ne $cur_date) {
      print "</table>\n" if $in_table;
      print "<b>$date</b><br/>\n";
      print "<table style='border-collapse:collapse; margin-bottom:12px'>\n";
      $cur_date = $date;
      $in_table = 1;
    }

    my $attached = photo_attached_str($c, $p);
    my $cap = $p->{Caption}
      ? "<b>" . util::htmlesc($p->{Caption}) . "</b><br/>\n"
      : '';
    my $meta = "";
    $meta .= $cap;
    $meta .= "$attached<br/>\n" if $attached;
    $meta .= "<small>$p->{Ts} &mdash; $p->{Uploader}</small>\n";

    print qq{<tr valign='top'>
  <td style='padding:2px 8px 6px 0'>$thumb</td>
  <td style='padding:2px 0 6px 0'><small>$meta</small></td>
</tr>
};
    $count++;
  }
  print "</table>\n" if $in_table;
  print "<p>$count photo" . ($count == 1 ? '' : 's') . ".</p>\n";
} # listphotos

################################################################################
# Return an HTML string describing what a photo is attached to.
# Each entity on its own line (joined with <br/>).
sub photo_attached_str {
  my $c = shift;
  my $p = shift;  # photo record hashref

  my @attached;

  if ( $p->{Glass} ) {
    my $gid = $p->{Glass};
    my $glink = "<a href='$c->{url}?o=Full&e=$gid'><span>$gid</span></a>";
    my $row = db::queryrecord($c, q{
      SELECT l.Name  AS Loc,
             b.Name  AS Brew,
             pl.Name AS Producer
        FROM glasses g
        LEFT JOIN locations l  ON l.Id  = g.Location
        LEFT JOIN brews b      ON b.Id  = g.Brew
        LEFT JOIN locations pl ON pl.Id = b.ProducerLocation
       WHERE g.Id = ?
    }, $gid);
    if ($row) {
      my $s = "G[$glink]:";
      $s .= " <i>$row->{Producer}:</i>" if $row->{Producer};
      $s .= " <b>$row->{Brew}</b>"      if $row->{Brew};
      $s .= " \@<b>$row->{Loc}</b>"     if $row->{Loc};
      push @attached, $s;
    } else {
      push @attached, "G[$glink]";
    }
  }

  if ( $p->{Comment} ) {
    my $cid = $p->{Comment};
        my $row = db::queryrecord($c, q{
         SELECT c.Comment AS Txt,
          c.Glass   AS Gid,
          c.Rating  AS Rating,
          group_concat(p.Name, ', ') AS PersName,
          l.Name    AS Loc,
          b.Name    AS Brew,
          pl.Name   AS Producer
        FROM comments c
        LEFT JOIN comment_persons cp ON cp.Comment = c.Id
        LEFT JOIN persons p     ON p.Id = cp.Person
        LEFT JOIN glasses g    ON g.Id  = c.Glass
        LEFT JOIN locations l  ON l.Id  = g.Location
        LEFT JOIN brews b      ON b.Id  = g.Brew
        LEFT JOIN locations pl ON pl.Id = b.ProducerLocation
          WHERE c.Id = ?
          GROUP BY c.Id
        }, $cid);
    if ($row) {
      # only emit a comment line when there's something useful to show
      if ( defined $row->{Rating} || $row->{PersName} || $row->{Txt} ) {
        # make the comment id itself a link to the glass full view
        my $clink;
        if (defined $row->{Gid} && $row->{Gid} ne '') {
          $clink = "<a href='$c->{url}?o=Comment&e=$cid'>" .
                   "<span>$cid</span></a>";
        } else {
          $clink = $cid;
        }
        my $s = "C[$clink]:";
        $s .= " <i>$row->{Producer}:</i>" if $row->{Producer};
        $s .= " <b>$row->{Brew}</b>"      if $row->{Brew};
        $s .= " \@<b>$row->{Loc}</b>"     if $row->{Loc};
        # build rating/person/text string (no newline)
        my $txt = "";
        if ( defined $row->{Rating} && $row->{Rating} ne '' ) {
          $txt .= "(" . "<b>" . $row->{Rating} . "</b>" . ") ";
        }
        if ( $row->{PersName} ) {
          $txt .= "<b>" . util::htmlesc($row->{PersName}) . "</b>: ";
        }
        if ( $row->{Txt} ) {
          $txt .= util::htmlesc($row->{Txt});
        }
        $s .= "<br/>" . $txt if $txt;
        push @attached, $s;
      }
    } else {
      push @attached, "C[$cid]";
    }
  }

  if ( $p->{Location} ) {
    my $lid = $p->{Location};
    my $llink = "<a href='$c->{url}?o=Location&e=$lid'><span>$lid</span></a>";
    my $row = db::queryrecord($c, "SELECT Name, Description FROM locations WHERE Id = ?", $lid);
    if ($row) {
      my $s = "L[$llink]: <b>$row->{Name}</b>";
      $s .= " &mdash; " . util::htmlesc(substr($row->{Description}, 0, 80))
        if $row->{Description};
      push @attached, $s;
    } else {
      push @attached, "L[$llink]";
    }
  }

  if ( $p->{Person} ) {
    my $peid = $p->{Person};
    my $pelink = "<a href='$c->{url}?o=Person&e=$peid'><span>$peid</span></a>";
    my $row = db::queryrecord($c, "SELECT Name, Description FROM persons WHERE Id = ?", $peid);
    if ($row) {
      my $s = "P[$pelink]: <b>$row->{Name}</b>";
      $s .= " &mdash; " . util::htmlesc(substr($row->{Description}, 0, 80))
        if $row->{Description};
      push @attached, $s;
    } else {
      push @attached, "P[$pelink]";
    }
  }

  if ( $p->{Brew} ) {
    my $bid = $p->{Brew};
    my $blink = "<a href='$c->{url}?o=Brew&e=$bid'><span>$bid</span></a>";
    my $row = db::queryrecord($c, q{
      SELECT b.Name, b.Details, pl.Name AS Producer
        FROM brews b
        LEFT JOIN locations pl ON pl.Id = b.ProducerLocation
       WHERE b.Id = ?
    }, $bid);
    if ($row) {
      my $s = "B[$blink]:";
      $s .= " <i>$row->{Producer}:</i>" if $row->{Producer};
      $s .= " <b>$row->{Name}</b>";
      $s .= " &mdash; " . util::htmlesc(substr($row->{Details}, 0, 80))
        if $row->{Details};
      push @attached, $s;
    } else {
      push @attached, "B[$blink]";
    }
  }

  return join('<br/>', @attached);
} # photo_attached_str

################################################################################
# GET: edit form for a single photo record.
sub editphoto {
  my $c = shift;
  my $photo_id = $c->{edit};

  my ($p) = do {
    my $sth = db::query($c, "SELECT * FROM photos WHERE Id = ?", $photo_id);
    $sth->fetchrow_hashref;
  };
  util::error("Photo $photo_id not found") unless $p;
  util::error("Photo $photo_id is not visible to you")
    unless $p->{Public} || lc($p->{Uploader}) eq lc($c->{username});

  my $return_url  = "$c->{url}?o=Photos";
  my $caption     = util::htmlesc($p->{Caption} // '');
  my $pub_checked = $p->{Public}  ? ' checked' : '';

  # Entity summary — fetch human-readable details for each attached entity
  my $attached_str = photo_attached_str($c, $p) || 'none';

  # Fetch sibling records (same filename, different Id)
  my $sib_sth = db::query($c,
    "SELECT * FROM photos WHERE Filename = ? AND Id != ? ORDER BY Id",
    $p->{Filename}, $photo_id);
  my @siblings;
  while (my $s = $sib_sth->fetchrow_hashref) {
    push @siblings, $s;
  }

  print qq{<b>Edit Photo $photo_id</b><br/>
<form method='post' action='$c->{url}'>
  <input type='hidden' name='o'          value='Photos' />
  <input type='hidden' name='photo_id'   value='$photo_id' />
  <input type='hidden' name='return_url' value='$return_url' />
  <table>
    <tr><td><small>Attached</small></td>
        <td><small>$attached_str</small></td></tr>
    <tr><td><small>Uploaded</small></td>
        <td><small>$p->{Ts} by $p->{Uploader}</small></td></tr>
    <tr><td><small>Caption</small></td>
        <td><input type='text' name='caption' value='$caption' size='20' /></td></tr>
    <tr><td><small>Public</small></td>
        <td><input type='checkbox' name='public' value='1'$pub_checked /></td></tr>
    <tr><td colspan='2'>
          <input type='submit' name='submit' value='Update Photo' />
          &nbsp;
          <input type='submit' name='submit' value='Delete Photo'
            onclick='return confirm("Delete this photo?")' />
          &nbsp;
          <a href='$return_url'><span>(Back to list)</span></a>
        </td></tr>
  </table>
</form>
};

  # Siblings section
  if (@siblings) {
    print "<hr/>\n";
    for my $s (@siblings) {
      my $sib_str = photo_attached_str($c, $s) || 'unknown';
      my $sib_url = "$c->{url}?o=Photos&e=$s->{Id}";
      print "<small><span><a href='$sib_url'><span>Also</span></a> $sib_str</span></small><br/>\n";
    }
  }

  # Collapsed "Also attach to" form
  my $pid = $photo_id; # for readability in the heredoc
  my $person_sel   = persons::selectperson($c, 'attach_person_id', '', '', '', 0);
  my $location_sel = locations::selectlocation($c, 'attach_location_id', '', '', 0, 0);
  my $brew_sel     = brews::selectbrew($c, '', '');

  print qq{<details style='margin-top:6px'>
<summary style='cursor:pointer'>Also attach to&hellip;</summary>
<form method='post' action='$c->{url}' style='margin-top:4px'>
  <input type='hidden' name='o'          value='Photos' />
  <input type='hidden' name='photo_id'   value='$pid' />
  <input type='hidden' name='return_url' value='$return_url' />
  Type: <select name='attach_type' id='atype_$pid'
    onchange='atype_change_$pid(this.value)'>
    <option value='person'>Person</option>
    <option value='location'>Location</option>
    <option value='brew'>Brew</option>
  </select><br/>
  <div id='atype_person_$pid'>$person_sel</div>
  <div id='atype_location_$pid' style='display:none'>$location_sel</div>
  <div id='atype_brew_$pid' style='display:none'>$brew_sel</div>
  <input type='submit' name='submit' value='Add Attachment' />
</form>
</details>
<script>
function atype_change_$pid(v) {
  ['person','location','brew'].forEach(function(t) {
    document.getElementById('atype_' + t + '_$pid').style.display = (t === v) ? '' : 'none';
  });
}
</script>
<hr/>
};

  # Full-size image below the form — opens in a new tab when clicked
  my $orig = imagefilename($c, $p->{Filename}, 'orig');
  if (-r $orig) {
    print "<a href='$orig' target='_blank'><img src='$orig' "
        . "style='max-width:100%; max-height:80vh; cursor:pointer' /></a>\n";
  } else {
    print "<p><i>Image file not found: $orig</i></p>\n";
  }
} # editphoto

################################################################################
# Report module loaded ok
1;
