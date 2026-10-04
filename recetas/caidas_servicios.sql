-- @descripcion: HEURISTICO (revisar hoja reglas_de_error: no todo error es caida). Sesiones que entran a un trámite con integración y después reciben una regla de error (lógica de boti_vw_v1_problemas_servicios, con el rango pedido).
-- @costo: medio
-- @hoja: por_dia
WITH base AS (
  SELECT session_id, rule_name, creation_time
  FROM "caba-piba-consume-zone-db"."boti_message_metrics_2"
  WHERE {part_ext} AND {rango_creation} AND message_type = 'Text' AND msg_from = 'bot' {no_testers}
),
entrada AS (
  SELECT session_id, MIN(creation_time) AS t_entrada, MIN_BY(rule_name, creation_time) AS rule_entrada
  FROM base
  WHERE NOT regexp_like(lower(rule_name), 'error|servicio ca')
    AND regexp_like(rule_name, '^(MIBA01CUX02|MO05CUX0[18]|MO05CUX10|MO06CUX02|SE06CUX01|SUA01CUX|TUR01CUX0[358])')
  GROUP BY session_id
),
error AS (
  SELECT session_id, MIN(creation_time) AS t_error, MIN_BY(rule_name, creation_time) AS rule_error
  FROM base
  WHERE regexp_like(lower(rule_name), 'error|servicio ca') AND NOT regexp_like(lower(rule_name), 'duplicad')
  GROUP BY session_id
)
SELECT CAST(e.t_entrada AS DATE) AS fecha, e.rule_entrada, r.rule_error,
       COUNT(DISTINCT e.session_id) AS sesiones_con_error
FROM entrada e JOIN error r ON e.session_id = r.session_id AND r.t_error > e.t_entrada
GROUP BY CAST(e.t_entrada AS DATE), e.rule_entrada, r.rule_error
ORDER BY fecha, sesiones_con_error DESC

-- @hoja: reglas_de_error
SELECT rule_name, COUNT(DISTINCT session_id) AS sesiones
FROM "caba-piba-consume-zone-db"."boti_message_metrics_2"
WHERE {part_ext} AND {rango_creation} {no_testers}
  AND regexp_like(lower(rule_name), 'error|servicio ca')
GROUP BY rule_name
ORDER BY sesiones DESC
