-- @descripcion: Ranking de rulenames disparados en el período (sin pushes ni vacíos), con tema de Botmaker. Sirve para "qué se consultó más" y para descubrir nombres.
-- @costo: medio
-- @hoja: ranking
SELECT rule_name,
       COUNT(DISTINCT session_id)               AS sesiones,
       COUNT(DISTINCT SUBSTR(session_id, 1, 20)) AS usuarios
FROM "caba-piba-consume-zone-db"."boti_message_metrics_2"
WHERE {part_ext} AND {rango_creation} {no_testers}
  AND rule_name <> '' AND lower(rule_name) NOT LIKE '%push%'
  AND {cond_rulename}
GROUP BY rule_name
ORDER BY sesiones DESC
LIMIT 3000
