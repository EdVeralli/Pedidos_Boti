-- @descripcion: Colas de atención (CATs): sesiones, usuarios y mensajes por cola y por día. Ojo: queue no es un indicador perfecto.
-- @costo: medio
-- @hoja: por_cola
SELECT queue,
       COUNT(DISTINCT session_id)               AS sesiones,
       COUNT(DISTINCT SUBSTR(session_id, 1, 20)) AS usuarios,
       COUNT(DISTINCT CASE WHEN msg_from = 'operator' THEN id END) AS msjs_operador,
       COUNT(DISTINCT CASE WHEN msg_from = 'user' THEN id END)     AS msjs_usuario
FROM "caba-piba-consume-zone-db"."boti_message_metrics_2"
WHERE {part_ext} AND {rango_creation} {no_testers}
  AND queue IS NOT NULL AND queue <> ''
GROUP BY queue
ORDER BY sesiones DESC

-- @hoja: por_dia
SELECT CAST(creation_time AS DATE) AS fecha, queue, COUNT(DISTINCT session_id) AS sesiones
FROM "caba-piba-consume-zone-db"."boti_message_metrics_2"
WHERE {part_ext} AND {rango_creation} {no_testers}
  AND queue IS NOT NULL AND queue <> ''
GROUP BY CAST(creation_time AS DATE), queue
ORDER BY fecha, sesiones DESC
