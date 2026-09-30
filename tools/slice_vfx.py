import numpy as np
from PIL import Image
U='/root/.claude/uploads/0fd7481c-189d-5931-953e-db25d6f3cd99/'
O='/home/claude/raccoon/assets/vfx/'
def key(im):
    a=np.asarray(im.convert('RGB')).astype(np.float32)/255
    R,G,B=a[...,0],a[...,1],a[...,2]
    m=np.clip((np.minimum(R,B)-G-0.3)/0.3,0,1)*np.clip((1-np.abs(R-B)-0.75)/0.15,0,1)
    al=1-m
    cap=G+0.12
    edge=(al<0.999)&(al>0)
    R2=np.where(edge,np.minimum(R,cap),R);B2=np.where(edge,np.minimum(B,cap),B)
    out=np.dstack([R2,G,B2,al]);out[al<0.02]=0
    return Image.fromarray((out*255).astype(np.uint8),'RGBA')
def grid(f,cols,rows,cell,name,skip=()):
    im=key(Image.open(U+f)); w,h=im.size; cw,ch=w/cols,h/rows
    cw_o,ch_o=cell if isinstance(cell,tuple) else (cell,cell)
    sheet=Image.new('RGBA',(cw_o*cols,ch_o*rows),(0,0,0,0))
    for r in range(rows):
        for c in range(cols):
            if r*cols+c in skip: continue
            t=im.crop((int(c*cw),int(r*ch),int((c+1)*cw),int((r+1)*ch)))
            t.thumbnail((cw_o,ch_o),Image.LANCZOS)
            sheet.paste(t,(c*cw_o+(cw_o-t.width)//2,r*ch_o+(ch_o-t.height)//2),t)
    sheet.save(O+name,optimize=True); print(name,sheet.size)

def stack(f,n,cell,name):
    im=key(Image.open(U+f)); w,h=im.size; ch=h/n
    sheet=Image.new('RGBA',(cell[0],cell[1]*n),(0,0,0,0))
    for r in range(n):
        t=im.crop((0,int(r*ch),w,int((r+1)*ch))); t.thumbnail(cell,Image.LANCZOS)
        sheet.paste(t,((cell[0]-t.width)//2,r*cell[1]+(cell[1]-t.height)//2),t)
    sheet.save(O+name,optimize=True); print(name,sheet.size)
grid('025f4d46-image.png',4,2,160,'ice_block.png')
grid('0a36e442-image.png',4,2,128,'icons_status.png')
grid('6628f634-image.png',4,2,128,'icons_attach.png')
for r,fs in {'common':('199b2215','1c5cafae','53d9c0ca'),'rare':('c1a7138f','b9aff553','9d5f6f63'),'epic':('811e4bb0','84fc16c2','c7d9d481')}.items():
    grid(fs[0]+'-image.png',4,2,128,'bullets_%s.png'%r)
    grid(fs[1]+'-image.png',4,2,128,'muzzle_%s.png'%r)
    grid(fs[2]+'-image.png',4,2,160,'slash_%s.png'%r)
grid('1aceeb8a-image.png',2,2,224,'legend_melee.png')
for n,f in {'toaster':'a95bc695','minigun':'e0aede50','magnet':'81d22df8','prism':'30b5a8d1','flamer':'ce1a8ad0','railgun':'d0a97c98'}.items():
    stack(f+'-image.png',3,(384,192),'fx_%s.png'%n)
U2='/root/.claude/uploads/0fd7481c-189d-5931-953e-db25d6f3cd99/'
Uo=U
U=U2
grid('749d7d87-image.png',4,2,160,'melee_icons.png',skip=(2,))
sh=Image.open(O+'melee_icons.png')
im=key(Image.open(U+'dfba9009-image.jpg')); bb=im.getbbox(); im=im.crop(bb); im.thumbnail((150,150),Image.LANCZOS)
sh.paste(im,(2*160+(160-im.width)//2,(160-im.height)//2),im); sh.save(O+'melee_icons.png',optimize=True)
