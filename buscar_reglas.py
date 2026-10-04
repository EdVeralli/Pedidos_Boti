"""
buscar_reglas.py
================
Busca en el export de reglas de Botmaker (rules-*.tsv) sin tocar AWS.
Primer paso de cualquier pedido: saber qué rulenames existen sobre un tema.

Uso:
  cd C:\\GCBA\\Pedidos_Boti
  python buscar_reglas.py dengue
  python buscar_reglas.py "licencia|registro de conducir" --campos nombre,carpeta
  python buscar_reglas.py SUA01CUX04 --solo-activas --excel
  python buscar_reglas.py --id PLBWX5XYGQ2B3GP7IN8Q-6e5jiocf03@b.m-1688135541169
  python buscar_reglas.py --temas                     (cantidad de reglas por gran tema)

La búsqueda ignora mayúsculas y acentos. El término es una regex.
"""
import argparse
import re
import sys
import unicodedata
from datetime import datetime
from pathlib import Path

import pandas as pd

import boti_athena as ba

CAMPOS = {
    'nombre': 'Name',
    'carpeta': 'Topic path',
    'disparadores': 'Triggers',
    'keywords': 'Keywords',
    'respuesta': 'Bot Says',
    'variables': 'Variables',
}


def sin_acentos(t):
    t = unicodedata.normalize('NFKD', str(t))
    return ''.join(c for c in t if not unicodedata.combining(c)).lower()


def parse_args():
    p = argparse.ArgumentParser(description='Busca reglas en el TSV de Botmaker.',
                                formatter_class=argparse.RawDescriptionHelpFormatter, epilog=__doc__)
    p.add_argument('termino', nargs='?', help='regex a buscar (sin distinguir mayúsculas ni acentos)')
    p.add_argument('--campos', default='nombre,carpeta,disparadores,respuesta',
                   help='dónde buscar: ' + ','.join(CAMPOS) + ' (default: nombre,carpeta,disparadores,respuesta)')
    p.add_argument('--solo-activas', action='store_true', help='sólo reglas Active=true')
    p.add_argument('--id', help='buscar por ID exacto (acepta prefijo RuleBuilder:)')
    p.add_argument('--temas', action='store_true', help='resumen de reglas por gran tema')
    p.add_argument('--tsv', help='ruta a un rules-*.tsv puntual (default: el más reciente)')
    p.add_argument('--excel', action='store_true', help='guarda el resultado en output\\')
    p.add_argument('--max', type=int, default=60, help='máximo de filas a mostrar en pantalla')
    return p.parse_args()


def main():
    a = parse_args()
    ruta = a.tsv or ba.tsv_mas_reciente()
    if not ruta:
        sys.exit('No encontré ningún rules-*.tsv. Copiá el export de Botmaker a config\\ o usá --tsv.')
    df = ba.leer_tsv_reglas(ruta)
    print('TSV: {} | {} reglas ({} activas)'.format(Path(ruta).name, len(df), (df.Active == 'true').sum()))

    if a.temas:
        r = (df.assign(activa=df.Active == 'true')
               .groupby('Tema').agg(reglas=('ID', 'size'), activas=('activa', 'sum'))
               .sort_values('reglas', ascending=False))
        print(r.to_string())
        return

    if a.id:
        idb = a.id.replace('RuleBuilder:', '').strip()
        res = df[df.ID == idb]
    elif a.termino:
        patron = re.compile(sin_acentos(a.termino))
        cols = [CAMPOS[c.strip()] for c in a.campos.split(',') if c.strip() in CAMPOS]
        mascara = pd.Series(False, index=df.index)
        donde = pd.Series('', index=df.index)
        for c in cols:
            m = df[c].map(lambda v: bool(patron.search(sin_acentos(v))))
            donde = donde.where(~m | (donde != ''), c)
            mascara |= m
        res = df[mascara].assign(encontrado_en=donde[mascara])
    else:
        sys.exit('Indicá un término, --id o --temas')

    if a.solo_activas:
        res = res[res.Active == 'true']
    if res.empty:
        print('Sin resultados.')
        return

    vista = res[['Active', 'Name', 'Topic path'] + (['encontrado_en'] if 'encontrado_en' in res else [])]
    print('\n{} reglas encontradas ({} activas)\n'.format(len(res), (res.Active == 'true').sum()))
    with pd.option_context('display.max_colwidth', 80, 'display.width', 250):
        print(vista.head(a.max).to_string(index=False))
    if len(res) > a.max:
        print('\n... {} más. Usá --excel para verlas todas.'.format(len(res) - a.max))

    prefijos = res.Name.str.extract(r'^([A-Za-z]+\d+(?:CUX|CAT)\d+)')[0].dropna().value_counts()
    if not prefijos.empty:
        print('\nDocumentos CUX/CAT involucrados (para --rulename "PREFIJO%"):')
        print('  ' + ', '.join('{} ({})'.format(k, v) for k, v in prefijos.head(15).items()))

    if a.excel:
        carpeta = ba.BASE / 'output'
        carpeta.mkdir(exist_ok=True)
        nombre = re.sub(r'[^\w]+', '_', a.termino or a.id or 'reglas')[:40]
        xlsx = carpeta / 'reglas_{}_{}.xlsx'.format(nombre, datetime.now().strftime('%Y%m%d_%H%M%S'))
        res.drop(columns=['Keywords'], errors='ignore').to_excel(xlsx, index=False)
        print('\nExcel: {}'.format(xlsx))


if __name__ == '__main__':
    main()
