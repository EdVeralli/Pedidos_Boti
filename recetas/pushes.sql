-- @descripcion: Pushes del período: alcance por push (sesiones/usuarios que recibieron el Template) y sesiones abiertas por push. Filtrá con --rulename para una push puntual.
-- @costo: medio
-- @hoja: alcance_por_push
SELECT rule_name,
       COUNT(DISTINCT session_id)               AS sesiones_alcanzadas,
       COUNT(DISTINCT SUBSTR(session_id, 1, 20)) AS usuarios_alcanzados,
       COUNT(DISTINCT id)                        AS mensajes_template
FROM "caba-piba-consume-zone-db"."boti_message_metrics_2"
WHERE {part_ext} AND {rango_creation} AND {cond_rulename} {no_testers}
  AND regexp_like(message, '^Template')
GROUP BY rule_name
ORDER BY sesiones_alcanzadas DESC

-- @hoja: sesiones_abiertas_por_push
SELECT starting_cause_info_value AS push,
       COUNT(DISTINCT session_id) AS sesiones_abiertas
FROM "caba-piba-consume-zone-db"."boti_session_metrics_2"
WHERE {part} {no_testers}
  AND starting_cause = 'WhatsAppTemplate' AND starting_cause_info_name = 'name'
GROUP BY starting_cause_info_value
ORDER BY sesiones_abiertas DESC
