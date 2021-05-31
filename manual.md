# Heikki's Beer Tracker

## Overview
This is a simple script to track the beers I drink. I also use it for other
purposes, like remembering restaurants, tracking wines and booze, and displaying
nice graphs.


## Getting started
When you start, the database is empty. You need to enter all details on the first
beers. Your browser will remember some of those values and suggest them to you.
If you leave values empty (just click on any field, it clears), the program will
try to make a guess from your history. This only works if you spell the beer
name the same way, so be correct there. It is handy for picking up the strength
and price of beer, etc.

The system is optimized for filing things as you drink, but you can enter data
after the fact. In that case, put in the date and time in the two first input
fields, as YYYY-MM-DD HH:MM.

Most of the time, if you have drunk that beer before, it is easy to find the beer
in the list, and just click on the `copy` buttons. They come in predefined sizes of
25 and 40 cl, and if you drank some other quantity, that gets a copy button too.

On the beer list, almost every word is a link to filter the list. If you click on
the brewery name, the list shows only beers from that brewery. Same for location,
etc. You can also filter only those entries that have ratings on them, or comments.
This is good if you want to look up a beer before buying.

There are dedicated lists for beers, breweries, locations, etc. Those can be
selected from the "show" pull-down in the input form.


## Input fields
The first part of the screen is the put area, where you can enter what beers
you drink. Most of the fields start with default values. When you click on one,
the value disappears, making it easier to type in a new value, especially on
a phone.

### Date
Usually you can leave this empty, the system defaults to the current date. If
you want to enter data after the fact, you can put the actual date here, as
YYYY-MM-DD. There are two shortcuts: 'L' is the same date as the latest entry,
and 'Y' for yesterday.

### Time
Here you can enter the time when you drank the beer. It accepts some common
formats, like 23:55 1am 1pm 2335 etc. If you leave it emtpy, as you usually
should, it takes the system time. (but see timezones under tips and tricks)
Since drinking often continues past midnight, the system counts times up to
08 next morning as belonging to the day before.

### Location
Where you had your beer. Used for various lists. Defaults to the same place as
the previous beer.

### Style
The style of the beer. There are no predefined styles, you will have to enter
them the way you like to classify your beers. Used for various lists. The system
tries to copy the style from an earlier entry of the same name. The field can
also be used for the style of restaurants, booze, or wine.

### Brewery
Who made the beer. Again, if you have had the beer before (and spelled if the
same way), the system will reuse the brewery name.

The field can also be used for special cases that are not beers, for example
"Wine, Red", or "Booze, Whisky", or "Restaurant, Thai". These will show up on
the respective special lists.

### Beer Name
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

### Rating
A pull-down menu where you can choose how well you liked the beer, on a scale
from "0 - Undrinkable" to "10 - I'm in love". Later you can see how you liked
different beers, so you can choose one you like.

### Comments
Here you can write any descriptions or comments about the beer. These are shown
in the full list.

Before you type anything in the box, it is showing three lines of statistics:
* How many "standard" drinks you have had today, and how much you paid for them.
If you didn't have any today, it shows the date when you last had, and the values
for that date.
* Same for the last week, up to and including today. Also shows the average
"standard" drinks per day, and how many days without any.
* Same for the calendar month.

### Record Button
This button enters the beed into the system. it also fills some of the input
fields for the next one, assuming that you might have one more of the same
kind.

### Clear Button
Clears all input fields, in case you want to enter something completely different.

### Show pull-down
This is the main menu, where you can choose what to show under the input form.
See below.



## Editing
The input form is also used for editing old records. In that case there are
a few small differences:
* At the top there is a text telling which record you are editing. The records
are identified by their timestamps.
* Instead of the date and time, there are three fields: Timestamp, Weekday,
and effective date - this is normally the same as t he timestamp, except late
night, when it is the previous day, so late Friday night drinks count on that
Friday, even past midnight.
* The regular input fields are as before, but filled in with the values from
the record.
* The buttons are different. There is no "Record" button
* Instead, there is a "Save" button that saves your changes
* And a "Cancel" link that discards them
* And a "Delete" button that deletes your record.
* There is also a checkbox marked 'Clr'. By default it starts checked, which
means that most of the fields are cleared as soon as you click on them. If you
uncheck the box, the fields will not clear. This is handy for editing a small
typing error.


## The main menu
The "Show" menu allows you to choose what gets shown under the input form.

### Full list
This is the default. It shows a list of beers you have had, most recent first.
There are many ways to filter that list.

At the top of the list are some links to filter the list:
* Ratings - Shows only the beer entries where you have filled in a rating
* Comments - Shows only the beers that you have commented on
* Links - Shows some extra links for each beer
* Print - Hides the input form, so you can take a screen print of more beers

The list itself is divided into days, and those can be divided into locations,
if you have been drinking at different places.

The first line of each beer has the time, brewery, and name of the beer. These
can be marked with 'new' if it looks like it is the first time you enter such.
That is useful for catching spelling errors. The brewery and beer names are links
that cause the list to be filtered so that only that beer or brewery is shown.
That makes it easier to see what you have thought about the beer, or what else
the brewery has made.

The second line has the beer style (also a link to filter the list), and a few
numbers:
* Price
* Volume
* Alc
* "Standard drinks"

The next line has the rating you have given the beer, and comments, if you
entered any.

The last line has a link for editing the entry - that puts all the values in
the input fileds above, where you can correct mistakes. (See above.)
That line also has a few "Copy" buttons, defaulting to most likely sizes you
might drink again. You can click those buttons on any beer entry, and the system
will create a new entry for todays date and time, with that amount of that beer.
That is by far the easiest way to enter data.

At the end of each day or location there will be summaries on how much you have
drank there.

### Short list
Gives you a list of days, where you have been drinking, and how much.

### Graph
Shows a graph of your drinking. Time is on the X-axis, and on Y is the number
of drinks:
* The grey bars represent weekdays, and the blue bars are weekends. This
is to make it a bit easier to follow the days.
* For days with no drinks, there is a green dot in the bottom.
* For each day there is a little '+' that indicates the average number of
drinks for the preceding 7 days. When showing a longer graph, this is only
shown for Tuesdays, for clarity.
* There is a purple line that is a floating average of the past 30 days, with
higher weights for the more recent days.

Under the graph are navigation buttons:
* "<<" and ">>" move the graph earlier and later in time
* "Month", "Year", and "All" adjsut how long time is shown in the graph
* [-] and [+] fine tune the zoom factor

Clicking on the graph itself zooms it to double the size. Clicking again zooms
back.

Under the graph is the usual full list. Since we have calculated the floating
averages for the graph, they are shown in the list for each day too.

### Location
Shows a list of the most recent watering holes you have visited. For each there
is
* Name of the place. Clicking on this gets you to the full list, filtered by
that location.
* Link to their beer list, if known to the system
* Link to a google search of the place name
* Last time you visited, and how many visits the system knows about
* The last beer you drank there: Brewery and name. These are links that filter
the location list by that beer or brewery.

At the top there is a link to sort the list alphabetically, instead of most
recent first.


### Brewery
Shows the most recent breweries you have been enjoying, with about the same data
as for the location list, except that it lists where you had the beer last.
The list excludes all "special" breweries that have a comma in their names.

### Beer
Lists the beers you have had. On the left is the beer name with a count how many
of them you have had, and on the right side when and where you had it last, and
the style, alcohol, and brewery of the beer. Also this list excludes the "special"
breweries, so it only shows things that really are beers.

### Wine and Booze
This shows all the "beers" that have a special brewery that starts with "Wine"
or "Booze" and a comma, for example "Wine, Red" or "Booze, Vodka". Otherwise
this is much like the beer list.

### Restaurant
Shows a list of the "special breweries" that start with "Restaurant" and a comma.
For each it shows the style, what you had (comes from the beer name), when you
visited last, and how much did you spend - if you entered that in the price field.

### Style
Lists all beer styles known to the system, when and where you last had one.

### Months
Shows monthly statistics. Shows a graph from January to December, with different
colored lines for each year. Plots the average alcohol intake per day, in
"standard drinks".

Under the graph, the same data is in a table form. For each month there is the
number of drinks, and how much money you have spent.

### Years
Shows statistics for each year you have used the system. For each year there
is a list of the most frequented locations, and how much money you have spent
there, and how many "standard" drinks you have had there. For the current year
there is also a projection how the year might look like if it continues the same
speed. This is a wild guess based on some unreliable statistics, probably wildly
off for the first year you use the system.

### Datafile
Allows you to retrieve all your raw data, just as it is stored in the system.
It is in plain text, you can save the page as a text file, and probably import
it to a spreadsheet or something. Use the back button to get back.

### About
Contains the copyright message, and all kind of useful details I didn't know
where else to put.
* Link to the source code and bug tracker on GitHub
* Links to RateBeer and Untappd, as well as some of my favourite watering holes
* Information on what time zone the system thinks you are in
* Summary of the abbreviations for various volumes





## Tpis and tricks

* I use the brewery field for specifying non-beer categories. All of them should
have a comma in the name, for example `Booze, whisky`, or `Wine, Red`. These can
be shown in separate booze and wine lists. I try to put wine styles in the style
field, but it is small, so most of the stuff needs to go in the comments.
* I file restaurants the same way, for example "Restaurant, Thai". I fill in the
whole price of the evening, for one person. But no alcohol or volume, those I
should have filed separately. In the comments I write what I ate and drunk, some
comments about prices, or what ever else comes to mind.
* There is a small list of pre-defined beer sizes. The 'About' page will show
you the current list. If traveling in the US, you can give the size as `12 oz`
and it will be converted into 36 cl.
* The time defaults to the time on the server. But you can enter a fake brewery
line like 'tz,Copenhagen' to change your time zone. It gets remembered until you
set it again. To clear it, just set a new with 'tz,'
* If you buy a box wine, enter its price as negative. That way, the system
knows it is a box wine, and makes a comment on it, like "(B17:300)". Enter your
drinks as usual, and see the volume in the box comment go down. If you use wine
for cooking, for guests, enter the volume as negative, that way the box volume
will go down, but it will not be counted against you.

## Problems
If you are just starting, I may be willing to help with technical issues, especially
if I have set up an account for you on my system. If you are self-hosting, I hope you
can manage most technical problems yourself, and/or look in the code to see what
is going on.

If you run into bugs and real problems, please file them as issues on GitHub, at
https://github.com/heikkilevanto/beertracker/issues. Even better, if you can fix it
yourself, file a pull request.

