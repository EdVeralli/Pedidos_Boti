-- @descripcion: Disparos de uno o varios rulenames (LIKE): total, serie diaria y links a conversaciones.
-- @requiere: rulename
-- @costo: medio
-- @hoja: por_rulename
SELECT rule_name,
       COUNT(DISTINCT session_id)               AS sesiones,
       COUNT(DISTINCT SUBSTR(session_id, 1, 20)) AS usuarios,
       COUNT(*)                                  AS disparos
FROM "caba-piba-consume-zone-db"."boti_message_metrics_2"
WHERE {part_ext} AND {rango_creation} AND {cond_rulename} {no_testers}
GROUP BY rule_name
ORDER BY sesiones DESC

-- @hoja: por_dia
SELECT CAST(creation_time AS DATE) AS fecha, rule_name,
       COUNT(DISTINCT session_id)  AS sesiones
FROM "caba-piba-consume-zone-db"."boti_message_metrics_2"
WHERE {part_ext} AND {rango_creation} AND {cond_rulename} {no_testers}
GROUP BY CAST(creation_time AS DATE), rule_name
ORDER BY fecha, sesiones DESC

-- @hoja: links
SELECT session_id,
       MIN(creation_time) AS primer_disparo_utc,
       array_join(array_agg(DISTINCT rule_name), ' | ') AS rulenames,
       CONCAT('https://go.botmaker.com/#/chats/', SUBSTR(session_id, 1, 20)) AS link
FROM "caba-piba-consume-zone-db"."boti_message_metrics_2"
WHERE {part_ext} AND {rango_creation} AND {cond_rulename} {no_testers}
GROUP BY session_id
ORDER BY primer_disparo_utc DESC
LIMIT 3000
