#!/usr/bin/env node
// Replace only the lawn family. Preserve every other accepted material/palette.
import fs from 'node:fs';
import path from 'node:path';
import crypto from 'node:crypto';
import {PNG} from './png_core96.mjs';
import {quantizer,sampleMedian} from './palette96.mjs';
const [sourcePath,palettePath,out]=process.argv.slice(2),raw=fs.readFileSync(sourcePath),src=PNG.decode(raw);
const strip=PNG.decode(fs.readFileSync(palettePath)),palette=[];
for(let x=0;x<strip.width;x++)palette.push(Array.from(strip.data.slice(x*4,x*4+3)));
const nearest=quantizer(palette),S=192,P=191,tiles=[];
fs.mkdirSync(out,{recursive:true});
for(let v=0;v<3;v++){
 const rgb=new Float64Array(S*S*3),mean=[0,0,0];
 for(let y=0;y<S;y++)for(let x=0;x<S;x++){
  const u=v===0?x:v===1?P-y:P-x,t=v===0?y:v===1?x:P-y;
  const c=sampleMedian(src,(u+.5)/S*src.width,(t+.5)/S*src.height,src.width/S);
  for(let k=0;k<3;k++){rgb[(y*S+x)*3+k]=c[k];mean[k]+=c[k]/(S*S)}
 }
 // Quiet living-green base with readable blade/clover clusters and flower accents.
 for(let i=0;i<S*S;i++){
  const c=Array.from(rgb.slice(i*3,i*3+3)),flower=c[0]>c[1]*.88&&c[2]>c[1]*.65&&c[0]>140;
  for(let k=0;k<3;k++)rgb[i*3+k]=Math.max(0,Math.min(255,(flower?[187,187,158]:[77,107,46])[k]+(c[k]-mean[k])*(flower?.7:.78)));
 }
 tiles.push(rgb);
}
// A shared periodic border is taken from variant1, then blended into interiors.
const base=tiles[0].slice(),band=10;
for(let y=0;y<S;y++)for(let d=0;d<band;d++)for(let k=0;k<3;k++){
 const l=(y*S+d)*3+k,r=(y*S+P-d)*3+k,t=(1-d/band)**2,a=(base[l]+base[r])/2;
 base[l]=base[l]*(1-t)+a*t;base[r]=base[r]*(1-t)+a*t;
}
for(let x=0;x<S;x++)for(let d=0;d<band;d++)for(let k=0;k<3;k++){
 const l=(d*S+x)*3+k,r=((P-d)*S+x)*3+k,t=(1-d/band)**2,a=(base[l]+base[r])/2;
 base[l]=base[l]*(1-t)+a*t;base[r]=base[r]*(1-t)+a*t;
}
const files=[];
for(let v=0;v<3;v++){
 const ids=new Uint8Array(S*S);
 for(let y=0;y<S;y++)for(let x=0;x<S;x++){
  const d=Math.min(x,y,P-x,P-y),t=Math.max(0,Math.min(1,(d-4)/12)),i=y*S+x;
  ids[i]=nearest([0,1,2].map(k=>Math.round(base[i*3+k]*(1-t)+tiles[v][i*3+k]*t)));
 }
 const normal=new Uint8Array(S*S*3);for(let i=0;i<S*S;i++)normal.set([128,128,255],i*3);
 const name=`lawn_0${v+1}.png`,bytes=PNG.encode(S,S,ids,{palette}),nb=PNG.encode(S,S,normal,{rgb:true});
 fs.writeFileSync(path.join(out,name),bytes);fs.writeFileSync(path.join(out,name.replace('.png','_n.png')),nb);
 files.push({file:name,sha256:crypto.createHash('sha256').update(bytes).digest('hex')});
}
fs.writeFileSync(path.join(out,'export.json'),JSON.stringify({source_sha256:crypto.createHash('sha256').update(raw).digest('hex'),
 pixels_per_metre:96,tile_px:[192,192],size_m:[2,2],palette_preserved:true,normal_method:'flat tangent normal; blade form comes from albedo, no noisy luminance embossing',files},null,2)+'\n');
console.log('LAWN96_EXPORTED',files);
