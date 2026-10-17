"""Bank v38: metric architectural kit, Blender4.3 -> external-texture glTF.

Run: blender -b -t 4 --python tools/art_v38/build_bank.py -- export_dir texture_dir
Blender is Z-up/front-Y. glTF export converts to Y-up/front+Z.
"""
import bpy
import bmesh
import math
import json
import sys
from pathlib import Path
from mathutils import Vector,Matrix
from mathutils.bvhtree import BVHTree

args=sys.argv[sys.argv.index('--')+1:]
OUT=Path(args[0]).resolve();TEX=Path(args[1]).resolve();OUT.mkdir(parents=True,exist_ok=True)
bpy.ops.object.select_all(action='SELECT');bpy.ops.object.delete(use_global=False)
scene=bpy.context.scene;scene.unit_settings.system='METRIC';scene.unit_settings.scale_length=1
ROOT=Path(__file__).resolve().parents[2]
images={};materials={};model=[];uv_records=[]

def image(name,data=False):
    key=(name,data)
    if key not in images:
        im=bpy.data.images.load(str(TEX/name),check_existing=False)
        if data:im.colorspace_settings.name='Non-Color'
        images[key]=im
    return images[key]

def material(name,albedo,normal=None,rough=.8,metal=0,cutout=False,glow=None):
    m=bpy.data.materials.new(name);m.use_nodes=True
    nodes=m.node_tree.nodes;links=m.node_tree.links;p=nodes.get('Principled BSDF')
    t=nodes.new('ShaderNodeTexImage');t.image=image(albedo);t.interpolation='Closest';t.extension='REPEAT';links.new(t.outputs['Color'],p.inputs['Base Color'])
    p.inputs['Roughness'].default_value=rough;p.inputs['Metallic'].default_value=metal
    if cutout:
        a=nodes.new('ShaderNodeMath');a.operation='GREATER_THAN';a.inputs[1].default_value=.5
        links.new(t.outputs['Alpha'],a.inputs[0]);links.new(a.outputs[0],p.inputs['Alpha'])
        m.surface_render_method='DITHERED';m.use_transparency_overlap=False
    if normal:
        n=nodes.new('ShaderNodeTexImage');n.image=image(normal,True);n.interpolation='Closest'
        bump=nodes.new('ShaderNodeNormalMap');bump.inputs['Strength'].default_value=.3
        links.new(n.outputs['Color'],bump.inputs['Color']);links.new(bump.outputs['Normal'],p.inputs['Normal'])
    if glow:
        g=nodes.new('ShaderNodeTexImage');g.image=image(glow,True);g.interpolation='Closest'
        tint=nodes.new('ShaderNodeMixRGB');tint.blend_type='MULTIPLY';tint.inputs[0].default_value=1
        tint.inputs[2].default_value=(1,.53,.16,1);links.new(g.outputs['Color'],tint.inputs[1])
        links.new(tint.outputs[0],p.inputs['Emission Color']);p.inputs['Emission Strength'].default_value=.05
    m['albedo_file']=albedo;m['cutout']=cutout;m['glow_file']=glow or '';materials[name]=m
    return m

plaster=material('Bank_Limestone_Plaster','bank_plaster.png','bank_plaster_n.png')
masonry=material('Bank_Ashlar','bank_masonry.png','bank_masonry_n.png')
roofmat=material('Bank_Terracotta','bank_roof.png','bank_roof_n.png')
stone=material('Bank_Stone_Trim','bank_trim.png','bank_trim_n.png')
gold=material('Bank_Gilded_Trim','bank_trim.png','bank_trim_n.png',.45,.32)
wood=material('Bank_Walnut','bank_trim.png','bank_trim_n.png',.62)
iron=material('Bank_Iron','bank_trim.png','bank_trim_n.png',.55,.35)
amber=material('Bank_Lantern_Glass','bank_trim.png',None,.28,0,False,'bank_trim_glow.png')
glass=material('Bank_Window_Glass','bank_glass.png',None,.3,0,False,'bank_glass_glow.png')
ivy=material('Bank_Ivy','bank_ivy.png',None,.9,0,True)
crest=material('Bank_Crowned_Pig_Crest','bank_crest.png',None,.55,.35,True)
REGIONS={'frieze':(0,0,256,64),'gold_leaf':(256,0,256,64),'shaft':(512,0,256,256),'brass':(768,0,256,256),
         'plinth':(0,256,128,128),'wood':(256,256,256,256),'iron':(512,256,256,256),'amber':(768,256,256,256)}

def metric_uv(o,region=None):
    """Face-local orthonormal UVs:96 texels/metre. Tile materials may repeat."""
    mesh=o.data;layer=mesh.uv_layers.new(name='UV96') if not mesh.uv_layers else mesh.uv_layers[0]
    layer.name='UV96'
    texture=o.data.materials[0]['albedo_file'];im=image(texture);tw,th=im.size
    largest=0
    for poly in mesh.polygons:
        n=poly.normal.copy().normalized();points=[mesh.vertices[mesh.loops[i].vertex_index].co for i in poly.loop_indices]
        u=Vector((1,0,0))
        if abs(n.z)>.9 and max(p.y for p in points)-min(p.y for p in points)>max(p.x for p in points)-min(p.x for p in points):u=Vector((0,1,0))
        u-=n*u.dot(n)
        if u.length<.01:u=Vector((0,1,0));u-=n*u.dot(n)
        u.normalize();v=n.cross(u).normalized()
        pu=[p.dot(u) for p in points];pv=[p.dot(v) for p in points]
        if region:
            rx,ry,rw,rh=REGIONS[region];cu=(min(pu)+max(pu))/2;cv=(min(pv)+max(pv))/2
            # Broad horizontal cap faces use a plain field, not a stretched frieze.
            if (max(pv)-min(pv))*96>=rh-2 and region in ('frieze','gold_leaf'):
                rx,ry,rw,rh=REGIONS['brass' if region=='gold_leaf' else 'plinth']
            assert (max(pu)-min(pu))*96<rw-2,(o.name,region,'U overflow')
            assert (max(pv)-min(pv))*96<rh-2,(o.name,region,'V overflow')
        for loop_id,a,b in zip(poly.loop_indices,pu,pv):
            if region:uv=((rx+rw/2+(a-cu)*96)/tw,1-(ry+rh/2-(b-cv)*96)/th)
            else:uv=(a*96/tw,b*96/th)
            layer.data[loop_id].uv=uv
    o['pixel_density']=96;o['uv_kind']='metric_isometry';o['trim_region']=region or ''

def finish(o,m,region=None):
    if m['albedo_file']=='bank_trim.png' and region is None:
        region='brass' if m==gold else 'plinth' if m==stone else 'iron' if m==iron else 'wood'
    o.data.materials.clear();o.data.materials.append(m)
    bpy.context.view_layer.objects.active=o;o.select_set(True)
    bpy.ops.object.transform_apply(location=False,rotation=False,scale=True)
    o.data.update();metric_uv(o,region);model.append(o);o.select_set(False);return o

def mesh_object(name,verts,faces,m,region=None):
    mesh=bpy.data.meshes.new(name);mesh.from_pydata(verts,[],faces);mesh.update()
    o=bpy.data.objects.new(name,mesh);scene.collection.objects.link(o)
    # Recalculate consistent outward normals on solids.
    return finish(o,m,region)

def box(name,at,size,m,region=None):
    # Large trim surfaces are real2m modules; atlas pixels retain physical size.
    limits=[2.25,2.25,2.25]
    if region:
        rw,rh=REGIONS[region][2:];limits=[min(2.25,(rw-4)/96),min(2.25,(rw-4)/96),min(2.25,(rh-4)/96)]
    if region and max(size[k]/limits[k] for k in range(3))>1:
        axis=max(range(3),key=lambda k:size[k]/limits[k]);count=math.ceil(size[axis]/limits[axis])
        result=[]
        for i in range(count):
            ss=list(size);ss[axis]/=count;aa=list(at);aa[axis]+=-size[axis]/2+ss[axis]*(i+.5)
            result+=box(name+f'_{i:02}',aa,ss,m,region)
        return result
    # Thin glazing bars keep real front/top reveals; backs face opaque glass.
    if any(s in name for s in ('Mullion','Crossbar')):
        x,y,z=at;w,d,h=[v/2 for v in size]
        return [mesh_object(name,[(x-w,y-d,z-h),(x+w,y-d,z-h),(x+w,y-d,z+h),(x-w,y-d,z+h),(x-w,y+d,z+h),(x+w,y+d,z+h)],[(0,1,2,3),(3,2,5,4)],m,region)]
    bpy.ops.mesh.primitive_cube_add(size=1,location=at);o=bpy.context.object;o.name=name;o.dimensions=size;o['solid_occluder']=True
    return [finish(o,m,region)]

def cylinder(name,at,radius,depth,m,region=None,vertices=10,axis='Z'):
    bpy.ops.mesh.primitive_cylinder_add(vertices=vertices,radius=radius,depth=depth,end_fill_type='NGON',location=at)
    o=bpy.context.object;o.name=name
    if axis=='Y':o.rotation_euler.x=math.pi/2
    if vertices>=8:
        for p in o.data.polygons:p.use_smooth=len(p.vertices)==4
    finish(o,m,region);return o

def baluster(name,x,y,z,height=.66):
    # Five-sided turned stone profile: real silhouette/recesses, not a billboard.
    profile=[(0,.105),(.40,.112),(.78,.047),(1,.075)]
    verts=[(x+r*math.cos(k*math.tau/5),y+r*math.sin(k*math.tau/5),z+t*height) for t,r in profile for k in range(5)]
    faces=[(j*5+k,j*5+(k+1)%5,(j+1)*5+(k+1)%5,(j+1)*5+k) for j in range(3) for k in range(5)]
    o=mesh_object(name,verts,faces,stone,'plinth')
    for p in o.data.polygons:p.use_smooth=True
    return o

def scroll(name,points,radius=.045):
    # Compact gilded relief strips, cross-section4. No scene lighting baked in.
    verts=[]
    for i,p in enumerate(points):
        tangent=Vector(points[min(i+1,len(points)-1)])-Vector(points[max(0,i-1)])
        tangent.normalize();n=Vector((0,1,0));b=tangent.cross(n).normalized()
        verts += [tuple(Vector(p)+radius*(math.cos(k*math.tau/4)*n+math.sin(k*math.tau/4)*b)) for k in range(4)]
    # Bent quads are not coplanar: split before metric UV projection.
    quads=[(j*4+k,j*4+(k+1)%4,(j+1)*4+(k+1)%4,(j+1)*4+k) for j in range(len(points)-1) for k in range(4)]
    faces=[t for a,b,c,d in quads for t in [(a,b,c),(a,c,d)]]
    return mesh_object(name,verts,faces,gold,'brass')

def sphere(name,at,radius,m,region='brass',scale=(1,1,1)):
    small=name in ('Door_Boss','Lamp_Finial','Capital_Volute') or (name=='Gold_Finial_Ball' and at[1]>0)
    bpy.ops.mesh.primitive_uv_sphere_add(segments=8 if small else 12,ring_count=3 if small else 6,radius=radius,location=at)
    o=bpy.context.object;o.name=name;o.scale=scale
    for p in o.data.polygons:p.use_smooth=True
    return finish(o,m,region)

def arch_profile(width,spring,bottom=0,steps=10):
    r=width/2
    return [(-r,bottom),(r,bottom)]+[(r*math.cos(t*math.pi/steps),spring+r*math.sin(t*math.pi/steps)) for t in range(steps+1)]

def arch_solid(name,x,bottom,width,spring,yfront,yback,m):
    profile=arch_profile(width,spring);N=len(profile)
    verts=[(x+xx,y,bottom+zz) for y in [yfront,yback] for xx,zz in profile]
    faces=[tuple(reversed(range(N))),tuple(range(N,2*N))]
    faces += [(i,(i+1)%N,(i+1)%N+N,i+N) for i in range(N)]
    o=mesh_object(name,verts,faces,m)
    bm=bmesh.new();bm.from_mesh(o.data);bmesh.ops.recalc_face_normals(bm,faces=list(bm.faces));bm.to_mesh(o.data);bm.free();o.data.update()
    while o.data.uv_layers:o.data.uv_layers.remove(o.data.uv_layers[0])
    metric_uv(o)
    return o

def arch_ring(name,x,bottom,width,spring,thick,yfront,yback,m,region=None,steps=10):
    r=width/2;verts=[];faces=[]
    for i in range(steps+1):
        angle=i*math.pi/steps
        for y in [yfront,yback]:
            for rr in [r,r+thick]:verts.append((x+rr*math.cos(angle),y,bottom+spring+rr*math.sin(angle)))
    for i in range(steps):
        a=i*4;b=(i+1)*4
        faces +=[(a,a+1,b+1,b),(a+2,b+2,b+3,a+3),(a,b,a+2+4,a+2),(a+1,a+3,b+3,b+1)]
    faces += [(0,2,3,1),(steps*4,steps*4+1,steps*4+3,steps*4+2)]
    return mesh_object(name,verts,faces,m,region)

def arch_glass(name,x,bottom,width,spring,y):
    pts=arch_profile(width,spring)
    return mesh_object(name,[(x+xx,y,bottom+zz) for xx,zz in pts],[tuple(range(len(pts)))],glass)

def boolean_cut(wall,cutter):
    bpy.context.view_layer.objects.active=wall
    mod=wall.modifiers.new('Actual recessed aperture','BOOLEAN');mod.operation='DIFFERENCE';mod.solver='EXACT';mod.object=cutter
    bpy.ops.object.modifier_apply(modifier=mod.name)
    if cutter in model:model.remove(cutter)
    bpy.data.objects.remove(cutter,do_unlink=True)

# Main hollow shell: front has actual holes, glass sits0.28m behind the face.
front=box('Front_Ashlar_Wall',(0,-3.8,4.05),(16,.4,8.1),plaster)[0]
box('Back_Wall',(0,3.8,4.05),(16,.4,8.1),plaster)
sidewalls={-1:box('West_Wall',(-7.8,0,4.05),(.4,7.2,8.1),plaster)[0],1:box('East_Wall',(7.8,0,4.05),(.4,7.2,8.1),plaster)[0]}
box('Bank_Floor',(0,0,.08),(16,8,.16),masonry)
for x in [-5.45,0,5.45]:
    w=3.3 if x==0 else 2.55;bottom=0 if x==0 else .75;spring=2.7 if x==0 else 2.05
    cutter=arch_solid('Opening_Cutter',x,bottom,w,spring,-4.5,-3.3,plaster);boolean_cut(front,cutter)
    arch_glass('Recessed_Door_Glass' if x==0 else 'Recessed_Arch_Glass',x,bottom,w-.12,spring,-3.74)
    arch_ring('Carved_Arch',x,bottom,w,spring,.24,-4.22,-3.98,stone)
    arch_ring('Brass_Arch_Liner',x,bottom,w-.12,spring,.07,-4.06,-3.75,gold)
    for sign in [-1,1]:
        box('Stone_Jamb',(x+sign*(w/2+.12),-4.10,bottom+spring/2),(.24,.24,spring),stone,'plinth')
        box('Brass_Jamb',(x+sign*(w/2-.04),-4.025,bottom+spring/2),(.08,.13,spring),gold,'brass')
    box('Window_Sill',(x,-4.23,.09 if x==0 else bottom-.025),(w+.66,.48,.18),stone,'plinth')
    for frac in [-.5,0,.5]:
        xx=x+frac*w/2;top=bottom+spring+math.sqrt(max(0,(w/2-.06)**2-(xx-x)**2))
        box('Arch_Window_Mullion',(xx,-3.96,(bottom+top)/2),(.055,.08,top-bottom),gold,'brass')
    for zz in [bottom+1.,bottom+2.,bottom+spring]:
        box('Window_Crossbar',(x,-3.97,zz),(w-.12,.075,.055),gold,'brass')
    if x==0:
        for sign in [-1,1]:
            box('Door_Walnut_Lower_Panel',(sign*.8,-3.98,.5),(1.5,.12,.94),wood,'wood')
            box('Door_Panel_Upper_Rail',(sign*.8,-4.06,.98),(1.5,.10,.10),gold,'gold_leaf')
            sphere('Door_Boss',(sign*.8,-4.10,.51),.13,gold,scale=(1,.35,1))
            box('Door_Pull',(sign*.13,-4.13,1.42),(.055,.10,.38),gold,'brass')

# Upper wing windows, same physical scale; masonry remains between the openings.
for x in [-6.32,-4.58,4.58,6.32]:
    bottom=5.65;w=1.22;h=1.75
    cutter=box('Upper_Window_Cutter',(x,-3.85,bottom+h/2),(w,.95,h),plaster)[0];boolean_cut(front,cutter)
    mesh_object('Upper_Glass',[(x-w/2,-3.72,bottom),(x+w/2,-3.72,bottom),(x+w/2,-3.72,bottom+h),(x-w/2,-3.72,bottom+h)],[(0,1,2,3)],glass)
    for sign in [-1,1]:
        box('Upper_Stone_Jamb',(x+sign*(w/2+.09),-4.10,bottom+h/2),(.18,.24,h+.36),stone,'plinth')
        box('Upper_Stone_Rail',(x,-4.13,bottom+(h if sign>0 else 0)),(w+.36,.30,.17),stone,'frieze')
    box('Upper_Brass_Mullion',(x,-3.96,bottom+h/2),(.055,.08,h),gold,'brass')
    for zz in [bottom+.58,bottom+1.16]:box('Upper_Crossbar',(x,-3.96,zz),(w,.08,.045),gold,'brass')
    # Four genuine balconettes and gilded over-window relief panels.
    box('Balcony_Floor',(x,-4.32,5.44),(1.66,.76,.16),stone,'plinth')
    box('Balcony_Handrail',(x,-4.64,6.05),(1.66,.20,.13),stone,'frieze')
    for dx in [-.51,0,.51]:baluster('Window_Baluster',x+dx,-4.64,5.52,.47)
    box('Window_Gold_Ornament',(x,-4.29,7.57),(1.35,.15,.27),gold,'gold_leaf')

# UVs rebuilt after Boolean tessellation so reveals retain metric texture density.
while front.data.uv_layers:front.data.uv_layers.remove(front.data.uv_layers[0])
metric_uv(front)
# Side elevations remain architectural when the camera moves: recessed glazing,
# stone arch and two upper windows on each side; rear wall intentionally simpler.
for side,wall in sidewalls.items():
    transform=Matrix.Translation((side*8,0,0))@Matrix.Rotation(side*math.pi/2,4,'Z')
    cutter=arch_solid('Side_Arch_Cutter',0,.9,2.4,1.6,-.5,.6,plaster);cutter.matrix_world=transform@cutter.matrix_world;boolean_cut(wall,cutter)
    start=len(model)
    arch_glass('Side_Recessed_Glass',0,.9,2.28,1.6,.28)
    arch_ring('Side_Stone_Arch',0,.9,2.4,1.6,.18,-.20,.02,stone)
    for sign in [-1,1]:box('Side_Stone_Jamb',(sign*1.29,-.10,1.7),(.18,.24,1.6),stone,'plinth')
    box('Side_Window_Sill',(0,-.18,.9),(2.9,.42,.16),stone,'plinth')
    for xx in [-.55,0,.55]:box('Side_Brass_Mullion',(xx,.06,2.1),(.05,.07,2.4),gold,'brass')
    for zz in [1.8,2.5]:box('Side_Crossbar',(0,.06,zz),(2.3,.07,.05),gold,'brass')
    for o in model[start:]:o.matrix_world=transform@o.matrix_world
    for center in [-1.8,1.8]:
        cutter=box('Side_Upper_Cutter',(center,0,6.5),(1.35,1.1,1.7),plaster)[0];cutter.matrix_world=transform@cutter.matrix_world;boolean_cut(wall,cutter)
        start=len(model)
        mesh_object('Side_Upper_Glass',[(center-.675,.28,5.65),(center+.675,.28,5.65),(center+.675,.28,7.35),(center-.675,.28,7.35)],[(0,1,2,3)],glass)
        for sign in [-1,1]:
            box('Side_Upper_Gold_Jamb',(center+sign*.68,-.03,6.5),(.07,.11,1.78),gold,'brass')
            box('Side_Upper_Gold_Rail',(center,-.03,6.5+sign*.86),(1.44,.11,.07),gold,'brass')
        box('Side_Upper_Mullion',(center,.06,6.5),(.05,.07,1.7),gold,'brass')
        box('Side_Upper_Crossbar',(center,.06,6.5),(1.35,.07,.05),gold,'brass')
        for o in model[start:]:o.matrix_world=transform@o.matrix_world
    while wall.data.uv_layers:wall.data.uv_layers.remove(wall.data.uv_layers[0])
    metric_uv(wall)
for y in [-3.99,3.99]:
    for z,h,depth in [(.18,.36,.28),(4.85,.22,.25),(5.12,.26,.4),(7.72,.18,.22),(8.02,.28,.58)]:
        if y>0:
            if z in (.18,8.02):box('Rear_Plain_Cornice',(0,4.08,z),(16.4,depth,h),masonry)
            continue
        for xx,ww in ([(-5.65,5.1),(5.65,5.1)] if y<0 and z>7.5 else [(0,16.4)]):
            outer=min(.30,max(.15,depth/2))
            box('Running_Stone_Cornice',(xx,math.copysign(4+outer-depth/2,y),z),(ww,depth,h),stone,'frieze')
for x in [-7.99,7.99]:
    for z,h,depth in [(.18,.36,.28),(5.05,.26,.35),(8.02,.28,.58)]:
        outer=min(.30,max(.15,depth/2))
        box('Return_Cornice',(math.copysign(8+outer-depth/2,x),0,z),(depth,8,h),stone if z>7 else masonry,'frieze' if z>7 else None)

# Genuine projecting columns and pilasters. Capital/base rings and flutes cast shadows.
for x in [-3.18,3.18]:
    box('Column_Square_Plinth',(x,-4.25,.26),(.98,.95,.52),stone,'plinth')
    cylinder('Column_Base_Torus',(x,-4.25,.59),.44,.16,gold,'brass')
    cylinder('Column_Base_Stone',(x,-4.25,.75),.39,.18,stone,'plinth')
    for i in range(2):cylinder('Column_Fluted_Shaft',(x,-4.25,1.7+i*1.7),.335,1.7,stone,'shaft',vertices=10)
    cylinder('Column_Gilded_Base_Collar',(x,-4.25,.90),.37,.14,gold,'gold_leaf',vertices=10)
    cylinder('Column_Neck',(x,-4.25,4.31),.37,.16,gold,'brass')
    # Flared acanthus basket as twelve real facets, relief comes from shared trim.
    bpy.ops.mesh.primitive_cone_add(vertices=12,radius1=.37,radius2=.49,depth=.35,location=(x,-4.25,4.55))
    o=bpy.context.object;o.name='Gilded_Corinthian_Capital';finish(o,gold,'gold_leaf')
    box('Capital_Abacus',(x,-4.25,4.80),(1.03,.98,.16),gold,'gold_leaf')
    for sign in [-1,1]:
        sphere('Capital_Volute',(x+sign*.35,-4.59,4.65),.16,gold,scale=(1,.45,.8))
        scroll('Capital_Acanthus_Leaf',[(x+sign*.12,-4.63,4.39),(x+sign*.25,-4.68,4.52),(x+sign*.29,-4.65,4.68)],.065)
for x in [-7.42,7.42]:
    box('Corner_Pilaster',(x,-4.10,3.95),(.61,.31,7.9),stone,'shaft')
    box('Pilaster_Base',(x,-4.2,.40),(.91,.47,.8),stone,'plinth')
    box('Pilaster_Gold_Capital',(x,-4.2,7.74),(.93,.49,.38),gold,'gold_leaf')

# Owner revision3: the roof is a walkable terrace. Stone paving, a low open balustrade on all
# four sides and a rooftop access pavilion with a real arched door, so the balcony zone reads
# as a place people go up to, not a parapet stuck onto a tiled roof.
DECK=8.22
box('Roof_Terrace_Paving',(0,0,DECK-.06),(16,8,.12),masonry)
def balustrade(name,a,b,count):
    # Straight run from a to b (x,y): solid base, rail, turned balusters and coping, ~0.9 m tall.
    (ax,ay),(bx,by)=a,b;cx,cy=(ax+bx)/2,(ay+by)/2;length=math.hypot(bx-ax,by-ay);along_x=abs(bx-ax)>abs(by-ay)
    size=lambda w,h:(length,w,h) if along_x else (w,length,h)
    box(name+'_Base',(cx,cy,DECK+.12),size(.42,.24),masonry)
    box(name+'_Rail',(cx,cy,DECK+.30),size(.46,.12),stone,'frieze')
    box(name+'_Coping',(cx,cy,DECK+.88),size(.50,.16),stone,'frieze')
    for i in range(count):
        t=(i+.5)/count;baluster(name+'_Baluster',ax+(bx-ax)*t,ay+(by-ay)*t,DECK+.30,.50)
for center,width in [(-5.62,4.72),(5.62,4.72)]:
    balustrade('Roof_Front_Balustrade',(center-width/2,-4.02),(center+width/2,-4.02),8)
balustrade('Roof_Rear_Balustrade',(-7.6,4.02),(7.6,4.02),20)
for x in [-8.02,8.02]:
    balustrade('Roof_Side_Balustrade',(x,-3.75),(x,3.75),10)
for x in [-7.42,7.42]:
    for y in [-4.02,4.02]:
        box('Finial_Stone_Pedestal',(x,y,DECK+.45),(.71,.70,.90),stone,'plinth')
        cylinder('Finial_Gold_Collar',(x,y,DECK+.97),.24,.14,gold,'brass',vertices=8)
        sphere('Gold_Finial_Ball',(x,y,DECK+1.21),.27,gold)

# Rooftop access pavilion (stair house) behind the crest: arched walnut door facing the camera,
# corner pilasters, cornice and a small hipped terracotta roof with a gold finial.
PX,PY,PW,PD,PH=0.0,1.75,4.0,2.9,2.7
front_y=PY-PD/2
pavilion=box('Pavilion_Walls',(PX,PY,DECK+PH/2),(PW,PD,PH),plaster)[0]
cutter=arch_solid('Pavilion_Door_Cutter',PX,DECK,1.5,1.55,front_y-.3,front_y+.25,plaster);boolean_cut(pavilion,cutter)
while pavilion.data.uv_layers:pavilion.data.uv_layers.remove(pavilion.data.uv_layers[0])
metric_uv(pavilion)
arch_glass('Pavilion_Fanlight_Glass',PX,DECK,1.38,1.55,front_y+.2)
arch_ring('Pavilion_Door_Arch',PX,DECK,1.5,1.55,.2,front_y-.12,front_y+.02,stone)
for sign in [-1,1]:
    box('Pavilion_Door_Leaf',(PX+sign*.34,front_y+.16,DECK+.78),(.66,.08,1.52),wood,'wood')
    box('Pavilion_Door_Jamb',(PX+sign*.86,front_y-.05,DECK+.78),(.2,.2,1.56),stone,'plinth')
    box('Pavilion_Door_Pull',(PX+sign*.08,front_y+.1,DECK+.95),(.05,.08,.3),gold,'brass')
box('Pavilion_Threshold',(PX,front_y-.25,DECK+.06),(1.9,.5,.12),stone,'plinth')
for sx in [-1,1]:
    for sy in [-1,1]:
        box('Pavilion_Corner_Pilaster',(PX+sx*(PW/2-.12),PY+sy*(PD/2-.12),DECK+PH/2),(.34,.34,PH),stone,'shaft')
box('Pavilion_Cornice',(PX,PY,DECK+PH+.1),(PW+.36,PD+.36,.2),stone,'plinth')
EAVE=DECK+PH+.2;RIDGE=EAVE+.95;ex,ey=PW/2+.35,PD/2+.35
hip=[(PX-ex,PY-ey,EAVE),(PX+ex,PY-ey,EAVE),(PX+ex,PY+ey,EAVE),(PX-ex,PY+ey,EAVE),(PX-.7,PY,RIDGE),(PX+.7,PY,RIDGE)]
mesh_object('Pavilion_Hipped_Roof',hip,[(0,1,5,4),(2,3,4,5),(1,2,5),(3,0,4)],roofmat)
box('Pavilion_Ridge_Capping',(PX,PY,RIDGE+.04),(1.5,.2,.1),roofmat)
cylinder('Pavilion_Finial_Collar',(PX,PY,RIDGE+.14),.16,.12,gold,'brass',vertices=8)
sphere('Gold_Finial_Ball',(PX,PY,RIDGE+.34),.22,gold)
for x in [PX-1.15,PX+1.15]:
    box('Pavilion_Lamp_Bracket',(x,front_y-.12,DECK+2.05),(.08,.3,.08),iron,'iron')
    cylinder('Pavilion_Lamp_Glass',(x,front_y-.3,DECK+1.75),.11,.36,amber,'amber',4)
    cylinder('Pavilion_Lamp_Roof',(x,front_y-.3,DECK+1.98),.17,.1,iron,'iron',4)

# Central raised pediment: real stone blockwork/arch in front of roof.
arch_solid('Central_Attic_Stone_Pediment',0,5.27,5.9,1.4,-4.52,-4.15,plaster)
box('Attic_Lower_Cornice',(0,-4.25,5.28),(6.65,.58,.24),stone,'frieze')
arch_ring('Attic_Arch_Moulding',0,5.27,5.90,1.4,.26,-4.68,-4.33,stone,steps=12)
for sign in [-1,1]:box('Attic_Side_Pier',(sign*3.0,-4.44,6.16),(.44,.44,1.8),stone,'plinth')
arch_ring('Pediment_Gilded_Inner_Relief',0,5.70,4.92,1.20,.085,-4.73,-4.60,gold,steps=10)
for sign in [-1,1]:
    scroll('Pediment_Acanthus_Curl',[(sign*.40,-4.76,6.03),(sign*1.10,-4.77,6.10),(sign*1.77,-4.76,6.40),(sign*2.21,-4.76,6.93),(sign*2.18,-4.76,7.35),(sign*1.95,-4.76,7.42)],.075)
    for x,z in [(1.35,6.2),(1.80,6.55),(2.15,6.98)]:
        scroll('Pediment_Acanthus_Leaf',[(sign*x,-4.78,z),(sign*(x-.17),-4.83,z+.22),(sign*(x-.07),-4.78,z+.36)],.065)
for x in [-5.45,5.45]:
    cylinder('Window_Keystone_Gold_Medallion',(x,-4.25,4.31),.20,.12,gold,'gold_leaf',8,'Y')

def textured_card(name,m,at,size,curve=False,flip=False,region=None):
    nx,ny=(6,4) if curve else (1,1);w,h=size;verts=[];faces=[];uvs=[]
    for j in range(ny+1):
        for i in range(nx+1):
            u=i/nx;v=j/ny;xx=(u-.5)*w;zz=(v-.5)*h
            depth=.12*math.exp(-((u-.5)**2+(v-.48)**2)*10) if curve else 0
            verts.append((at[0]+xx,at[1]-depth,at[2]+zz));uvs.append((1-u if flip else u,v))
    for j in range(ny):
        for i in range(nx):
            a=j*(nx+1)+i;faces.append((a,a+1,a+nx+2,a+nx+1))
    o=mesh_object(name,verts,faces,m)
    for poly in o.data.polygons:
        for li in poly.loop_indices:
            u,v=uvs[o.data.loops[li].vertex_index]
            if region:
                rx,ry,rw,rh=region;u=(rx+u*rw)/512;v=1-(ry+(1-v)*rh)/512
            o.data.uv_layers[0].data[li].uv=(u,v)
    o['uv_kind']='canonical_cutout_projection';return o

# Crowned pig emblem: canonical approved artwork on a curved relief card + bronze mount.
cylinder('Crest_Raised_Mount',(0,-4.70,7.44),1.0,.23,gold,'brass',16,'Y')
textured_card('Crowned_Pig_Heraldic_Relief',crest,(0,-4.86,7.55),(4,3),curve=True,region=(64,0,384,288))
for x in [-6.32,-4.58,4.58,6.32]:
    textured_card('Window_Acanthus_Ornament',crest,(x,-4.39,7.73),(128/96,64/96),region=(0,320,128,64))
for x,z,flip in [(-7.28,6.74,False),(7.22,6.65,True),(-3.18,8.02,False),(3.23,8.05,True),(-7.26,3.95,True),(7.26,3.58,False),(-3.17,4.85,True),(3.13,4.73,False)]:
    textured_card('Separate_Ivy_Cutout',ivy,(x,-4.81 if abs(x)<4 else -4.47,z),(256/96,256/96),flip=flip)

# Two small real wall lanterns; metal, glass and emissive mask are separate.
for x in [-2.28,2.28]:
    box('Lamp_Wall_Bracket',(x,-4.20,3.84),(.10,.48,.10),iron,'iron')
    cylinder('Lamp_Amber_Chamber',(x,-4.53,3.39),.145,.49,amber,'amber',4)
    cylinder('Lamp_Roof',(x,-4.53,3.70),.23,.13,iron,'iron',4)
    cylinder('Lamp_Lower_Rim',(x,-4.53,3.09),.18,.11,gold,'brass',4)
    for sign in [-1,1]:box('Lamp_Front_Mullion',(x+sign*.105,-4.645,3.39),(.025,.04,.52),iron,'iron')
    sphere('Lamp_Finial',(x,-4.53,3.83),.07,gold)

# The whole architectural body is raised60cm, supported by real rusticated stone.
# Four broad15cm risers meet the actual doorway threshold, not a painted decal.
box('Rusticated_Foundation',(0,0,-.30),(16.20,8.15,.60),masonry)
for i in range(4):
    height=.15*(i+1);depth=1.80-i*.40
    box('Entrance_Step_'+str(i+1),(0,-3.95-depth/2,height/2-.60),(8.0-i*.22,depth,height),masonry)
for x in [-5.3,5.3]:
    box('Wing_Rusticated_Plinth',(x,-4.13,.34),(4.25,.38,.68),masonry)
    box('Wing_Plinth_Coping',(x,-4.26,.70),(4.35,.48,.12),stone,'frieze')
for o in model:o.location.z+=.60
bpy.context.view_layer.update()
detail_counts={}
for o in model:
    key=o.name.split('.')[0];detail_counts[key]=detail_counts.get(key,0)+sum(len(p.vertices)-2 for p in o.data.polygons)
print('DETAIL_TRIANGLES',json.dumps(dict(sorted(detail_counts.items(),key=lambda x:-x[1]))))
print('HIGHEST_DETAIL',max((max((o.matrix_world@v.co).z for v in o.data.vertices),o.name) for o in model))

# Cull only fully enclosed faces of small opaque details. Every corner and the face
# centroid must be inside one closed architectural solid. Never cull alpha cards.
# This recovers hidden trim/back faces for real balusters within the6k budget.
occluders=[]
for o in model:
    if o.data.materials[0] in (ivy,crest,glass):continue
    if not (o.get('solid_occluder',False) or o.name.startswith(('Front_Ashlar','Back_Wall','West_Wall','East_Wall','Central_Attic'))):continue
    bm=bmesh.new();bm.from_mesh(o.data);bm.transform(o.matrix_world);bmesh.ops.recalc_face_normals(bm,faces=list(bm.faces))
    tree=BVHTree.FromBMesh(bm);bounds=[o.matrix_world@v.co for v in o.data.vertices]
    lo=Vector(tuple(min(v[k] for v in bounds) for k in range(3)));hi=Vector(tuple(max(v[k] for v in bounds) for k in range(3)))
    occluders.append((o,tree,lo,hi));bm.free()
culled=0
for o in model:
    if o.data.materials[0] in (ivy,crest,glass):continue
    bm=bmesh.new();bm.from_mesh(o.data);remove=[]
    for face in bm.faces:
        points=[o.matrix_world@v.co for v in face.verts];center=sum(points,Vector())/len(points)
        face_normal=(o.matrix_world.to_3x3()@face.normal).normalized()
        probes=[p.lerp(center,.002) for p in points]+[center]
        for solid,tree,lo,hi in occluders:
            if solid==o or any(center[k]<lo[k]-1e-5 or center[k]>hi[k]+1e-5 for k in range(3)):continue
            inside=True
            for p in probes:
                q,n,_,dist=tree.find_nearest(p)
                dot=(p-q).dot(n) if q is not None else 1
                if q is None or dot>1e-5 or (dot>=-1e-5 and n.dot(face_normal)>-.99):inside=False;break
            if inside:remove.append(face);break
    if remove:culled+=sum(len(f.verts)-2 for f in remove);bmesh.ops.delete(bm,geom=remove,context='FACES_ONLY')
    bm.to_mesh(o.data);bm.free();o.data.update()

# Retain logical assembly nodes, but join surfaces by material to keep draw calls low.
bpy.ops.object.select_all(action='DESELECT')
groups={}
for o in model:
    if o.name in bpy.data.objects:groups.setdefault(o.data.materials[0].name,[]).append(o)
joined=[]
for name,objects in groups.items():
    bpy.ops.object.select_all(action='DESELECT')
    for o in objects:o.select_set(True)
    bpy.context.view_layer.objects.active=objects[0];bpy.ops.object.join();o=bpy.context.object;o.name=name+'_Geometry'
    bpy.ops.object.transform_apply(location=True,rotation=True,scale=True);joined.append(o)
    # Remove paired, opposite internal caps between exactly abutting trim modules.
    bm=bmesh.new();bm.from_mesh(o.data);buckets={}
    for f in bm.faces:
        key=tuple(sorted(tuple(round(v.co[k],5) for k in range(3)) for v in f.verts));buckets.setdefault(key,[]).append(f)
    remove=[]
    for bucket in buckets.values():
        if len(bucket)==2 and bucket[0].normal.dot(bucket[1].normal)<-.99:remove+=bucket
    if remove:bmesh.ops.delete(bm,geom=remove,context='FACES_ONLY')
    bm.to_mesh(o.data);bm.free();o.data.update()
    # Triangulate in Blender, not silently in the game importer.
    mod=o.modifiers.new('Export_Triangles','TRIANGULATE');bpy.ops.object.modifier_apply(modifier=mod.name)
triangles=sum(len(o.data.polygons) for o in joined)
root=bpy.data.objects.new('BankHall_Anchor',None);scene.collection.objects.link(root)
for o in joined:o.parent=root
bounds=[(o.matrix_world@v.co) for o in joined for v in o.data.vertices]
lo=[min(v[i] for v in bounds) for i in range(3)];hi=[max(v[i] for v in bounds) for i in range(3)]
report={'triangles':triangles,'mesh_count':len(joined),'material_count':len(materials),'blender_bounds':[lo,hi],
    'native_up':'Z','export_up':'Y','native_front':'-Y','export_front':'+Z','body_size_m':[16,10.5,8],
    'roof':'walkable terrace with access pavilion',
    'revision':'bank3d-roof-terrace-3','hidden_triangles_removed':culled,'foundation_height_m':.6,'entrance_steps':4,'step_rise_m':.15,
    'uv_policy':'Face-local metric isometry96px/m. Canonical curved crest/ivy cards preserve their source-grid projection.',
    'real_features':['Boolean recessed arches/windows0.28m','gilded columns/capitals/bases','projecting cornices15-30cm','walkable roof terrace, open balustrade on four sides, access pavilion with arched door and hipped roof','four real balconettes','pediment raised gilded acanthus relief','rusticated plinth and four entrance steps','separate curved crest and flowering ivy','wall lantern metal/glass'],
    'materials':{name:{'albedo':m['albedo_file'],'cutout':m['cutout'],'glow':m['glow_file']} for name,m in materials.items()}}
(OUT/'model_report.json').write_text(json.dumps(report,indent=2)+'\n')
# glTF separate is packed into GLB later with external PNG URIs retained.
bpy.ops.object.select_all(action='DESELECT');root.select_set(True)
for o in joined:o.select_set(True)
bpy.ops.export_scene.gltf(filepath=str(OUT/'bank_hall.gltf'),export_format='GLTF_SEPARATE',use_selection=True,
    export_texcoords=True,export_normals=True,export_tangents=True,export_materials='EXPORT',
    export_image_format='AUTO',export_keep_originals=True,export_yup=True,export_extras=True)
if '--no-render' in args:
    print('BANK38_GEOMETRY_EXPORTED',json.dumps(report));sys.exit(0)

# Review camera and light are NOT exported into the production asset.
groundmat=bpy.data.materials.new('Review paving only');groundmat.use_nodes=True
gn=groundmat.node_tree.nodes;gl=groundmat.node_tree.links;gp=gn.get('Principled BSDF')
gt=gn.new('ShaderNodeTexImage');gt.image=bpy.data.images.load(str(ROOT/'astra/inbox/hd2d_test/materials/cobble_gold_01.png'));gt.interpolation='Closest';gt.extension='REPEAT';gl.new(gt.outputs['Color'],gp.inputs['Base Color']);gp.inputs['Roughness'].default_value=.95
bpy.ops.mesh.primitive_plane_add(size=70);ground=bpy.context.object;ground.name='QA_Ground';ground.data.materials.append(groundmat)
for face in ground.data.polygons:
    for li in face.loop_indices:
        co=ground.data.vertices[ground.data.loops[li].vertex_index].co;ground.data.uv_layers[0].data[li].uv=(co.x/2,co.y/2)
# Accepted Riko is a scale reference in review only, never included in GLB.
rico_path=ROOT/'astra/inbox/hd2d_test/chars/raccoon_idle.png'
rm=bpy.data.materials.new('QA_Riko_only');rm.use_nodes=True
rn=rm.node_tree.nodes;rl=rm.node_tree.links;rp=rn.get('Principled BSDF');rt=rn.new('ShaderNodeTexImage');rt.image=bpy.data.images.load(str(rico_path));rt.interpolation='Closest'
rl.new(rt.outputs['Color'],rp.inputs['Base Color']);rl.new(rt.outputs['Alpha'],rp.inputs['Alpha']);rm.surface_render_method='DITHERED';rp.inputs['Roughness'].default_value=.85
rmesh=bpy.data.meshes.new('QA_Riko');rmesh.from_pydata([(-4.5-128/96,-6.3,-32/96),(-4.5+128/96,-6.3,-32/96),(-4.5+128/96,-6.3,224/96),(-4.5-128/96,-6.3,224/96)],[],[(0,1,2,3)]);rmesh.materials.append(rm)
ro=bpy.data.objects.new('QA_Riko_1_75m',rmesh);scene.collection.objects.link(ro);uv=rmesh.uv_layers.new(name='UVMap')
for li,coord in zip(rmesh.polygons[0].loop_indices,[(0,0),(1,0),(1,1),(0,1)]):uv.data[li].uv=coord
scene.render.engine='CYCLES';scene.cycles.samples=64;scene.cycles.use_denoising=False;scene.cycles.max_bounces=4
scene.render.resolution_x=1920;scene.render.resolution_y=1080;scene.render.resolution_percentage=100
scene.render.image_settings.file_format='PNG';scene.view_settings.view_transform='AgX'
scene.world.use_nodes=True;bg=scene.world.node_tree.nodes.get('Background');bg.inputs['Color'].default_value=(.40,.49,.66,1);bg.inputs['Strength'].default_value=.45
bpy.ops.object.light_add(type='SUN',location=(-10,-10,20));sun=bpy.context.object;sun.name='QA_Sun';sun.rotation_euler=(math.radians(28),math.radians(-26),math.radians(-28));sun.data.energy=2.2;sun.data.angle=math.radians(4)
bpy.ops.object.camera_add();camera=bpy.context.object;scene.camera=camera
camera.data.sensor_fit='VERTICAL';camera.data.sensor_height=24;camera.data.lens=24/(2*math.tan(math.radians(30)/2))
def place_camera(side=0):
    target=Vector((0,-1.2,4.75));pitch=math.radians(32);yaw=math.radians(side)
    camera.location=target+Vector((math.sin(yaw)*math.cos(pitch)*28,-math.cos(yaw)*math.cos(pitch)*28,math.sin(pitch)*28))
    camera.rotation_euler=(target-camera.location).to_track_quat('-Z','Y').to_euler()
    camera.data.dof.use_dof=False
for name,side in ([('bank_day',0)] if '--day-only' in args else [('bank_day',0),('bank_three_quarter',24)]):
    place_camera(side);scene.render.filepath=str(OUT/(name+'.png'));bpy.ops.render.render(write_still=True)
if '--day-only' in args:
    bpy.ops.wm.save_as_mainfile(filepath=str(OUT/'bank_review.blend'))
    print('BANK38_MODEL_EXPORTED',json.dumps(report));sys.exit(0)
place_camera(0);sun.data.energy=.18;bg.inputs['Strength'].default_value=.22
for m in [glass,amber]:m.node_tree.nodes.get('Principled BSDF').inputs['Emission Strength'].default_value=.7
scene.render.filepath=str(OUT/'bank_evening.png');bpy.ops.render.render(write_still=True)
bpy.ops.wm.save_as_mainfile(filepath=str(OUT/'bank_review.blend'))
print('BANK38_MODEL_EXPORTED',json.dumps(report))
