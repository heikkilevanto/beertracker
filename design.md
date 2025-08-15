
# BeerTracker Overall Design

## Overview
The BeerTracker is used for tracking beers and other drinks I meet. It can
tell me if I have seen a beer before, and how I liked it. It can also keep
track of the money I spend on beers, and my total alcohol intake.

Although the system is intended for tracking my own stuff, I have made it so
that it scales for a small number of users.

The system is under constant development, so this document is likely to be
somewhat out of date - the actual code is the source of truth.


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
including addresses, coordinates, contact info, and type.

### Relationships
- `brews.ProducerLocation → locations.Id`
- `glasses.Brew → brews.Id`
- `glasses.Location → locations.Id`
- `comments.Glass → glasses.Id`
- `persons.Location → locations.Id`
- `persons.RelatedPerson → persons.Id`



## Program modules
Originally BeerTracker was one large script, but for version 3 I split it into
many smaller modules. The definitive list of them is near the beginning of
index.cgi.

- `./persons.pm`  -   List of people, their details, editing, helpers
- `./locations.pm`  -   Locations stuff
- `./brews.pm`  -   Lists of various brews, etc
- `./glasses.pm`  -   Main input for and the full list
- `./comments.pm`  -   Stuff for comments, ratings, and photos
- `./util.pm`  -   Various helper functions
- `./graph.pm`  -   The daily graph
- `./stats.pm`  -   Various statistics
- `./monthstat.pm`  -   Monthly statistics
- `./yearstat.pm`  -   annual stats
- `./mainlist.pm`  -   The main `full` list
- `./beerboard.pm`  -   The beer board for the current bar
- `./inputs.pm`  -   Helper routines for input forms
- `./listrecords.pm`  -   A way to produce a nice list from db records
- `./aboutpage.pm`  -   The About page
- `./VERSION.pm`  -   auto-generated version info
- `./copyproddata.pm`  -   Copy production database into the dev version
- `./db.pm`  -   Various database helpers
- `./geo.pm`  -   Geo coordinate stuff
- `./ratestats.pm`  -   Histogram of the ratings
- `./export.pm`  -   Export the users own data

