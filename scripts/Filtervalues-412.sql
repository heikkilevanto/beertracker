
-- Add Filtervalue fields to views used in lists
-- See issue #412


DROP VIEW IF EXISTS BREWS_LIST;

CREATE VIEW BREWS_LIST AS select
    BREWS.Id,
    COALESCE(PLOC.Name,"") || ":" || COALESCE(BREWS.Name,"") as Filtervalue,
    BREWS.Name,
    PLOC.Name as Producer,
    BREWS.Alc as Alc,
    BREWS.BrewType || ", " || BREWS.Subtype as Type,
    strftime ( '%Y-%m-%d %w %H:%M', max(GLASSES.Timestamp), '-06:00' ) as Last,
    LOCATIONS.Name as Location,
    count(COMMENTS.Id) as Com,
    count(GLASSES.Id) as Count
  from BREWS
  left join LOCATIONS PLOC on PLOC.id = BREWS.ProducerLocation
  left join GLASSES on Glasses.Brew = BREWS.Id
  left join COMMENTS on COMMENTS.Glass = GLASSES.Id
  left join LOCATIONS on LOCATIONS.id = GLASSES.Location
  group by BREWS.id


DROP VIEW IF EXISTS PERSONS_LIST;
CREATE VIEW PERSONS_LIST AS select
    PERSONS.Id,
    COALESCE(PERSONS.Name,"") as Filtervalue,
    PERSONS.Name,
    count(COMMENTS.Id) - 1 as Com,
    strftime ( '%Y-%m-%d %w', max(GLASSES.Timestamp), '-06:00' ) as Last,
    LOCATIONS.Name as Location
  from PERSONS
  left join COMMENTS on COMMENTS.Person = PERSONS.Id
  left join GLASSES on COMMENTS.Glass = GLASSES.Id
  left join LOCATIONS on LOCATIONS.id = GLASSES.Location
  group by Persons.id
