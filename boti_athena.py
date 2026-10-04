"""
boti_athena.py
==============
Biblioteca común para resolver pedidos de Boti contra AWS Athena.

- Login con aws-azure-login (rol PIBADataScientist) y re-login si vence el token.
- Ejecución de queries con polling, MB escaneados y cancelación con Ctrl+C.
- Armado de filtros: partición (year/month/day = fecha UTC de la sesión),
  rangos de fecha, testers, rulenames, canal.
- Exportación a Excel (formateado) + CSV, y enriquecimiento con el TSV de reglas.

Lo usan pedido.py y buscar_reglas.py. No se ejecuta solo.
"""
import csv
import glob
import logging
import os
import re
import sys
import time
from datetime import date, datetime, timedelta
from pathlib import Path

import pandas as pd

BASE = Path(__file__).resolve().parent

CONFIG = {
    'region': 'us-east-1',
    'workgroup': 'Production-caba-piba-athena-boti-group',
    'database': 'caba-piba-consume-zone-db',
    'perfil': 'default',
}
CMD_LOGIN = 'aws-azure-login --profile {perfil} --mode=gui'
POLL_SEGUNDOS = 2
AVISO_SEGUNDOS = 30
FILAS_MAX_EXCEL = 1_000_000

TESTERS_CSV = BASE / 'config' / 'testers.csv'
CARPETAS_TSV = [
    BASE / 'config',
    Path(r'C:\GCBA\Metricas_Boti_Mensual\Contenidos_Bot'),
    Path(r'C:\GCBA\Metricas_Boti_Mensual\Contenidos_mas_disparados'),
]

log = logging.getLogger('boti')


# ==================== LOG ====================

def configurar_log(archivo=None):
    log.setLevel(logging.INFO)
    log.handlers.clear()
    fmt = logging.Formatter('%(asctime)s [%(levelname)s] %(message)s', '%H:%M:%S')
    h = logging.StreamHandler(sys.stdout)
    h.setFormatter(fmt)
    log.addHandler(h)
    if archivo:
        fh = logging.FileHandler(archivo, encoding='utf-8')
        fh.setFormatter(fmt)
        log.addHandler(fh)


# ==================== LOGIN ====================

def _sesion():
    import boto3
    return boto3.Session(profile_name=CONFIG['perfil'], region_name=CONFIG['region'])


def _credenciales_validas():
    try:
        arn = _sesion().client('sts').get_caller_identity().get('Arn', '')
        log.info('Credenciales OK: %s', arn.split('/')[-1] if arn else '')
        if 'PIBADataScientist' not in arn:
            log.warning('El rol no es PIBADataScientist; puede faltar acceso')
        return True
    except Exception as e:
        log.warning('Credenciales no válidas: %s', str(e).splitlines()[0])
        return False


def _pedir_login():
    while True:
        print('')
        print('=' * 70)
        print('LOGIN AWS (rol PIBADataScientist)')
        print('=' * 70)
        print('En OTRA terminal ejecutá:')
        print('')
        print('     ' + CMD_LOGIN.format(perfil=CONFIG['perfil']))
        print('')
        print('Completá el login en el navegador y volvé acá.')
        print('=' * 70)
        if input('ENTER para continuar (q para salir): ').strip().lower() == 'q':
            sys.exit(1)
        time.sleep(2)
        if _credenciales_validas():
            return _sesion()
        print('[!] Todavía no es válido. Probá de nuevo.')


def _token_vencido(e):
    m = str(e)
    return 'ExpiredToken' in m or 'expired' in m.lower()


class Athena:
    '''Conexión a Athena con re-login automático.'''

    def __init__(self):
        self.session = _sesion() if _credenciales_validas() else _pedir_login()
        self.mb_total = 0.0

    def _llamar(self, fn):
        while True:
            try:
                return fn(self.session.client('athena'))
            except Exception as e:
                if _token_vencido(e):
                    log.warning('Token AWS vencido')
                    self.session = _pedir_login()
                    continue
                raise

    def query(self, sql, etiqueta=''):
        '''Ejecuta la query y devuelve un DataFrame (columnas como texto -> numéricas si se puede).'''
        import awswrangler as wr
        qid = self._llamar(lambda c: c.start_query_execution(
            QueryString=sql,
            QueryExecutionContext={'Database': CONFIG['database']},
            WorkGroup=CONFIG['workgroup'],
        )['QueryExecutionId'])
        log.info('Query %s lanzada (%s)', etiqueta, qid[:8])
        t0, ultimo = time.time(), 0
        try:
            while True:
                q = self._llamar(lambda c: c.get_query_execution(QueryExecutionId=qid)['QueryExecution'])
                estado = q['Status']['State']
                if estado in ('SUCCEEDED', 'FAILED', 'CANCELLED'):
                    break
                seg = time.time() - t0
                if seg - ultimo >= AVISO_SEGUNDOS:
                    mb = q.get('Statistics', {}).get('DataScannedInBytes', 0) / 1024 ** 2
                    log.info('   ... %s | %d s | %.0f MB', estado, seg, mb)
                    ultimo = seg
                time.sleep(POLL_SEGUNDOS)
        except KeyboardInterrupt:
            log.warning('Cancelando la query en Athena...')
            self._llamar(lambda c: c.stop_query_execution(QueryExecutionId=qid))
            raise
        if estado != 'SUCCEEDED':
            raise RuntimeError('{}: {}'.format(estado, q['Status'].get('StateChangeReason', '')))
        mb = q['Statistics'].get('DataScannedInBytes', 0) / 1024 ** 2
        self.mb_total += mb
        ruta = q['ResultConfiguration']['OutputLocation']
        while True:
            try:
                # Lista explícita: si se pasa como texto, awswrangler lo toma como PREFIJO
                # y también lee <id>.csv.metadata (binario) -> filas basura / error 0xFF.
                df = wr.s3.read_csv([ruta], boto3_session=self.session, dtype=str,
                                    keep_default_na=False, na_values=[''])
                break
            except Exception as e:
                if _token_vencido(e):
                    self.session = _pedir_login()
                    continue
                if 'EmptyDataError' in type(e).__name__ or 'No columns' in str(e):
                    df = pd.DataFrame()
                    break
                raise
        log.info('   OK %s: %s filas | %.0f s | %.0f MB escaneados', etiqueta, len(df),
                 time.time() - t0, mb)
        return a_numerico(df), mb


def a_numerico(df):
    for c in df.columns:
        conv = pd.to_numeric(df[c], errors='coerce')
        if df[c].notna().sum() and conv.notna().sum() == df[c].notna().sum():
            df[c] = conv
    return df


# ==================== FILTROS SQL ====================

def esc(texto):
    '''Escapa comillas simples para meter texto del usuario en un literal SQL.'''
    return str(texto).replace("'", "''")


def _pref(alias):
    return alias + '.' if alias else ''


def filtro_particion(desde, hasta, alias=''):
    '''
    Filtro por particiones year/month/day (strings sin ceros) para el rango
    [desde, hasta]. En las tablas _2 la partición es la fecha UTC de la sesión;
    en las de IA, la de ts.
    '''
    p = _pref(alias)
    partes, d = [], date(desde.year, desde.month, 1)
    while d <= hasta:
        fin_mes = (date(d.year + (d.month == 12), d.month % 12 + 1, 1) - timedelta(days=1))
        ini = max(d, desde)
        fin = min(fin_mes, hasta)
        base = "{p}year = '{y}' AND {p}month = '{m}'".format(p=p, y=d.year, m=d.month)
        if ini.day == 1 and fin == fin_mes:
            partes.append('(' + base + ')')
        else:
            partes.append("({b} AND CAST({p}day AS INTEGER) BETWEEN {a} AND {z})".format(
                b=base, p=p, a=ini.day, z=fin.day))
        d = fin_mes + timedelta(days=1)
    return '(' + ' OR '.join(partes) + ')'


def cargar_testers():
    if not TESTERS_CSV.exists():
        log.warning('No encontré %s: NO se filtran testers', TESTERS_CSV)
        return []
    ids = []
    with open(TESTERS_CSV, encoding='utf-8-sig') as f:
        for fila in csv.reader(f):
            for v in fila:
                v = v.strip()
                if re.fullmatch(r'[A-Z0-9]{20}', v):
                    ids.append(v)
    return ids


def armar_placeholders(desde, hasta, rulenames=None, texto=None, canal=None,
                       variables=None, con_testers=True):
    '''
    Devuelve un dict de funciones/valores para renderizar recetas.
    Marcadores soportados (alias opcional con ':alias'):
      {part}            partición del rango (sesiones del período)
      {part_ext}        partición del rango + 1 día (para medir por creation_time)
      {rango_creation}  CAST(creation_time AS DATE) BETWEEN desde AND hasta
      {rango_sesion}    CAST(session_creation_time AS DATE) BETWEEN ...
      {rango_ts}        CAST(ts AS DATE) BETWEEN ...
      {no_testers}      AND SUBSTR(session_id,1,20) NOT IN (...)
      {cond_rulename}   (rule_name LIKE 'a' OR rule_name LIKE 'b')
      {cond_canal}      AND channel_name LIKE '%x%'   (vacío si no se pidió)
      {cond_variable}   AND vars_name IN (...)        (vacío si no se pidió)
      {texto}           regex del usuario (escapada)
      {desde} {hasta}   'YYYY-MM-DD'
    '''
    testers = cargar_testers() if con_testers else []
    lista_testers = '(' + ', '.join("'{}'".format(t) for t in testers) + ')' if testers else None
    rulenames = rulenames or []

    def f_part(a):
        return filtro_particion(desde, hasta, a)

    def f_part_ext(a):
        return filtro_particion(desde, hasta + timedelta(days=1), a)

    def f_rango(col):
        return lambda a: "CAST({}{} AS DATE) BETWEEN DATE '{}' AND DATE '{}'".format(
            _pref(a), col, desde.isoformat(), hasta.isoformat())

    def f_testers(a):
        if not lista_testers:
            return ''
        return 'AND SUBSTR({}session_id, 1, 20) NOT IN {}'.format(_pref(a), lista_testers)

    def f_rulename(a):
        if not rulenames:
            return 'TRUE'
        return '(' + ' OR '.join("{}rule_name LIKE '{}'".format(_pref(a), esc(r)) for r in rulenames) + ')'

    def f_canal(a):
        return "AND {}channel_name LIKE '%{}%'".format(_pref(a), esc(canal)) if canal else ''

    def f_variable(a):
        if not variables:
            return ''
        return 'AND {}vars_name IN ({})'.format(_pref(a), ', '.join("'{}'".format(esc(v)) for v in variables))

    return {
        'part': f_part, 'part_ext': f_part_ext,
        'rango_creation': f_rango('creation_time'),
        'rango_sesion': f_rango('session_creation_time'),
        'rango_ts': f_rango('ts'),
        'no_testers': f_testers, 'cond_rulename': f_rulename,
        'cond_canal': f_canal, 'cond_variable': f_variable,
        'texto': esc(texto) if texto else '',
        'desde': desde.isoformat(), 'hasta': hasta.isoformat(),
    }


_MARCADOR = re.compile(r'\{([a-z_]+)(?::([a-z0-9_]+))?\}')


def renderizar(sql, ph):
    def reemplazo(m):
        nombre, alias = m.group(1), m.group(2) or ''
        if nombre not in ph:
            raise KeyError('Marcador desconocido en la receta: {' + nombre + '}')
        v = ph[nombre]
        return v(alias) if callable(v) else v
    return _MARCADOR.sub(reemplazo, sql)


# ==================== RECETAS ====================

def leer_receta(ruta):
    '''
    Una receta es un .sql con metadatos en comentarios:
      -- @descripcion: texto
      -- @requiere: rulename | texto
      -- @costo: bajo | medio | alto
      -- @hoja: nombre        (cada bloque SQL va a una hoja del Excel)
      -- @resumen: col1, col2 (cuenta valores de esas columnas en una hoja aparte)
    '''
    texto = Path(ruta).read_text(encoding='utf-8')
    meta = {'descripcion': '', 'requiere': [], 'costo': 'bajo', 'hojas': []}
    hoja = None
    for linea in texto.splitlines():
        m = re.match(r'\s*--\s*@(\w+)\s*:\s*(.*)$', linea)
        if m:
            clave, valor = m.group(1).lower(), m.group(2).strip()
            if clave == 'hoja':
                hoja = {'nombre': valor[:31], 'sql': [], 'resumen': []}
                meta['hojas'].append(hoja)
            elif clave == 'resumen' and hoja:
                hoja['resumen'] = [c.strip() for c in valor.split(',') if c.strip()]
            elif clave == 'requiere':
                meta['requiere'] = [c.strip() for c in valor.split(',') if c.strip()]
            else:
                meta[clave] = valor
            continue
        if hoja is not None:
            hoja['sql'].append(linea)
    for h in meta['hojas']:
        h['sql'] = '\n'.join(h['sql']).strip().rstrip(';')
    return meta


# ==================== TSV DE REGLAS ====================

def tsv_mas_reciente(carpeta_extra=None):
    carpetas = ([Path(carpeta_extra)] if carpeta_extra else []) + CARPETAS_TSV
    archivos = []
    for c in carpetas:
        archivos += glob.glob(str(c / 'rules-*.tsv'))
    if not archivos:
        return None
    return max(archivos, key=lambda a: os.path.basename(a))


def leer_tsv_reglas(ruta):
    for enc in ('utf-8-sig', 'cp1252'):
        try:
            df = pd.read_csv(ruta, sep='\t', dtype=str, keep_default_na=False,
                             on_bad_lines='skip', encoding=enc)
            break
        except UnicodeDecodeError:
            continue
    for c in df.columns:
        df[c] = df[c].str.strip()
    df['Tema'] = df['Topic path'].str.split('/').str[0]
    return df


def enriquecer_con_reglas(df, reglas):
    '''Si el resultado tiene rule_name, agrega Tema / Topic / Activa desde el TSV.'''
    if reglas is None or df.empty or 'rule_name' not in df.columns:
        return df
    mapa = (reglas.drop_duplicates('Name')
            .set_index('Name')[['Tema', 'Topic', 'Active']]
            .rename(columns={'Tema': 'tema_botmaker', 'Topic': 'documento_cux', 'Active': 'activa'}))
    out = df.merge(mapa, how='left', left_on=df['rule_name'].astype(str).str.strip(), right_index=True)
    return out.drop(columns=['key_0'], errors='ignore')


# ==================== EXPORTACIÓN ====================

def exportar(hojas, carpeta, nombre):
    '''hojas: dict nombre -> DataFrame. Escribe un Excel + un CSV por hoja.'''
    carpeta.mkdir(parents=True, exist_ok=True)
    for h, df in hojas.items():
        df.to_csv(carpeta / '{}.csv'.format(h), index=False, encoding='utf-8-sig')
    xlsx = carpeta / '{}.xlsx'.format(nombre)
    with pd.ExcelWriter(xlsx, engine='openpyxl') as w:
        for h, df in hojas.items():
            if len(df) > FILAS_MAX_EXCEL:
                log.warning('Hoja %s tiene %s filas: sólo va al CSV', h, len(df))
                pd.DataFrame({'aviso': ['Demasiadas filas para Excel; ver {}.csv'.format(h)]}).to_excel(
                    w, sheet_name=h, index=False)
                continue
            df.to_excel(w, sheet_name=h, index=False)
            ws = w.sheets[h]
            ws.freeze_panes = 'A2'
            for celda in ws[1]:
                celda.font = celda.font.copy(bold=True)
            for i, col in enumerate(df.columns, 1):
                largo = max([len(str(col))] + [len(str(v)) for v in df[col].head(200).tolist()])
                ws.column_dimensions[ws.cell(1, i).column_letter].width = min(max(10, largo + 2), 70)
    return xlsx


def resumen_valores(df, columnas):
    filas = []
    for c in columnas:
        if c not in df.columns:
            continue
        vc = df[c].fillna('(vacío)').value_counts()
        tot = vc.sum()
        for valor, n in vc.items():
            filas.append({'columna': c, 'valor': valor, 'cantidad': n,
                          'porcentaje': round(100 * n / tot, 2) if tot else 0})
    return pd.DataFrame(filas)


def carpeta_salida(nombre):
    return BASE / 'output' / '{}_{}'.format(datetime.now().strftime('%Y%m%d_%H%M%S'), nombre)
