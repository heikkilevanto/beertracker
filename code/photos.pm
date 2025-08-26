# Part of my beertracker
# Routines for managing photos

package photos;
use strict;
use warnings;
use feature 'unicode_strings';
use utf8;  # Source code and string literals are utf-8

use CGI qw( -utf8 );
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
  my $c = shift;
  my $photo = shift;  # The name, as in the db
  my $width = shift || "thumb" ; # One of the keys in %imagesizes
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
  my $w = $imagesizes{$width};
  my $itag = "<img src='$fn' width='$w />";
  my $tag = "<a href='$orig' target='_blank'>$itag</a>";
  return $tag;
} # image


# Save the uploaded image in a file
sub savefile {
  my $c = shift;
  my $cid = shift; # comment id, for the file name

  my $storename = "c-$cid";
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
# Report module loaded ok
1;
