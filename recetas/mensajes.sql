-- @descripcion: Mensajes escritos por usuarios que matchean una regex (case-insensitive): resumen, top mensajes y detalle con link.
-- @requiere: texto
-- @costo: medio
-- @hoja: resumen
SELECT COUNT(DISTINCT session_id)               AS sesiones,
       COUNT(DISTINCT SUBSTR(session_id, 1, 20)) AS usuarios,
       COUNT(DISTINCT id)                        AS mensajes
FROM "caba-piba-consume-zone-db"."boti_message_metrics_2"
WHERE {part_ext} AND {rango_creation} {no_testers}
  AND msg_from = 'user' AND message_type = 'Text' AND LENGTH(message) > 2
  AND regexp_like(lower(message), '{texto}')

-- @hoja: top_mensajes
SELECT lower(trim(message)) AS mensaje, COUNT(DISTINCT session_id) AS sesiones
FROM "caba-piba-consume-zone-db"."boti_message_metrics_2"
WHERE {part_ext} AND {rango_creation} {no_testers}
  AND msg_from = 'user' AND message_type = 'Text' AND LENGTH(message) > 2
  AND regexp_like(lower(message), '{texto}')
GROUP BY lower(trim(message))
ORDER BY sesiones DESC
LIMIT 1000

-- @hoja: detalle
SELECT CAST(creation_time AS DATE) AS fecha, session_id, message,
       CONCAT('https://go.botmaker.com/#/chats/', SUBSTR(session_id, 1, 20)) AS link
FROM "caba-piba-consume-zone-db"."boti_message_metrics_2"
WHERE {part_ext} AND {rango_creation} {no_testers}
  AND msg_from = 'user' AND message_type = 'Text' AND LENGTH(message) > 2
  AND regexp_like(lower(message), '{texto}')
ORDER BY fecha DESC
LIMIT 5000
