#!/usr/bin/env node
// Palette/grid export of a supplied concept. No generated geometry in this tool.
import fs from 'node:fs';
import path from 'node:path';
import crypto from 'node:crypto';
import {PNG} from './png_core96.mjs';
import {quantizer} from './palette96.mjs';
import {segment,sampleObject,outline} from './object_pixels96.mjs';
const [sourcePath,palettePath,specPath,out]=process.argv.slice(2);
const spec=JSON.parse(fs.readFileSync(specPath)),raw=fs.readFileSync(sourcePath),src=PNG.decode(raw);
const p=PNG.decode(fs.readFileSync(palettePath)),palette=[];
for(let x=0;x<p.width;x++)palette.push(Array.from(p.data.slice(x*4,x*4+3)));
const nearest=quantizer(palette.slice(1)),{labels,objects}=segment(src,1);
const a=sampleObject(src,labels,objects[0],spec),[w,h]=spec.canvas,ids=new Uint8Array(w*h);
for(let y=0;y<h;y++)for(let x=0;x<w;x++){
 const i=y*w+x;if(!a.core[i])continue;
 const c=Array.from(a.rgba.slice(i*4,i*4+3));ids[i]=1+nearest(c);
}
const result=outline(ids,a.core,w,h),bytes=PNG.encode(w,h,result,{palette,alpha:palette.map((_,i)=>i?255:0)});
fs.mkdirSync(out,{recursive:true});fs.writeFileSync(path.join(out,spec.file),bytes);
const sha=b=>crypto.createHash('sha256').update(b).digest('hex');
fs.writeFileSync(path.join(out,'export.json'),JSON.stringify({...spec,source_sha256:sha(raw),
 source_bounds:objects[0].bounds,source_scale:a.source_scale,visible_bounds:PNG.bbox(PNG.decode(bytes)),
 sha256:sha(bytes),method:'median target-grid material samples, fixed palette, binary silhouette, dark1px contour'},null,2)+'\n');
console.log('OBJECT96_EXPORTED',spec.file,PNG.bbox(PNG.decode(bytes)));
