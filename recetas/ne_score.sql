-- @descripcion: No entendidos por score insuficiente (max score <= 5.36 en el modelo de IA): por día y mensajes.
-- @costo: bajo
-- @hoja: por_dia
WITH b AS (
  SELECT id, MIN(ts) AS ts, MAX(results_score) AS max_score
  FROM "caba-piba-consume-zone-db"."boti_intent_search"
  WHERE {part} AND {rango_ts} {no_testers}
    AND rule_id = 'PLBWX5XYGQ2B3GP7IN8Q-6e5jiocf03@b.m-1688135541169'
    AND message IS NOT NULL AND message_id <> '' AND NOT regexp_like(message, '"button":')
  GROUP BY id
)
SELECT CAST(ts AS DATE) AS fecha,
       COUNT(*) AS busquedas,
       COUNT_IF(max_score <= 5.36) AS ne_score,
       ROUND(100.0 * COUNT_IF(max_score <= 5.36) / COUNT(*), 2) AS pct_ne
FROM b
GROUP BY CAST(ts AS DATE)
ORDER BY fecha

-- @hoja: mensajes_ne
SELECT lower(trim(message)) AS mensaje, COUNT(DISTINCT id) AS veces
FROM (
  SELECT id, MAX(message) AS message, MAX(results_score) AS max_score
  FROM "caba-piba-consume-zone-db"."boti_intent_search"
  WHERE {part} AND {rango_ts} {no_testers}
    AND rule_id = 'PLBWX5XYGQ2B3GP7IN8Q-6e5jiocf03@b.m-1688135541169'
    AND message IS NOT NULL AND message_id <> '' AND NOT regexp_like(message, '"button":')
  GROUP BY id
) t
WHERE max_score <= 5.36
GROUP BY lower(trim(message))
ORDER BY veces DESC
LIMIT 2000
