-- @descripcion: Sesiones y usuarios únicos del período (total, por día, por canal/bot/origen). Base de D2/D3/D4.
-- @costo: bajo
-- @hoja: total
SELECT COUNT(DISTINCT session_id)               AS sesiones,
       COUNT(DISTINCT SUBSTR(session_id, 1, 20)) AS usuarios
FROM "caba-piba-consume-zone-db"."boti_session_metrics_2"
WHERE {part} {no_testers} {cond_canal}

-- @hoja: por_dia
SELECT CAST(session_creation_time AS DATE)       AS fecha,
       COUNT(DISTINCT session_id)               AS sesiones,
       COUNT(DISTINCT SUBSTR(session_id, 1, 20)) AS usuarios
FROM "caba-piba-consume-zone-db"."boti_session_metrics_2"
WHERE {part} {no_testers} {cond_canal}
GROUP BY CAST(session_creation_time AS DATE)
ORDER BY fecha

-- @hoja: por_canal_origen
SELECT channel_id, channel_name, bot_id, starting_cause,
       COUNT(DISTINCT session_id)               AS sesiones,
       COUNT(DISTINCT SUBSTR(session_id, 1, 20)) AS usuarios
FROM "caba-piba-consume-zone-db"."boti_session_metrics_2"
WHERE {part} {no_testers} {cond_canal}
GROUP BY channel_id, channel_name, bot_id, starting_cause
ORDER BY sesiones DESC
