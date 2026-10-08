-- @descripcion: Push edu06push02_iel_preinicio_ut_v1: personas que llegaron a EDU04CUX21 (Inscripción escolar) DESPUÉS de recibir la push, en cualquier sesión.
-- @costo: medio
-- persona = SUBSTR(session_id, 1, 20). Llegó = mensaje del bot con rule_name LIKE 'EDU04CUX21%' posterior a la push. Fechas UTC. Testers excluidos.

-- @hoja: resumen
WITH p AS (
  SELECT SUBSTR(session_id, 1, 20) AS persona, MIN(creation_time) AS t_push,
         min_by(session_id, creation_time) AS ses_push
  FROM "caba-piba-consume-zone-db"."boti_message_metrics_2"
  WHERE {part_ext} AND {rango_creation} {no_testers}
    AND rule_name = 'edu06push02_iel_preinicio_ut_v1' AND regexp_like(message, '^Template')
  GROUP BY 1
),
e AS (
  SELECT p.persona, p.t_push,
         MIN(m.creation_time)                     AS t_edu,
         MAX(IF(m.session_id = p.ses_push, 1, 0)) AS en_sesion_push
  FROM p
  JOIN "caba-piba-consume-zone-db"."boti_message_metrics_2" m
    ON SUBSTR(m.session_id, 1, 20) = p.persona
   AND m.creation_time > p.t_push
  WHERE {part_ext:m} AND m.rule_name LIKE 'EDU04CUX21%'
  GROUP BY 1, 2
)
SELECT (SELECT COUNT(*) FROM p)                              AS recibieron_push,
       COUNT(*)                                              AS llegaron_edu04cux21,
       ROUND(100.0 * COUNT(*) / (SELECT COUNT(*) FROM p), 2) AS pct,
       COUNT_IF(en_sesion_push = 1)                          AS llegaron_en_la_sesion_de_la_push,
       COUNT_IF(en_sesion_push = 0)                          AS llegaron_solo_en_otra_sesion,
       COUNT_IF(date_diff('minute', t_push, t_edu) <= 60)    AS llegaron_1h,
       COUNT_IF(date_diff('minute', t_push, t_edu) <= 1440)  AS llegaron_24h
FROM e

-- @hoja: por_dia
WITH p AS (
  SELECT SUBSTR(session_id, 1, 20) AS persona, MIN(creation_time) AS t_push
  FROM "caba-piba-consume-zone-db"."boti_message_metrics_2"
  WHERE {part_ext} AND {rango_creation} {no_testers}
    AND rule_name = 'edu06push02_iel_preinicio_ut_v1' AND regexp_like(message, '^Template')
  GROUP BY 1
),
e AS (
  SELECT p.persona, MIN(m.creation_time) AS t_edu
  FROM p
  JOIN "caba-piba-consume-zone-db"."boti_message_metrics_2" m
    ON SUBSTR(m.session_id, 1, 20) = p.persona AND m.creation_time > p.t_push
  WHERE {part_ext:m} AND m.rule_name LIKE 'EDU04CUX21%'
  GROUP BY 1
)
SELECT CAST(t_edu AS DATE) AS dia_utc, COUNT(*) AS personas
FROM e GROUP BY 1 ORDER BY 1

-- @hoja: entrada
WITH p AS (
  SELECT SUBSTR(session_id, 1, 20) AS persona, MIN(creation_time) AS t_push
  FROM "caba-piba-consume-zone-db"."boti_message_metrics_2"
  WHERE {part_ext} AND {rango_creation} {no_testers}
    AND rule_name = 'edu06push02_iel_preinicio_ut_v1' AND regexp_like(message, '^Template')
  GROUP BY 1
),
e AS (
  SELECT p.persona,
         min_by(m.rule_name, m.creation_time) AS primer_rulename,
         min_by(COALESCE(regexp_extract(m.original_user_message, '"button":"([^"]*)"', 1),
                         SUBSTR(lower(trim(m.original_user_message)), 1, 50), '(sin dato)'),
                m.creation_time)               AS que_toco_o_escribio
  FROM p
  JOIN "caba-piba-consume-zone-db"."boti_message_metrics_2" m
    ON SUBSTR(m.session_id, 1, 20) = p.persona AND m.creation_time > p.t_push
  WHERE {part_ext:m} AND m.rule_name LIKE 'EDU04CUX21%'
  GROUP BY 1
)
SELECT primer_rulename, que_toco_o_escribio, COUNT(*) AS personas
FROM e GROUP BY 1, 2 ORDER BY personas DESC
LIMIT 300