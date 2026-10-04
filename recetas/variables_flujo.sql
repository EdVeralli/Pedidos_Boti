-- @descripcion: Variables que se setean en las sesiones de un flujo (nombre, valor, sesiones). Con --variable se limita a esas variables.
-- @requiere: rulename
-- @costo: medio
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
