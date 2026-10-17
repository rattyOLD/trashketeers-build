#!/usr/bin/env node
// Concept sources -> one metric trim sheet, tiled materials and canonical cutouts.
import fs from 'node:fs';
import path from 'node:path';
import crypto from 'node:crypto';
import {PNG} from '../art_v36/png_core96.mjs';
import {makePalette,quantizer,sampleMedian} from '../art_v36/palette96.mjs';
import {outline} from '../art_v36/object_pixels96.mjs';
const [materialsPath,trimPath,elevationPath,out]=process.argv.slice(2);
if(!out)throw Error('Usage: prepare_bank_textures.mjs materials.png trim.png approved_elevation.png export_dir');
const raw=[materialsPath,trimPath,elevationPath].map(p=>fs.readFileSync(p)),[src,trim,elevation]=raw.map(b=>PNG.decode(b));
const sha=b=>crypto.createHash('sha256').update(b).digest('hex'),samples=[],tiles=[];
fs.mkdirSync(out,{recursive:true});
const rects=[[0,0,256,64],[256,0,256,64],[512,0,256,256],[768,0,256,256],[0,256,128,128],[256,256,256,256],[512,256,256,256],[768,256,256,256]];
function sampleCell(image,col,row,cols,rows,w,h){
 const rgb=new Uint8Array(w*h*3),cw=image.width/cols,ch=image.height/rows;
 for(let y=0;y<h;y++)for(let x=0;x<w;x++)rgb.set(sampleMedian(image,(col+(x+.5)/w)*cw,(row+(y+.5)/h)*ch,cw/w),(y*w+x)*3);
 return rgb;
}
function periodic(rgb,w,h){
 // Only the small edge neighborhoods change; source pixel clusters remain discrete after quantization.
 for(let y=0;y<h;y++)for(let d=0;d<6;d++)for(let c=0;c<3;c++){
  const l=(y*w+d)*3+c,r=(y*w+w-1-d)*3+c,t=(1-d/6)**2,a=(rgb[l]+rgb[r])/2;rgb[l]=Math.round(rgb[l]*(1-t)+a*t);rgb[r]=Math.round(rgb[r]*(1-t)+a*t);
 }
 for(let x=0;x<w;x++)for(let d=0;d<6;d++)for(let c=0;c<3;c++){
  const l=(d*w+x)*3+c,r=((h-1-d)*w+x)*3+c,t=(1-d/6)**2,a=(rgb[l]+rgb[r])/2;rgb[l]=Math.round(rgb[l]*(1-t)+a*t);rgb[r]=Math.round(rgb[r]*(1-t)+a*t);
 }
 return rgb;
}
for(let i=0;i<4;i++){
 const rgb=periodic(sampleCell(src,i%2,Math.floor(i/2),2,2,192,192),192,192);
 tiles.push({name:['bank_plaster','bank_masonry','bank_roof','bank_glass'][i],rgb});samples.push(rgb);
}
const trimPixels=new Uint8Array(1024*1024*3);
for(let i=0;i<8;i++){
 const [x0,y0,w,h]=rects[i],rgb=sampleCell(trim,i%4,Math.floor(i/4),4,2,w,h);
 for(let y=0;y<h;y++)trimPixels.set(rgb.slice(y*w*3,(y+1)*w*3),((y+y0)*1024+x0)*3);
 samples.push(rgb);
}
// Masks extract the approved heraldic face/ivy, rather than regenerating their design.
function cutout(box,kind,w,h){
 const [x0,y0,x1,y1]=box,sw=x1-x0,sh=y1-y0,mask=new Uint8Array(sw*sh);
 for(let y=0;y<sh;y++)for(let x=0;x<sw;x++){
  const i=((y+y0)*elevation.width+x+x0)*4,[r,g,b,a]=elevation.data.slice(i,i+4);
  const gold=r>75&&r>g*1.16&&g>b*1.5;
  const leaf=g>r*.94&&g>b*1.3&&g>15;
  const flower=r>g*1.45&&b>g*.83&&b<r*.9;
  if(a>=128&&(kind==='crest'?gold:leaf||flower))mask[y*sw+x]=1;
 }
 const rgb=new Uint8Array(w*h*3),core=new Uint8Array(w*h),s=Math.min((w-12)/sw,(h-12)/sh),left=(w-sw*s)/2,top=(h-sh*s)/2;
 const leaves=[[115,78],[125,105],[125,139],[143,173],[163,220],[185,242],[178,259],[144,251],[120,236],[98,230],[68,225],[35,221],[7,220],[7,167],[32,155],[45,140],[69,121],[81,101],[96,87]];
 function inside(x,y,poly){let yes=false;for(let i=0,j=poly.length-1;i<poly.length;j=i++){const a=poly[i],b=poly[j];if((a[1]>y)!==(b[1]>y)&&x<(b[0]-a[0])*(y-a[1])/(b[1]-a[1])+a[0])yes=!yes}return yes}
 for(let y=0;y<h;y++)for(let x=0;x<w;x++){
  const xx=Math.floor((x+.5-left)/s),yy=Math.floor((y+.5-top)/s);
  if(xx<0||yy<0||xx>=sw||yy>=sh)continue;
  let keep=mask[yy*sw+xx];
  if(kind==='crest'){
   const face=((x-192)/88)**2+((y-150)/88)**2<1;
   const rim=((x-192)/100)**2+((y-150)/100)**2<1;
   const crown=inside(x,y,[[156,18],[220,18],[229,54],[218,80],[161,80],[150,48]]);
   const wreath=inside(x,y,leaves)||inside(384-x,y,leaves)||Math.hypot((x-192)/24,(y-241)/22)<1;
   keep=face||(keep&&(rim||crown||wreath));
  }
  if(!keep)continue;
  core[y*w+x]=1;rgb.set(elevation.data.slice(((yy+y0)*elevation.width+xx+x0)*4,((yy+y0)*elevation.width+xx+x0)*4+3),(y*w+x)*3);
 }
 const colors=[];for(let i=0;i<core.length;i++)if(core[i])colors.push(...rgb.slice(i*3,i*3+3));samples.push(new Uint8Array(colors));return{rgb,core,w,h,box};
}
const crest=cutout([600,105,988,365],'crest',384,288),ivy=cutout([5,115,205,950],'ivy',128,512);
const sampledPalette=[[0,0,0],[30,27,25],...makePalette(samples,126)],nearest=quantizer(sampledPalette.slice(1));
// The sky remains reflected in glass, but the window is a restrained navy field.
// Keep indices and all non-blue materials unchanged; avoid electric-blue glazing.
const palette=sampledPalette.map(c=>c[2]>130&&c[2]>c[0]*1.25&&c[2]>c[1]*1.1?
 [Math.round(18+(c[0]-12)*.54),Math.round(46+(c[1]-85)*.74),Math.round(75+(c[2]-191)*.8+Math.max(0,c[0]-12)*.35)]:c);
function indexed(rgb,core=null){const ids=new Uint8Array(rgb.length/3);for(let i=0;i<ids.length;i++)if(!core||core[i])ids[i]=nearest(Array.from(rgb.slice(i*3,i*3+3)))+1;return ids}
const files=[];
function save(file,w,h,data,options,role,extra={}){const bytes=PNG.encode(w,h,data,options);fs.writeFileSync(path.join(out,file),bytes);files.push({file,width:w,height:h,role,sha256:sha(bytes),bytes:bytes.length,...extra})}
save('bank_palette.png',128,1,new Uint8Array(palette.flat()),{rgb:true},'palette');
save('bank_trim.png',1024,1024,indexed(trimPixels),{palette},'albedo',{regions:rects});
for(const t of tiles)save(t.name+'.png',192,192,indexed(t.rgb),{palette},'albedo',{size_m:[2,2],tileable:true});
for(const[c,name]of [[crest,'bank_crest'],[ivy,'bank_ivy']]){
 const ids=indexed(c.rgb,c.core),final=outline(ids,c.core,c.w,c.h);
 save(name+'.png',c.w,c.h,final,{palette,alpha:palette.map((_,i)=>i?255:0)},'cutout',{source_box:c.box,binary_alpha:true,canonical_elevation_sha256:sha(raw[2])});
}
function normal(w,h,height,periodicEdges=false){
 const data=new Uint8Array(w*h*3);
 for(let y=0;y<h;y++)for(let x=0;x<w;x++){
  const pw=periodicEdges?w-1:w,ph=periodicEdges?h-1:h,xx=x%pw,yy=y%ph;
  let nx=-(height((xx+1)%pw,yy)-height((xx+pw-1)%pw,yy))*.45,ny=(height(xx,(yy+1)%ph)-height(xx,(yy+ph-1)%ph))*.45;
  const z=Math.hypot(nx,ny);if(z>.55){nx*=.55/z;ny*=.55/z}const len=Math.hypot(nx,ny,1);
  data.set([nx,ny,1].map(v=>Math.round((v/len*.5+.5)*255)),(y*w+x)*3);
 }
 return data;
}
const normalAtlas=new Uint8Array(1024*1024*3);for(let i=0;i<1024*1024;i++)normalAtlas.set([128,128,255],i*3);
for(let i=0;i<8;i++){
 const [x0,y0,w,h]=rects[i],height=(x,y)=>{
  const u=x/w,v=y/h;
  if(i===0||i===1)return 1.2*Math.cos(v*Math.PI*6)+.8*Math.sin(u*Math.PI*8)*Math.sin(v*Math.PI)**2;
  if(i===2)return 2*Math.cos(x*Math.PI/16);
  if(i===4)return 1.6*Math.sin(u*Math.PI*2)*Math.sin(v*Math.PI*2)+.8*Math.cos(v*Math.PI*8);
  return 0;
 },n=normal(w,h,height);
 for(let y=0;y<h;y++)normalAtlas.set(n.slice(y*w*3,(y+1)*w*3),((y+y0)*1024+x0)*3);
}
save('bank_trim_n.png',1024,1024,normalAtlas,{rgb:true},'normal',{method:'authored broad cornice/flute/panel relief fields; not albedo luminance and not a sculpt scan'});
save('bank_plaster_n.png',192,192,normal(192,192,()=>0,true),{rgb:true},'normal',{method:'flat smooth plaster tangent normal'});
save('bank_masonry_n.png',192,192,normal(192,192,(x,y)=>{
 const row=Math.floor(y/38.2),xx=(x+(row%2)*24)%48,yy=y%38.2;return -1.8*Math.exp(-(Math.min(xx,48-xx,yy,38.2-yy)**2)/3);
},true),{rgb:true},'normal',{method:'approximate authored block mortar profile; no mineral fleck embossing'});
save('bank_roof_n.png',192,192,normal(192,192,(x,y)=>1.6*Math.cos(x*Math.PI*14/192)+1.4*Math.exp(-((y%32)**2)/8),true),{rgb:true},'normal',{method:'approximate authored curved clay courses and overlapping lips'});
const glow=new Uint8Array(1024*1024*3);for(let y=256;y<512;y++)for(let x=768;x<1024;x++)glow.set([255,255,255],(y*1024+x)*3);
save('bank_trim_glow.png',1024,1024,glow,{rgb:true},'emission_mask',{active_region:'amber only; metal/wood/stone zero'});
save('bank_glass_glow.png',192,192,new Uint8Array(192*192*3).fill(255),{rgb:true},'emission_mask',{active_region:'window-glass material only; opaque mullions are separate geometry'});
fs.writeFileSync(path.join(out,'texture_export.json'),JSON.stringify({pixels_per_metre:96,palette_colors:128,sources:raw.map(sha),files,
 normal_note:'Broad approximate relief; macro shape from true geometry. No claim of carved/scanned microscopic normals.'},null,2)+'\n');
console.log('BANK38_TEXTURES_EXPORTED',files.length);
