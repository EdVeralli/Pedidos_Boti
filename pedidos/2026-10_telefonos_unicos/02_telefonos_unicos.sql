-- @descripcion: Pedido teléfonos únicos 2026 — paso 2: un teléfono por fila, de quienes ESCRIBIERON al WhatsApp de Boti (5491150500147), sin testers.
-- Fuente del teléfono: variable realwhatsappid (verificado el 05/10/2026: user_id_on_business viene vacío;
-- realwhatsappid trae el número en ~96% de los usuarios; ~3% de las sesiones no lo tiene y quedan afuera).
-- Correr con: --desde 2026-01-01 --hasta <ayer>.  Costo estimado: ~230 GB (~US$ 1,2) por la tabla de variables.
-- @hoja: telefonos
WITH s AS (
  SELECT DISTINCT session_id
  FROM "caba-piba-consume-zone-db"."boti_session_metrics_2"
  WHERE {part} AND {rango_sesion} AND channel_name = '5491150500147' {no_testers}
),
u AS (
  SELECT session_id, MIN(creation_time) AS primer_msj
  FROM "caba-piba-consume-zone-db"."boti_message_metrics_2"
  WHERE {part} AND msg_from = 'user'
  GROUP BY session_id
),
v AS (
  SELECT session_id, max_by(vars_value, creation_time) AS telefono
  FROM "caba-piba-consume-zone-db"."boti_user_vars_metrics_2"
  WHERE {part} AND vars_name = 'realwhatsappid' AND vars_value IS NOT NULL AND vars_value <> ''
  GROUP BY session_id
)
SELECT v.telefono,
       IF(regexp_like(v.telefono, '^549\d{10}$'), 'celular AR', 'otro formato') AS formato,
       CAST(MIN(u.primer_msj) AS DATE) AS primera_fecha,
       CAST(MAX(u.primer_msj) AS DATE) AS ultima_fecha,
       COUNT(*) AS sesiones
FROM s
JOIN u ON u.session_id = s.session_id
JOIN v ON v.session_id = s.session_id
GROUP BY v.telefono
