# Heikki's Beer Tracker

## Overview
This is a simple script to track the beers I drink. I also use it for other
purposes like remembering restaurants, tracking wines and booze, and displaying
nice graphs.


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

The input form is how you record what you're drinking. It's designed for quick entry while you're at the bar, but you can also backfill old data.

Most fields remember your last entry, so if you're drinking multiple beers at the same place, you just change the beer name and hit Record. Click on any field and start typing to replace the value.

The main fields are:
- Date and Time (usually auto-filled to now)
- Location (pick from your history or add a new one)
- Type (Beer, Wine, Booze, or Restaurant/Night/Bar for visits without specific drinks)
- Which beer/wine/booze you're drinking
- Volume, alcohol %, and price

### Date

The date field defaults to today. If you want a different date, just type it in as `YYYY-MM-DD` (like `2024-03-15`).

Shortcuts:
- **L** - Use the date from your last entry (plus 5 minutes)
- **Y** - Yesterday's date

When editing an old entry, it keeps the original date unless you change it.

### Time

The time field defaults to now. You can type time in several formats:
- `23:55` - Standard format
- `2355` - No colon needed
- `15` - Just the hour (becomes 15:00)
- **L** - 5 minutes after your last entry

The system adds seconds automatically to make each entry unique. Those are usually not displayed.

### Location

Pick where you're drinking from the dropdown. It shows your most recent locations first, so your regular spots are easy to find. You can also type to search.

Click the "Location" label itself to auto-select your nearest location (if you've enabled geolocation).

To add a new location, select "new location" from the dropdown and fill in the details. You can click "(here)" to grab your current GPS coordinates for the new location.

### Record Type

Choose what you're tracking: Beer, Wine, Booze, Restaurant, Night, Bar, or Feedback.

**Beer/Wine/Booze** show the normal fields - which drink, volume, alcohol percentage, and price.

**Restaurant/Night/Bar/Feedback** are for recording visits without specific drinks. The brew fields hide, and you just enter the type of place and how much you spent. This is handy for tracking restaurant visits or nights out, and for anchoring comments.

### What You're Drinking

For Beer/Wine/Booze, pick from the dropdown. It shows your recent drinks first, making it quick to log something you've had before. You can type a part of the name, and the list filters out all that don't match.
There is also a trick, if you type something like @xxx, it shows only drinks you have had at a location that matches xxx. If you want to filter by style, you can just type it "smoke", but if that matches too many smoked
porters, you can put it in square brackets "[smoke]". Only the opening bracket is important. You can filter by anything that shows in the entry, even alc %, by entering "4.6%". 

If the system knows the drink, the volume, alcohol, and price fields will auto-fill with previous values.

To add a new beer, select "new brew" and fill in the details. The brewery field also lets you pick from recent breweries or add a new one.

### Volume

How much you drank, usually in centiliters. You can type shorthand codes for common sizes:

- **T** = 2cl (Taster)
- **G** = 16cl (Glass of wine)
- **S** = 25cl (Small)
- **M** = 33cl (Medium bottle)
- **L** = 40cl (Large, the default)
- **C** = 44cl (Can)
- **W** or **B** = 75cl (Wine bottle)

Prefix with **H** for half portions: `HB` = 37cl

You can also enter `12 oz` for US fluid ounces (converts to 36cl), or just type the number directly like `33`.

Type **X** if you don't know or don't want to record the volume.

### Alcohol Percentage

The alcohol by volume (ABV). Just type the number like `4.6` or `5.5`. The % sign is added automatically.

This auto-fills from previous entries of the same beer, so you usually don't need to change it.

Type **X** if you don't know.

### Price

What you paid. This is the only required field - everything else can be guessed or left empty.

Just type the number like `45` or `89`. The system adds the `.-` decoration automatically.

If you've ordered this same beer at this place before, the price might auto-fill. Otherwise you need to enter it. Type **X** for free drinks.

For "empty" glasses, that is notes on restaurants, nights, etc, you should enter the total price,
including all the drinks you had there. Or set it to zero or **X** if you can not be bothered.

### Extra Fields

Click "(more)" in the left column to reveal:

**Tap** - Which tap number the beer came from (mainly for tracking beer boards)

**Note** - Free text note about this specific glass. Good for recording beer mixes or other one-off details.

**Def checkbox** - Check this to update the beer's default price and volume to what you just entered. Useful when prices change or you usually drink a different size than what's stored.

### Buttons

**Record** - Save a new entry

**Save** - Update the entry you're editing

**Del** - Delete the current entry (only when editing)

**Clr** - Clear all text fields to start fresh

**cancel** - Stop editing and go back to normal mode (only when editing)

### Tips

**Quick entry at the bar**: The form remembers your last location and settings. Just pick the beer and hit Record. If it's the same beer, you don't even need to change anything.

**Backfilling old data**: Clear the date field and type in the old date. Use **L** for time to add entries 5 minutes apart from the same session.

**Common workflows**:
- Tracking a restaurant visit: Choose "Restaurant" type, pick location, enter total price
- Recording multiple beers at one place: Just change the beer name between entries
- Beer you've had before: Pick it from the dropdown and volume/price auto-fill

When you pick a beer you've had before, the system tries to guess the price based on what you paid last time at that location.

---

## Comments and Ratings

You can add comments and ratings to any entry. These show up in the full list and help you remember what you thought about different beers.

**Adding comments**: In the full list below the input form, find the entry you want to comment on and click the little speech bubble icon or "comment" link. A text box appears where you can write your thoughts. Comments can be as short or long as you want.

**Ratings**: When commenting, you can also give a rating from 1-10. Just select a rating from the dropdown. This is useful for remembering which beers you liked.

**Photos**: You can attach a photo to any entry - handy for remembering what the beer looked like, or capturing the scene at a restaurant. Click the Photo button. On a phone that should open up the camera, on machines without cameras you can still upload a photo.

**People**: You can tag who you were drinking with. This is especially useful for restaurant and night entries to remember who was at dinner. Just add their names when commenting or editing. Only one name
per comment.

**Multiple comments**: You can add multiple comments to the same entry over time. Each comment gets timestamped, so you can track how your opinion changes.

**Empty entries for comments**: Sometimes you want to comment on a general experience rather than a specific drink. That's what the "Feedback" record type is for - it creates an entry with no drink details that you can hang comments on.

**Finding comments**: Use the "Comments" filter link at the top of the full list to see only entries that have comments. Similarly, "Ratings" shows only entries you've rated. This makes it easy to review your tasting notes when deciding what to order.

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
