-- @descripcion: Encuesta CXF (efectividad, esfuerzo, satisfacción, sugerencia) de las sesiones que pasaron por un flujo. Incluye "Ni fácil ni difícil" (CATs), a diferencia de CEDETAC.
-- @requiere: rulename
-- @costo: medio
-- @hoja: respuestas
-- @resumen: efectividad, esfuerzo, satisfaccion
WITH flujo AS (
  SELECT DISTINCT session_id
  FROM "caba-piba-consume-zone-db"."boti_message_metrics_2"
  WHERE {part_ext} AND {rango_creation} AND {cond_rulename} {no_testers}
),
cxf AS (
  SELECT m.session_id,
         MIN(CAST(m.session_creation_time AS DATE)) AS fecha,
         MAX(CASE WHEN regexp_like(m.rule_name, '^CXF01CUX0[1-4] (S.|No)( avisos)? [A-Z]') THEN m.rule_name END) AS efectividad_regla,
         MAX(CASE WHEN regexp_like(m.rule_name, '^CXF01CUX0[1-4] (Muy f.cil|F.cil|M.s o menos|Ni f.cil ni dif.cil|Dif.cil|Muy dif.cil) ') THEN m.rule_name END) AS esfuerzo_regla,
         MAX(CASE WHEN regexp_like(m.rule_name, '^CXF01CUX0[1-4] (Muy conforme|Conforme|Inconforme|Muy inconforme|No s.) ') THEN m.rule_name END) AS satisfaccion_regla
  FROM "caba-piba-consume-zone-db"."boti_message_metrics_2" m
  JOIN flujo f ON m.session_id = f.session_id
  WHERE {part_ext:m} AND m.rule_name LIKE 'CXF01CUX0%'
  GROUP BY m.session_id
),
sug AS (
  SELECT v.session_id,
         MAX(CASE WHEN v.vars_name IN ('sugerenciacxf', 'sugerencianps') AND v.vars_value <> 'Cancelar' THEN v.vars_value END) AS sugerencia
  FROM "caba-piba-consume-zone-db"."boti_user_vars_metrics_2" v
  JOIN flujo f ON v.session_id = f.session_id
  WHERE {part_ext:v} AND v.vars_name IN ('sugerenciacxf', 'sugerencianps')
  GROUP BY v.session_id
)
SELECT c.fecha, c.session_id,
       regexp_replace(c.efectividad_regla,  '^CXF01CUX0[1-4] (.*?) ?(Integraciones|Est.ticos|Pushes|CATs) *$', '$1') AS efectividad,
       COALESCE(regexp_replace(c.esfuerzo_regla,     '^CXF01CUX0[1-4] (.*?) ?(Integraciones|Est.ticos|Pushes|CATs) *$', '$1'), 'Sin Datos') AS esfuerzo,
       COALESCE(regexp_replace(c.satisfaccion_regla, '^CXF01CUX0[1-4] (.*?) ?(Integraciones|Est.ticos|Pushes|CATs) *$', '$1'), 'Sin Datos') AS satisfaccion,
       s.sugerencia,
       regexp_extract(COALESCE(c.efectividad_regla, c.esfuerzo_regla, c.satisfaccion_regla), '(Integraciones|Est.ticos|Pushes|CATs)') AS categoria_cxf,
       CONCAT('https://go.botmaker.com/#/chats/', SUBSTR(c.session_id, 1, 20)) AS link
FROM cxf c
LEFT JOIN sug s ON c.session_id = s.session_id
WHERE c.efectividad_regla IS NOT NULL OR c.esfuerzo_regla IS NOT NULL OR c.satisfaccion_regla IS NOT NULL
ORDER BY c.fecha
