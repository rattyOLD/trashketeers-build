#!/usr/bin/env node
import fs from 'node:fs';
import {PNG} from './png_core96.mjs';
const [folder,out]=process.argv.slice(2),W=576,H=384,rgba=new Uint8Array(W*H*4);
for(let v=0;v<3;v++){
 const src=PNG.decode(fs.readFileSync(`${folder}/lawn_0${v+1}.png`));
 for(let y=0;y<384;y++)for(let x=0;x<192;x++)rgba.set(src.data.slice(((y%192)*192+x)*4,((y%192)*192+x)*4+4),(y*W+v*192+x)*4);
}
fs.writeFileSync(out,PNG.encode(W,H,rgba));
