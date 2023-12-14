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
 - Stores all data in a flat text file
 - Written in Perl, run as a CGI script under Apache

Although this is a personal project to scratch my own itch, I might as well
release it under GPL, in case someone else finds this interesting. The system
can handle multiple accounts, so if you ask nicely (and if I know you already)
I may give you one to play with. A few of my friends have tried the system,
on and off, but they all have given up at some point. Most people don't have
the disciplne to note down every beer they drink.

Version 1.0 was released in Feb-2016. It works, and I am using it myself. Of
course there is a small list of features I will want to add some day "real
soon now".

As of June 2021, we are at version 1.3, and I am still using this to track
(almost?) all the beers I drink.

## Installation

Here are a few things you need to remember when setting this up. I am using a
Debian server. Adjust as needed

There is an Apache config file example under /etc.

You need to set up a .htpasswd to protect the main directory. First time with
`htpasswd -c .htpasswd username`. For later users, do *not* include the `-c`.

You also need to make a directory under it called beerdata, and an empty file
like `heikki.data` in it. Both need to be owned and writable by www-data.
```
  mkdir beerdata
  chown www-data beerdata
  touch beerdata/heikki.data
  chown www-data beerdata/*.data
```
There is also a script `newuser.sh` that does most of that. Needs to be run
as root.

Point your browser to beerdata. You should see a dark input form. If not, check
/var/log/apache2/error.log. If you do, enter a test beer or two, and look at
the lists.


## Problems
If you are just starting, I may be willing to help with technical issues, especially
if I have set up an account for you on my system. If you are self-hosting, I hope you
can manage most technical problems yourself, and/or look in the code to see what
is going on.

If you run into bugs and real problems, please file them as issues on GitHub, at
https://github.com/heikkilevanto/beertracker/issues. Even better, if you can fix it
yourself, file a pull request.



## See also
 - The [User Manual](./manual.md)
 - The [Source Code](./index.cgi)


