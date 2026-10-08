-- @descripcion: Respuesta a una push POR PERSONA en cualquier sesión (la sesión de la push se cierra ~1 h después y la respuesta posterior abre otra): recibieron, respondieron en la misma sesión / 1 h / 24 h / 72 h, y qué respondieron. --rulename = nombre del template (ej. "edu06push02_iel%").
-- @requiere: rulename
-- @costo: medio
--
-- Criterio (pedido push EDU04CUX21, 08/10/2026 — ver BOTI_AWS_Referencia.md 6.3.b):
--   recibió    = mensaje del bot que empieza con 'Template' y rule_name = la push (incluye pushes que cayeron en sesión abierta)
--   respondió  = fila msg_from = 'user' de la misma persona (SUBSTR(session_id,1,20)) posterior a la push, en CUALQUIER sesión
--   NO usar original_user_message: en la fila del Template trae lo último que la persona hizo ANTES (otra push, otro flujo).
--   Botones de tipo URL del template NO generan fila de usuario: no se ven acá.
--   "Respondió en otra sesión" incluye cosas que no son respuesta a la push (otro tema): mirar la hoja primera_respuesta.
--   Si una persona recibió varias pushes del filtro, su respuesta cuenta para cada una.

-- @hoja: por_push
WITH p AS (
  SELECT rule_name AS push, SUBSTR(session_id, 1, 20) AS persona,
         MIN(creation_time) AS t_push, min_by(session_id, creation_time) AS ses_push
  FROM "caba-piba-consume-zone-db"."boti_message_metrics_2"
  WHERE {part_ext} AND {rango_creation} AND {cond_rulename} {no_testers}
    AND regexp_like(message, '^Template')
  GROUP BY 1, 2
),
u AS (
  SELECT SUBSTR(session_id, 1, 20) AS persona, session_id, creation_time
  FROM "caba-piba-consume-zone-db"."boti_message_metrics_2"
  WHERE {part_ext} {no_testers}
    AND msg_from = 'user'
    AND SUBSTR(session_id, 1, 20) IN (SELECT persona FROM p)
),
j AS (
  SELECT p.push, p.persona, p.t_push,
         MIN(IF(u.session_id = p.ses_push, u.creation_time)) AS t_misma_sesion,
         MIN(u.creation_time)                                AS t_resp
  FROM p
  LEFT JOIN u ON u.persona = p.persona
             AND u.creation_time > p.t_push
             AND u.creation_time <= p.t_push + INTERVAL '72' HOUR
  GROUP BY 1, 2, 3
)
SELECT push,
       COUNT(*)                                                    AS recibieron,
       COUNT(t_misma_sesion)                                       AS respondieron_misma_sesion,
       COUNT_IF(date_diff('minute', t_push, t_resp) <= 60)         AS respondieron_1h,
       COUNT_IF(date_diff('minute', t_push, t_resp) <= 1440)       AS respondieron_24h,
       COUNT(t_resp)                                               AS respondieron_72h,
       ROUND(100.0 * COUNT(t_misma_sesion) / COUNT(*), 2)          AS pct_misma_sesion,
       ROUND(100.0 * COUNT_IF(date_diff('minute', t_push, t_resp) <= 1440) / COUNT(*), 2) AS pct_24h
FROM j
GROUP BY push
ORDER BY recibieron DESC

-- @hoja: primera_respuesta
-- Primera cosa que mandó cada persona dentro de las 24 h (botón o texto), y si fue en la sesión de la push.
WITH p AS (
  SELECT rule_name AS push, SUBSTR(session_id, 1, 20) AS persona,
         MIN(creation_time) AS t_push, min_by(session_id, creation_time) AS ses_push
  FROM "caba-piba-consume-zone-db"."boti_message_metrics_2"
  WHERE {part_ext} AND {rango_creation} AND {cond_rulename} {no_testers}
    AND regexp_like(message, '^Template')
  GROUP BY 1, 2
),
u AS (
  SELECT SUBSTR(session_id, 1, 20) AS persona, session_id, creation_time, message
  FROM "caba-piba-consume-zone-db"."boti_message_metrics_2"
  WHERE {part_ext} {no_testers}
    AND msg_from = 'user'
    AND SUBSTR(session_id, 1, 20) IN (SELECT persona FROM p)
),
f AS (
  SELECT p.push, p.persona,
         min_by(COALESCE(regexp_extract(u.message, '"button":"([^"]*)"', 1),
                         SUBSTR(lower(trim(u.message)), 1, 50)), u.creation_time) AS primera_respuesta,
         min_by(IF(u.session_id = p.ses_push, 'misma sesión', 'otra sesión'), u.creation_time) AS donde
  FROM p
  JOIN u ON u.persona = p.persona
        AND u.creation_time > p.t_push
        AND u.creation_time <= p.t_push + INTERVAL '24' HOUR
  GROUP BY 1, 2
)
SELECT push, primera_respuesta, donde, COUNT(*) AS personas
FROM f
GROUP BY 1, 2, 3
ORDER BY push, personas DESC
LIMIT 3000
