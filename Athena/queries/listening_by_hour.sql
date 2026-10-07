SELECT HOUR(played_at AT TIME ZONE 'Africa/Johannesburg') AS hour_of_day, COUNT(*) AS plays
FROM (SELECT DISTINCT played_at, track_id FROM recently_played) -- deduplicating the plays to avoid double counting
GROUP BY HOUR(played_at AT TIME ZONE 'Africa/Johannesburg')
ORDER BY hour_of_day