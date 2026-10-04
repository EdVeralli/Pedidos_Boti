-- @descripcion: Sesiones sin ningún mensaje del usuario (pushes no respondidas, números inválidos), por origen.
-- @costo: medio
-- @hoja: por_origen
WITH con_usuario AS (
  SELECT DISTINCT session_id
  FROM "caba-piba-consume-zone-db"."boti_message_metrics_2"
  WHERE {part} AND msg_from = 'user'
)
SELECT s.starting_cause,
       COUNT(DISTINCT s.session_id) AS sesiones,
       COUNT(DISTINCT CASE WHEN u.session_id IS NULL THEN s.session_id END) AS sesiones_fantasma,
       ROUND(100.0 * COUNT(DISTINCT CASE WHEN u.session_id IS NULL THEN s.session_id END)
             / COUNT(DISTINCT s.session_id), 2) AS pct_fantasma
FROM "caba-piba-consume-zone-db"."boti_session_metrics_2" s
LEFT JOIN con_usuario u ON s.session_id = u.session_id
WHERE {part:s} {no_testers:s} {cond_canal:s}
GROUP BY s.starting_cause
ORDER BY sesiones DESC
