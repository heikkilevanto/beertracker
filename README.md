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

File issues or pull requests if you find something broken or missing.

