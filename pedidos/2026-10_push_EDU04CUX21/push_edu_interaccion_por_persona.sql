-- @descripcion: Pushes de Educación: interacción POR PERSONA en cualquier sesión (la sesión de la push se cierra ~1 h después y una respuesta posterior abre otra sesión). Ventanas 1 h / 24 h / 72 h.
-- @costo: medio
-- persona = SUBSTR(session_id, 1, 20). interacción = fila msg_from = 'user' posterior a la push.

-- @hoja: por_push
WITH p AS (
  SELECT rule_name AS push, SUBSTR(session_id, 1, 20) AS persona, session_id AS ses_push, MIN(creation_time) AS t_push
  FROM "caba-piba-consume-zone-db"."boti_message_metrics_2"
  WHERE {part_ext} AND {rango_creation} {no_testers}
    AND rule_name LIKE 'edu%push%' AND regexp_like(message, '^Template')
  GROUP BY 1, 2, 3
),
u AS (
  SELECT SUBSTR(session_id, 1, 20) AS persona, session_id, creation_time
  FROM "caba-piba-consume-zone-db"."boti_message_metrics_2"
  WHERE {part_ext} {no_testers}
    AND msg_from = 'user'
    AND SUBSTR(session_id, 1, 20) IN (SELECT persona FROM p)
),
j AS (
  SELECT p.push, p.persona, p.ses_push, p.t_push,
         MIN(IF(u.session_id = p.ses_push, u.creation_time)) AS t_misma_sesion,
         MIN(u.creation_time)                                AS t_cualquier_sesion
  FROM p
  LEFT JOIN u ON u.persona = p.persona
             AND u.creation_time > p.t_push
             AND u.creation_time <= p.t_push + INTERVAL '72' HOUR
  GROUP BY 1, 2, 3, 4
)
SELECT push,
       COUNT(*)                                       AS recibieron,
       COUNT(t_misma_sesion)                          AS interactuaron_misma_sesion,
       COUNT_IF(date_diff('minute', t_push, t_cualquier_sesion) <= 60)   AS interactuaron_1h,
       COUNT_IF(date_diff('minute', t_push, t_cualquier_sesion) <= 1440) AS interactuaron_24h,
       COUNT(t_cualquier_sesion)                      AS interactuaron_72h,
       ROUND(100.0 * COUNT_IF(date_diff('minute', t_push, t_cualquier_sesion) <= 1440) / COUNT(*), 2) AS pct_24h,
       ROUND(100.0 * COUNT(t_cualquier_sesion) / COUNT(*), 2) AS pct_72h
FROM j
GROUP BY push
ORDER BY recibieron DESC

-- @hoja: otra_sesion_iel
WITH p AS (
  SELECT SUBSTR(session_id, 1, 20) AS persona, session_id AS ses_push, MIN(creation_time) AS t_push
  FROM "caba-piba-consume-zone-db"."boti_message_metrics_2"
  WHERE {part_ext} AND {rango_creation} {no_testers}
    AND rule_name = 'edu06push02_iel_preinicio_ut_v1' AND regexp_like(message, '^Template')
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
  SELECT p.persona,
         min_by(COALESCE(regexp_extract(u.message, '"button":"([^"]*)"', 1),
                         SUBSTR(lower(trim(u.message)), 1, 50)), u.creation_time) AS primera_respuesta,
         MIN(date_diff('hour', p.t_push, u.creation_time))                        AS horas_despues
  FROM p
  JOIN u ON u.persona = p.persona
        AND u.session_id <> p.ses_push
        AND u.creation_time > p.t_push
        AND u.creation_time <= p.t_push + INTERVAL '72' HOUR
  GROUP BY p.persona
)
SELECT primera_respuesta, COUNT(*) AS personas, ROUND(AVG(horas_despues), 1) AS horas_promedio
FROM f
GROUP BY 1
ORDER BY personas DESC
LIMIT 300