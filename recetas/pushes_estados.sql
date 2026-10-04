-- @descripcion: Embudo de pushes desde eventos: sesiones enviadas / entregadas / leídas / con error por push. El nombre viene en templateName (en los errores, en template); se descarta el valor que es un ID. Tabla de eventos (~4 GB por día): rangos cortos.
-- @costo: alto
-- @hoja: embudo_por_push
-- Ojo: en ~16% de los envíos templateName sólo trae el ID, así que "enviadas" queda algo por debajo
-- de las sesiones abiertas por push (receta pushes). La mayoría de los errores no trae el nombre: ver hoja errores.
WITH ev AS (
  SELECT e.session_id, e.events_name, e.events_info_value AS rule_name
  FROM "caba-piba-consume-zone-db"."boti_event_metrics_2" e
  WHERE {part_ext:e} AND {rango_creation:e} {no_testers:e}
    AND e.events_name LIKE 'notification-status-%'
    AND e.events_info_name IN ('templateName', 'template')
    AND NOT regexp_like(e.events_info_value, '^[A-Za-z0-9]{20}$')
),
p AS (
  SELECT rule_name AS push,
         COUNT(DISTINCT IF(events_name = 'notification-status-sent', session_id))      AS enviadas,
         COUNT(DISTINCT IF(events_name = 'notification-status-delivered', session_id)) AS entregadas,
         COUNT(DISTINCT IF(events_name = 'notification-status-read', session_id))      AS leidas,
         COUNT(DISTINCT IF(events_name = 'notification-status-error', session_id))     AS con_error
  FROM ev
  WHERE {cond_rulename}
  GROUP BY rule_name
)
SELECT push, enviadas, entregadas, leidas, con_error,
       ROUND(100.0 * entregadas / NULLIF(enviadas, 0), 1) AS pct_entregadas,
       ROUND(100.0 * leidas / NULLIF(enviadas, 0), 1)     AS pct_leidas
FROM p
ORDER BY enviadas DESC

-- @hoja: errores
-- Motivo normalizado: código de WhatsApp/Meta + texto sin IDs (fbtrace, columna). La push sale del campo
-- template o, si falta, del texto del error ("template name (x)" / "WhatsApp template [x]").
WITH er AS (
  SELECT e.session_id, e.creation_time,
         MAX(IF(e.events_info_name = 'template', e.events_info_value)) AS push,
         MAX(IF(e.events_info_name = 'reason', e.events_info_value))   AS motivo
  FROM "caba-piba-consume-zone-db"."boti_event_metrics_2" e
  WHERE {part_ext:e} AND {rango_creation:e} {no_testers:e}
    AND e.events_name = 'notification-status-error'
    AND e.events_info_name IN ('template', 'reason')
  GROUP BY e.session_id, e.creation_time
), n AS (
  SELECT session_id,
         COALESCE(push,
                  regexp_extract(motivo, 'template name \(([^)]+)\)', 1),
                  regexp_extract(motivo, 'WhatsApp template \[([^\]]+)\]', 1),
                  '(sin nombre)') AS push,
         COALESCE(regexp_extract(motivo, '"code":(\d+)', 1),
                  regexp_extract(motivo, '\((\d{5,6})(\.0)?\)', 1), '') AS codigo,
         SUBSTR(regexp_replace(regexp_replace(regexp_replace(COALESCE(motivo, '(sin motivo)'),
                '"fbtrace_id":"[^"]*",?', ''), 'column: \d+', 'column: N'), '\s+', ' '), 1, 180) AS motivo
  FROM er
)
SELECT push, codigo, motivo, COUNT(DISTINCT session_id) AS sesiones, COUNT(*) AS errores
FROM n
GROUP BY 1, 2, 3
ORDER BY sesiones DESC
LIMIT 2000

-- @hoja: estados_total
SELECT events_name AS estado, COUNT(DISTINCT session_id) AS sesiones
FROM "caba-piba-consume-zone-db"."boti_event_metrics_2"
WHERE {part_ext} AND {rango_creation} {no_testers}
  AND events_name LIKE 'notification-status-%'
GROUP BY events_name
ORDER BY sesiones DESC
