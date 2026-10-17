#!/usr/bin/env node
// Offline art preparation only. No game runtime dependency.
import fs from 'node:fs';
import path from 'node:path';
import crypto from 'node:crypto';
import {fileURLToPath} from 'node:url';
import {PNG} from './png_core96.mjs';
export function cleanup(source,PNG){
const src=PNG.decode(source),bounds=PNG.bbox(src),H=bounds[3]-bounds[1],scale=168/H,W=256;
let footMin=src.width,footMax=0;
for(let y=Math.floor(bounds[3]-H*.08);y<bounds[3];y++)for(let x=bounds[0];x<bounds[2];x++)if(src.data[(y*src.width+x)*4+3]>=128){footMin=Math.min(footMin,x);footMax=Math.max(footMax,x+1)}
const foot=(footMin+footMax)/2,rgba=new Uint8Array(W*W*4);
for(let y=0;y<W;y++)for(let x=0;x<W;x++){const sx=foot+(x+.5-128)/scale,sy=bounds[1]+(y+.5-55)/scale;let rs=[],gs=[],bs=[];
for(const dy of [-.32,0,.32])for(const dx of [-.32,0,.32]){const ix=Math.floor(sx+dx/scale),iy=Math.floor(sy+dy/scale);if(ix<0||iy<0||ix>=src.width||iy>=src.height)continue;const i=(iy*src.width+ix)*4;if(src.data[i+3]<128)continue;rs.push(src.data[i]);gs.push(src.data[i+1]);bs.push(src.data[i+2])}
if(rs.length<5)continue;const median=a=>a.sort((a,b)=>a-b)[Math.floor(a.length/2)],i=(y*W+x)*4;rgba[i]=median(rs);rgba[i+1]=median(gs);rgba[i+2]=median(bs);rgba[i+3]=255}
const hist=new Map();for(let i=0;i<rgba.length;i+=4)if(rgba[i+3]){const r=rgba[i],g=rgba[i+1],b=rgba[i+2],key=((r>>3)<<10)|((g>>3)<<5)|(b>>3);if(!hist.has(key))hist.set(key,{n:0,sum:[0,0,0]});const q=hist.get(key);q.n++;q.sum[0]+=r;q.sum[1]+=g;q.sum[2]+=b}
const points=[...hist.values()].map(q=>({n:q.n,c:q.sum.map(v=>v/q.n)}));
function box(points){let min=[255,255,255],max=[0,0,0],n=0;for(const q of points){n+=q.n;for(let a=0;a<3;a++){min[a]=Math.min(min[a],q.c[a]);max[a]=Math.max(max[a],q.c[a])}}const ranges=max.map((v,i)=>(v-min[i])*[.9,1,.8][i]),axis=ranges.indexOf(Math.max(...ranges));return{points,n,axis,score:points.length>1?Math.sqrt(n)*ranges[axis]**2:0}}
const boxes=[box(points)];while(boxes.length<124){let k=0;for(let i=1;i<boxes.length;i++)if(boxes[i].score>boxes[k].score)k=i;const b=boxes[k];if(!b.score)break;const sorted=b.points.slice().sort((a,c)=>a.c[b.axis]-c.c[b.axis]);let n=0,j=0;while(j<sorted.length-1&&n<b.n/2){n+=sorted[j].n;j++}j=Math.max(1,Math.min(sorted.length-1,j));boxes.splice(k,1,box(sorted.slice(0,j)),box(sorted.slice(j)))}
const palette=[[0,0,0],[33,25,30],[20,20,23],[250,240,216],...boxes.map(b=>[0,1,2].map(a=>Math.round(b.points.reduce((s,q)=>s+q.c[a]*q.n,0)/b.n)))];
PNG.assert(palette.length<=128,"Palette limit");const indices=new Uint8Array(W*W),cache=new Map();
function nearest(r,g,b){const key=(r<<16)|(g<<8)|b;if(cache.has(key))return cache.get(key);let best=1,d=Infinity;for(let j=1;j<palette.length;j++){const c=palette[j],e=2*(r-c[0])**2+4*(g-c[1])**2+(b-c[2])**2;if(e<d){d=e;best=j}}cache.set(key,best);return best}
for(let i=0;i<indices.length;i++)if(rgba[i*4+3])indices[i]=nearest(rgba[i*4],rgba[i*4+1],rgba[i*4+2]);
const clean=indices.slice();for(let y=1;y<255;y++)for(let x=1;x<255;x++){const k=y*W+x,old=indices[k];if(!old)continue;const counts=new Map();let inside=true;
for(let dy=-1;dy<=1;dy++)for(let dx=-1;dx<=1;dx++){if(!dx&&!dy)continue;const v=indices[k+dy*W+dx];if(!v)inside=false;else counts.set(v,(counts.get(v)||0)+1)}if(!inside)continue;let best=old,n=0;for(const[v,count]of counts)if(count>n){best=v;n=count}if(best!==old&&n>=5){const a=palette[old],b=palette[best],delta=Math.sqrt((a[0]-b[0])**2+(a[1]-b[1])**2+(a[2]-b[2])**2);if(delta<22)clean[k]=best}}
const core=clean.slice();let outlined=0;for(let y=1;y<255;y++)for(let x=1;x<255;x++){const k=y*W+x;if(core[k])continue;if(core[k-1]||core[k+1]||core[k-W]||core[k+W]){clean[k]=1;outlined++}}
const alpha=palette.map((_,i)=>i?255:0),encoded=PNG.encode(W,W,clean,{palette,alpha}),roundtrip=PNG.decode(encoded),colors=new Set();for(let i=0;i<clean.length;i++)if(clean[i])colors.add(palette[clean[i]].join(","));
const report={source_dimensions:[src.width,src.height],source_visible_bounds:bounds,canvas:[256,256],pixels_per_metre:96,core_body_height_px:168,anchor_px:[128,224],visible_bounds:PNG.bbox(roundtrip),visible_colors:colors.size,alpha_values:[...new Set(roundtrip.data.filter((_,i)=>i%4===3))],outline_added_pixels:outlined};
return{width:W,height:W,indices:clean,core,palette,alpha,rgba:roundtrip.data,encoded,report}
}
export function formNormals(asset,recipe,PNG){
const W=256,n=new Float64Array(W*W*3);for(let i=0;i<W*W;i++)n[i*3+2]=1;
function inside(x,y,poly){let yes=false;for(let i=0,j=poly.length-1;i<poly.length;j=i++){const A=poly[i],B=poly[j];if(((A[1]>y)!==(B[1]>y))&&x<(B[0]-A[0])*(y-A[1])/(B[1]-A[1])+A[0])yes=!yes}return yes}
function distance(x,y,poly){let d=Infinity;for(let i=0;i<poly.length;i++){const A=poly[i],B=poly[(i+1)%poly.length],dx=B[0]-A[0],dy=B[1]-A[1],t=Math.max(0,Math.min(1,((x-A[0])*dx+(y-A[1])*dy)/(dx*dx+dy*dy||1)));d=Math.min(d,Math.hypot(x-A[0]-t*dx,y-A[1]-t*dy))}return d}
for(const f of recipe.forms)for(let y=0;y<W;y++)for(let x=0;x<W;x++){const i=y*W+x;if(!asset.core[i]||!inside(x+.5,y+.5,f.polygon))continue;let nx=(x+.5-f.center[0])/f.radii[0]*f.depth,ny=(f.center[1]-y-.5)/f.radii[1]*f.depth,len=Math.hypot(nx,ny);if(len>.65){nx*=.65/len;ny*=.65/len}const nz=Math.sqrt(1-nx*nx-ny*ny),blend=Math.min(1,distance(x+.5,y+.5,f.polygon)/2);n[i*3]=n[i*3]*(1-blend)+nx*blend;n[i*3+1]=n[i*3+1]*(1-blend)+ny*blend;n[i*3+2]=n[i*3+2]*(1-blend)+nz*blend}
for(const f of recipe.folds){const shape=recipe.forms.find(q=>q.name===f.part);for(let y=0;y<W;y++)for(let x=0;x<W;x++){const i=y*W+x;if(!asset.core[i]||!inside(x+.5,y+.5,shape.polygon))continue;for(let k=0;k<f.line.length-1;k++){const A=f.line[k],B=f.line[k+1],dx=B[0]-A[0],dy=B[1]-A[1],den=dx*dx+dy*dy,t=Math.max(0,Math.min(1,((x+.5-A[0])*dx+(y+.5-A[1])*dy)/den)),px=x+.5-A[0]-t*dx,py=y+.5-A[1]-t*dy,d=Math.hypot(px,py);if(d<f.radius&&d>.01){const gain=f.depth*Math.sin(d/f.radius*Math.PI);n[i*3]+=px/d*gain;n[i*3+1]-=py/d*gain}}}}
const bytes=new Uint8Array(W*W*3);let error=0;const unique=new Set();for(let i=0;i<W*W;i++){let nx=n[i*3],ny=n[i*3+1],nz=n[i*3+2],len=Math.hypot(nx,ny,nz);nx/=len;ny/=len;nz/=len;const values=[nx,ny,nz].map(v=>Math.round((v*.5+.5)*255));bytes.set(values,i*3);const decoded=values.map(v=>v/255*2-1);error=Math.max(error,Math.abs(Math.hypot(...decoded)-1));if(asset.core[i])unique.add(values.join(","))}
PNG.assert(error<.015,"Normal vector length");return{encoded:PNG.encode(W,W,bytes,{rgb:true}),maxUnitError:error,uniqueVectors:unique.size}
}
if (process.argv[1] && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  const [sourcePath,outPath]=process.argv.slice(2);
  if(!sourcePath||!outPath) throw Error('Usage: node prepare_rico96.mjs source.png output_dir');
  const raw=fs.readFileSync(sourcePath);
  const sha=bytes=>crypto.createHash('sha256').update(bytes).digest('hex');
  const recipe=JSON.parse(fs.readFileSync(new URL('./rico96_form_normals.json',import.meta.url),'utf8'));
  if(sha(raw)!==recipe.source_sha256) throw Error('Use the source illustration paired with this geometry recipe');
  const asset=cleanup(raw,PNG),normals=formNormals(asset,recipe,PNG);
  fs.mkdirSync(outPath,{recursive:true});
  const palette=PNG.encode(128,1,new Uint8Array(asset.palette.flat()),{rgb:true});
  for(const [name,data] of [['raccoon_idle.png',asset.encoded],['raccoon_idle_n.png',normals.encoded],['chars.png',palette]]) fs.writeFileSync(path.join(outPath,name),data);
  const report={...asset.report,png_crc:true,zlib_adler:true,normal_unit_max_error:normals.maxUnitError,normal_unique_vectors:normals.uniqueVectors,albedo_sha256:sha(asset.encoded),normal_sha256:sha(normals.encoded),godot_checked:false,artistic_approval:false};
  fs.writeFileSync(path.join(outPath,'pixel_validation.json'),JSON.stringify(report,null,2)+'\n');
  console.log('RICO96_PIXEL_EXPORT_OK',JSON.stringify(report));
}
