-- @descripcion: EXPERIMENTAL. Estados de notificación (sent/delivered/read/error/answered) por plantilla, desde la tabla de eventos. Tabla cara: usar rangos cortos.
-- @costo: alto
-- @hoja: estados_por_template
SELECT e.events_info_name AS campo, e.events_info_value AS template, e.events_name AS estado,
       COUNT(DISTINCT e.session_id) AS sesiones,
       COUNT(*) AS filas
FROM "caba-piba-consume-zone-db"."boti_event_metrics_2" e
WHERE {part_ext:e} AND {rango_creation:e} {no_testers:e}
  AND e.events_name LIKE 'notification-status-%'
  AND e.events_info_name IN ('templateName', 'notification_name')
GROUP BY e.events_info_name, e.events_info_value, e.events_name
ORDER BY template, estado

-- @hoja: estados_total
SELECT events_name AS estado, COUNT(DISTINCT session_id) AS sesiones
FROM "caba-piba-consume-zone-db"."boti_event_metrics_2"
WHERE {part_ext} AND {rango_creation} {no_testers}
  AND events_name LIKE 'notification-status-%'
GROUP BY events_name
ORDER BY sesiones DESC
