
# BeerTracker Overall Design

## Overview
The BeerTracker is used for tracking beers and other drinks I meet. It can
tell me if I have seen a beer before, and how I liked it. It can also keep
track of the money I spend on beers, and my total alcohol intake.

Although the system is intended for tracking my own stuff, I have made it so
that it scales for a small number of users.

The system is under constant development, so this document is likely to be
somewhat out of date - the actual code is the source of truth.

## History
I wrote the first version (v0.1) on a Friday afternoon, sick and tired of 
abstract design discussions at work. The first versions used a flat text file 
for the database (quick to append, easy to read, but inflexible). I started to
use it for real in January 2016, and have been using the system ever since.

- v1.0 Feb'16: I felt I had something ready enough
- v1.1 Mar'17: Improved lists, graphs, menu, etc
- v1.2 Aug'18: Small improvements
- v1.3 Sep'20: Restaurant entries, graph zoom, summaries
- v1.4 Apr'24: Scrape beer list for a few bars, fancy colors, blood alc, caching
- v2.0 Jun'24: Record types on the text lines (incompatible).
- v2.1 Oct'24: Last version with a text file
- v3.0 Jul'25: Sqlite for all data, redesign ui, split into modules
- v3.1 Aug'25: Rating stats, photos, geo coordinates, generic brews, refactoring
- v3.2 Jan'26: Tracking beer taps, prices, AI-assisted refactoring

## TODO
This document is nowhere near ready. Should write something about these:
- Something about typical data flow, logging a glass
- Future considerations

---

**Quickstart (TL;DR):** Clone the repo, copy a recent `beerdata/production` DB to `beerdata/beertracker.db`, ensure required Perl modules are installed, put `code/index.cgi` under Apache cgi-bin (or configure a vhost to serve the `beertracker` directory), and start making entries. See `copilot-instructions.md`, `README.md` and `etc/apache-config.example.txt` for more details.


## Architecture

BeerTracker is a lightweight web application built with procedural Perl CGI
scripts and SQLite as the backend. The main entry point is `index.cgi`, which
loads short, focused modules for handling forms, reports, and utilities. This
is controlled by the `?o=Module` url parameter.

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

### tap_beers
Track what beers various places have on tap now or in the past. Also what
volumes the beer was sold at, and for what price. 

### Relationships
- `brews.ProducerLocation → locations.Id`
- `glasses.Brew → brews.Id`
- `glasses.Location → locations.Id`
- `comments.Glass → glasses.Id`
- `persons.Location → locations.Id`
- `persons.RelatedPerson → persons.Id`
- `taps_beers.Location → locations.Id`
- `taps_beers.Brew → brews.Id`

## Program modules
Originally BeerTracker was one large script, but for version 3 I split it into
many smaller modules. Later I moved them all to live under .../code. The
definitive list of them is in the `require` statements near the beginning of
index.cgi. I will add more modules when features creep in, and/or when I 
refactor larger modules into a few smaller ones. Therefore this list is
almost certain to be out of date.

Main operations:
- `code/mainlist.pm` - The main "full" list
- `code/graph.pm` - The daily graph
- `code/beerboard.pm` - The beer board for the current bar
- `code/glasses.pm` - Main input for and the full list
- `code/postglass.pm` - POST handling for glass records

Listing/Editing various helper records:
- `code/persons.pm` - List of people, their details, editing, helpers
- `code/locations.pm` - Locations stuff
- `code/brews.pm` - Lists of various brews, etc
- `code/styles.pm` - Beer style utilities: colors, display, shortening
- `code/comments.pm` - Stuff for comments, ratings, and photos
- `code/photos.pm` - Helpers for managing photo files
- `code/taps.pm` - Updating tap_beers table

Statistics:
- `code/stats.pm` - Various statistics
- `code/monthstat.pm` - Monthly statistics
- `code/yearstat.pm` - annual stats
- `code/ratestats.pm` - Histogram of the ratings

Other utilities:
- `code/aboutpage.pm` - The About page
- `code/export.pm` - Export the users own data
- `code/db.pm` - Various database helpers
- `code/geo.pm` - Geo coordinate stuff
- `code/inputs.pm` - Helper routines for input forms
- `code/listrecords.pm` - A way to produce a nice list from db records
- `code/scrapeboard.pm` - Scraping and updating beer boards
- `code/superuser.pm` - Superuser functions: Copy prod data, git pull
- `code/util.pm` - Various helper functions
- `code/VERSION.pm` - auto-generated version info

There are also a small number of javascript and css files under static

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
you may have to do some manual trickery in both development and production db.

