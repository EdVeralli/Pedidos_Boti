-- @descripcion: ¿El botón URL "Inscripción en línea" de la push edu06push02_iel_preinicio_ut_v1 deja registro? Busca eventos user-clicked-url (boti_event_metrics_2) y los cruza con quienes recibieron la push.
-- @costo: alto
-- Uso (UN día; tabla de eventos ~4 GB/día):
--   cd C:\GCBA\Pedidos_Boti
--   python pedido.py sql --archivo pedidos\2026-10_push_EDU04CUX21\control_click_url.sql --desde 2026-10-05 --hasta 2026-10-05

-- @hoja: clicks_receptores
-- URLs clickeadas (user-clicked-url) por personas que recibieron la push, después de recibirla. Si aparece buenosaires.gob.ar/gcaba_historico/educacion/... el botón SÍ deja registro.
WITH p AS (
  SELECT SUBSTR(session_id, 1, 20) AS persona, MIN(creation_time) AS t_push,
         min_by(session_id, creation_time) AS ses_push
  FROM "caba-piba-consume-zone-db"."boti_message_metrics_2"
  WHERE {part_ext} AND {rango_creation} {no_testers}
    AND rule_name = 'edu06push02_iel_preinicio_ut_v1' AND regexp_like(message, '^Template')
  GROUP BY 1
),
c AS (
  SELECT e.session_id, e.creation_time, e.events_info_value AS url
  FROM "caba-piba-consume-zone-db"."boti_event_metrics_2" e
  WHERE {part_ext:e}
    AND e.events_name = 'user-clicked-url' AND e.events_info_name = 'url'
)
SELECT regexp_replace(c.url, '\?.*$', '')                       AS url_sin_parametros,
       IF(c.session_id = p.ses_push, 'sesión de la push', 'otra sesión') AS donde,
       COUNT(DISTINCT p.persona)                                AS personas,
       COUNT(*)                                                 AS clicks,
       MIN(date_diff('minute', p.t_push, c.creation_time))      AS min_minutos_despues
FROM c
JOIN p ON SUBSTR(c.session_id, 1, 20) = p.persona AND c.creation_time > p.t_push
GROUP BY 1, 2
ORDER BY personas DESC
LIMIT 200

-- @hoja: urls_educacion_del_dia
-- Control general: todos los clicks del día a URLs de educación/inscripción (de cualquiera), para ver si ese tipo de link se registra.
SELECT regexp_replace(events_info_value, '\?.*$', '') AS url_sin_parametros,
       COUNT(DISTINCT session_id)                     AS sesiones,
       COUNT(*)                                       AS clicks
FROM "caba-piba-consume-zone-db"."boti_event_metrics_2"
WHERE {part_ext} AND {rango_creation} {no_testers}
  AND events_name = 'user-clicked-url' AND events_info_name = 'url'
  AND regexp_like(lower(events_info_value), 'educacion|inscripcion|inscripción')
GROUP BY 1
ORDER BY sesiones DESC
LIMIT 200
