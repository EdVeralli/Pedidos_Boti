# Pedido: teléfonos únicos de quienes usaron Boti (05/10/2026 y 09/10/2026)

**Pedido:** la lista de números de teléfono de la gente que se contactó con Boti por WhatsApp.
Primero pidieron **2026**; después, **2025** solo.
**Contacto** = la persona mandó algo (texto, audio, imagen, o tocó un botón, incluso respondiendo una push).
Canal `5491150500147`. Testers excluidos.

## De dónde sale el teléfono

De la variable **`realwhatsappid`** de `boti_user_vars_metrics_2`, tomando el último valor de cada
sesión con `max_by(vars_value, creation_time)`.

Lo que **no** sirve, y conviene no volver a probarlo:

| Candidato | Por qué no |
|---|---|
| `boti_session_metrics_2.user_id_on_business` | Viene **vacío en el 100%** de las sesiones. Verificado en 2026 y en dos días de 2025 |
| `SUBSTR(session_id, 1, 20)` | Es el id interno de usuario de Botmaker. Sirve para **contar** usuarios (lo usa `Usuarios_Conversaciones.py`), pero no es el teléfono |

## Cobertura: la lista NO es el universo completo

Un porcentaje de la gente que escribió no tiene `realwhatsappid` registrado y queda afuera.
Medido sobre un día entero, usuarios con mensaje propio:

| Día | Con teléfono | Cobertura |
|---|---:|---:|
| 15/01/2025 | 30.473 de 33.177 | 91,8% |
| 05/03/2025 | 54.174 de 58.251 | 93,0% |
| 02/10/2026 | 48.970 de 50.962 | 96,1% |

El registro mejoró con el tiempo. **Aclararlo siempre al entregar**: es el universo de usuarios
*con número registrado*, no el total de usuarios.

Control de unicidad: ningún usuario tiene dos números distintos en el mismo día
(hoja `numeros_por_usuario`, columna `rw_distintos` siempre 0 o 1).

## Resultados entregados

| Período | Teléfonos únicos | Corrida | GB | Carpeta de salida |
|---|---:|---|---:|---|
| 01/01/2026 – 04/10/2026 | 2.051.840 | 05/10 15:05, 41 s | 222 | `output\20261005_150421_sql\` |
| 01/01/2025 – 31/12/2025 | 2.090.880 | 09/10 10:58, 66 s | 222 | `output\20261009_105721_sql\` |

2025 por formato: 2.075.983 celulares AR válidos (99,3%, 14.055.741 sesiones) y 14.897 de otro
formato (0,7%, 34.157 sesiones — largos de 8 a 13 dígitos, promedian 2,3 sesiones contra 6,8 los
válidos). **Si el destino es una campaña, filtrar por la columna `formato`.**

## Cómo se corre

```powershell
cd C:\GCBA\Pedidos_Boti

# Paso 1 — verificar la fuente en un día del período (≈1 GB). Mirar formatos.csv.
python pedido.py sql --archivo pedidos\2026-10_telefonos_unicos\01_verificar_fuente.sql --desde 2025-03-05 --hasta 2025-03-05

# Paso 2 — el año completo (≈222 GB, ≈US$ 1,1)
python pedido.py sql --archivo pedidos\2026-10_telefonos_unicos\02_telefonos_unicos.sql --desde 2025-01-01 --hasta 2025-12-31
```

El paso 1 no es opcional para un período nuevo: si la variable no existía o el `channel_name`
cambió, la lista sale corta **sin ningún error que lo avise**.

| Archivo | Para qué |
|---|---|
| `01_verificar_fuente.sql` | Qué campo trae el teléfono y con qué cobertura. Solo formatos y conteos, no baja números |
| `02_telefonos_unicos.sql` | La lista: teléfono, formato, primera y última fecha, sesiones |
| `consulta_athena_consola.sql` | Lo mismo para pegar en la consola de Athena (testers en línea, fechas fijas de 2026) |
| `consulta_athena_solo_telefonos.sql` | Igual, pero una sola columna |

## Para ver la variable en pocos registros

```sql
SELECT session_id, vars_value AS telefono, creation_time
FROM "caba-piba-consume-zone-db"."boti_user_vars_metrics_2"
WHERE year = '2026' AND month = '10' AND CAST(day AS INTEGER) = 2
  AND vars_name = 'realwhatsappid' AND vars_value <> ''
LIMIT 20
```

## Lo que salió mal en el camino (no repetir)

1. **Las particiones son strings sin ceros a la izquierda.** Va `month = '10'` pero el día con
   `CAST(day AS INTEGER) = 2`, no `day = '02'`. Con `'02'` no trae nada y parece que no hay datos.
2. **La lista no entra en el Excel.** Dos millones de filas: `pedido.py` avisa
   `Hoja telefonos tiene N filas: sólo va al CSV` y deja el `.xlsx` sin esa hoja. **El entregable
   es el CSV.** Si solo piden el número, se saca la columna del CSV con Python, sin volver a Athena.
3. **Los testers que se excluyen son los actuales.** Para períodos viejos puede haber testers que
   ya no están en `config\testers.csv` y entran a la lista.

## Datos personales

`output\` está en `.gitignore`: los CSV con los teléfonos **nunca** se suben, y este repo es
público. Acá se versiona el método, no los números. Antes de mandar una lista, acordar con quien
la pidió cómo la quiere recibir: son millones de teléfonos de vecinos y un archivo de 100 MB no
pasa por una casilla de mail.
