
-- Add Filtervalue fields to views used in lists
-- See issue #412

-- Removed the Filtervalue fields, not going to use them anyway
-- Modifying/adding views for more lists

DROP VIEW IF EXISTS BREWS_LIST;
CREATE VIEW BREWS_LIST AS select
    BREWS.Id,
    BREWS.Name,
    PLOC.Name as Producer,
    BREWS.Alc as Alc,
    BREWS.BrewType || ", " || BREWS.Subtype as Type,
    strftime ( '%Y-%m-%d %w ', max(GLASSES.Timestamp), '-06:00' ) ||  strftime ( '%H:%M', max(GLASSES.Timestamp)) as Last,
    LOCATIONS.Name as Location,
    count(COMMENTS.Id) as Com,
    count(GLASSES.Id) as Count
  from BREWS
  left join LOCATIONS PLOC on PLOC.id = BREWS.ProducerLocation
  left join GLASSES on Glasses.Brew = BREWS.Id
  left join COMMENTS on COMMENTS.Glass = GLASSES.Id
  left join LOCATIONS on LOCATIONS.id = GLASSES.Location
  group by BREWS.id;


DROP VIEW IF EXISTS PERSONS_LIST;
CREATE VIEW PERSONS_LIST AS select
    PERSONS.Id,
    PERSONS.Name,
    count(COMMENTS.Id) - 1 as Com,
    strftime ( '%Y-%m-%d %w ', max(GLASSES.Timestamp), '-06:00' ) ||  strftime ( '%H:%M', max(GLASSES.Timestamp)) as Last,
    LOCATIONS.Name as Location
  from PERSONS
  left join COMMENTS on COMMENTS.Person = PERSONS.Id
  left join GLASSES on COMMENTS.Glass = GLASSES.Id
  left join LOCATIONS on LOCATIONS.id = GLASSES.Location
  group by Persons.id;

DROP VIEW IF EXISTS "main"."LOCATIONS_LIST";
CREATE VIEW LOCATIONS_LIST AS select
    LOCATIONS.Id,
    LOCATIONS.Name,
    strftime ( '%Y-%m-%d %w ', max(GLASSES.Timestamp), '-06:00' ) ||  strftime ( '%H:%M', max(GLASSES.Timestamp)) as Last,
    LOCATIONS.LocType || ", " || LOCATIONS.LocSubType as Type,
    LOCATIONS.Description as Desc
  from LOCATIONS
  left join GLASSES on GLASSES.Location = LOCATIONS.Id
  group by LOCATIONS.Id;


-- This works, kind of, but uses a comma as separator
-- Some kind of subselect trick might be better
-- Never mind, the style list is disabled for now anyway
-- DROP VIEW IF EXISTS STYLES_LIST;
-- CREATE VIEW STYLES_LIST AS select
 -- coalesce(Brewtype,"") || ", " || coalesce(SubType,"") as Type,
 -- GROUP_CONCAT( DISTINCT BREWSTYLE ) as Style
 -- from BREWS
 -- group by Type;


