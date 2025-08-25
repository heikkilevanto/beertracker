# Heikki's Beer Tracker

## Overview
This is a simple script to track the beers I drink. I also use it for other
purposes, like remembering restaurants, tracking wines and booze, and displaying
nice graphs.

## WARNING - This manual is badly out of date, and needs an almost complete rewrite

---

## Getting started
When you start, the database is empty. You need to enter all details on the first
beers. Your browser will remember some of those values and suggest them to you.
If you leave values empty, the program will try to make a guess from your history.
This only works if you spell the beer name the same way, so be correct there.
It is handy for picking up the strength and price of beer, etc.

The system is optimized for filing things as you drink, but you can enter data
after the fact. In that case, click on the little ^ to get more fields visible,
and put in the date and time in the two first input fields, as YYYY-MM-DD HH:MM

Most of the time, if you have drunk that beer before, it is easy to find the beer
in the list, and just click on the `copy` buttons. They come in predefined sizes of
25 and 40 cl, and if you drank some other quantity, that gets a copy button too.

On the beer list, almost every word is a link to filter the list. If you click on
the brewery name, the list shows only beers from that brewery. Same for location,
etc. You can also filter only those entries that have ratings on them, or comments.
This is good if you want to look up a beer before buying.

There are dedicated lists for beers, breweries, locations, etc. Those can be
selected from the "show" pull-down in the input form.

---

## Input fields
The first part of the screen is the input area, where you can enter what beers
you drink. Most of the fields start with default values. When you click on one,
the whole field gets selected, so if you start typing, the old value disappears.

The first four input fields are normally not visible. There is a little
up-arrow on first visible line, clicking on that will show the fields.

### Date
Usually you can leave this empty, the system defaults to the current date. If
you want to enter data after the fact, you can put the actual date here, as
YYYY-MM-DD. There are two shortcuts: 'L' is the same date as the latest entry,
and 'Y' for yesterday.

### Time
Here you can enter the time when you drank the beer. It accepts some common
formats, like 23:55 1am 1pm 2335 etc. If you leave it emtpy, as you usually
should, it takes the system time. Since drinking often continues past midnight,
the system counts times up to 08 next morning as belonging to the day before.

### Geo Coordinates
Automagically filled in by the browser, these show your current location. If
you don't want the system to use the location, put a simple X in there. Otherwise
it will try to autofill it again.

### Record type
This is a pull-down for changing the type of the record. At the moment we have
Beer, Wine, Booze, and also Restaurant and Night.

### Location
Where you had your beer. Used for various lists. Guesses from the geo coordinates
when possible. That failing, defaults to the same location as the previous beer.

### Subtype
Most often used for wines, this could take values like Red or White. For beers
the system can automatically fill in the country where the beer comes from.

You can also enter the whole record type here, for example "Wine, Red".

The subtype is preceded by the record type, so you can see it without flipping
the hidden lines.

### Style
The style of the beer. There are no predefined styles, you will have to enter
them the way you like to classify your beers. Used for various lists. The system
tries to copy the style from an earlier entry of the same name. The field can
also be used for the style of restaurants, booze, or wine.

### Maker
Who made the beer (or wine or...). Again, if you have had the beer before (and
spelled if the same way), the system will reuse the brewery name.

### Name
The name of the beer (or wine, or whatever).

### Volume
How much did you have. Defaults to centiliters, but there are several predefined
sizes (which you can see on the 'About' page), for example 'HB' means half a
wine bottle, 37 cl. If you are in the US, you can enter the volume in ounces,
'12 oz' gets translated to 36cl. Defaults to 'L', which is a (Danish) large
beer, 40 cl, or which ever size you had the same beer previously.

### Alc
Alcohol percentage, probably by volume. Used in calculating "standard drinks"
according to the Danish system, where a 33cl bottle of 4.6% pilsner counts as
one "standard" drink. Again, the system tries to reuse the value from an earlier
entry if you have had the same beer before.

### Price
What did you pay for the beer. Used for statistics. It is just a number, so you
can assume it is in your local currency. But for us who live in Denmark, there
are some shortcuts, you can add 'EUR' or 'USD' to the end of the amount, and
the system will convert to DKK using some fixed rates. (Sorry, the € and $
symbols don't work. Maybe some day)

### Rate
A pull-down menu where you can choose how well you liked the beer, on a scale
from "0 - Undrinkable" to "10 - I'm in love". Later you can see how you liked
different beers, so you can choose one you like.

### Comments
Here you can write any descriptions or comments about the beer. These are shown
in the full list.

Before you type anything in the box, it is showing three lines of statistics:
* How many "standard" drinks you have had today, and how much you paid for them.
If you didn't have any today, it shows the weekday when you last had, and the
values for that date.
* Same for the last week, up to and including today. Also shows the average
"standard" drinks per day, and how many days without any.
* Same for the calendar month.

### Record Button
This button enters the beed into the system. it also fills some of the input
fields for the next one, assuming that you might have one more of the same
kind.

### Save Button
Updates the current record. Usually the last beer you enterd. Useful if you want
to correct the price, or add a rating or a comment. You can edit older entries
by clicking on the "Edit" link next to them.

### Clr Button
Clears all input fields, in case you want to enter something completely different.

### Show pull-down
This is the main menu, where you can choose what to show under the input form.
See below.

### Quick link
There is a simple "G" that is a quick link to showing the graph (see below).
When the graph is shown, the link changes to "B" to show the beer board of the
current location, or if not known, of my favourite place, Ølbaren.

---

## Editing
The input form is also used for editing old records. In that case there are
a few small differences:
* At the top there is a text telling which record you are editing. The records
are identified by their timestamps.
* The regular input fields are as before, but filled in with the values from
the record.
* There is a 'Del' button for deleting the record, and a 'Cancel' link to get
out of the edit mode.
* There is no 'Record' button, you should use the 'Save' button to save your
changes to that record.

---

## The main menu
The "Show" menu allows you to choose what gets shown under the input form.

### Full list
It shows a list of beers you have had, most recent first. There are many ways
to filter that list.

At the top of the list are some links to filter the list:
* Ratings - Shows only the beer entries where you have filled in a rating
* Comments - Shows only the beers that you have commented on
There is also a link to show Extra Info for each beer. Ratings, when last seen,
and such.

The list itself is divided into days, and those can be divided into locations,
if you have been drinking at different places.

The first line of each beer has the time, brewery, and name of the beer. These
can be marked with 'new' if it looks like it is the first time you enter such.
That is useful for catching spelling errors. The brewery and beer names are links
that cause the list to be filtered so that only that beer or brewery is shown.
That makes it easier to see what you have thought about the beer, or what else
the brewery has made.

Next comes a number of small facts about the beer. They are on a line of their
own when seen on a phone, or appended to the first line on a wider computer
screen.
* Style. This is solor-coded to match the graph (see below). It is also a link
to filter the list by this style.
* Price
* Volume
* Alc
* "Standard drinks"
* Blood alc (only if showing Extra Info). This is a rough estimate, based on
some formulas I found on the net, and my own body weight.

The next line has the rating you have given the beer, and comments, if you
entered any.

If you asked to show Extra Info, it will be on the next lines. These include
how many times the system has seen the beer, how many ratings we have for it,
and the average of them, as well as the geo location for that entry (mostly
for debugging the geo stuff)

The last line has a link for editing the entry - that puts all the values in
the input fileds above, where you can correct mistakes. (See above.)
That line also has a few "Copy" buttons, defaulting to most likely sizes you
might drink again. You can click those buttons on any beer entry, and the system
will create a new entry for todays date and time, with that amount of that beer.
That is by far the easiest way to enter data.

At the end of each day or location there will be summaries on how much you have
drank there.

### Graph
Shows a graph of your drinking. Time is on the X-axis, with different background
color for weekend (Fri, Sat, and Sun). On Y is the number of drinks:

* Each drink is a little bar of its own. Color coded to indicate the beer style.
* Each change of location is indicated by a thin white line
* For days with no drinks, there is a green dot in the bottom. For consecutive
days, the dot moves a bit higher, up to 7 days.
* There is a white line that is a floating average of the past 30 days, with
higher weights for the more recent days.
* There is a green line that shows the (arithmetic) average for the last 7
days, including today.

Under the graph are navigation buttons:
* "<<" and ">>" move the graph earlier and later in time
* "2w", "Month", "3m", "6m", "Year", "2y", and "All" adjsut how long time is
shown in the graph
* [-] and [+] fine tune the zoom factor

Clicking on the graph itself zooms it to double the size. Clicking again zooms
back.

Under the graph is the usual full list. Since we have calculated the floating
averages for the graph, they are shown in the list for each day too.

### Beer Board
This is a list of beers available on the current location (or Ølbaren, if no
list available for that location). There is a pull-down for selecting the location
out of the few I have scripted access to. There are couple of links nex to it:
* www links to the home page of the bar, if known
* (PA) filters the list so it only shows Pale Ales, IPAs and suchlike, as those
are what I most often drink.
* (Reload) forces a reload of the beer list. Otherwise the system caches the
list for a couple of hours to make things go faster. Useful if you see the
bartender writing a new one on the blackboard.
* (all) expands all the entries, making the list more informative, but also
using up much more space on the screen.

In the simple form, each beer is on a line of its own. The lines can get wider
than your phone screen, you can scroll sideways to read the rest. The important
details are in the beginning of the line.
* Tap number. Color coded for beer style. Clicking on this expands that one
beer entry.
* Two buttons for entering the beer into the system. One for a small beer, the
other for a large one. Usually 25 and 40 cl, but can vary depending on what sizes
the beer is served.
* Alc percentage
* Beer name
* Brewer
* Country
* Style (simplified)

If you selected the Extended display, each beer takes up a few lines. Where we
have it, there will be a line telling how many times we have seen that beer
before, when was the last time, how many ratings and their average, compressed
into something like "3 rat=6.3"

Before the beer board is always the graph (see bove), and under it the display
continues as the full list (see above).

### Stats
Shows some statistics for each day, month, or year. On top is a line with links
to each statistic. When selected from the menu, this starts as the monthly
statistic.

#### Days
Shows a line for each day with
* Date and weekday
* How many drinks
* How much money
* Highest blood alc for the day
* Locations where I have been that day, in reverse order. Some are abbreviated,
like "Øb" for Ølbaren and "H" for Home.

Consecutive days with no drinks are compressed in one line like "... (3 days)..."

#### Months
This shows a graph of average daily consumption for each month. Each year is
plotted with a different color. The most recent years are plotted with thicker
lines.

Underneath is the same data in a table form. For each month we have average
drinks per day and week, and amount of money spent. For the current month there
is also a projection where we might end at the same speed.

There are also averages for each calendar month, and averages and sums for
each year.

#### Years
This shows in a table form where I have spent most money for each year, with the
biggest spending locations first. The list shows also the number of drinks at
the location. The sorting defaults to money, but can be changed to number of
drinks.

### Small lists
There are a number of "small" lists. The main menu only has the Beer List, but
from that it is easy to navigate to the other ones. All the lists default to
chronological order with the most recent first, but can be sorted alphabetically.

There is also a search box that filters only the lines matching what ever you
enter there.

#### Location
Shows a list of the most recent watering holes you have visited. For each there
is
* Name of the place. Clicking on this gets you to the full list, filtered by
that location.
* Link to the beer board of the location, if known to the system
* Link to the bars web page, if known to the system
* Link to a google search of the place name
* Last time you visited, and how many visits the system knows about
* The last beer you drank there: Brewery and name. These are links that filter
the location list by that beer or brewery.

#### Brewery
Shows the most recent breweries you have been enjoying, with about the same data
as for the location list, except that it lists where you had the beer last.
The list excludes all "special" breweries that have a comma in their names.

#### Beer
Lists the beers you have had. On the left is the beer name with a count how many
of them you have had, and on the right side when and where you had it last, and
the style, alcohol, and brewery of the beer. Also this list excludes the "special"
breweries, so it only shows things that really are beers.

#### Wine and Booze
Much like the beer list, these show record types "Wine" and "Booze".

#### Restaurant
Shows a list of the "Restaurant" type records. Shows the style of the place,
what you had there, how much you spent (total price, for one person), and ratings
if you rated the place.

#### Style
Lists all beer styles known to the system, when and where you last had one.

### About
Contains the copyright message, and all kind of useful details I didn't know
where else to put.
* Link to the source code and bug tracker on GitHub
* Links to RateBeer and Untappd, as well as some of my favourite watering holes
* Summary of the abbreviations for various volumes
* Debug info, including a download of the whole data file or just the tail of it.


---


## Problems
If you are just starting, I may be willing to help with technical issues, especially
if I have set up an account for you on my system. If you are self-hosting, I hope you
can manage most technical problems yourself, and/or look in the code to see what
is going on.

If you run into bugs and real problems, please file them as issues on GitHub, at
https://github.com/heikkilevanto/beertracker/issues. Even better, if you can fix it
yourself, file a pull request.

See also the [README](./README.md)
