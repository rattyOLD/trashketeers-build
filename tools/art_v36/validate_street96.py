#!/usr/bin/env python3
import argparse
import hashlib
import json
from pathlib import Path
import numpy as np
from PIL import Image
from scipy import ndimage

ROOT=Path(__file__).resolve().parents[2]


def validate(root):
    m=json.loads((root/'manifest.json').read_text());errors=[];stats={};images={}
    def check(ok,message):
        if not ok:errors.append(message)
    palette=np.array(Image.open(root/m['palette']).convert('RGB'))
    colors=set(map(tuple,palette.reshape(-1,3)))
    check(palette.shape==(1,128,3) and len(colors)==128,'128 distinct palette colors')
    expected={'bank_balustrade.png':(192,128),'bank_balustrade_n.png':(192,128),
        'bank_umbrella.png':(288,272),'bank_bistro_table.png':(128,128)}
    if m['revision']=='street96-control-2':
        expected.update({'bank_balustrade_02.png':(192,128),'bank_balustrade_02_n.png':(192,128),
            'bank_balustrade_03.png':(192,128),'bank_balustrade_03_n.png':(192,128),
            'bank_bistro_table_parasol.png':(128,128),'bank_chair_left.png':(128,128),
            'bank_chair_right.png':(128,128),'bank_umbrella_pole_front.png':(288,272)})
    check(set(expected)=={f['file'] for f in m['files']}=={p.name for p in root.glob('*.png')},'Complete PNG set')
    for f in m['files']:
        p=root/f['file']
        with Image.open(p) as probe:probe.verify()
        im=Image.open(p).convert('RGBA');a=np.array(im);images[p.name]=a
        check(im.size==expected[p.name],p.name+': dimensions')
        check(f['size_m']==[v/96 for v in im.size],p.name+': metres')
        check(f['sha256']==hashlib.sha256(p.read_bytes()).hexdigest() and f['bytes']==p.stat().st_size,p.name+': SHA/bytes')
        if f['role'] in ('vertical_sprite','assembly_overlay'):
            v=a[:,:,3]>0;check(set(a[:,:,3].ravel())=={0,255},p.name+': alpha')
            used=set(map(tuple,a[v,:3]));check(used<=colors,p.name+': palette')
            _,count=ndimage.label(v,structure=np.ones((3,3)));check(count==1,p.name+': stray components')
            edge=v & ~ndimage.binary_erosion(v,structure=ndimage.generate_binary_structure(2,1))
            if f.get('tileable_x'):edge[:,[0,-1]]=False
            if f['role']!='assembly_overlay':check(np.all(a[edge,:3]==(30,28,27)),p.name+': silhouette contour')
            check(f['ground_cast_shadow_baked'] is False,p.name+': baked ground shadow')
            check(f['collider_radius_m']>0 if f['role']=='vertical_sprite' else f['collider_radius_m']==0,p.name+': collider')
            stats[p.name]={'visible_bounds':list(im.getbbox()),'colors':len(used),'components':count}
        else:
            n=a[:,:,:3]/255*2-1;check(np.max(abs(np.linalg.norm(n,axis=2)-1))<.008 and n[:,:,2].min()>.5,p.name+': normals')
    for name in ('bank_balustrade.png','bank_balustrade_n.png'):
        a=images[name];check(np.array_equal(a[:,0],a[:,-1]),name+': horizontal connection')
    rail=m['files'][0]
    check(rail['repeat_step_m']==[2,0,0] and rail['end_pillars_baked'] is False,'Repeat step/no end pillars')
    if m['revision']=='street96-control-2':
        import itertools
        variants=m['balustrade_variants']
        for x,y in itertools.product(variants,repeat=2):
            check(np.array_equal(images[x][:,-1],images[y][:,0]),'Variant seam '+x+'/'+y)
            check(np.array_equal(images[x.replace('.png','_n.png')][:,-1],images[y.replace('.png','_n.png')][:,0]),'Variant normal seam '+x+'/'+y)
        base=images['bank_balustrade.png']
        for name in variants[1:]:
            check(np.count_nonzero(np.any(base!=images[name],axis=2))>=30,name+': no distinct damage')
            check(np.array_equal(base[:,:8],images[name][:,:8]) and np.array_equal(base[:,-8:],images[name][:,-8:]),name+': connection neighborhood changed')
            check(np.array_equal(base[:,:,3],images[name][:,:,3]),name+': accepted silhouette changed')
        check(hashlib.sha256((root/'bank_balustrade.png').read_bytes()).hexdigest()=='7a4bb440c487fece95b17a38a0c84ee77616d602d9fbee8d01021c68651d7c60','Accepted base changed')
        table=images['bank_bistro_table_parasol.png'];socket=next(f for f in m['files'] if f['file']=='bank_bistro_table_parasol.png')['pole_socket_px']
        sx,sy=socket;check(float(table[sy,sx,:3].mean())<100,'Table center is obstructed instead of a dark socket')
        overlay=images['bank_umbrella_pole_front.png'];visible=overlay[:,:,3]>0
        check(np.array_equal(overlay[visible],images['bank_umbrella.png'][visible]),'Upper pole not registered to parasol')
        yy,xx=np.where(visible);check(xx.min()>=136 and xx.max()<152 and yy.min()>=146 and yy.max()<=201,'Upper pole clip exceeds socket')
        check(m['assembly']['collision_owners']==['bank_bistro_table_parasol.png','bank_chair_left.png','bank_chair_right.png'],'Cafe collision owners')
    else:
        check(m['assembly']['collision_owner']=='bank_bistro_table.png','Table owns assembled collider')
    return {'ok':not errors,'errors':errors,'pixels_per_metre':96,'png_count':len(expected),
        'sprites':stats,'horizontal_connections_checked':['albedo RGBA','normal RGB'],
        'owner_visual_approved':m['owner_visual_approved']}


def main():
    p=argparse.ArgumentParser();p.add_argument('--root',type=Path,default=ROOT/'astra/inbox/hd2d_test/props/street96');p.add_argument('--report',type=Path);args=p.parse_args()
    report=validate(args.root)
    if args.report:args.report.write_text(json.dumps(report,ensure_ascii=False,indent=2)+'\n')
    print(json.dumps(report,ensure_ascii=False,indent=2));print('STREET96_CONTRACT_OK' if report['ok'] else 'STREET96_CONTRACT_FAILED')
    raise SystemExit(0 if report['ok'] else 1)


if __name__=='__main__':main()
