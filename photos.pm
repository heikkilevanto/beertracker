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
  my $fn = shift; # The raw file name
  my $width = shift; # How wide we want it, or "orig" or ""
  $fn =~ s/(\.?\+?orig)?\.jpe?g$//i; # drop extension if any
  return $fn if (!$width); # empty width for saving the clean filename in $rec
  $fn = "$photodir/$fn"; # a real filename
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
sub image {
  my $rec = shift;
  my $width = shift; # One of the keys in %imagesizes
  return "" unless ( $rec->{photo} && $rec->{photo} =~ /^2/);
  my $orig = imagefilename($rec->{photo}, "orig");
  if ( ! -r $orig ) {
    print STDERR "Photo file '$orig' not found for record $rec->{stamp} \n";
    return "";
  }
  my $fn = imagefilename($rec->{photo}, $width);
  return "" unless $fn;
  if ( ! -r $fn ) { # Need to resize it
    my $size = $imagesizes{$width};
    $size = $size . "x". $size .">";
    system ("convert $orig -resize '$size' $fn");
    print STDERR "convert $orig -resize '$size' $fn \n";
  }
  my $w = $imagesizes{$width};
  my $itag = "<img src='$fn' width='$w' />";
  my $tag = "<a href='$orig'>$itag</a>";
  return $tag;
} # image


sub savefile {
  my $c = shift;
  my $cid = shift; # comment id, for the file name
  my $fn = "c-$cid";
  $fn =~ s/ /+/; # Remove spaces
  my $serial = "0";
  my $savefile;
  do {
    $serial++;
    $savefile = "$c->{photodir}/$fn-$serial.jpg";
    print STDERR "Looking to save in '$savefile' \n";
  }  while ( -e $savefile ) ;
  my $storename = imagefilename($fn,"");  # To be saved in the db
  my $filehandle = $q->upload('photo');
  if ( ! $filehandle ) {
    print STDERR "No upload filehandle in photos::savefile\n";
    return "";
  }
  my $tmpfilename = $q->tmpFileName( $filehandle );
  my $conv = `/usr/bin/convert $tmpfilename -auto-orient -strip $savefile 2>&1`;
    # -auto-orient turns them upside up. -strip removes the orientation, so
    # they don't get turned again when displaying.
  my $rc = $?;
  print STDERR "Conv returned '$rc' and '$conv' \n" if ($rc || $conv); # Can this happen
  my $fsz = -s $savefile;
  print STDERR "Uploaded $fsz bytes into '$savefile' \n";
  return $savefile; # The name without width-specs
}# savefile


################################################################################
# Report module loaded ok
1;
