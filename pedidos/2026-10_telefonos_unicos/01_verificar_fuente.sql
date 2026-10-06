-- @descripcion: Pedido teléfonos únicos 2026 — paso 1: ver qué campo trae el teléfono (sin bajar números, sólo formatos).
-- Correr sobre UN día: --desde 2026-10-02 --hasta 2026-10-02
-- @hoja: formatos
WITH s AS (
  SELECT session_id, MAX(user_id_on_business) AS uob, MAX(alt_plat_contact_id) AS alt
  FROM "caba-piba-consume-zone-db"."boti_session_metrics_2"
  WHERE {part} AND channel_name = '5491150500147' {no_testers}
  GROUP BY session_id
),
u AS (
  SELECT DISTINCT session_id
  FROM "caba-piba-consume-zone-db"."boti_message_metrics_2"
  WHERE {part} AND msg_from = 'user'
),
v AS (
  SELECT session_id, max_by(vars_value, creation_time) AS rw
  FROM "caba-piba-consume-zone-db"."boti_user_vars_metrics_2"
  WHERE {part} AND vars_name = 'realwhatsappid'
  GROUP BY session_id
),
x AS (
  SELECT s.session_id, s.uob, v.rw,
         CASE WHEN s.uob IS NULL OR s.uob = '' THEN 'vacío'
              WHEN regexp_like(s.uob, '^549\d{10}$') THEN 'celular AR (549 + 10 dígitos)'
              WHEN regexp_like(s.uob, '^\d+$') THEN 'numérico, largo ' || CAST(length(s.uob) AS varchar)
              ELSE 'alfanumérico, largo ' || CAST(length(s.uob) AS varchar) END AS forma_user_id_on_business,
         CASE WHEN v.rw IS NULL OR v.rw = '' THEN 'vacío'
              WHEN regexp_like(v.rw, '^549\d{10}$') THEN 'celular AR (549 + 10 dígitos)'
              WHEN regexp_like(v.rw, '^\d+$') THEN 'numérico, largo ' || CAST(length(v.rw) AS varchar)
              ELSE 'alfanumérico, largo ' || CAST(length(v.rw) AS varchar) END AS forma_realwhatsappid
  FROM s JOIN u ON u.session_id = s.session_id
  LEFT JOIN v ON v.session_id = s.session_id
)
SELECT forma_user_id_on_business, forma_realwhatsappid,
       CASE WHEN uob IS NULL OR rw IS NULL THEN 'falta uno'
            WHEN uob = rw THEN 'iguales' ELSE 'distintos' END AS comparacion,
       COUNT(*) AS sesiones_con_msj_usuario,
       COUNT(DISTINCT SUBSTR(session_id, 1, 20)) AS usuarios
FROM x
GROUP BY 1, 2, 3
ORDER BY sesiones_con_msj_usuario DESC

-- @hoja: numeros_por_usuario
-- ¿Cada usuario de Botmaker tiene un solo número? (cuántos valores distintos por usuario en el día)
WITH s AS (
  SELECT session_id, MAX(user_id_on_business) AS uob
  FROM "caba-piba-consume-zone-db"."boti_session_metrics_2"
  WHERE {part} AND channel_name = '5491150500147' {no_testers}
  GROUP BY session_id
),
v AS (
  SELECT session_id, max_by(vars_value, creation_time) AS rw
  FROM "caba-piba-consume-zone-db"."boti_user_vars_metrics_2"
  WHERE {part} AND vars_name = 'realwhatsappid'
  GROUP BY session_id
),
p AS (
  SELECT SUBSTR(s.session_id, 1, 20) AS usuario,
         COUNT(DISTINCT NULLIF(s.uob, '')) AS uob_distintos,
         COUNT(DISTINCT NULLIF(v.rw, '')) AS rw_distintos
  FROM s LEFT JOIN v ON v.session_id = s.session_id
  GROUP BY 1
)
SELECT uob_distintos, rw_distintos, COUNT(*) AS usuarios
FROM p GROUP BY 1, 2 ORDER BY usuarios DESC
