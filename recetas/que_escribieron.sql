-- @descripcion: Qué escribió (o qué botón tocó) la gente para llegar a un contenido (original_user_message de las respuestas del bot).
-- @requiere: rulename
-- @costo: medio
-- @hoja: textos
SELECT lower(trim(original_user_message)) AS texto_usuario,
       COUNT(DISTINCT session_id)          AS sesiones
FROM "caba-piba-consume-zone-db"."boti_message_metrics_2"
WHERE {part_ext} AND {rango_creation} AND {cond_rulename} {no_testers}
  AND original_user_message IS NOT NULL
  AND NOT regexp_like(original_user_message, 'RuleBuilder:|"button"|"intent"|__audio__')
  AND LENGTH(original_user_message) > 2
GROUP BY lower(trim(original_user_message))
ORDER BY sesiones DESC
LIMIT 2000

-- @hoja: botones
SELECT regexp_extract(original_user_message, '"button":"([^"]*)"', 1) AS boton,
       COUNT(DISTINCT session_id) AS sesiones
FROM "caba-piba-consume-zone-db"."boti_message_metrics_2"
WHERE {part_ext} AND {rango_creation} AND {cond_rulename} {no_testers}
  AND original_user_message LIKE '%"button"%'
GROUP BY regexp_extract(original_user_message, '"button":"([^"]*)"', 1)
ORDER BY sesiones DESC
LIMIT 500
