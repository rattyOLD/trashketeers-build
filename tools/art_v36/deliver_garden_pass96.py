#!/usr/bin/env python3
"""Deliver the reviewed grid exports, preserve unrelated assets and palettes."""
import argparse
import hashlib
import json
import shutil
from pathlib import Path
from PIL import Image

ROOT=Path(__file__).resolve().parents[2]
BASE=ROOT/'astra/inbox/hd2d_test'
def write(path,data):path.write_text(json.dumps(data,ensure_ascii=False,indent=2)+'\n')

def main():
    parser=argparse.ArgumentParser();parser.add_argument('lawn',type=Path);parser.add_argument('umbrella',type=Path);a=parser.parse_args()
    materials=BASE/'materials';m=json.loads((materials/'manifest.json').read_text())
    for entry in m['files']:
        if entry['material']!='lawn':continue
        p=materials/entry['file'];shutil.copy2(a.lawn/entry['file'],p)
        entry.update(sha256=hashlib.sha256(p.read_bytes()).hexdigest(),bytes=p.stat().st_size)
        if entry['role']=='albedo':entry.update(source_image='../../../previews/v36/lawn96_source.png',normal_scale=0.)
        else:entry['source']='flat tangent normal; no luminance-derived grass embossing'
    m['revision']='seven-materials-96-lawn-2';m['lawn_revision_note']='Larger readable grass/clover clusters and sparse flowers; accepted other six families and palette preserved'
    write(materials/'manifest.json',m);shutil.copy2(a.lawn/'export.json',materials/'LAWN_EXPORT.json')
    folder=BASE/'props/cafe96';folder.mkdir(exist_ok=True)
    specs=[('bank_umbrella_standalone.png',a.umbrella/'bank_umbrella_standalone.png',[144,270],.25),
           ('bank_cafe_table.png',BASE/'props/street96/bank_bistro_table.png',[64,126],.48),
           ('bank_cafe_chair_left.png',BASE/'props/street96/bank_chair_left.png',[64,126],.30),
           ('bank_cafe_chair_right.png',BASE/'props/street96/bank_chair_right.png',[64,126],.30)]
    files=[]
    for name,source,anchor,radius in specs:
        p=folder/name;shutil.copy2(source,p);im=Image.open(p);w,h=im.size
        files.append(dict(file=name,width=w,height=h,format=im.mode,sha256=hashlib.sha256(p.read_bytes()).hexdigest(),
            bytes=p.stat().st_size,role='vertical_sprite',pixels_per_metre=96,size_m=[w/96,h/96],anchor_px=anchor,
            anchor_uv=[anchor[0]/w,anchor[1]/h],visible_bounds_px=list(im.convert('RGBA').getbbox()),
            palette='../../palettes/street96.png',alpha='binary 0/255',collider_radius_m=radius,
            ground_cast_shadow_baked=False,local_form_shading_baked=True,resampled_from_concept=True,
            outline='dark 1px',cast_shadow_in_engine=True))
    manifest=dict(schema_version=1,brief='v36',revision='cafe96-independent-1',studio='TrashSquad · Beer Party Studio',
        pixels_per_metre=96,delivery_status='review_candidate',owner_visual_approved=False,files=files,
        palette='../../palettes/street96.png',umbrella_pole_through_table=False,
        supersedes='street96 shared-pole cafe assembly; old files are historical, not the current composition',
        suggested_layout={'table_position_m':[0,0,0],'chair_left_position_m':[-65/96,0,.005],
            'chair_right_position_m':[65/96,0,.005],'umbrella_position_m':[-1.15,0,-.55],
            'umbrella_is_independent':True,'note':'Positions are a QA suggestion; developer controls real placement and lighting.'},
        import_settings=dict(filter='nearest_with_mipmaps',alpha_scissor=.5,shaded=True,roughness=.85))
    write(folder/'manifest.json',manifest);shutil.copy2(a.umbrella/'export.json',folder/'PIXEL_EXPORT.json')
    rootprops=BASE/'props/manifest.json';p=json.loads(rootprops.read_text());p.setdefault('additional_batches',[])
    if 'cafe96/manifest.json' not in p['additional_batches']:p['additional_batches'].append('cafe96/manifest.json')
    write(rootprops,p)
    (folder/'README.md').write_text('''# Кафе: отдельный зонт, 96 px/м\n\nПо новому решению владельца зонт стоит рядом со столом на собственной тяжёлой латунной подставке. Вид сверху спереди около 35°, купол с чистыми винными/светлыми полосами. Стол и два кованых стула — независимые предметы. Стол скопирован без изменения прежнего standalone-рисунка; бутылка в центре допустима, стойки в нём нет.\n\nНовая композиция заменяет прежнюю сборку из street96 с шестом через стол. Не использовать старые bank_umbrella_pole_front/bank_bistro_table_parasol в новой сборке. Позиции в manifest — пример QA, не обязательная расстановка. Стол/стулья и палитра сохранены побайтно. Зонт — новая концептная основа с очисткой на целевой сетке; не нативный 3D-рендер.\n\nУ каждого предмета собственная опора и радиус столкновения. Альфа жёсткая, сетка 96 px/м; падающие тени и свет даёт движок. Никаких новых настроек света или игровых изменений в source/. Художественное принятие нового зонта не заявлено.\n\nTrashSquad · Beer Party Studio.\n''')
    print('GARDEN_PASS96_DELIVERED lawn6 + cafe4 PNG')
if __name__=='__main__':main()
