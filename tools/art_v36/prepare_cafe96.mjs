#!/usr/bin/env node
import fs from 'node:fs';
import path from 'node:path';
import crypto from 'node:crypto';
import {PNG} from './png_core96.mjs';
import {quantizer} from './palette96.mjs';
import {segment,sampleObject,outline} from './object_pixels96.mjs';
const [sourcePath,palettePath,outPath]=process.argv.slice(2);
if(!sourcePath||!palettePath||!outPath)throw Error('Usage: node prepare_cafe96.mjs source.png street96.png export_dir');
const sha=b=>crypto.createHash('sha256').update(b).digest('hex'),raw=fs.readFileSync(sourcePath),src=PNG.decode(raw),pal=PNG.decode(fs.readFileSync(palettePath)),palette=[];
for(let i=0;i<pal.width;i++)palette.push(Array.from(pal.data.slice(i*4,i*4+3)));
const nearest=quantizer(palette.slice(1)),{labels,objects}=segment(src,4),out=path.resolve(outPath);fs.mkdirSync(out,{recursive:true});
const specs=[{name:'bank_umbrella',canvas:[288,272],anchor:[144,270],height:248},
 {name:'bank_bistro_table_parasol',canvas:[128,128],anchor:[64,126],height:90},
 {name:'bank_chair_left',canvas:[128,128],anchor:[64,126],height:98},
 {name:'bank_chair_right',canvas:[128,128],anchor:[64,126],height:98}];
const luma=c=>c[0]*.299+c[1]*.587+c[2]*.114;
function material(c){return c[0]>c[1]*1.4&&c[2]>c[1]*.6?1:c[0]>110&&c[0]<c[1]*1.35&&c[1]<c[2]*1.6?2:0}
function ramp(test){const candidates=palette.map((c,i)=>({c,i})).filter(p=>p.i>1&&test(p.c)).sort((a,b)=>luma(a.c)-luma(b.c));if(candidates.length<5)throw Error('Insufficient material ramp');return Array.from({length:7},(_,i)=>candidates[Math.round(i*(candidates.length-1)/6)])}
const wine=ramp(c=>c[0]>c[1]*1.4&&c[2]>c[1]*.6),ivory=ramp(c=>c[0]>110&&c[0]<c[1]*1.35&&c[1]<c[2]*1.6);
const report={pixels_per_metre:96,source_sha256:sha(raw),palette_sha256:sha(fs.readFileSync(palettePath)),
 method:'median target-grid samples, fixed accepted street palette; canopy same-material5x5 medians and7-tone ramps, cluster cleanup and dark1px outline',
 camera_down_angle_deg:35,canopy_underside_visible:false,files:[]};
const assets=[];
for(let k=0;k<4;k++){
 const spec=specs[k],a=sampleObject(src,labels,objects[k],spec),[w,h]=spec.canvas,indices=new Uint8Array(w*h);
 for(let y=0;y<h;y++)for(let x=0;x<w;x++){const i=y*w+x;if(!a.core[i])continue;let c=Array.from(a.rgba.slice(i*4,i*4+3));
  if(k===0&&y<155&&material(c)){const tag=material(c),channels=[[],[],[]];for(let dy=-2;dy<=2;dy++)for(let dx=-2;dx<=2;dx++){const xx=x+dx,yy=y+dy;if(xx<0||xx>=w||yy<0||yy>=h)continue;const p=yy*w+xx,cc=Array.from(a.rgba.slice(p*4,p*4+3));if(a.core[p]&&material(cc)===tag)for(let j=0;j<3;j++)channels[j].push(cc[j])}if(channels[0].length>=9)c=channels.map(v=>v.sort((a,b)=>a-b)[Math.floor(v.length/2)])}
  let index=nearest(c)+1;
  if(k===0&&y<155){let options=null;if(c[0]>c[1]*1.4&&c[2]>c[1]*.6)options=wine;else if(c[0]>110&&c[0]<c[1]*1.35&&c[1]<c[2]*1.6)options=ivory;if(options){let d=Infinity;for(const p of options){const e=c.reduce((s,v,j)=>s+(v-p.c[j])**2,0);if(e<d){d=e;index=p.i}}}}
  indices[i]=index;
 }
 const clean=indices.slice();
 for(let y=1;y<h-1;y++)for(let x=1;x<w-1;x++){const i=y*w+x;if(!a.core[i])continue;const counts=new Map();let full=true;for(let dy=-1;dy<=1;dy++)for(let dx=-1;dx<=1;dx++){if(!dx&&!dy)continue;const v=indices[i+dy*w+dx];if(!v)full=false;else counts.set(v,(counts.get(v)||0)+1)}if(!full)continue;for(const[v,n]of counts)if(n>=5&&v!==indices[i]&&Math.hypot(...palette[v].map((c,j)=>c-palette[indices[i]][j]))<26)clean[i]=v}
 const final=outline(clean,a.core,w,h),bytes=PNG.encode(w,h,final,{palette,alpha:palette.map((_,i)=>i?255:0)}),file=spec.name+'.png';fs.writeFileSync(path.join(out,file),bytes);
 assets.push({...spec,...a,indices:final});report.files.push({file,canvas:spec.canvas,anchor_px:spec.anchor,source_bounds:a.source_bounds,visible_bounds:PNG.bbox(PNG.decode(bytes)),sha256:sha(bytes),colors:new Set([...final].filter(Boolean)).size});
}
// Assembly-only upper pole layer ends exactly at the table socket. It lets
// the shaft emerge from the center rather than from the table's back edge.
const umbrella=assets[0],overlay=new Uint8Array(288*272);
for(let y=146;y<=201;y++)for(let x=136;x<152;x++)overlay[y*288+x]=umbrella.indices[y*288+x];
const overlayBytes=PNG.encode(288,272,overlay,{palette,alpha:palette.map((_,i)=>i?255:0)});
fs.writeFileSync(path.join(out,'bank_umbrella_pole_front.png'),overlayBytes);
report.files.push({file:'bank_umbrella_pole_front.png',canvas:[288,272],anchor_px:[144,270],role:'assembly_overlay',sha256:sha(overlayBytes),clip_rect_px:[136,146,152,202]});
report.table_socket_px=[64,57];report.table_socket_height_m=69/96;
fs.writeFileSync(path.join(out,'export.json'),JSON.stringify(report,null,2)+'\n');console.log('CAFE96_EXPORT_OK',JSON.stringify(report));
