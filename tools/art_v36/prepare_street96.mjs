#!/usr/bin/env node
import fs from 'node:fs';
import path from 'node:path';
import crypto from 'node:crypto';
import {PNG} from './png_core96.mjs';
import {makePalette,quantizer} from './palette96.mjs';
const [sourcePath,outPath]=process.argv.slice(2);
if(!sourcePath||!outPath)throw Error('Usage: node prepare_street96.mjs source.png export_dir');
const sha=b=>crypto.createHash('sha256').update(b).digest('hex'),source=fs.readFileSync(sourcePath),src=PNG.decode(source),out=path.resolve(outPath);
fs.mkdirSync(out,{recursive:true});
// Segment objects, not equally sized atlas columns: canopy and rail bounds
// overlap horizontally while remaining disconnected in transparent space.
const N=src.width*src.height,labels=new Int32Array(N),queue=new Uint32Array(N),components=[];
let id=0;
for(let start=0;start<N;start++){
 if(labels[start]||src.data[start*4+3]<128)continue;
 id++;let head=0,tail=1;queue[0]=start;labels[start]=id;let x0=src.width,y0=src.height,x1=0,y1=0;
 while(head<tail){const p=queue[head++],x=p%src.width,y=Math.floor(p/src.width);x0=Math.min(x0,x);x1=Math.max(x1,x+1);y0=Math.min(y0,y);y1=Math.max(y1,y+1);
  for(let dy=-1;dy<=1;dy++)for(let dx=-1;dx<=1;dx++){if(!dx&&!dy)continue;const xx=x+dx,yy=y+dy;if(xx<0||xx>=src.width||yy<0||yy>=src.height)continue;const q=yy*src.width+xx;if(!labels[q]&&src.data[q*4+3]>=128){labels[q]=id;queue[tail++]=q}}
 }
 components.push({id,count:tail,bounds:[x0,y0,x1,y1]});
}
const objects=components.sort((a,b)=>b.count-a.count).slice(0,3).sort((a,b)=>a.bounds[0]-b.bounds[0]);
if(objects.some(o=>o.count<10000))throw Error('Three major source objects required');
const specs=[{name:'bank_balustrade',canvas:[192,128],anchor:[96,126],height:98,tileable:true},
 {name:'bank_umbrella',canvas:[288,272],anchor:[144,270],height:248},
 {name:'bank_bistro_table',canvas:[128,128],anchor:[64,126],height:90}];
const assets=[],samples=[];
for(let k=0;k<3;k++){
 const spec=specs[k],object=objects[k],[w,h]=spec.canvas,[x0,y0,x1,y1]=object.bounds,scale=spec.height/(y1-y0),sx=spec.tileable?(x1-x0-24)/w:1/scale,left=spec.tileable?0:spec.anchor[0]-(x1-x0)*scale/2,top=spec.anchor[1]-1-spec.height;
 const pixels=new Uint8Array(w*h*4),core=new Uint8Array(w*h);
 for(let y=0;y<h;y++)for(let x=0;x<w;x++){
  const cx=spec.tileable?x0+12+(x+.5)*sx:x0+(x+.5-left)/scale,cy=y0+(y+.5-top)/scale,values=[[],[],[]];let n=0;
  for(const dy of [-.3,0,.3])for(const dx of [-.3,0,.3]){const xx=Math.floor(cx+dx*sx),yy=Math.floor(cy+dy/scale);if(xx<0||xx>=src.width||yy<0||yy>=src.height)continue;const p=yy*src.width+xx;if(labels[p]!==object.id)continue;n++;for(let c=0;c<3;c++)values[c].push(src.data[p*4+c])}
  if(n<5)continue;core[y*w+x]=1;for(let c=0;c<3;c++)pixels[(y*w+x)*4+c]=values[c].sort((a,b)=>a-b)[Math.floor(n/2)];pixels[(y*w+x)*4+3]=255;
 }
 // Open rail cut profiles must agree, including alpha. They are connections,
 // not external silhouette edges; no black vertical end cap is added there.
 if(spec.tileable)for(let y=0;y<h;y++){
  const l=y*w+3,r=y*w+w-4,solid=core[l]&&core[r];
  for(let x=0;x<4;x++)for(const xx of [x,w-1-x]){const i=y*w+xx;core[i]=solid?1:0;pixels[i*4+3]=solid?255:0;for(let c=0;c<3;c++)pixels[i*4+c]=Math.round((pixels[l*4+c]+pixels[r*4+c])/2)}
 }
 const packed=[];for(let i=0;i<core.length;i++)if(core[i])packed.push(...pixels.slice(i*4,i*4+3));samples.push(new Uint8Array(packed));assets.push({...spec,source_component:object,pixels,core});
}
const palette=[[0,0,0],[30,28,27],...makePalette(samples,126)],nearest=quantizer(palette.slice(1));
const report={pixels_per_metre:96,source_sha256:sha(source),palette_colors:palette.length,method:'concept-based target-grid median sampling; shared palette; complete outline except open tile connections',files:[]};
for(const a of assets){
 const [w,h]=a.canvas,indices=new Uint8Array(w*h);
 for(let i=0;i<indices.length;i++)if(a.core[i])indices[i]=nearest(Array.from(a.pixels.slice(i*4,i*4+3)))+1;
 for(let y=0;y<h;y++)for(let x=0;x<w;x++){
  const i=y*w+x;if(a.core[i])continue;
  const left=x>0?i-1:a.tileable?i+w-1:-1,right=x<w-1?i+1:a.tileable?i-w+1:-1;
  if((left>=0&&a.core[left])||(right>=0&&a.core[right])||(y>0&&a.core[i-w])||(y<h-1&&a.core[i+w]))indices[i]=1;
 }
 const bytes=PNG.encode(w,h,indices,{palette,alpha:palette.map((_,i)=>i?255:0)}),file=a.name+'.png';fs.writeFileSync(path.join(out,file),bytes);
 a.indices=indices;
 report.files.push({file,canvas:a.canvas,anchor_px:a.anchor,source_bounds:a.source_component.bounds,visible_bounds:PNG.bbox(PNG.decode(bytes)),sha256:sha(bytes),tileable_x:!!a.tileable});
}
const rail=assets[0],[w,h]=rail.canvas,normals=new Uint8Array(w*h*3);let error=0;
for(let y=0;y<h;y++)for(let x=0;x<w;x++){
 const i=y*w+x;let n=[0,0,1];
 if(rail.core[i]){
  if(y>=27&&y<=32)n=[0,.52,.854];
  else if(y>=42&&y<=45)n=[0,-.3,.954];
  else if(y>=108&&y<=112)n=[0,.45,.893];
  else if(y>46&&y<107){const cx=24+Math.floor(x/48)*48,dx=(x+.5-cx)/16,dy=(75-y)/35;if(Math.abs(dx)<=1){const nx=dx*.65,ny=dy*.18;n=[nx,ny,Math.sqrt(Math.max(.25,1-nx*nx-ny*ny))]}}
 }
 const len=Math.hypot(...n),c=n.map(v=>Math.round((v/len*.5+.5)*255));normals.set(c,i*3);error=Math.max(error,Math.abs(Math.hypot(...c.map(v=>v/255*2-1))-1));
}
const ne=PNG.encode(w,h,normals,{rgb:true});fs.writeFileSync(path.join(out,'bank_balustrade_n.png'),ne);
report.files.push({file:'bank_balustrade_n.png',sha256:sha(ne),normal_source:'authored turned-shaft ellipsoids and rail planes; approximate form normals, not albedo brightness',normal_unit_max_error:error});
fs.writeFileSync(path.join(out,'street96.png'),PNG.encode(palette.length,1,new Uint8Array(palette.flat()),{rgb:true}));
fs.writeFileSync(path.join(out,'export.json'),JSON.stringify(report,null,2)+'\n');
console.log('STREET96_EXPORT_OK',JSON.stringify(report));
