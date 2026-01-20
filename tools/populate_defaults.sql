-- Populate DefVol and DefPrice for brews lacking DefPrice
-- Only updates where DefPrice is NULL, and both volume and price are available
-- One-time script, can be deleted any time, it has served its purpose. 

WITH volume_stats AS (
    SELECT Brew, Volume, COUNT(*) AS cnt, MAX(Timestamp) AS latest_ts
    FROM glasses
    WHERE Volume IS NOT NULL AND Brew IS NOT NULL AND Volume > 5 AND Volume < 64
    GROUP BY Brew, Volume
),
ranked_volumes AS (
    SELECT *, ROW_NUMBER() OVER (PARTITION BY Brew ORDER BY cnt DESC, Volume DESC) AS rn
    FROM volume_stats
),
selected_volumes AS (
    SELECT Brew, Volume
    FROM ranked_volumes
    WHERE rn = 1
),
price_stats AS (
    SELECT Brew, Volume, Price, Timestamp
    FROM glasses
    WHERE Price IS NOT NULL AND Volume IS NOT NULL AND Brew IS NOT NULL
),
ranked_prices AS (
    SELECT *, ROW_NUMBER() OVER (PARTITION BY Brew, Volume ORDER BY Timestamp DESC) AS rn
    FROM price_stats
),
latest_prices AS (
    SELECT Brew, Volume, Price
    FROM ranked_prices
    WHERE rn = 1
)
UPDATE brews
SET DefVol = sv.Volume, DefPrice = lp.Price
FROM selected_volumes sv
JOIN latest_prices lp ON sv.Brew = lp.Brew AND sv.Volume = lp.Volume
WHERE brews.Id = sv.Brew AND brews.DefPrice IS NULL AND brews.BrewType = 'Beer';