SELECT COUNT(track_id) as number_of_plays, dt
FROM recently_played
GROUP BY dt