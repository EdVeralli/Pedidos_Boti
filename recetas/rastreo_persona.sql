-- @descripcion: Conversaciones completas de una persona buscada por regex (DNI, mail, apellido) en mensajes y variables. DATOS PERSONALES: rango corto. Sólo desde 05/2024.
-- @requiere: texto
-- @costo: medio
-- @hoja: conversaciones
WITH s AS (
  SELECT DISTINCT session_id
  FROM "caba-piba-consume-zone-db"."boti_message_metrics_2"
  WHERE {part} AND msg_from = 'user' AND message IS NOT NULL
    AND regexp_like(message, '{texto}')
  UNION
  SELECT DISTINCT session_id
  FROM "caba-piba-consume-zone-db"."boti_user_vars_metrics_2"
  WHERE {part} AND regexp_like(vars_value, '{texto}')
)
SELECT m.session_id, m.creation_time, m.msg_from, m.message_type, m.message, m.rule_name,
       m.images_urls, m.files_urls,
       CONCAT('https://go.botmaker.com/#/chats/', SUBSTR(m.session_id, 1, 20)) AS link
FROM "caba-piba-consume-zone-db"."boti_message_metrics_2" m
JOIN s ON m.session_id = s.session_id
WHERE {part:m}
ORDER BY m.session_id, m.creation_time
LIMIT 20000
