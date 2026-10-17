#!/usr/bin/env node
// New concept textures cleaned on a native target grid. Not enlarged legacy tiles.
import fs from 'node:fs';
import path from 'node:path';
import crypto from 'node:crypto';
import {PNG} from './png_core96.mjs';
import {makePalette,quantizer,sampleMedian} from './palette96.mjs';
const [sourcePath,outPath]=process.argv.slice(2);
if(!sourcePath||!outPath)throw Error('Usage: node prepare_materials96.mjs source.png export_dir');
const sha=b=>crypto.createHash('sha256').update(b).digest('hex');
const sourceBytes=fs.readFileSync(sourcePath);
const src=PNG.decode(sourceBytes),out=path.resolve(outPath),S=192,P=191;
fs.mkdirSync(out,{recursive:true});
const specs=[['cobble_gold',0,[164,147,121]],['cobble_worn',1,[170,154,129]],
 ['rose_path',2,[168,138,132]],['marble',3,[215,210,194]],['lawn',4,[74,100,43]],
 ['stone_wall',5,[170,160,141]],['step_riser',6,[171,161,142]]];
const all=[];
for(const [name,cell,target] of specs){
 const raw=new Float64Array(S*S*3),mean=[0,0,0],cellW=src.width/4,cellH=src.height/2;
 for(let y=0;y<S;y++)for(let x=0;x<S;x++){const c=sampleMedian(src,(cell%4)*cellW+(x+.5)/S*cellW,Math.floor(cell/4)*cellH+(y+.5)/S*cellH,cellW/S);for(let a=0;a<3;a++){raw[(y*S+x)*3+a]=c[a];mean[a]+=c[a]/(S*S)}}
 for(let i=0;i<raw.length;i++)raw[i]=Math.max(0,Math.min(255,target[i%3]+(raw[i]-mean[i%3])*(name==='lawn'?.68:.72)));
 // Shared toroidal edge neighborhoods. Quantization follows this operation,
 // so the final game image retains discrete color steps, no alpha blur.
 const horizontal=raw.slice(),band=12;
 for(let y=0;y<S;y++)for(let k=0;k<band;k++){const t=(1-k/band)**2;for(let a=0;a<3;a++){const l=(y*S+k)*3+a,r=(y*S+P-k)*3+a,average=(raw[l]+raw[r])/2;horizontal[l]=raw[l]*(1-t)+average*t;horizontal[r]=raw[r]*(1-t)+average*t}}
 const base=horizontal.slice();
 for(let x=0;x<S;x++)for(let k=0;k<band;k++){const t=(1-k/band)**2;for(let a=0;a<3;a++){const l=(k*S+x)*3+a,r=((P-k)*S+x)*3+a,average=(horizontal[l]+horizontal[r])/2;base[l]=horizontal[l]*(1-t)+average*t;base[r]=horizontal[r]*(1-t)+average*t}}
 for(let v=0;v<3;v++){
  const rgb=new Uint8Array(S*S*3);
  for(let y=0;y<S;y++)for(let x=0;x<S;x++){
   const edge=Math.min(x,y,P-x,P-y),fade=Math.min(1,Math.max(0,(edge-8)/22)),phase=v*2.1;
   const irregular=name.startsWith('cobble')||name==='lawn';
   const dx=v&&irregular?Math.round(Math.sin(y*.047+phase)*Math.sin(x*.021)*7*fade):0;
   const dy=v&&irregular?Math.round(Math.cos(x*.041-phase)*Math.sin(y*.025)*6*fade):0;
   const xx=Math.max(0,Math.min(P,x+dx)),yy=Math.max(0,Math.min(P,y+dy));
   for(let a=0;a<3;a++)rgb[(y*S+x)*3+a]=Math.round(Math.max(0,Math.min(255,base[(yy*S+xx)*3+a]+(v&&!irregular?Math.sin(x*.16+Math.sin(y*.17)+phase)*1.8*fade:0))));
  }
  all.push({name,variant:v+1,rgb});
 }
}
const palette=makePalette(all.map(a=>a.rgb),128),nearest=quantizer(palette);
const report={pixels_per_metre:96,source_sha256:sha(sourceBytes),palette_colors:palette.length,
 source_method:'new concept texture atlas, median target-grid samples, restrained material colors, toroidal edge cleanup, three interior geometry variations',
 normal_method:'shallow approximate joint relief from texture structure; not a scanned or geometric 3D normal bake',
 files:[]};
const thresholds=new Map();
for(const a of all){
 const ids=new Uint8Array(S*S);for(let i=0;i<ids.length;i++)ids[i]=nearest(Array.from(a.rgb.slice(i*3,i*3+3)));
 const encoded=PNG.encode(S,S,ids,{palette}),file=`${a.name}_${String(a.variant).padStart(2,'0')}.png`;
 fs.writeFileSync(path.join(out,file),encoded);
 const luminance=new Float64Array(S*S);for(let i=0;i<luminance.length;i++){const c=palette[ids[i]];luminance[i]=c[0]*.299+c[1]*.587+c[2]*.114}
 const sorted=Array.from(luminance).sort((x,y)=>x-y);
 if(!thresholds.has(a.name))thresholds.set(a.name,[sorted[Math.floor(sorted.length*.15)],sorted[Math.floor(sorted.length*.55)]]);
 const [low,high]=thresholds.get(a.name),height=new Float64Array(S*S);
 // Dark recessed joints have a shallow relief. Most stone tops stay flat;
 // this avoids turning every bright mineral fleck into an embossed bump.
 for(let i=0;i<height.length;i++)height[i]=Math.max(0,Math.min(1,(luminance[i]-low)/Math.max(1,high-low)))*(a.name==='lawn'?.035:.12);
 const normal=new Uint8Array(S*S*3);let err=0;
 for(let y=0;y<S;y++)for(let x=0;x<S;x++){
  const xx=x%P,yy=y%P,index=(yy*S+xx),dx=height[yy*S+(xx+1)%P]-height[yy*S+(xx+P-1)%P],dy=height[((yy+1)%P)*S+xx]-height[((yy+P-1)%P)*S+xx],n=[-dx,dy,1],len=Math.hypot(...n),c=n.map(v=>Math.round((v/len*.5+.5)*255));normal.set(c,(y*S+x)*3);err=Math.max(err,Math.abs(Math.hypot(...c.map(v=>v/255*2-1))-1));
 }
 const nf=file.replace('.png','_n.png'),ne=PNG.encode(S,S,normal,{rgb:true});fs.writeFileSync(path.join(out,nf),ne);
 report.files.push({file,material:a.name,variant:a.variant,sha256:sha(encoded),normal_map:nf,normal_sha256:sha(ne),mean_luma:Math.round(luminance.reduce((s,v)=>s+v,0)/luminance.length*100)/100,normal_unit_max_error:err});
}
fs.writeFileSync(path.join(out,'materials96.png'),PNG.encode(palette.length,1,new Uint8Array(palette.flat()),{rgb:true}));
fs.writeFileSync(path.join(out,'export.json'),JSON.stringify(report,null,2)+'\n');
console.log('MATERIALS96_EXPORT_OK',report.files.length,'tiles, same-size normal maps, palette',palette.length);
