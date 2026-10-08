# Pedidos_Boti — caja de herramientas para pedidos "voladores" de Boti (AWS Athena)

> Referencia completa de tablas, reglas y trampas: `C:\GCBA\Documentacion\BOTI_AWS_Referencia.md`.
> Acá está lo práctico: cómo resolver un pedido nuevo en minutos.

## Estado

- Repo: https://github.com/EdVeralli/Pedidos_Boti (público).
- Validado: las 57 consultas que generan las recetas parsean con un parser de SQL Trino; ejecución completa simulada (Excel, resúmenes, embudo, `--probar`); `buscar_reglas.py` probado con el TSV real (cp1252).
- ✅ **04/10/2026: `--probar` contra Athena real, 15/15 recetas OK** (día 02/10/2026, ~5,6 GB escaneados en total). Bug corregido: `wr.s3.read_csv` recibía la ruta como prefijo y leía también el `.csv.metadata` binario (filas basura / error `0xFF`); ahora se pasa como lista.
- Costos de referencia por 1 día: la mayoría 100–300 MB; `feedback_flujo` y `variables_flujo` ~1,2–1,4 GB (leen vars); `rastreo_persona` ~0,8 GB.
- `caidas_servicios` es heurístico; `ne_score` no es el D13; `pushes_estados` y `colas` se rehicieron el 04/10 con lo medido en `mapa_pendientes.py` (eventos; la columna `queue` no indica derivación) y falta probarlas.
- Historial del relevamiento y decisiones: `C:\GCBA\Documentacion\BOTI_AWS_Referencia.md` (sección "Estado de este documento").

## Requisitos (una vez)

- Python 3.10+ (Anaconda) con `boto3`, `awswrangler`, `pandas`, `openpyxl` (los mismos que `Metricas_Boti_Mensual`).
- `aws-azure-login` configurado en el profile `default` con el rol **PIBADataScientist**.
- `config\testers.csv` (copia de `Metricas_Boti_Mensual\No_Entendidos\testers.csv`).
- Un `rules-*.tsv` reciente (export de Botmaker). Se busca en `config\`, `Metricas_Boti_Mensual\Contenidos_Bot\` y `\Contenidos_mas_disparados\`; se usa el de fecha más nueva.

El login se pide solo: si no hay credenciales válidas (o vencen a mitad de camino), el programa muestra el comando
`aws-azure-login --profile default --mode=gui` para correr en otra terminal y espera ENTER.

## Cómo atender un pedido en 5 pasos

1. **Precisar el pedido:** objetivo (qué pregunta hay que responder), contenido/flujo, fechas desde–hasta, desglose (total, diario, por canal…) y fecha de entrega.
2. **Ubicar los contenidos sin gastar Athena:**
   ```powershell
   cd C:\GCBA\Pedidos_Boti
   python buscar_reglas.py "licencia"
   ```
   Devuelve rulenames, carpeta, si están activos y los prefijos CUX/CAT para usar en `--rulename "PREFIJO%"`.
3. **Elegir la receta** (tabla de abajo). Si dudás, `python pedido.py --lista`.
4. **Correrla:**
   ```powershell
   cd C:\GCBA\Pedidos_Boti
   python pedido.py flujo --mes 2026-09 --rulename "MO05CUX02%"
   ```
5. **Controlar antes de entregar:** abrir 2–3 links de conversaciones, comparar con el mes anterior, mirar la hoja `parametros` (rango, testers, MB escaneados).

Cada corrida deja `output\<fecha_hora>_<receta>\` con: `<receta>.xlsx` (una hoja por resultado + `parametros`), un CSV por hoja, `consulta.sql` (el SQL exacto que se ejecutó) y `log.txt`.

## Qué receta usar

| Te piden… | Receta | Ejemplo |
|---|---|---|
| Cuántas sesiones / usuarios hubo (total, por día, por canal, por origen push/orgánico) | `sesiones` | `python pedido.py sesiones --mes 2026-09` · `--canal "BAX - App"` |
| Cuántas veces se usó un contenido / flujo / trámite, y links para leer charlas | `flujo` | `--rulename "SUA01CUX04%"` (repetible) |
| Cuánta gente llega del paso A al B al C | `embudo` | `--rulename "X Apertura" --rulename "X Paso 2%" --rulename "X Éxito"` |
| Qué escribe la gente sobre un tema | `mensajes` | `--texto "dengue|vacuna"` (regex, minúsculas) |
| Qué escribió/tocó la gente para llegar a un contenido | `que_escribieron` | `--rulename "SUA01CUX04 Apertura"` |
| Lo más consultado del período | `top_rulenames` | `python pedido.py top_rulenames --mes 2026-09` (opcional `--rulename "SA%"`) |
| Resultado de pushes (alcance, sesiones abiertas) | `pushes` | `--rulename "sa01push%"` |
| Entregadas / leídas / con error por push (embudo desde eventos) | `pushes_estados` ($$$) | rango corto: `--dias 3` · `--rulename "sa01push%"` |
| Cuánta gente **respondió** a una push (por persona, en cualquier sesión; 1 h / 24 h / 72 h) y qué respondió | `push_respuesta` | `--dias 7 --rulename "edu06push02_iel%"` |
| Feedback (efectividad, esfuerzo, satisfacción, sugerencias) de un flujo | `feedback_flujo` | `--rulename "%SA01CAT01%"` |
| Datos que dejó la gente en un flujo (variables) | `variables_flujo` | `--rulename "TUR01CUX06%" --variable fechaturno` |
| Atención humana: derivadas por cola (evento `queue-assigned`), atendidas por operador, espera | `colas` ($$$) | rango corto: `--dias 7` · `--canal 5491150500147` |
| Encontrar las charlas de una persona (área pide por DNI/mail) | `rastreo_persona` | `--texto "12345678|nombre@mail.com" --dias 30` |
| Cómo respondió el buscador del Boti clásico (one-shots, menús; no es BAX) | `ia_respuestas` | `--mes 2026-09` |
| No entendidos por score | `ne_score` | `--dias 14` |
| Fallas de integraciones (trámites que terminan en error) | `caidas_servicios` | `--dias 31` |
| Sesiones sin respuesta del usuario | `sesiones_fantasma` | `--mes 2026-09` |
| Algo que no está en ninguna receta | `sql` | `python pedido.py sql --archivo mi.sql --mes 2026-09` |

Período: `--desde AAAA-MM-DD --hasta AAAA-MM-DD`, o `--mes AAAA-MM`, o `--dias N` (últimos N días cerrados).
Otras opciones: `--con-testers` (no excluirlos), `--solo-sql` (genera el SQL sin ejecutarlo).

## Escribir una consulta propia (`sql`) o una receta nueva

Un `.sql` con estos marcadores (alias opcional: `{part:m}`):

| Marcador | Se reemplaza por |
|---|---|
| `{part}` | particiones `year/month/day` del rango (= fecha UTC de la sesión) |
| `{part_ext}` | ídem + 1 día (usar cuando se mide por `creation_time`) |
| `{rango_creation}` / `{rango_sesion}` / `{rango_ts}` | `CAST(col AS DATE) BETWEEN desde AND hasta` |
| `{no_testers}` | `AND SUBSTR(session_id,1,20) NOT IN (…234 IDs…)` |
| `{cond_rulename}` | `(rule_name LIKE '…' OR …)` con los `--rulename` |
| `{cond_canal}` / `{cond_variable}` | filtros opcionales (vacíos si no se pasan) |
| `{texto}` `{desde}` `{hasta}` | valores escapados |

Para varias hojas, separá bloques con `-- @hoja: nombre`; `-- @resumen: col1, col2` agrega una hoja con conteos.
Para que aparezca en `--lista`, guardalo en `recetas\` con `-- @descripcion:`, `-- @requiere:` y `-- @costo:`.

Ejemplo mínimo:
```sql
-- @hoja: resultado
SELECT CAST(creation_time AS DATE) AS fecha, COUNT(DISTINCT session_id) AS sesiones
FROM "caba-piba-consume-zone-db"."boti_message_metrics_2"
WHERE {part_ext} AND {rango_creation} AND {cond_rulename} {no_testers}
GROUP BY 1 ORDER BY 1
```

## Verificar que todo anda

```powershell
cd C:\GCBA\Pedidos_Boti
python pedido.py --probar
```
Corre todas las recetas (menos las caras) sobre un día de hace 2 días y deja `output\<fecha>_probar\reporte_probar.csv` con OK/ERROR y MB escaneados. `--probar-todo` incluye las caras.

## Recordatorios que evitan errores

- Fechas en **UTC** (Argentina = UTC−3). El día en curso no está; el último día cargado está cortado a ~03:00 AR.
- Sólo desde **05/2024** (tablas `_2`). Lo anterior está en tablas viejas con otra estructura.
- Sesiones = `COUNT(DISTINCT session_id)`; usuarios = `COUNT(DISTINCT SUBSTR(session_id,1,20))` (confiable sólo en WhatsApp).
- `boti_event_metrics_2` es carísima (~4 GB por día leyendo todas las columnas): sólo `pushes_estados` y `colas`, y con rangos cortos.
- `feedback_flujo` cuenta `Ni fácil ni difícil` (CATs); CEDETAC no, a propósito: no comparar uno con otro sin aclararlo.
- `rastreo_persona` trae datos personales: rango corto, no compartir el Excel fuera del área que lo pidió.
- La columna `tema_botmaker` / `documento_cux` / `activa` se agrega sola cuando el resultado tiene `rule_name` (cruce con el TSV).
- **Pushes — interacción:** nunca contar con `original_user_message` (en la fila del `Template` trae lo que la persona hizo *antes*); contar filas `msg_from = 'user'` posteriores a la push y **por persona**, porque la sesión de la push se cierra a la hora y la respuesta tardía abre otra sesión. Los botones de tipo URL del template no dejan rastro en mensajes. Si el pedido nombra un contenido (CUX), no es el nombre de la push: ubicarla con `pushes`. Ejemplo completo: `pedidos\2026-10_push_EDU04CUX21\README.md`.
