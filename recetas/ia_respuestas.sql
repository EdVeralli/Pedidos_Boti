-- @descripcion: Cómo respondió el buscador del Boti clásico (no BAX): oneShot / oneShotSearch / menú (Original Buttons, Boost), por día.
-- @costo: bajo
-- @hoja: por_dia
SELECT CAST(ts AS DATE) AS fecha, type, one_shot,
       COUNT(DISTINCT id) AS interacciones,
       COUNT(DISTINCT session_id) AS sesiones
FROM "caba-piba-consume-zone-db"."boti_intent_search_user_buttons"
WHERE {part} AND {rango_ts} {no_testers} AND message_id <> ''
GROUP BY CAST(ts AS DATE), type, one_shot
ORDER BY fecha, type

-- @hoja: total
SELECT type, one_shot, COUNT(DISTINCT id) AS interacciones
FROM "caba-piba-consume-zone-db"."boti_intent_search_user_buttons"
WHERE {part} AND {rango_ts} {no_testers} AND message_id <> ''
GROUP BY type, one_shot
ORDER BY interacciones DESC
