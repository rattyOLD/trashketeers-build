"""Native-grid sculptural prop study, Blender 4.3. No supersampling/resizing."""
import bpy
import os
import math
import random
from mathutils import Vector
from pathlib import Path

OUT=Path(os.environ.get('TRASHSQUAD_V36_RENDER_DIR','/tmp/trashsquad-v36-native'))
OUT.mkdir(parents=True,exist_ok=True)
random.seed(718)
bpy.ops.object.select_all(action='SELECT')
bpy.ops.object.delete(use_global=False)
scene=bpy.context.scene
scene.render.engine='CYCLES'
scene.cycles.device='CPU'
scene.cycles.samples=1024
scene.cycles.use_denoising=False
scene.cycles.pixel_filter_type='BOX'
scene.cycles.filter_width=.01
scene.render.film_transparent=True
scene.render.image_settings.file_format='PNG'
scene.render.image_settings.color_mode='RGBA'
scene.render.image_settings.color_depth='8'
scene.render.resolution_percentage=100
scene.render.dither_intensity=0
scene.view_settings.view_transform='Standard'
scene.view_settings.look='None'
scene.view_settings.exposure=0
scene.view_settings.gamma=1
scene.render.threads_mode='FIXED'
scene.render.threads=4
scene.world.color=(.28,.28,.28)
world=scene.world
world.use_nodes=True
world.node_tree.nodes['Background'].inputs['Color'].default_value=(.70,.72,.76,1)
world.node_tree.nodes['Background'].inputs['Strength'].default_value=.30

CATS=['iron','brass','amber_glass','stone','terracotta','foliage','petals','white','earth']
IDS=[(1,0,0),(0,1,0),(0,0,1),(1,1,0),(1,0,1),(0,1,1),(.5,0,1),(1,.5,0),(.5,1,0)]
MATS=[]


def linear(h):
    return tuple(((v/255+.055)/1.055)**2.4 if v/255>.04045 else v/255/12.92 for v in bytes.fromhex(h))


def mat(name,color,cat,metal=0,rough=.55,alpha=1):
    m=bpy.data.materials.new(name)
    m.use_nodes=True
    n=m.node_tree.nodes.get('Principled BSDF')
    n.inputs['Base Color'].default_value=(*linear(color),1)
    n.inputs['Metallic'].default_value=metal
    n.inputs['Roughness'].default_value=rough
    n.inputs['Alpha'].default_value=alpha
    m['category']=cat
    MATS.append(m)
    return m


iron=mat('Oxidised iron','292a32','iron',.25,.6)
iron_dark=mat('Iron underside','272832','iron',.2,.55)
brass=mat('Brass','ca923c','brass',.65,.3)
brass_dark=mat('Brass crevice','805128','brass',.35,.45)
brass_light=mat('Brass collar','e1b34e','brass',.6,.3)
glass=mat('Amber glass','bfa16c','amber_glass',.05,.20,.25)
glass_glint=mat('Glass glint','e9dab3','amber_glass',.12,.2,.52)
bulb=mat('Unlit quartz bulb','dac08b','amber_glass',.08,.32,.46)
filament=mat('Visible tungsten thread','ffe39a','amber_glass',0,.35)
stone=mat('Warm limestone','c6bca9','stone',0,.9)
stone_top=mat('Stone cornice','d5cab2','stone',0,.8)
stone_deep=mat('Stone crevice','736c60','stone',0,1)
stone_patch=mat('Stone wear','b0a28a','stone',0,.95)
for m in [stone,stone_top]:
    nodes=m.node_tree.nodes
    links=m.node_tree.links
    principled=nodes.get('Principled BSDF')
    base=list(principled.inputs['Base Color'].default_value)
    noise=nodes.new('ShaderNodeTexNoise')
    noise.inputs['Scale'].default_value=5.0
    noise.inputs['Detail'].default_value=1
    ramp=nodes.new('ShaderNodeValToRGB')
    ramp.color_ramp.elements[0].position=.28
    ramp.color_ramp.elements[0].color=tuple([c*.84 for c in base[:3]]+[1])
    ramp.color_ramp.elements[1].position=.72
    ramp.color_ramp.elements[1].color=tuple([min(1,c*1.10) for c in base[:3]]+[1])
    links.new(noise.outputs['Fac'],ramp.inputs['Fac'])
    links.new(ramp.outputs['Color'],principled.inputs['Base Color'])
terra=mat('Fluted terracotta','ce8050','terracotta',0,.6)
terra_dark=mat('Clay foot','9b5238','terracotta',0,.8)
terra_rim=mat('Glazed worn rim','e5a169','terracotta',.05,.38)
greens=[mat('Leaf '+str(i),h,'foliage',0,.65) for i,h in enumerate(['426a34','598438','779f40','96b34e'])]
stemmat=mat('Leaf veins','3e5d30','foliage',0,.9)
pink=mat('Dusty pink petals','df8693','petals',0,.62)
pink_dark=mat('Petal folds','bc5c70','petals',0,.72)
white=mat('Ivory petals','eee7d5','white',0,.65)
yellow=mat('Flower stamens','e2b750','brass',0,.65)
soil=mat('Garden earth','6c5550','earth',0,1)


def assign(obj,m):
    obj.data.materials.append(m)
    return obj


def bevelbox(name,loc,size,m,bevel=.015):
    bpy.ops.mesh.primitive_cube_add(size=1,location=loc)
    o=bpy.context.object
    o.name=name
    o.dimensions=size
    bpy.ops.object.transform_apply(location=False,rotation=False,scale=True)
    assign(o,m)
    if bevel:
        mod=o.modifiers.new('Sculpted edges','BEVEL')
        mod.width=bevel
        mod.segments=2
        mod.affect='EDGES'
        normal=o.modifiers.new('Weighted corners','WEIGHTED_NORMAL')
        normal.keep_sharp=True
    return o


def sphere(name,loc,scale,m):
    bpy.ops.mesh.primitive_uv_sphere_add(segments=16,ring_count=8,radius=1,location=loc)
    o=bpy.context.object
    o.name=name
    o.scale=scale if hasattr(scale,'__len__') else (scale,scale,scale)
    assign(o,m)
    for p in o.data.polygons:p.use_smooth=True
    return o


def tube(name,pts,r,m):
    curve=bpy.data.curves.new(name,'CURVE')
    curve.dimensions='3D'
    curve.resolution_u=1
    curve.bevel_depth=r
    curve.bevel_resolution=2
    s=curve.splines.new('POLY')
    s.points.add(len(pts)-1)
    for p,co in zip(s.points,pts):p.co=(*co,1)
    o=bpy.data.objects.new(name,curve)
    bpy.context.collection.objects.link(o)
    assign(o,m)
    return o


def lathe(name,profile,m,n=48,flute=0):
    verts=[]
    for j,(z,r) in enumerate(profile):
        for i in range(n):
            angle=2*math.pi*i/n
            f=1+flute*math.cos(angle*12)*math.sin(math.pi*j/(len(profile)-1))
            verts.append((r*f*math.cos(angle),r*f*math.sin(angle),z))
    faces=[]
    for j in range(len(profile)-1):
        for i in range(n):faces.append((j*n+i,j*n+(i+1)%n,(j+1)*n+(i+1)%n,(j+1)*n+i))
    faces.extend([tuple(range(n-1,-1,-1)),tuple((len(profile)-1)*n+i for i in range(n))])
    mesh=bpy.data.meshes.new(name)
    mesh.from_pydata(verts,[],faces)
    mesh.update()
    o=bpy.data.objects.new(name,mesh)
    bpy.context.collection.objects.link(o)
    assign(o,m)
    for p in mesh.polygons:p.use_smooth=len(p.vertices)==4
    return o


def frustum(name,z0,z1,w0,d0,w1,d1,m):
    verts=[(-w0/2,-d0/2,z0),(w0/2,-d0/2,z0),(w0/2,d0/2,z0),(-w0/2,d0/2,z0),
           (-w1/2,-d1/2,z1),(w1/2,-d1/2,z1),(w1/2,d1/2,z1),(-w1/2,d1/2,z1)]
    faces=[(0,3,2,1),(4,5,6,7),(0,1,5,4),(1,2,6,5),(2,3,7,6),(3,0,4,7)]
    mesh=bpy.data.meshes.new(name)
    mesh.from_pydata(verts,[],faces)
    mesh.update()
    o=bpy.data.objects.new(name,mesh)
    bpy.context.collection.objects.link(o)
    assign(o,m)
    bevel=o.modifiers.new('Roof rim rounding','BEVEL')
    bevel.width=.012
    bevel.segments=2
    return o


def leaf(name,loc,size,angle,m,tilt=0):
    # Folded, eight-lobed ivy blade. The crease and changing normal shade it.
    shape=[(0,-.60),(-.24,-.27),(-.5,-.13),(-.38,.10),(-.48,.31),
           (-.17,.32),(0,.48),(.17,.32),(.48,.31),(.38,.10),(.5,-.13),(.24,-.27)]
    verts=[(0,-.045*size,0)]
    for x,z in shape:
        xx=(x*math.cos(angle)-z*math.sin(angle))*size
        zz=(x*math.sin(angle)+z*math.cos(angle))*size
        verts.append((xx,tilt*zz,zz))
    faces=[(0,i+1,(i+1)%len(shape)+1) for i in range(len(shape))]
    mesh=bpy.data.meshes.new(name)
    mesh.from_pydata(verts,[],faces)
    mesh.update()
    o=bpy.data.objects.new(name,mesh)
    bpy.context.collection.objects.link(o)
    o.location=loc
    assign(o,m)
    # A short vein is large enough to survive native-grid rasterisation.
    start=Vector(loc)+Vector((0,-.05*size,0))
    end=Vector(loc)+Vector((-.22*size*math.sin(angle),-.027*size,.22*size*math.cos(angle)))
    tube(name+' vein',[start,end],.007,stemmat)
    return o


def make_lamp():
    bevelbox('Stepped cast-iron foot',(0,0,.035),(.42,.30,.07),iron_dark,.02)
    bevelbox('Brass foot edge',(0,0,.078),(.38,.27,.025),brass_light,.009)
    lathe('Turned slender stem',[(.09,.13),(.13,.095),(.16,.057),(.30,.057),(.33,.10),(.36,.12)],iron)
    for z,r in [(.12,.10),(.20,.065),(.32,.10),(.36,.125)]:
        lathe('Stem collar',[(z-.012,r),(z+.012,r)],brass_light)
    # Spirals are real rounded metal, with a dark cavity and bright upper lip.
    for sign in (-1,1):
        pts=[]
        for i in range(42):
            t=i/41*math.pi*2.1
            r=.125*(1-.62*i/41)
            pts.append((sign*(.25+r*math.cos(t)),-.15,.40+r*math.sin(t)))
        tube('Forged brass scroll',pts,.022,brass)
        tube('Scroll root',[(sign*.07,-.1,.30),(sign*.15,-.14,.37),pts[0]],.02,brass_dark)
    bevelbox('Chamber bottom',(0,0,.53),(.75,.44,.065),iron_dark,.02)
    bevelbox('Bottom brass lip',(0,0,.572),(.70,.40,.025),brass_light,.009)
    bevelbox('Inner chamber back',(0,.16,.90),(.61,.035,.62),iron_dark,.012)
    bevelbox('Interior floor',(0,0,.60),(.60,.32,.025),brass_dark,.008)
    # Unlit bulb and tungsten loop: warm glass, no emission at all in albedo.
    lathe('Bulb socket',[(.60,.065),(.66,.065),(.69,.035),(.73,.035)],brass)
    sphere('Quartz bulb',(0,-.04,.85),(.07,.055,.16),bulb)
    tube('Visible filament',[(-.025,-.19,.76),(-.025,-.19,.96),(0,-.19,.99),(.025,-.19,.96),(.025,-.19,.76)],.013,filament)
    bevelbox('Amber glass plane',(0,-.176,.905),(.59,.007,.61),glass,.01)
    # A restrained reflection, equally present on both panes.
    for x in (-.235,.22):
        bevelbox('Glass vertical glint',(x,-.195,1.015),(.023,.005,.22),glass_glint,.004)
    # Two internal mullions plus the outer frame are opaque iron geometry.
    # They remain black in the glow pass rather than painted over by emission.
    for x in (-.32,-.115,.115,.32):
        bevelbox('Iron vertical mullion',(x,-.204,.90),(.035,.035,.66),iron_dark,.006)
        if abs(x)>.3:
            bevelbox('Brass frame bevel',(x-.006,-.227,.90),(.011,.008,.62),brass,.003)
    for x in (-.32,.32):
        for y in (-.19,.19):
            tube('Brass corner post',[(x,y,.60),(x,y,1.21)],.018,brass)
            for z in (.59,1.20):sphere('Frame rivet',(x,y-.015,z),.032,brass_light)
    bevelbox('Eave deep shadow',(0,0,1.245),(.94,.58,.07),iron_dark,.012)
    bevelbox('Brass eave rim',(0,0,1.29),(1.16,.67,.035),brass,.012)
    bevelbox('Eave upper bead',(0,0,1.318),(1.18,.69,.022),brass_light,.008)
    frustum('Steep dark iron roof',1.33,1.64,1.12,.63,.32,.22,iron)
    for sx in (-1,1):
        for sy in (-1,1):
            tube('Roof brass seam',[(sx*.56,sy*.315,1.34),(sx*.16,sy*.11,1.64)],.019,brass)
    tube('Front central roof rib',[(0,-.325,1.34),(0,-.12,1.64)],.018,brass)
    for x in (-.54,.54):
        neck=lathe('Corner finial neck',[(1.34,.031),(1.40,.031)],brass)
        neck.location=(x,-.29,0)
        sphere('Corner ball',(x,-.29,1.445),.06,brass_light)
    lathe('Top finial collars',[(1.64,.15),(1.67,.15),(1.70,.09),(1.72,.09)],brass)
    sphere('Large brass finial',(0,0,1.82),(.12,.12,.115),brass_light)
    lathe('Finial crown',[(1.91,.035),(1.95,.02)],brass)


def chip(o,loc,r):
    bpy.ops.mesh.primitive_ico_sphere_add(subdivisions=1,radius=r,location=loc)
    cutter=bpy.context.object
    mod=o.modifiers.new('Chipped stone','BOOLEAN')
    mod.operation='DIFFERENCE'
    mod.solver='EXACT'
    mod.object=cutter
    bpy.context.view_layer.objects.active=o
    bpy.ops.object.modifier_apply(modifier=mod.name)
    bpy.data.objects.remove(cutter,do_unlink=True)


def seam(o,loc,size):
    cutter=bevelbox('Mortar cutter',loc,size,stone_deep,0)
    mod=o.modifiers.new('Open masonry joint','BOOLEAN')
    mod.operation='DIFFERENCE'
    mod.solver='EXACT'
    mod.object=cutter
    bpy.context.view_layer.objects.active=o
    bpy.ops.object.modifier_apply(modifier=mod.name)
    bpy.data.objects.remove(cutter,do_unlink=True)


def make_pedestal():
    foot=bevelbox('Broad limestone plinth',(0,0,.08),(1.78,1.04,.16),stone_patch,.035)
    bevelbox('Plinth upper step',(0,0,.205),(1.58,.90,.095),stone_top,.025)
    body=bevelbox('Masonry core',(0,0,.75),(1.38,.78,1.02),stone,.025)
    bevelbox('Under cornice shadow',(0,0,1.27),(1.52,.86,.07),stone_patch,.018)
    cap=bevelbox('Massive cornice',(0,0,1.365),(1.84,1.08,.15),stone_top,.035)
    upper=bevelbox('Flat upper cap',(0,0,1.465),(1.72,1.0,.06),stone,.014)
    seam(cap,(-.24,0,1.38),(.025,1.2,.30))
    seam(upper,(-.24,0,1.47),(.025,1.2,.20))
    for o,loc,r in [(foot,(-.86,-.50,.14),.10),(foot,(.42,-.52,.03),.09),
                    (cap,(-.90,-.5,1.42),.08),(cap,(.37,-.55,1.40),.10),
                    (cap,(.91,-.3,1.33),.09),(body,(-.68,-.38,.91),.065)]:
        chip(o,loc,r)
    # Carved baroque panel. Profile is actual raised/recessed relief.
    outline=[(-.25,.47),(.25,.47),(.25,.39),(.30,.39),(.30,.34),(.36,.34),
             (.36,-.34),(.30,-.34),(.30,-.39),(.25,-.39),(.25,-.47),
             (-.25,-.47),(-.25,-.39),(-.30,-.39),(-.30,-.34),(-.36,-.34),
             (-.36,.34),(-.30,.34),(-.30,.39),(-.25,.39)]
    profile=[(1.,-.408),(.99,-.46),(.94,-.53),(.88,-.53),(.83,-.43),(.78,-.44)]
    verts=[]
    for scale,y in profile:
        verts.extend([(x*scale,y,.76+z*scale) for x,z in outline])
    n=len(outline)
    faces=[]
    for j in range(len(profile)-1):
        for i in range(n):faces.append((j*n+i,j*n+(i+1)%n,(j+1)*n+(i+1)%n,(j+1)*n+i))
    faces.append(tuple((len(profile)-1)*n+i for i in range(n)))
    faces=[tuple(reversed(f)) for f in faces]
    mesh=bpy.data.meshes.new('Panel relief')
    mesh.from_pydata(verts,[],faces)
    mesh.update()
    o=bpy.data.objects.new('Deeply carved panel',mesh)
    bpy.context.collection.objects.link(o)
    assign(o,stone_top)
    # Small, coherent worn areas sit outside the carved panel.
    for x,z,w,h in [(-.49,.57,.07,.10),(.50,1.04,.06,.08),(-.55,1.13,.05,.05),(.56,.35,.07,.055)]:
        sphere('Stone patina',(x,-.393,z),(w,.007,h),stone_patch)
    # Mortar joints outside the carved central slab.
    for side in (-1,1):
        for z in (.45,.89,1.13):
            tube('Masonry joint',[(side*.49,-.402,z),(side*.67,-.402,z)],.012,stone_deep)
        tube('Outer quoin seam',[(side*.58,-.404,.29),(side*.58,-.404,.43)],.008,stone_patch)
    cracks=[[(.30,-.552,1.44),(.33,-.555,1.41),(.31,-.555,1.37),(.35,-.554,1.32)],
            [(-.32,-.522,.145),(-.28,-.525,.11),(-.30,-.526,.06),(-.27,-.525,.02)],
            [(.62,-.403,.70),(.58,-.405,.73),(.56,-.405,.78)]]
    for pts in cracks:tube('Dark fissure',pts,.012,stone_deep)
    for side in (-1,1):
        pts=[(side*(.65+.035*math.sin(i)), -.42,.25+i*.085) for i in range(11)]
        tube('Ivy stem on stone',pts,.012,stemmat)
        for i in range(9):
            z=.32+i*.10
            x=side*(.64+(.06 if i%2 else -.02))
            leaf('Stone ivy',(x,-.46,z),.16+random.random()*.04,side*(.5 if i%2 else -.45),random.choice(greens),.1)
    for x,z in [(-.61,.16),(.53,.16),(-.67,1.43),(.56,1.43)]:
        y=-.54 if z>1 else -.51
        for i in range(5):
            sphere('Moss patch',(x+random.uniform(-.06,.06),y,z+random.uniform(-.015,.015)),(.055,.025,.03),greens[i%3])


def flower(loc,r,white_flower=False):
    x,y,z=loc
    m=white if white_flower else pink
    for i in range(6):
        t=i*math.pi/3
        o=sphere('Flower petal',(x+math.sin(t)*r*.58,y,z+math.cos(t)*r*.58),
                 (r*.44,r*.20,r*.62),m)
        o.rotation_euler.y=t
    sphere('Golden flower center',(x,y-r*.24,z),(r*.27,r*.18,r*.27),yellow)
    for dx,dz in [(-.12,0),(.12,.08),(0,-.12)]:
        sphere('Stamens',(x+dx*r,y-r*.42,z+dz*r),r*.055,brass_light)


def make_planter():
    lathe('Deep round fluted terracotta',[(.12,.30),(.16,.34),(.22,.38),(.34,.44),(.53,.49),(.72,.51),(.86,.49),(.91,.51)],terra,64,.09)
    lathe('Pot foot',[(.025,.32),(.06,.36),(.11,.36),(.14,.31)],terra_dark)
    lathe('Foot bead',[(.09,.355),(.115,.355)],terra_dark)
    lathe('Thick elliptical lip',[(.87,.51),(.89,.55),(.94,.56),(.97,.53),(.97,.44),(.91,.43)],terra_rim)
    lathe('Rim underside',[(.845,.497),(.88,.52)],terra_dark)
    lathe('Soil',[(.91,.43),(.94,.43)],soil)
    # Large embossed clay ribs/petals on the body.
    for angle in [-2.28,-1.93,-1.57,-1.21,-.86]:
        pts=[]
        for i in range(25):
            t=i*2*math.pi/24
            a=angle+math.sin(t)*.14
            z=.50+math.cos(t)*.18
            r=.49+.017*math.cos(t)
            pts.append((math.cos(a)*r,math.sin(a)*r,z))
        tube('Embossed terracotta flute',pts,.008,terra)
    # Deliberate organic crowns, each leaf is 6–12 native pixels, not speckles.
    crowns=[(-.43,-.12,1.11),(-.25,.03,1.43),(0,.04,1.50),(.29,.01,1.48),(.48,-.10,1.19),(0,-.25,1.14)]
    for j,(cx,cy,cz) in enumerate(crowns):
        tube('Flower stem',[(0,0,.94),(cx*.6,cy,cz-.2),(cx,cy,cz)],.012,stemmat)
        for i in range(10):
            a=i*2.399+j*.3
            r=.10+.12*(i%3)/2
            x=cx+math.cos(a)*r
            z=cz+math.sin(a)*r*.7
            y=cy-.06-.04*(i%3)
            leaf('Canopy ivy',(x,y,z),.22+random.random()*.09,math.sin(a)*.9,random.choice(greens),-.25)
    # Three trailing strands cover rim and break the silhouette down to ground.
    for side in (-1,1):
        pts=[]
        for i in range(18):
            t=i/17
            pts.append((side*(.43+.17*math.sin(t*math.pi)), -.39-.11*t,1.02-.90*t))
        tube('Trailing ivy',pts,.014,stemmat)
        for i in range(10):
            t=i/10
            x=side*(.44+.17*math.sin(t*math.pi))
            leaf('Hanging ivy leaf',(x,-.42-.11*t,1.0-.90*t),.22,.45*side*(-1 if i%2 else 1),random.choice(greens),-.1)
    tube('Front trailing stem',[(.1,-.48,1.05),(.2,-.56,.83),(.13,-.57,.65)],.012,stemmat)
    for x,z in [(.10,.98),(.18,.86),(.14,.72)]:leaf('Front ivy',(x,-.58,z),.19,-.5,greens[2])
    # Big heads, medium heads, small buds: all have a yellow center.
    heads=[(-.25,-.31,1.52,.145,False),(.18,-.31,1.64,.14,False),
           (-.02,-.39,1.35,.125,True),(.44,-.32,1.27,.13,True),
           (-.47,-.32,1.17,.11,False),(.21,-.42,1.13,.105,False),
           (-.28,-.29,1.25,.085,True),(.42,-.25,1.51,.075,False),
           (-.05,-.16,1.68,.06,False),(-.54,-.18,1.39,.055,False)]
    for x,y,z,r,w in heads:flower((x,y,z),r,w)


def emission_override(mode):
    for m in MATS:
        nodes=m.node_tree.nodes
        links=m.node_tree.links
        for n in list(nodes):nodes.remove(n)
        out=nodes.new('ShaderNodeOutputMaterial')
        em=nodes.new('ShaderNodeEmission')
        links.new(em.outputs[0],out.inputs['Surface'])
        if mode=='id':
            color=IDS[CATS.index(m['category'])]
            em.inputs['Color'].default_value=(*color,1)
        elif mode=='glow':
            # The glass glows gently; the thread is brighter. Iron and the
            # reflection stay black so they survive the evening emission.
            value=0
            if m.name=='Amber glass':value=48/255
            elif m.name=='Visible tungsten thread':value=1
            em.inputs['Color'].default_value=(value,value,value,1)
        elif mode=='normal':
            geom=nodes.new('ShaderNodeNewGeometry')
            transform=nodes.new('ShaderNodeCombineXYZ')
            basis=scene.camera.rotation_euler.to_quaternion()
            for socket,axis in zip(['X','Y','Z'],[(1,0,0),(0,1,0),(0,0,1)]):
                dot=nodes.new('ShaderNodeVectorMath')
                dot.operation='DOT_PRODUCT'
                dot.inputs[1].default_value=basis@Vector(axis)
                links.new(geom.outputs['Normal'],dot.inputs[0])
                links.new(dot.outputs['Value'],transform.inputs[socket])
            scale=nodes.new('ShaderNodeVectorMath')
            scale.operation='SCALE'
            scale.inputs[3].default_value=.5
            links.new(transform.outputs['Vector'],scale.inputs[0])
            add=nodes.new('ShaderNodeVectorMath')
            add.operation='ADD'
            add.inputs[1].default_value=(.5,.5,.5)
            links.new(scale.outputs['Vector'],add.inputs[0])
            links.new(add.outputs['Vector'],em.inputs['Color'])


def render(name,size,make):
    before=set(bpy.data.objects)
    make()
    bpy.context.view_layer.update()
    objects=[o for o in bpy.data.objects if o not in before]
    depsgraph=bpy.context.evaluated_depsgraph_get()
    corners=[]
    for o in objects:
        if o.type in {'MESH','CURVE'}:
            evaluated=o.evaluated_get(depsgraph)
            mesh=evaluated.to_mesh()
            corners.extend(evaluated.matrix_world@v.co for v in mesh.vertices)
            evaluated.to_mesh_clear()
    direction=Vector((0,-math.cos(math.radians(25)),math.sin(math.radians(25))))
    rot=(-direction).to_track_quat('-Z','Y')
    inv=rot.inverted()
    projected=[inv@c for c in corners]
    xmin,xmax=min(p.x for p in projected),max(p.x for p in projected)
    ymin,ymax=min(p.y for p in projected),max(p.y for p in projected)
    center=rot@Vector(((xmin+xmax)/2,(ymin+ymax)/2,0))
    bpy.ops.object.camera_add(location=center+direction*8)
    camera=bpy.context.object
    camera.rotation_euler=rot.to_euler()
    camera.data.type='ORTHO'
    camera.data.ortho_scale=max((ymax-ymin)*size[0]/(size[1]-4),(xmax-xmin)*size[0]/(size[0]-4))
    # ortho_scale is horizontal extent in Blender's landscape/portrait camera.
    # Set fit explicitly so height is independent of aspect and no pixels resize.
    camera.data.sensor_fit='HORIZONTAL'
    print('BOUNDS',name,(xmin,xmax,ymin,ymax),'ortho',camera.data.ortho_scale,flush=True)
    scene.camera=camera
    scene.render.resolution_x,scene.render.resolution_y=size
    lights=[]
    for loc,power,radius in [((0,-3.5,6),260,4),((0,3,4),100,3)]:
        bpy.ops.object.light_add(type='AREA',location=loc)
        light=bpy.context.object
        light.data.energy=power
        light.data.shape='DISK'
        light.data.size=radius
        light.rotation_euler=(Vector((0,0,.8))-light.location).to_track_quat('-Z','Y').to_euler()
        lights.append(light)
    # Save materials and one native beauty render, then data-only passes.
    scene.render.filepath=str(OUT/(name+'_beauty.png'))
    bpy.ops.render.render(write_still=True)
    for mode in ['id','glow','normal']:
        emission_override(mode)
        scene.view_settings.view_transform='Raw'
        scene.render.filepath=str(OUT/(name+'_'+mode+'.png'))
        # One center sample keeps material labels categorical: averaging red
        # iron and green brass labels must not invent a yellow stone label.
        scene.cycles.samples=1 if mode=='id' else 4
        bpy.ops.render.render(write_still=True)
    # Each model runs in its own process, so no restoration of node graphs needed.
    print('NATIVE_MODEL_RENDER_OK',name,size,flush=True)


if __name__=='__main__':
    import sys
    name=sys.argv[sys.argv.index('--')+1]
    if name=='lamp':render('bank_lantern',(64,92),make_lamp)
    elif name=='pedestal':render('bank_pedestal',(104,88),make_pedestal)
    elif name=='planter':render('bank_flower_planter',(96,100),make_planter)
    else:raise ValueError(name)
