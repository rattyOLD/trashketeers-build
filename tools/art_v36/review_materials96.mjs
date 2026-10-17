#!/usr/bin/env node
import fs from 'node:fs';
import path from 'node:path';
import {PNG} from './png_core96.mjs';
const [folder,output]=process.argv.slice(2);
if(!folder||!output)throw Error('Usage: node review_materials96.mjs tiles_dir preview.png');
const W=1536,H=768,data=new Uint8Array(W*H*3),names=['cobble_gold','cobble_worn','rose_path','marble','lawn','stone_wall','step_riser'];
for(let k=0;k<names.length;k++)for(let ty=0;ty<2;ty++)for(let tx=0;tx<2;tx++){
 const variant=[1,2,3,1][ty*2+tx],src=PNG.decode(fs.readFileSync(path.join(folder,`${names[k]}_0${variant}.png`)));
 for(let y=0;y<192;y++)for(let x=0;x<192;x++){const p=((Math.floor(k/4)*384+ty*192+y)*W+(k%4)*384+tx*192+x)*3,i=(y*192+x)*4;data.set(src.data.slice(i,i+3),p)}
}
fs.writeFileSync(output,PNG.encode(W,H,data,{rgb:true}));
