#!/usr/bin/env node
// Offline concept-to-grid cleanup. Does not edit source/ or any live game asset.
import fs from 'node:fs';
import path from 'node:path';
import crypto from 'node:crypto';
import {PNG} from './png_core96.mjs';
const [sourcePath,outputPath]=process.argv.slice(2);
if(!sourcePath||!outputPath) throw Error('Usage: node prepare_props96.mjs source.png output_dir');
const src=PNG.decode(fs.readFileSync(sourcePath)),out=path.resolve(outputPath);
fs.mkdirSync(out,{recursive:true});
const sha=b=>crypto.createHash('sha256').update(b).digest('hex');
const recipe=JSON.parse(fs.readFileSync(new URL('./props96_relief.json',import.meta.url),'utf8'));
if(sha(fs.readFileSync(sourcePath))!==recipe.source_sha256)throw Error('Use the source paired with this relief/mask recipe');
const specs=[
 {name:'bank_lantern',range:[0,.3],canvas:[128,184],height:180,anchor:[64,182],radius:.28},
 {name:'bank_pedestal',range:[.3,.6],canvas:[192,176],height:172,anchor:[96,174],radius:.76},
 {name:'bank_flower_planter',range:[.6,1],canvas:[208,208],height:198,anchor:[104,206],radius:.65}];
const assets=[];
for(const spec of specs){
 const [w,h]=spec.canvas;let x0=src.width,y0=src.height,x1=0,y1=0;
 for(let y=0;y<src.height;y++)for(let x=Math.floor(spec.range[0]*src.width);x<Math.floor(spec.range[1]*src.width);x++)if(src.data[(y*src.width+x)*4+3]>=128){x0=Math.min(x0,x);x1=Math.max(x1,x+1);y0=Math.min(y0,y);y1=Math.max(y1,y+1)}
 if(x1<=x0)throw Error('No source object: '+spec.name);
 const scale=spec.height/(y1-y0),left=spec.anchor[0]-(x1-x0)*scale/2,top=spec.anchor[1]-1-spec.height;
 const pixels=new Uint8Array(w*h*4),core=new Uint8Array(w*h);
 for(let y=0;y<h;y++)for(let x=0;x<w;x++){
  const sx=x0+(x+.5-left)/scale,sy=y0+(y+.5-top)/scale,values=[[],[],[]];let count=0;
  for(const dy of [-.3,0,.3])for(const dx of [-.3,0,.3]){const xx=Math.floor(sx+dx/scale),yy=Math.floor(sy+dy/scale);if(xx<x0||xx>=x1||yy<y0||yy>=y1)continue;const i=(yy*src.width+xx)*4;if(src.data[i+3]<128)continue;count++;for(let c=0;c<3;c++)values[c].push(src.data[i+c])}
  if(count<5)continue;core[y*w+x]=1;for(let c=0;c<3;c++)pixels[(y*w+x)*4+c]=values[c].sort((a,b)=>a-b)[Math.floor(count/2)];pixels[(y*w+x)*4+3]=255;
 }
 assets.push({...spec,width:w,pixels,core,source_bounds:[x0,y0,x1,y1]});
}
// One deterministic shared 128-color environment palette, including contour.
const histogram=new Map();
for(const a of assets)for(let i=0;i<a.core.length;i++)if(a.core[i]){const rgb=Array.from(a.pixels.slice(i*4,i*4+3)),key=rgb.map(v=>v>>3).join(',');if(!histogram.has(key))histogram.set(key,{n:0,sum:[0,0,0]});const p=histogram.get(key);p.n++;for(let c=0;c<3;c++)p.sum[c]+=rgb[c]}
function box(points){let lo=[255,255,255],hi=[0,0,0],n=0;for(const p of points){n+=p.n;for(let c=0;c<3;c++){lo[c]=Math.min(lo[c],p.rgb[c]);hi[c]=Math.max(hi[c],p.rgb[c])}}const ranges=hi.map((v,c)=>(v-lo[c])*[.9,1,.8][c]),axis=ranges.indexOf(Math.max(...ranges));return{points,n,axis,score:points.length>1?Math.sqrt(n)*ranges[axis]**2:0}}
const boxes=[box([...histogram.values()].map(p=>({n:p.n,rgb:p.sum.map(v=>v/p.n)})))];
while(boxes.length<126){let k=0;for(let i=1;i<boxes.length;i++)if(boxes[i].score>boxes[k].score)k=i;const b=boxes[k];if(!b.score)break;const p=b.points.slice().sort((a,c)=>a.rgb[b.axis]-c.rgb[b.axis]);let n=0,j=0;while(j<p.length-1&&n<b.n/2){n+=p[j].n;j++}j=Math.max(1,j);boxes.splice(k,1,box(p.slice(0,j)),box(p.slice(j)))}
const palette=[[0,0,0],[30,28,27],...boxes.map(b=>[0,1,2].map(c=>Math.round(b.points.reduce((s,p)=>s+p.rgb[c]*p.n,0)/b.n)))];
const cache=new Map();function nearest(rgb){const key=rgb.join(',');if(cache.has(key))return cache.get(key);let best=1,d=Infinity;for(let i=1;i<palette.length;i++){const q=palette[i],e=2*(q[0]-rgb[0])**2+4*(q[1]-rgb[1])**2+(q[2]-rgb[2])**2;if(e<d){d=e;best=i}}cache.set(key,best);return best}
const report={source_sha256:sha(fs.readFileSync(sourcePath)),pixels_per_metre:96,palette_colors:palette.length,creation_method:'concept-based median material sampling on target grid, shared palette and complete 1px dark contour',resampled_from_concept:true,files:[]};
for(const a of assets){const [w,h]=a.canvas,indices=new Uint8Array(w*h);for(let i=0;i<indices.length;i++)if(a.core[i])indices[i]=nearest(Array.from(a.pixels.slice(i*4,i*4+3)));
 const before=indices.slice();for(let y=1;y<h-1;y++)for(let x=1;x<w-1;x++){const i=y*w+x;if(!before[i])continue;const counts=new Map();let full=true;for(let dy=-1;dy<=1;dy++)for(let dx=-1;dx<=1;dx++){if(!dx&&!dy)continue;const v=before[i+dy*w+dx];if(!v)full=false;else counts.set(v,(counts.get(v)||0)+1)}if(!full)continue;for(const[v,n]of counts)if(n>=5&&v!==before[i]){const p=palette[v],q=palette[before[i]];if(Math.hypot(...p.map((c,j)=>c-q[j]))<22)indices[i]=v}}
 let outline=0;for(let y=0;y<h;y++)for(let x=0;x<w;x++){const i=y*w+x;if(!a.core[i]&&((x>0&&a.core[i-1])||(x<w-1&&a.core[i+1])||(y>0&&a.core[i-w])||(y<h-1&&a.core[i+w]))){indices[i]=1;outline++}}
 const encoded=PNG.encode(w,h,indices,{palette,alpha:palette.map((_,i)=>i?255:0)});fs.writeFileSync(path.join(out,a.name+'.png'),encoded);
 a.indices=indices;a.palette=palette;
 report.files.push({file:a.name+'.png',canvas:a.canvas,anchor_px:a.anchor,source_bounds:a.source_bounds,visible_bounds:PNG.bbox(PNG.decode(encoded)),visible_colors:new Set([...indices].filter(Boolean)).size,outline_pixels:outline,sha256:sha(encoded)});
}
fs.writeFileSync(path.join(out,'bank96.png'),PNG.encode(palette.length,1,new Uint8Array(palette.flat()),{rgb:true}));
function inside(x,y,poly){let yes=false;for(let i=0,j=poly.length-1;i<poly.length;j=i++){const a=poly[i],b=poly[j];if((a[1]>y)!==(b[1]>y)&&x<(b[0]-a[0])*(y-a[1])/(b[1]-a[1])+a[0])yes=!yes}return yes}
function edgeDistance(x,y,poly){let d=Infinity;for(let i=0;i<poly.length;i++){const a=poly[i],b=poly[(i+1)%poly.length],dx=b[0]-a[0],dy=b[1]-a[1],t=Math.max(0,Math.min(1,((x-a[0])*dx+(y-a[1])*dy)/(dx*dx+dy*dy)));d=Math.min(d,Math.hypot(x-a[0]-dx*t,y-a[1]-dy*t))}return d}
const lamp=assets[0],glow=new Uint8Array(lamp.canvas[0]*lamp.canvas[1]*3);
for(let y=0;y<lamp.canvas[1];y++)for(let x=0;x<lamp.width;x++){
 const i=y*lamp.width+x;if(!lamp.core[i])continue;const rgb=lamp.palette[lamp.indices[i]];
 if(!recipe.glow_panes.some(p=>inside(x+.5,y+.5,p))||inside(x+.5,y+.5,recipe.reflection_polygon))continue;
 if(rgb[0]<80||rgb[0]<rgb[1]*1.03||rgb[1]<rgb[2]*1.08)continue;
 const f=recipe.filament_rect,value=x>=f[0]&&x<f[2]&&y>=f[1]&&y<f[3]&&rgb[0]>180&&rgb[1]>145?255:48;
 glow.fill(value,i*3,i*3+3);
}
fs.writeFileSync(path.join(out,'bank_lantern_glow.png'),PNG.encode(...lamp.canvas,glow,{rgb:true}));
const stone=assets[1],[sw,sh]=stone.canvas,height=new Float64Array(sw*sh),normals=new Uint8Array(sw*sh*3);
for(let y=0;y<sh;y++)for(let x=0;x<sw;x++){
 let z=0;for(const b of recipe.stone_boxes){if(b.normal)continue;const [l,t,r,d]=b.rect,dist=Math.min(x+.5-l,r-x-.5,y+.5-t,d-y-.5);if(dist>=0)z+=b.depth*Math.min(1,dist/b.bevel)}
 const panel=recipe.carved_panel;if(inside(x+.5,y+.5,panel.polygon)){const d=edgeDistance(x+.5,y+.5,panel.polygon);z+=panel.height*Math.exp(-(((d-panel.rim_width)/2)**2))-.5*Math.min(1,d/12)}height[y*sw+x]=z;
}
let normalError=0;
for(let y=0;y<sh;y++)for(let x=0;x<sw;x++){
 const i=y*sw+x;let n=[0,0,1];const rgb=stone.palette[stone.indices[i]],green=rgb[1]>rgb[0]*1.03&&rgb[1]>rgb[2]*1.1;
 if(stone.core[i]&&!green&&x>0&&x<sw-1&&y>0&&y<sh-1){n=[-(height[i+1]-height[i-1])*.5,(height[i+sw]-height[i-sw])*.5,1];for(const b of recipe.stone_boxes)if(b.normal&&x>=b.rect[0]&&x<b.rect[2]&&y>=b.rect[1]&&y<b.rect[3])n=b.normal;}
 const len=Math.hypot(...n),encoded=n.map(v=>Math.round((v/len*.5+.5)*255));normals.set(encoded,i*3);normalError=Math.max(normalError,Math.abs(Math.hypot(...encoded.map(v=>v/255*2-1))-1));
}
fs.writeFileSync(path.join(out,'bank_pedestal_n.png'),PNG.encode(sw,sh,normals,{rgb:true}));
report.normal_unit_max_error=normalError;
report.normal_source=recipe.normal_method;
report.mask_levels=[...new Set(glow)];
for(const file of ['bank_lantern_glow.png','bank_pedestal_n.png','bank96.png'])report.files.push({file,sha256:sha(fs.readFileSync(path.join(out,file)))});
fs.writeFileSync(path.join(out,'pixel_validation.json'),JSON.stringify(report,null,2)+'\n');
console.log('PROPS96_PIXEL_EXPORT_OK',JSON.stringify(report));
