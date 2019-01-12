# beertracker
Simple script to track the beers I drink

Goals for this project:
 - Help me remember what beers I have been drinking, and how I liked them
 - Keep track of money and alcohol consumption

What this is not
 - Cloud based - I want to host it myself
 - Crowdsourced - I am only interested in my own opions about the beers
 - Public - There are many beer rating sites already
 - Global - I only care about the local watering holes

Outline
 - Simple form to enter a beer I am drinking
 - Store all data in a flat text file
 - Write in Perl, run as a CGI script under Apache

Although this is a personal project to scratch my own itch, I might as well
release it under GPL, in case someone else finds this interesting. The system
can handle multiple accounts, so if you ask nicely (and if I know you already)
I may give you one to play with.


Version 1.0 was released in Feb-2016. It works, and I am using it myself. Of
course there is a small list of features I will want to add some day "real
soon now".

## Installation

Here are a few things you need to remember when setting this up. I am using a 
Debian server. Adjust as needed

There is an Apache config file example under /etc.

You need to set up a .htpasswd to protect  the main directory, and make a 
directory under it called beerdata, and an empty file like `heikki.data` in
it. Both need to be owned and writable by www-data. 

Point your browser to beerdata. You should see a dark input form. If not, check
/var/log/apache2/error.log. If you do, enter a test beer or two, and look at 
the lists.

## Getting started
When you start, the database is empty. You need to enter all details on the first 
beers. Your browser will remember some of those values and suggest them to you.
If you leave values empty (just click on any field, it clears), the program will
try to make a guess from your history. This only works if you spell the beer
name the same way, so be correct there. It is handy for picking up the strength
and price of beer, etc. 

Most of the time, if you have drunk that beer before, it is easy to find the beer
in the list, and just click on the `copy` buttons. They come in predefined sizes of
25 and 40 cl, and if you drank some other quantity, that gets a copy button too.

On the beer list, almost every word is a link to filter the list. If you click on
the brewery name, the list shows only beers from that brewery. Same for location, 
etc. You can also filter only those entries that have ratings on them, or comments.
This is good if you want to look up a beer before buying.

There are dedicated lists for beers, breweries, locations, etc. Those can be
selected from the "show" pull-down in the input form. 

## Tpis and tricks

* I use the brewery field for specifying non-beer categories. All of them should
have a comma in the name, for example `Booze, whisky`, or `Wine, Red`. These can
be shown in separate booze and wine lists.
* I file restaurants the same way, for example "Restaurant, Thai". I fill in the 
whole price of the evening, for one person. But no alcohol or volume, those I
should have filed separately. In the comments I write what I ate and drunk, some
comments about prices, or what ever else comes to mind.
* There is a small list of pre-defined beer sizes. The most common (for me, in 
Denmark) are `L` which is 40 cl, and `S` for 25 cl. Also a `T` for a 2cl taster.


## Problems
If you are just starting, I may be willing to help with technical issues, especially
if I have set up an account for you on my system. If you are self-hosting, I hope you
can manage most technical problems yourself, and/or look in the code to see what 
is going on.

If you run into bugs and real problems, please file them as issues on GitHub, at
https://github.com/heikkilevanto/beertracker/issues. Even better, if you can fix it
yourself, file a pull request.

