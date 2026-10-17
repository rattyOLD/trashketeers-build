#!/usr/bin/env node
import fs from 'node:fs';import path from 'node:path';import crypto from 'node:crypto';
import {PNG} from './png_core96.mjs';import {quantizer} from './palette96.mjs';import {segment} from './object_pixels96.mjs';
const [sourcePath,baseDir,palettePath,outPath]=process.argv.slice(2);
if(!outPath)throw Error('Usage: node prepare_rail_variants96.mjs source.png base_dir palette.png export_dir');
const sha=b=>crypto.createHash('sha256').update(b).digest('hex'),source=fs.readFileSync(sourcePath),src=PNG.decode(source),{labels,objects}=segment(src,2,'y'),out=path.resolve(outPath);fs.mkdirSync(out,{recursive:true});
const baseBytes=fs.readFileSync(path.join(baseDir,'bank_balustrade.png')),normalBytes=fs.readFileSync(path.join(baseDir,'bank_balustrade_n.png')),base=PNG.decode(baseBytes),normal=PNG.decode(normalBytes),pal=PNG.decode(fs.readFileSync(palettePath)),palette=[];
for(let i=0;i<pal.width;i++)palette.push(Array.from(pal.data.slice(i*4,i*4+3)));
const nearest=quantizer(palette.slice(1)),w=192,h=128,regions=[[[54,28,77,48],[50,107,90,125],[107,65,130,88]],[[158,28,183,48],[104,108,142,125],[18,94,43,109]]],luma=c=>c[0]*.299+c[1]*.587+c[2]*.114;
fs.writeFileSync(path.join(out,'bank_balustrade.png'),baseBytes);fs.writeFileSync(path.join(out,'bank_balustrade_n.png'),normalBytes);
const report={pixels_per_metre:96,source_sha256:sha(source),base_albedo_sha256:sha(baseBytes),base_normal_sha256:sha(normalBytes),
 method:'image-generated damage transferred only into selected interior patches; accepted geometry/colors and connection neighborhoods preserved',variants:[]};
for(let k=0;k<2;k++){
 const object=objects[k],[x0,y0,x1,y1]=object.bounds,indices=new Uint8Array(w*h),damage=new Uint8Array(w*h);
 for(let y=0;y<h;y++)for(let x=0;x<w;x++){
  const i=y*w+x;if(!base.data[i*4+3])continue;
  const before=Array.from(base.data.slice(i*4,i*4+3));indices[i]=nearest(before)+1;
  if(!regions[k].some(r=>x>=r[0]&&x<r[2]&&y>=r[1]&&y<r[3]))continue;
  const cx=x0+12+(x+.5)/w*(x1-x0-24),cy=y0+(y+.5-27)/98*(y1-y0),channels=[[],[],[]];let n=0;
  for(const dy of [-.3,0,.3])for(const dx of [-.3,0,.3]){const xx=Math.floor(cx+dx*(x1-x0)/w),yy=Math.floor(cy+dy*(y1-y0)/98);if(xx<0||xx>=src.width||yy<0||yy>=src.height)continue;const p=yy*src.width+xx;if(labels[p]!==object.id)continue;n++;for(let c=0;c<3;c++)channels[c].push(src.data[p*4+c])}
  if(n<5)continue;const c=channels.map(a=>a.sort((a,b)=>a-b)[Math.floor(n/2)]);
  if(c[0]>c[1]*1.03&&c[1]>c[2]*1.04&&luma(c)+24<luma(before)){
   indices[i]=nearest(c)+1;damage[i]=1;
  }
 }
 let changed=0;for(let i=0;i<indices.length;i++)if(damage[i])changed++;
 if(changed<30)throw Error('Damage variant not sufficiently distinct: '+changed);
 const nn=new Uint8Array(w*h*3);
 for(let y=0;y<h;y++)for(let x=0;x<w;x++){
  const i=y*w+x,n=Array.from(normal.data.slice(i*4,i*4+3)).map(v=>v/255*2-1);
  if(x>0&&x<w-1&&y>0&&y<h-1){n[0]+=(damage[i+1]-damage[i-1])*.12;n[1]-=(damage[i+w]-damage[i-w])*.12}
  const len=Math.hypot(...n);nn.set(n.map(v=>Math.round((v/len*.5+.5)*255)),i*3);
 }
 const file=`bank_balustrade_0${k+2}.png`,nf=file.replace('.png','_n.png'),bytes=PNG.encode(w,h,indices,{palette,alpha:palette.map((_,i)=>i?255:0)}),nb=PNG.encode(w,h,nn,{rgb:true});fs.writeFileSync(path.join(out,file),bytes);fs.writeFileSync(path.join(out,nf),nb);
 report.variants.push({file,normal_map:nf,changed_pixels:changed,sha256:sha(bytes),normal_sha256:sha(nb)});
}
fs.writeFileSync(path.join(out,'export.json'),JSON.stringify(report,null,2)+'\n');console.log('RAIL96_VARIANTS_OK',JSON.stringify(report));
