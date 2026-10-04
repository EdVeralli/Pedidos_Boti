"""
pedido.py
=========
Resuelve pedidos "voladores" de Boti contra AWS Athena con recetas listas.

Uso:
  cd C:\\GCBA\\Pedidos_Boti
  python pedido.py --lista
  python pedido.py <receta> --desde AAAA-MM-DD --hasta AAAA-MM-DD [opciones]

Ejemplos:
  python pedido.py sesiones --desde 2026-09-01 --hasta 2026-09-30
  python pedido.py sesiones --desde 2026-09-01 --hasta 2026-09-30 --canal "BAX - App"
  python pedido.py flujo --mes 2026-09 --rulename "SUA01CUX04%"
  python pedido.py mensajes --mes 2026-09 --texto "dengue|vacuna"
  python pedido.py feedback_flujo --desde 2026-07-01 --hasta 2026-09-30 --rulename "%SA01CAT01%"
  python pedido.py embudo --mes 2026-09 --rulename "SUA01CUX04 Apertura" --rulename "SUA01CUX04 Pedido de patente%" --rulename "Solicitud exitosa"
  python pedido.py sql --archivo mi_query.sql --desde 2026-09-01 --hasta 2026-09-30
  python pedido.py --probar

Salida: output\\<fecha_hora>_<receta>\\ con el Excel, un CSV por hoja, el SQL ejecutado y el log.
"""
import argparse
import sys
import time
from datetime import date, datetime, timedelta
from pathlib import Path

import pandas as pd

import boti_athena as ba

RECETAS = ba.BASE / 'recetas'
COSTO_ICONO = {'bajo': '$', 'medio': '$$', 'alto': '$$$'}


# ==================== FECHAS ====================

def parse_fecha(t):
    return datetime.strptime(t, '%Y-%m-%d').date()


def rango_desde_args(a):
    if a.mes:
        y, m = [int(x) for x in a.mes.split('-')]
        ini = date(y, m, 1)
        fin = date(y + (m == 12), m % 12 + 1, 1) - timedelta(days=1)
        return ini, fin
    if a.dias:
        fin = date.today() - timedelta(days=1)
        return fin - timedelta(days=a.dias - 1), fin
    if a.desde and a.hasta:
        return parse_fecha(a.desde), parse_fecha(a.hasta)
    sys.exit('Falta el período: --desde/--hasta, --mes AAAA-MM o --dias N')


def avisos_de_fecha(desde, hasta):
    hoy = date.today()
    if hasta >= hoy:
        ba.log.warning('El rango incluye hoy: AWS no tiene el día en curso.')
    elif hasta == hoy - timedelta(days=1):
        ba.log.warning('El último día (%s) puede estar incompleto: la ingesta corre ~03:00 AR.', hasta)
    if desde < date(2024, 5, 1):
        ba.log.warning('Antes de 05/2024 los datos están en las tablas viejas (sin _2): estas recetas no los ven.')


# ==================== RECETAS ====================

def listar():
    print('\nRecetas disponibles (costo: $ bajo, $$ medio, $$$ alto):\n')
    for f in sorted(RECETAS.glob('*.sql')):
        meta = ba.leer_receta(f)
        req = ' [requiere: {}]'.format(', '.join(meta['requiere'])) if meta['requiere'] else ''
        print('  {:<20} {:<4} {}{}'.format(f.stem, COSTO_ICONO.get(meta['costo'], '?'), meta['descripcion'], req))
    print('  {:<20} {:<4} {}'.format('embudo', '$$', 'Embudo ordenado: sesiones que pasan por los --rulename en ese orden (2 a 8 pasos).'))
    print('  {:<20} {:<4} {}'.format('sql', '?', 'Ejecuta tu propio .sql (--archivo) con los mismos marcadores {part}, {no_testers}, etc.'))
    print('')


def sql_embudo(pasos, ph):
    '''Primer momento de cada paso por sesión; cuenta sesiones que cumplen el orden.'''
    cols, conds, sel = [], [], []
    for i, p in enumerate(pasos, 1):
        cols.append("MIN(CASE WHEN rule_name LIKE '{}' THEN creation_time END) AS t{}".format(ba.esc(p), i))
    for i in range(1, len(pasos) + 1):
        cond = ' AND '.join(['t1 IS NOT NULL'] + ['t{0} > t{1}'.format(j, j - 1) for j in range(2, i + 1)])
        sel.append("COUNT_IF({}) AS paso_{}".format(cond, i))
    condicion = ' OR '.join("rule_name LIKE '{}'".format(ba.esc(p)) for p in pasos)
    return '''
WITH t AS (
  SELECT session_id, {cols}
  FROM "caba-piba-consume-zone-db"."boti_message_metrics_2"
  WHERE {{part_ext}} AND {{rango_creation}} AND ({condicion}) {{no_testers}}
  GROUP BY session_id
)
SELECT {sel}
FROM t'''.format(cols=', '.join(cols), condicion=condicion, sel=', '.join(sel))


def armar_hojas(nombre, a):
    if nombre == 'embudo':
        if not a.rulename or len(a.rulename) < 2:
            sys.exit('embudo necesita al menos 2 --rulename, en orden')
        return {'descripcion': 'embudo', 'requiere': [], 'costo': 'medio',
                'hojas': [{'nombre': 'embudo', 'sql': sql_embudo(a.rulename, None), 'resumen': []}]}
    if nombre == 'sql':
        if not a.archivo:
            sys.exit('sql necesita --archivo ruta.sql')
        texto = Path(a.archivo).read_text(encoding='utf-8')
        meta = ba.leer_receta(a.archivo)
        if not meta['hojas']:
            meta['hojas'] = [{'nombre': 'resultado', 'sql': texto.strip().rstrip(';'), 'resumen': []}]
        return meta
    ruta = RECETAS / (nombre + '.sql')
    if not ruta.exists():
        sys.exit('No existe la receta "{}". Usá --lista.'.format(nombre))
    meta = ba.leer_receta(ruta)
    if 'rulename' in meta['requiere'] and not a.rulename:
        sys.exit('La receta {} necesita --rulename'.format(nombre))
    if 'texto' in meta['requiere'] and not a.texto:
        sys.exit('La receta {} necesita --texto'.format(nombre))
    return meta


def post_embudo(df, pasos):
    if df.empty:
        return df
    fila = df.iloc[0]
    filas, base = [], None
    for i, p in enumerate(pasos, 1):
        n = int(fila.get('paso_{}'.format(i), 0) or 0)
        base = n if base is None else base
        filas.append({'paso': i, 'rulename': p, 'sesiones': n,
                      'pct_del_paso_1': round(100 * n / base, 2) if base else 0})
    return pd.DataFrame(filas)


def ejecutar(nombre, a, ath, reglas, desde, hasta, carpeta=None, silencioso=False):
    meta = armar_hojas(nombre, a)
    ph = ba.armar_placeholders(desde, hasta, rulenames=a.rulename, texto=a.texto, canal=a.canal,
                               variables=a.variable, con_testers=not a.con_testers)
    carpeta = carpeta or ba.carpeta_salida(nombre)
    carpeta.mkdir(parents=True, exist_ok=True)
    hojas, sqls, mb_total = {}, [], 0.0
    for h in meta['hojas']:
        sql = ba.renderizar(h['sql'], ph)
        sqls.append('-- @hoja: {}\n{};\n'.format(h['nombre'], sql))
        if a.solo_sql:
            continue
        df, mb = ath.query(sql, etiqueta='{}/{}'.format(nombre, h['nombre']))
        mb_total += mb
        if nombre == 'embudo':
            df = post_embudo(df, a.rulename)
        df = ba.enriquecer_con_reglas(df, reglas)
        hojas[h['nombre']] = df
        if h['resumen']:
            hojas[(h['nombre'] + '_resumen')[:31]] = ba.resumen_valores(df, h['resumen'])
    (carpeta / 'consulta.sql').write_text('\n'.join(sqls), encoding='utf-8')
    if a.solo_sql:
        ba.log.info('SQL guardado en %s (no se ejecutó)', carpeta / 'consulta.sql')
        return carpeta, 0.0
    params = pd.DataFrame([
        {'parametro': 'receta', 'valor': nombre},
        {'parametro': 'desde', 'valor': desde.isoformat()},
        {'parametro': 'hasta', 'valor': hasta.isoformat()},
        {'parametro': 'rulename', 'valor': ' | '.join(a.rulename or [])},
        {'parametro': 'texto', 'valor': a.texto or ''},
        {'parametro': 'canal', 'valor': a.canal or ''},
        {'parametro': 'testers_excluidos', 'valor': 'no' if a.con_testers else 'sí'},
        {'parametro': 'MB_escaneados', 'valor': round(mb_total, 1)},
        {'parametro': 'generado', 'valor': datetime.now().strftime('%Y-%m-%d %H:%M')},
        {'parametro': 'nota', 'valor': 'Fechas en UTC (AR = UTC-3). Partición = fecha de la sesión.'},
    ])
    hojas['parametros'] = params
    xlsx = ba.exportar(hojas, carpeta, nombre)
    if not silencioso:
        ba.log.info('Listo: %s', xlsx)
        for h, df in hojas.items():
            if h != 'parametros':
                ba.log.info('   hoja %-28s %s filas', h, len(df))
    return carpeta, mb_total


# ==================== PROBAR ====================

def probar(a, ath, reglas):
    '''Corre todas las recetas sobre un día cerrado con parámetros de ejemplo.'''
    dia = date.today() - timedelta(days=2)
    base = ba.carpeta_salida('probar')
    ejemplos = {
        'flujo': dict(rulename=['SUA01CUX04%']),
        'que_escribieron': dict(rulename=['SUA01CUX04 Apertura']),
        'feedback_flujo': dict(rulename=['%SA01CAT01%']),
        'variables_flujo': dict(rulename=['SUA01CUX04%']),
        'mensajes': dict(texto='dengue|vacuna'),
        'rastreo_persona': dict(texto='zzz_no_existe_zzz'),
        'top_rulenames': dict(rulename=None),
        'embudo': dict(rulename=['SUA01CUX04 Apertura', 'SUA01CUX04 Pedido de patente%']),
    }
    nombres = [f.stem for f in sorted(RECETAS.glob('*.sql'))] + ['embudo']
    if not a.probar_todo:
        nombres = [n for n in nombres
                   if n == 'embudo' or ba.leer_receta(RECETAS / (n + '.sql'))['costo'] != 'alto']
    filas = []
    for n in nombres:
        args = argparse.Namespace(**vars(a))
        args.rulename, args.texto = None, None
        for k, v in ejemplos.get(n, {}).items():
            setattr(args, k, v)
        t0 = time.time()
        try:
            _, mb = ejecutar(n, args, ath, reglas, dia, dia, carpeta=base / n, silencioso=True)
            filas.append({'receta': n, 'estado': 'OK', 'MB': round(mb, 1), 'segundos': round(time.time() - t0), 'error': ''})
        except KeyboardInterrupt:
            raise
        except Exception as e:
            ba.log.error('   %s: %s', n, str(e).splitlines()[0][:300])
            filas.append({'receta': n, 'estado': 'ERROR', 'MB': 0, 'segundos': round(time.time() - t0),
                          'error': str(e)[:1000]})
    rep = pd.DataFrame(filas)
    base.mkdir(parents=True, exist_ok=True)
    rep.to_csv(base / 'reporte_probar.csv', index=False, encoding='utf-8-sig')
    print('\n' + rep[['receta', 'estado', 'MB', 'segundos']].to_string(index=False))
    print('\nReporte: {}'.format(base / 'reporte_probar.csv'))


# ==================== MAIN ====================

def parse_args():
    p = argparse.ArgumentParser(description='Pedidos de Boti contra Athena con recetas listas.',
                                formatter_class=argparse.RawDescriptionHelpFormatter, epilog=__doc__)
    p.add_argument('receta', nargs='?', help='nombre de la receta (ver --lista)')
    p.add_argument('--lista', action='store_true', help='lista las recetas disponibles')
    p.add_argument('--desde', help='AAAA-MM-DD (inclusive)')
    p.add_argument('--hasta', help='AAAA-MM-DD (inclusive)')
    p.add_argument('--mes', help='AAAA-MM: mes completo')
    p.add_argument('--dias', type=int, help='últimos N días cerrados (hasta ayer)')
    p.add_argument('--rulename', action='append', help='patrón LIKE (%% comodín). Repetible.')
    p.add_argument('--texto', help='regex para buscar en mensajes (se compara en minúsculas, salvo rastreo_persona)')
    p.add_argument('--canal', help='filtra channel_name LIKE %%canal%% (recetas que lo soportan)')
    p.add_argument('--variable', action='append', help='nombre de variable (variables_flujo). Repetible.')
    p.add_argument('--archivo', help='archivo .sql propio (receta "sql")')
    p.add_argument('--con-testers', action='store_true', help='NO excluir testers')
    p.add_argument('--solo-sql', action='store_true', help='sólo genera el SQL, no ejecuta')
    p.add_argument('--probar', action='store_true', help='corre todas las recetas sobre un día de prueba')
    p.add_argument('--probar-todo', action='store_true', help='--probar incluyendo las recetas caras')
    return p.parse_args()


def main():
    a = parse_args()
    ba.configurar_log()
    if a.lista or (not a.receta and not a.probar and not a.probar_todo):
        listar()
        return
    reglas = None
    tsv = ba.tsv_mas_reciente()
    if tsv:
        try:
            reglas = ba.leer_tsv_reglas(tsv)
            ba.log.info('Reglas de Botmaker: %s (%s reglas)', Path(tsv).name, len(reglas))
        except Exception as e:
            ba.log.warning('No pude leer el TSV de reglas (%s); sigo sin enriquecer', e)
    if a.probar or a.probar_todo:
        a.solo_sql = False
        ath = ba.Athena()
        probar(a, ath, reglas)
        return
    desde, hasta = rango_desde_args(a)
    if hasta < desde:
        sys.exit('--hasta es anterior a --desde')
    carpeta = ba.carpeta_salida(a.receta)
    carpeta.mkdir(parents=True, exist_ok=True)
    ba.configurar_log(carpeta / 'log.txt')
    ba.log.info('Receta %s | %s al %s', a.receta, desde, hasta)
    avisos_de_fecha(desde, hasta)
    ath = None if a.solo_sql else ba.Athena()
    ejecutar(a.receta, a, ath, reglas, desde, hasta, carpeta=carpeta)


if __name__ == '__main__':
    main()
