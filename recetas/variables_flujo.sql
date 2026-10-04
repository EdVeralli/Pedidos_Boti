-- @descripcion: Variables seteadas en las sesiones de un flujo: resumen por variable y detalle nombre/valor. Las variables de usuario arrastran valores de otras sesiones; para el detalle conviene --variable.
-- @requiere: rulename
-- @costo: medio
-- @hoja: resumen
WITH flujo AS (
  SELECT DISTINCT session_id
  FROM "caba-piba-consume-zone-db"."boti_message_metrics_2"
  WHERE {part_ext} AND {rango_creation} AND {cond_rulename} {no_testers}
)
SELECT v.vars_name,
       COUNT(DISTINCT v.session_id) AS sesiones,
       COUNT(DISTINCT v.vars_value) AS valores_distintos,
       MAX(v.vars_value) AS ejemplo_valor
FROM "caba-piba-consume-zone-db"."boti_user_vars_metrics_2" v
JOIN flujo f ON v.session_id = f.session_id
WHERE {part_ext:v} {cond_variable:v}
GROUP BY v.vars_name
ORDER BY sesiones DESC

-- @hoja: variables
WITH flujo AS (
  SELECT DISTINCT session_id
  FROM "caba-piba-consume-zone-db"."boti_message_metrics_2"
  WHERE {part_ext} AND {rango_creation} AND {cond_rulename} {no_testers}
)
SELECT v.vars_name, v.vars_value, COUNT(DISTINCT v.session_id) AS sesiones
FROM "caba-piba-consume-zone-db"."boti_user_vars_metrics_2" v
JOIN flujo f ON v.session_id = f.session_id
WHERE {part_ext:v} {cond_variable:v}
GROUP BY v.vars_name, v.vars_value
ORDER BY v.vars_name, sesiones DESC
LIMIT 20000
