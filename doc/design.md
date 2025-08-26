
# BeerTracker Overall Design

## Overview
The BeerTracker is used for tracking beers and other drinks I meet. It can
tell me if I have seen a beer before, and how I liked it. It can also keep
track of the money I spend on beers, and my total alcohol intake.

Although the system is intended for tracking my own stuff, I have made it so
that it scales for a small number of users.

The system is under constant development, so this document is likely to be
somewhat out of date - the actual code is the source of truth.


## TODO
This document is nowhere near ready. Should write something about these:
- Write a chapter about the history
- Something about typical data flow, logging a glass
- Configuration and deployment
- Future considerations


## Architecture

BeerTracker is a lightweight web application built with procedural Perl CGI
scripts and SQLite as the backend. The main entry point is `index.cgi`, which
loads short, focused modules for handling forms, reports, and utilities.

All data is stored in SQLite tables (`glasses`, `brews`, `comments`, `persons`,
`locations`), with foreign keys enforcing relationships. Each module interacts
directly with the database; there is no separate ORM or framework.

User sessions are minimal, with most data private per user, while shared
entities like `brews` and `locations` are available globally. The design
prioritizes readability, direct SQL usage, and modularity over abstraction or
heavy frameworks.


## BeerTracker Database Schema

### glasses
Stores individual drinking events, either actual drinks or placeholders like
restaurant visits. Each record is private per user and can reference a brew
and a location.

### comments
Private notes and ratings tied to a specific glass, optionally mentioning a
person or including a photo. Since these are tied to the glasses, they are
private per user.

### brews
Catalogs beverages, shared among users, with details like type, style,
producer location (as a location), alcohol content, and optional notes.

### persons
Tracks people you meet, with contact info, description, home/related location,
and possible related persons.

### locations
Represents physical places such as bars, restaurants, breweries, or homes,
including addresses, coordinates, contact info, and type. Also used for
producers of beer and other brews.

### Relationships
- `brews.ProducerLocation → locations.Id`
- `glasses.Brew → brews.Id`
- `glasses.Location → locations.Id`
- `comments.Glass → glasses.Id`
- `persons.Location → locations.Id`
- `persons.RelatedPerson → persons.Id`



## Program modules
Originally BeerTracker was one large script, but for version 3 I split it into
many smaller modules. Later I moved them all to live under .../code. The
definitive list of them is in the `require` statements near the beginning of
index.cgi. The modules can be divided roughly into

Main operations:
- `code/mainlist.pm`  -   The main `full` list
- `code/graph.pm`  -   The daily graph
- `code/beerboard.pm`  -   The beer board for the current bar
- `code/glasses.pm`  -   Main input for and the full list
- `code/aboutpage.pm`  -   The About page

Listing/Editing various helper records
- `code/persons.pm`  -   List of people, their details, editing, helpers
- `code/locations.pm`  -   Locations stuff
- `code/brews.pm`  -   Lists of various brews, etc
- `code/comments.pm`  -   Stuff for comments, ratings, and photos

Statistics etc
- `code/stats.pm`  -   Various statistics
- `code/monthstat.pm`  -   Monthly statistics
- `code/yearstat.pm`  -   annual stats
- `code/ratestats.pm`  -   Histogram of the ratings
- `code/export.pm`  -   Export the users own data

And all the various helpers. I will not list them here, as things are not at
all stable yet. There are also some things to make development work easier,
like copying the production database into the development setup, or forcing
a git pull...



## Configuration and Deployment
Beertracker lives as a cgi script under Apache. There is a config example under
etc.

The site is protected by regular htpassword, so you need to create those the
usual way.

## Development Environment
I normally develop under beertracker-dev, and when happy with it, commit and
push the code. Then I pull under beertracker itself for production use.

### Git trickery
The git hook `pre-commit` invokes `tools/makeversion.sh` which updates the
code/VERSION.pm with the current version number and a count of commits since,
so the about page and the top line can show where we are going.

The git hook `post-merge` invokes `tools/warn-schema.sh` which checks if the
db.schema has changed and if so, prints a warning to run the dbupdate script.

This is useful, if changing the schema under dev, for example adjusting some of
the  list views. Then you should run tools/dbdump.sh to update the db.schema
file. Commit and push that, and pull on production. The post-merge hook will
remind to run `tools/dbchange.sh` which tries to port the schema change to the
production database. It does it by exporting all the data, recreating the
database from db.schema, and importing the data back to it. This works for
changing views, or renaming columns in tables, but if adding columns or tables
you may have to do some manual trickery.

