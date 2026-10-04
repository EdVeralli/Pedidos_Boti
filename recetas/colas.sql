-- @descripcion: Atención humana: sesiones DERIVADAS (evento queue-assigned) por cola y canal, cuántas atendió un operador y cuánto esperaron. La columna queue de mensajes NO indica derivación. Usa la tabla de eventos (~6 GB por día): rangos cortos.
-- @costo: alto
-- @hoja: por_cola
WITH q AS (
  SELECT e.session_id, MIN(e.creation_time) AS t_cola,
         max_by(e.events_info_value, e.creation_time) AS cola
  FROM "caba-piba-consume-zone-db"."boti_event_metrics_2" e
  WHERE {part_ext:e} AND {rango_creation:e} {no_testers:e}
    AND e.events_name = 'queue-assigned' AND e.events_info_name = 'queue'
  GROUP BY e.session_id
),
o AS (
  SELECT m.session_id, MIN(m.creation_time) AS t_operador, COUNT(DISTINCT m.id) AS msjs_operador
  FROM "caba-piba-consume-zone-db"."boti_message_metrics_2" m
  WHERE {part_ext:m} AND m.msg_from = 'operator'
  GROUP BY m.session_id
),
s AS (
  SELECT session_id, MAX(channel_name) AS channel_name
  FROM "caba-piba-consume-zone-db"."boti_session_metrics_2"
  WHERE {part_ext}
  GROUP BY session_id
)
SELECT q.cola, s.channel_name AS canal,
       COUNT(*)                                   AS sesiones_derivadas,
       COUNT(DISTINCT SUBSTR(q.session_id, 1, 20)) AS usuarios_derivados,
       COUNT(o.session_id)                        AS atendidas_por_operador,
       ROUND(100.0 * COUNT(o.session_id) / COUNT(*), 1) AS pct_atendidas,
       approx_percentile(IF(o.t_operador >= q.t_cola, date_diff('minute', q.t_cola, o.t_operador)), 0.5) AS min_espera_p50,
       approx_percentile(IF(o.t_operador >= q.t_cola, date_diff('minute', q.t_cola, o.t_operador)), 0.9) AS min_espera_p90,
       approx_percentile(o.msjs_operador, 0.5)    AS msjs_operador_p50
FROM q
LEFT JOIN o ON o.session_id = q.session_id
LEFT JOIN s ON s.session_id = q.session_id
WHERE TRUE {cond_canal:s}
GROUP BY q.cola, s.channel_name
ORDER BY sesiones_derivadas DESC

-- @hoja: por_dia
WITH q AS (
  SELECT e.session_id, MIN(e.creation_time) AS t_cola,
         max_by(e.events_info_value, e.creation_time) AS cola
  FROM "caba-piba-consume-zone-db"."boti_event_metrics_2" e
  WHERE {part_ext:e} AND {rango_creation:e} {no_testers:e}
    AND e.events_name = 'queue-assigned' AND e.events_info_name = 'queue'
  GROUP BY e.session_id
),
o AS (
  SELECT DISTINCT m.session_id
  FROM "caba-piba-consume-zone-db"."boti_message_metrics_2" m
  WHERE {part_ext:m} AND m.msg_from = 'operator'
)
SELECT CAST(q.t_cola AS DATE) AS fecha, q.cola,
       COUNT(*) AS sesiones_derivadas, COUNT(o.session_id) AS atendidas_por_operador
FROM q LEFT JOIN o ON o.session_id = q.session_id
GROUP BY CAST(q.t_cola AS DATE), q.cola
ORDER BY fecha, sesiones_derivadas DESC
