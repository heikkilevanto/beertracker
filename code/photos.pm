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


# TODO - Not really used yet

# Default image sizes (width in pixels)
my %imagesizes;
$imagesizes{"thumb"} = 90;
$imagesizes{"mob"} = 240;  # 320 is full width on my phone
$imagesizes{"pc"} = 640;


# TODO - This should not be hard coded
# TODO - Pass $c to all subs, etc
#
my $photodir = "beerdata/photo";

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
    print STDERR "Photo file '$orig' not found \n";
    return "";
  }
  my $fn = imagefilename($c,$photo, $width);
  return "" unless $fn;
  if ( ! -r $fn ) { # Need to resize it
    my $size = $imagesizes{$width};
    $size = $size . "x". $size .">";
    print STDERR "convert $orig -resize '$size' $fn \n";
    my $conv = `convert $orig -resize '$size' $fn`;
    my $rc = $?;
    chomp($conv);
    print STDERR "Resize failed with $rc: '$conv' \n" if ( $conv );
  }
  my $w    = $imagesizes{$width};
  my $href = $link_url || $orig;
  my $tgt  = $link_url ? "" : " target='_blank'";
  my $itag = "<img src='$fn' width='$w' style='vertical-align:top' />";
  my $tag  = "<a href='$href'$tgt style='margin-right:6px; display:inline-block'>$itag</a>\n";
  return $tag;
} # imagetag


# Map entity type to the corresponding photos table column
my %entity_col = (
  comment  => 'Comment',
  glass    => 'Glass',
  location => 'Location',
  person   => 'Person',
  brew     => 'Brew',
);

# Return a list of photo records for a given entity.
# Usage: get_photos($c, 'comment', $comment_id)
sub get_photos {
  my $c    = shift;
  my $type = shift; # entity type: comment, glass, location, person, brew
  my $id   = shift;
  return () unless defined($id) && $id ne '';
  my $col = $entity_col{lc($type)};
  unless ($col) {
    print STDERR "get_photos: unknown entity type '$type'\n";
    return ();
  }
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
sub thumbnails_html {
  my $c    = shift;
  my $type = shift;
  my $id   = shift;
  return '' unless defined($id) && $id ne '';
  my @photos = get_photos($c, $type, $id);
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
  print STDERR "Saving image '$dbname' into '$filename' \n";

  util::error("FIle '$dbname' already exists, will not overwrite")
    if ( -e $filename );
  my $filehandle = $q->upload('photo');
  if ( ! $filehandle ) {
    print STDERR "No upload filehandle in photos::savefile\n";
    return "";
  }
  my $tmpfilename = $q->tmpFileName( $filehandle );
  my $convcmd = "/usr/bin/convert $tmpfilename -auto-orient -strip $filename 2>&1";
  print STDERR "About to run: $convcmd \n";
  my $conv = `$convcmd` ;
    # -auto-orient turns them upside up. -strip removes the orientation, so
    # they don't get turned again when displaying.
  my $rc = $?;
  print STDERR "Conv returned '$rc' and '$conv' \n" if ($rc || $conv); # Can this happen
  my $fsz = -s $filename;
  print STDERR "Uploaded $fsz bytes into '$filename' \n";
  return $dbname; # The name without width-specs
}# savefile


################################################################################
# Collapsible (photo) upload widget. Returns an HTML string.
# Clicking "(photo)" immediately triggers the file picker / camera.
# Once a file is chosen the form auto-submits — no extra button needed.
# Options (as key=>value pairs):
#   glass          => $id   (required)
#   public_default => 0|1   (default 0)
#   return_url     => $url  (where to redirect after upload)
sub photo_form {
  my $c    = shift;
  my %opts = @_;
  my $glassid     = $opts{glass}          // '';
  my $pub_default = $opts{public_default} // 0;
  my $return_url  = $opts{return_url}     // "$c->{url}?o=$c->{op}";
  my $fid         = "photoform_g${glassid}";
  my $pub_val     = $pub_default ? '1' : '0';

  my $s = '';
  # The trigger link directly clicks the hidden file input.
  $s .= "<span onclick='document.getElementById(\"${fid}_file\").click()' "
      . "style='cursor:pointer'>(Photo)</span>\n";
  # The form is invisible in the layout but present in the DOM.
  $s .= "<form id='${fid}_form' method='post' action='$c->{url}' "
      . "enctype='multipart/form-data' style='display:none'>\n";
  $s .= "  <input type='hidden' name='o' value='Photos' />\n";
  $s .= "  <input type='hidden' name='glass' value='$glassid' />\n";
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
    if ( util::param($c, 'submit') =~ /Delete/i ) {
      db::execute($c, "DELETE FROM photos WHERE Id = ?", $photo_id);
      print STDERR "Deleted photo id=$photo_id\n";
    } else {
      my $caption  = util::param($c, 'caption')  || undef;
      my $ispublic = util::param($c, 'public') ? 1 : 0;
      db::execute($c,
        "UPDATE photos SET Caption = ?, Public = ? WHERE Id = ?",
        $caption, $ispublic, $photo_id);
      print STDERR "Updated photo id=$photo_id\n";
    }
    $c->{redirect_url} = $return_url;
    return;
  }

  # --- New upload path ---
  my $glassid  = util::param($c, 'glass') || undef;
  my $caption  = util::param($c, 'caption') || undef;
  my $ispublic = util::param($c, 'public') ? 1 : 0;
  $return_url  = $c->{cgi}->param('return_url') || "$c->{url}?o=$c->{op}";

  util::error("No glass id provided for photo upload") unless $glassid;

  # Resolve uploader: look up person id by username
  my ($uploader) = $c->{dbh}->selectrow_array(
    "SELECT Id FROM persons WHERE lower(Name) = lower(?)", undef, $c->{username});

  # Use a human-readable timestamp for the filename
  my $ts        = strftime("%Y-%m-%d+%H:%M:%S", localtime);
  my $prefix    = "g-${glassid}-${ts}";
  my $photoname = savefile($c, $prefix);
  util::error("Photo upload failed or no file was selected") unless $photoname;

  db::execute($c,
    "INSERT INTO photos (Filename, Glass, Uploader, Caption, Public, Ts) VALUES (?, ?, ?, ?, ?, CURRENT_TIMESTAMP)",
    $photoname, $glassid, $uploader, $caption, $ispublic);

  print STDERR "Inserted photo '$photoname' for glass '$glassid' uploader='" . ($uploader//"NULL") . "'\n";
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
     WHERE p.Glass   IN (SELECT Id FROM glasses WHERE Username = ?)
        OR p.Comment IN (SELECT c.Id FROM comments c
                           JOIN glasses g ON g.Id = c.Glass
                          WHERE g.Username = ?)
        OR p.Uploader = (SELECT Id FROM persons WHERE lower(Name) = lower(?))
     ORDER BY p.Ts DESC
  };
  my $sth = db::query($c, $sql, $c->{username}, $c->{username}, $c->{username});

  my $count    = 0;
  my $cur_date = '';
  my $in_div   = 0;
  while (my $p = $sth->fetchrow_hashref) {
    my $editurl = "$c->{url}?o=Photos&e=$p->{Id}";
    my $thumb = imagetag($c, $p->{Filename}, 'thumb', $editurl);
    next unless $thumb;  # skip if file missing

    # Extract date part from Ts (e.g. "2026-02-21 15:54:12" -> "2026-02-21")
    my ($date) = split(' ', $p->{Ts});
    $date //= 'Unknown date';

    if ($date ne $cur_date) {
      print "</div>\n" if $in_div;
      print "<b>$date</b><br/>\n";
      print "<div style='display:flex; flex-wrap:wrap; gap:8px; margin-bottom:12px'>\n";
      $cur_date = $date;
      $in_div   = 1;
    }

    my $cap = $p->{Caption} ? "<br/><small>" . util::htmlesc($p->{Caption}) . "</small>" : '';
    print "<div style='text-align:center'>$thumb$cap</div>\n";
    $count++;
  }
  print "</div>\n" if $in_div;
  print "<p>$count photo" . ($count == 1 ? '' : 's') . ".</p>\n";
} # listphotos

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

  my $return_url  = "$c->{url}?o=Photos";
  my $caption     = $p->{Caption} // '';
  my $pub_checked = $p->{Public}  ? ' checked' : '';

  # Entity summary line
  my @attached;
  push @attached, "Glass $p->{Glass}"     if $p->{Glass};
  push @attached, "Comment $p->{Comment}" if $p->{Comment};
  push @attached, "Location $p->{Location}" if $p->{Location};
  push @attached, "Person $p->{Person}"   if $p->{Person};
  push @attached, "Brew $p->{Brew}"       if $p->{Brew};
  my $attached_str = @attached ? join(', ', @attached) : 'none';

  print qq{<b>Edit Photo $photo_id</b> &nbsp;
<a href='$return_url'><span>(Back to list)</span></a><br/>
<small>Attached to: $attached_str &nbsp; Uploaded: $p->{Ts}</small><br/>
<form method='post' action='$c->{url}'>
  <input type='hidden' name='o'          value='Photos' />
  <input type='hidden' name='photo_id'   value='$photo_id' />
  <input type='hidden' name='return_url' value='$return_url' />
  <label>Caption: <input type='text' name='caption' value='$caption' size='40' /></label><br/>
  <label><input type='checkbox' name='public' value='1'$pub_checked /> Public</label><br/>
  <input type='submit' name='submit' value='Update Photo' />
  &nbsp;
  <input type='submit' name='submit' value='Delete Photo'
    onclick='return confirm("Delete this photo?")' />
</form>
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
