#!/usr/bin/env node
import fs from 'node:fs';import path from 'node:path';import {PNG} from './png_core96.mjs';
const [folder,output]=process.argv.slice(2);if(!output)throw Error('Usage: node review_cafe96.mjs street_dir output.png');
const w=288,h=272,rgba=new Uint8Array(w*h*4);
function paste(name,x0,y0){const im=PNG.decode(fs.readFileSync(path.join(folder,name+'.png')));for(let y=0;y<im.height;y++)for(let x=0;x<im.width;x++){const i=(y*im.width+x)*4;if(!im.data[i+3])continue;const xx=x0+x,yy=y0+y;if(xx<0||xx>=w||yy<0||yy>=h)continue;rgba.set(im.data.slice(i,i+4),(yy*w+xx)*4)}}
paste('bank_umbrella',0,0);paste('bank_chair_left',15,144);paste('bank_chair_right',145,144);paste('bank_bistro_table_parasol',80,144);paste('bank_umbrella_pole_front',0,0);
const zoom=new Uint8Array(w*2*h*2*4);for(let y=0;y<h*2;y++)for(let x=0;x<w*2;x++){const i=(Math.floor(y/2)*w+Math.floor(x/2))*4;zoom.set(rgba.slice(i,i+4),(y*w*2+x)*4)}
fs.writeFileSync(output,PNG.encode(w*2,h*2,zoom));
