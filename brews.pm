# Part of my beertracker
# Stuff for listing, selecting, adding, and editing brews

# TODO - Edit a brew, maybe insert a new

package brews;
use strict;
use warnings;

# Formatting magic
my $clr = "Onfocus='value=value.trim();select();' autocapitalize='words'";


################################################################################
# List of brews
################################################################################
# TODO - More display fields. Country, region, etc
# TODO - Filtering by brew type, subtype, name, producer, etc
sub listbrews {
  my $c = shift; # context
  print util::listsmenu($c);
  print util::showmenu($c);
  print "<hr/>";

  if ( $c->{edit} =~ /^\d+$/ ) {  # Id for full info
    #editbrew($c);  # TODO
    return;
  }

  # Sort order or filtering
  my $sort = "last DESC";
  $sort = "BREWS.Id" if ( $c->{sort} eq "id" );
  $sort = "BREWS.Name" if ( $c->{sort} eq "name" );
  $sort = "BREWS.Producer" if ( $c->{sort} eq "maker" );
  $sort = "BREWS.BrewType, BREWS.Subtype COLLATE NOCASE" if ( $c->{sort} eq "type" );
  $sort = "last DESC" if ( $c->{sort} eq "last" );
  $sort = "LOCATIONS.Name" if ( $c->{sort} eq "where" );

  # Print list of people
  my $sql = "
  select
    BREWS.Id,
    BREWS.Name,
    BREWS.Producer,
    BREWS.BrewType,
    BREWS.Subtype,
    strftime ( '%Y-%m-%d %w', max(GLASSES.Timestamp), '-06:00' ) as last,
    LOCATIONS.Name as loc,
    count(COMMENTS.Id) as count
  from BREWS
  left join GLASSES on Glasses.Brew = BREWS.Id
  left join COMMENTS on COMMENTS.Glass = GLASSES.Id
  left join LOCATIONS on LOCATIONS.id = GLASSES.Location
  group by BREWS.id
  order by $sort
  ";
  my $list_sth = $c->{dbh}->prepare($sql);
  #$list_sth->execute($c->{username});
  $list_sth->execute();

  print "<table><tr>\n";
  my $url = $c->{url};
  my $op = $c->{op};
  my $maxwidth = "style='max-width:20em;'";
  print "<td><a href='$url?o=$op&s=id'><i>Id</i></a></td>";
  print "<td><a href='$url?o=$op&s=name'><i>Name</i></a></td>";
  print "<td><a href='$url?o=$op&s=maker'><i>Producer</i></a></td>";
  print "<td><a href='$url?o=$op&s=type'><i>Type</i></a></td>";
  print "<td colspan=2 ><a href='$url?o=$op&s=last'><i>Last seen</i></a></td>";
  print "<td><a href='$url?o=$op&s=where'><i>Where</i></a></td></tr>";
  while ( my ($id, $name, $maker, $typ, $sub, $last, $loc, $count) = $list_sth->fetchrow_array ) {
    $loc = "" unless ($loc);
    my ($stamp, $wd) = util::splitdate($last);

    print "<tr><td style='font-size: xx-small' align='right'>$id</td>\n";
    print "<td $maxwidth><a href='$url?o=$op&e=$id'><b>$name</b></a>";
    print " ($count) " if ( $count > 1 );
    print "<td $maxwidth>$maker</td>";
    print "</td>\n";
    print "<td>$typ, $sub </td>\n";
    print "<td>$wd</td>\n";
    print "<td>" . main::filt($stamp,"","","full") . "</td>\n";
    print "<td>$loc</td></tr>\n";
  }
  print "</table>\n";
  print "<hr/>\n" ;
} # listbrews


################################################################################
# Select a brew
# A key component of the main input form
################################################################################
# TODO - Many features missing
# TODO - Display the brew details under the selection
# TODO - Add an option to filter: Show filter field, redo the list on every change
# TODO - remember the selected value on start, and try re-establish it when changing
#        the brew style. That way, we can change from beer to wine, get an empty
#        default selection, and switch back to beer, and get the old value back.
# TODO - Use the saved value to link to the page editing the brew
# TODO - Make a helper to shorten producer names, maybe for each type

sub selectbrew {
  my $c = shift; # context
  my $selected = shift || "";  # The id of the selected brew
  my $brewtype = shift || "";
  my $s = "";
  $s .= "<div id='newbrewdiv' hidden>";
  $s .= "<input name='newbrewname' placeholder='New Name' $clr /><br/>\n";
  $s .= "<input name='newbrewstyle' placeholder='Style' $clr /><br/>\n";
  $s .= "<input name='newbrewsub' placeholder='SubType' $clr /><br/>\n";
  $s .= "<input name='newbrewproducer' width placeholder='Producer' $clr /><br/>\n";
  $s .= "<input name='newalc'  placeholder='Alc' onInput='updalc(this.value);' $clr /><br/>\n";
  $s .= "<input name='newbrewcountry' width placeholder='Country' $clr /><br/>\n";
  $s .= "<input name='newbrewregion' width placeholder='Region' $clr /><br/>\n";
  $s .= "<input name='newbrewflavor' width placeholder='Flavor' $clr /><br/>\n";
  $s .= "<input name='newbrewyear' width placeholder='Year' $clr /><br/>\n";
  $s .= "<input name='newbrewdetails' width placeholder='Details' $clr /><br/>\n";
  $s .= "</div>";
  $s .= "<select name='brewsel' id='brewsel' onchange='brewselchange();' style='width: 15em'>\n";
  $s .= "</select>\n";  # Options will be filled in populatebrews() js func below
  $s .= << "scriptend";
    <script>
      function brewselchange() {
        var sel = document.getElementById("brewsel");
        var inp = document.getElementById("newbrewdiv");
        if ( sel.value == "new" ) {
          sel.hidden = true;
          inp.hidden = false;
        }
        updalc(sel.options[ sel.selectedIndex ].alc );
      }

    function updalc(a) {
      var alc = document.getElementById("alc");
      if (alc && a ) {
        alc.value = a;
      }
    }
    const brews = [
scriptend
  my $sql = "
  select
    BREWS.Id, BREWS.Brewtype, BREWS.SubType, Name, Producer, BREWS.Alc
  from BREWS
  left join GLASSES on GLASSES.Brew= BREWS.ID
  group by BREWS.id
  order by GLASSES.Timestamp DESC ";
  #$sql .= "LIMIT 400" ; # Saves some time, but looses older records. Ok for beer, not the rest
  #  strftime ( '%Y-%m-%d %w', max(GLASSES.Timestamp), '-06:00' ) as last
  my $list_sth = $c->{dbh}->prepare($sql);
  $list_sth->execute(); # username ?
  while ( my ($id, $bt, $su, $na, $pr, $alc )  = $list_sth->fetchrow_array ) {
    my $disp = "";
    $disp .= $na if ($na);
    $disp = "$pr: $disp  " if ($pr && $na !~ /$pr/ ); # TODO Shorten producer names
    my $disptype = $su;
    $disptype .= $bt unless ($su);
    $disp .= " [$disptype]";
    $disp = substr($disp, 0, 30);
    $s .= "  { Id: '$id', BrewType: '$bt',  Disp: '$disp', Alc: '$alc' },\n";
  }

  $s .= << "scriptend";
    ];

    function populatebrews(typ, selected) {
        var sel = document.getElementById("brewsel");
        sel.innerHTML = "";
        if ( typ == "Restaurant" || typ == "Night" ) {
          sel.hidden = true;
          var avp = document.getElementById("avp");  /* alc-vol-pr */
          if ( avp )
            avp.hidden = true;
        } else {
          var inp = document.getElementById("newbrewdiv");
          inp.hidden = true;
          sel.hidden = false;
          sel.add( new Option( "(select)", "", true ) );
          sel.add( new Option( "(new)", "new" ) );
          var n = 0;
          for ( let i=0; i<brews.length; i++) {
            var b = brews[i];
            if ( b.BrewType == typ ) {
              var found = (selected == b.Id);
              var op = new Option( b.Disp , b.Id, found, found)
              op.arrayindex = i;
              op.alc = b.Alc;
              sel.add( op );
              n++;
              if ( n > 200 )
                return;
            }
          }
        }
      }
    </script>
    <script defer>
    populatebrews("$brewtype", "$selected");
    </script>
scriptend
    # The 'defer' in the script tag makes it execute after parsing the page,
    # which eliminates a visible stop at rendering the select. Declaring the
    # function is not deferred, so that it will be available.
  return $s;
} # selectbrew

################################################################################
# Update a brew, posted from the form in the selection above
################################################################################
# TODO - Calculate subtype, if not set. Make a separate helper, use in import
sub postbrew {
  my $c = shift; # context
  my $id = shift || $c->{edit};
  if ( $id eq "new" ) {
    my $name = util::param($c, "newbrewname");
    util::error ("A brew must have a name" ) unless $name;
    util::error ("A brew must have a type" ) unless util::param($c, "selbrewtype");
    my $sql = "insert into BREWS
       ( Name, BrewType, SubType,
         BrewStyle, Producer, Alc,
         Country, Region, Flavor, Year, Details )
       values ( ?, ?, ?,  ?, ?, ?,  ?, ?, ?, ?, ? ) ";
    my $sth = $c->{dbh}->prepare($sql);
    $sth->execute(
      $name,
      util::param($c,"selbrewtype"),
      util::param($c,"newbrewsub"),
      util::param($c,"newbrewstyle"),
      util::param($c,"newbrewproducer"),
      util::param($c,"newalc"),
      util::param($c,"newbrewcountry"),
      util::param($c,"newbrewregion"),
      util::param($c,"newbrewflavor"),
      util::param($c,"newbrewyear"),
      util::param($c,"newbrewdetails")
    );
    $id = $c->{dbh}->last_insert_id(undef, undef, "BREWS", undef) || undef;
    print STDERR "Inserted Brew id '$id' '$name' \n";
  } else {
    # TODO - This is still as stolen from Locations. Fix for brews. Make also an edit form
    my $name = $c->{cgi}->param("name");
    main::error ("A Location must have a name" )
      unless $name;
    my $off= $c->{cgi}->param("off") || "" ;
    my $desc= $c->{cgi}->param("desc") || "" ;
    my $geo= $c->{cgi}->param("geo") || "" ;
    my $web= $c->{cgi}->param("web") || "" ;
    my $phone=  $c->{cgi}->param("phone") || "";
    my $addr= $c->{cgi}->param("addr") || "" ;
    my $zip= $c->{cgi}->param("zip") || "" ;
    my $country= $c->{cgi}->param("country") || "" ;
    main::error ("Bad id for updating a brew '$id' ")
      unless $id =~ /^\d+$/;
    my $sql = "
      update LOCATIONS
        set
          Name = ?,
          OfficialName = ?,
          Description = ?,
          GeoCoordinates = ?,
          Website = ?,
          Phone = ?,
          StreetAddress = ?,
          PostalCode = ?,
          Country = ?
      where id = ? ";
    my $sth = $c->{dbh}->prepare($sql);
    $sth->execute( $name, $off, $desc, $geo, $web, $phone, $addr, $zip, $country, $id );
    print STDERR "Updated " . $sth->rows .
      " Location records for id '$id' : '$name' \n";
  }
  return $id;
  #print $c->{cgi}->redirect( "$c->{url}?o=$c->{op}&e=$c->{edit}" );
} # postbrew

################################################################################
# Helper to get a brew record
################################################################################
sub getbrew {
  my $c = shift;
  my $id = shift;
  return undef unless ($id);
  my $sql = "select * from BREWS where id = ? ";
  my $sth = $c->{dbh}->prepare($sql);
  $sth->execute($id);
  my $brew = $sth->fetchrow_hashref;
  return $brew;
}

################################################################################
# Report module loaded ok
1;
