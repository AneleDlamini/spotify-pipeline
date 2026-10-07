SELECT artist_names, COUNT(*) as plays
FROM (SELECT DISTINCT played_at, track_id, artist_names FROM recently_played) -- deduplicating the plays to avoid double counting
GROUP BY artist_names
ORDER BY plays desc
LIMIT 10