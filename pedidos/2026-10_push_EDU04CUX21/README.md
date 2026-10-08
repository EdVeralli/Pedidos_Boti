# Pedido: push de Educación "EDU04CUX21" — ¿cuánta gente interactuó? (08/10/2026)

**Pedido:** Boti mandó una push de Educación ("intent EDU04CUX21") y quieren saber cuánta gente interactuó.
**Período:** última semana, 01/10–07/10/2026 (UTC). Testers excluidos.

## Qué era cada cosa
- **EDU04CUX21 no es la push**: es el contenido "21. EDU04CUX21 - Inscripción escolar" (tema Educación).
- **La push** es el template `edu06push02_iel_preinicio_ut_v1`, enviado el **05/10/2026 ~12:15 AR** a 8.192 personas.
  Se identificó porque es la única push de Educación de la semana que lleva gente a EDU04CUX21.
- Texto: "Para el *ciclo lectivo 2027* tenés que hacer la *preinscripción* desde el sistema de Inscripción en Línea. Hay tiempo *hasta el 6 de noviembre*. Desde BAX podés chequear más info sobre este y otros trámites."
- Botones (Botmaker → Notifications Engine → Plantillas → Editar; salir con **Descartar**):
  | Botón | Tipo | Destino |
  |---|---|---|
  | Inscripción en línea | URL del sitio web | `https://buenosaires.gob.ar/gcaba_historico/educacion/…` → **no queda registrado en Boti** |
  | Más información | Bloque del bot | `EDU04CUX21 Cross BAX` |

## Resultado entregado
> La push de preinscripción escolar 2027 (enviada el 5/10) le llegó a 8.192 personas y tenía dos botones:
> "Más información" (lleva a Boti): **399 personas (4,9%)** llegaron después al contenido de Inscripción escolar
> (364 tocando ese botón y 35 escribiendo sobre inscripción por su cuenta en los días siguientes).
> "Inscripción en línea" abre directamente la web de inscripción: esos clics no quedan registrados en Boti.

Detalle: 286 llegaron en la misma sesión de la push y 113 en otra sesión posterior; 236 en la 1.ª hora, 358 en 24 h.
Por día (UTC): 05/10 333 · 06/10 40 · 07/10 24 · 08/10 2.

## Archivos
| Archivo | Para qué |
|---|---|
| `push_iel_llegaron_edu04cux21.sql` | **Número final**: personas que llegaron a EDU04CUX21 después de la push (cualquier sesión), por día y por punto de entrada |
| `push_edu_interaccion_por_persona.sql` | Respuesta a las 4 pushes de Educación de la semana, por persona (misma sesión / 1 h / 24 h / 72 h). Generalizado como receta `push_respuesta` |

```powershell
cd C:\GCBA\Pedidos_Boti
python pedido.py sql --archivo pedidos\2026-10_push_EDU04CUX21\push_iel_llegaron_edu04cux21.sql --dias 7
```

## Lo que salió mal en el camino (no repetir)
1. Se buscó la push con `rule_name LIKE 'EDU04CUX21%'` → 0 templates: era el contenido destino. Primero ubicar la push con `pedido.py pushes` (hoja `sesiones_abiertas_por_push`).
2. Se contó "interactuó" con `original_user_message` → 50% y después 25,7%, **ambos falsos**: en la fila del `Template` ese campo trae lo último que la persona hizo **antes** (botones de otras pushes, una "A"). Lo confiable son las filas `msg_from = 'user'` posteriores a la push.
3. Se midió sólo la sesión de la push (409 / 5,1%) → **subconteo**: la sesión se cierra a la hora (Boti manda la encuesta CXF "¡Hola! Acá Boti de nuevo") y quien toca el botón más tarde abre otra sesión. Contar **por persona** (`SUBSTR(session_id,1,20)`) en cualquier sesión.
4. "Respondió en cualquier sesión en 24 h" (971) tampoco sirve como interacción: incluye "Confirmar turno" de pushes de salud, multas, etc. Por eso el número final se definió por **llegada al contenido**.
