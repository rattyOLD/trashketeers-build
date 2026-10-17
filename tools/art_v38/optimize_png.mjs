#!/usr/bin/env node
// Lossless IDAT recompression only: no color/alpha/palette or pixel changes.
import fs from 'node:fs';
import zlib from 'node:zlib';
import {PNG} from '../art_v36/png_core96.mjs';
for(const file of process.argv.slice(2)){
 const source=fs.readFileSync(file),parts=[source.subarray(0,8)],idat=[];let p=8;
 function chunk(name,data){const b=Buffer.alloc(data.length+12);b.writeUInt32BE(data.length);b.write(name,4);data.copy(b,8);b.writeUInt32BE(PNG.crc(b.subarray(4,data.length+8)),data.length+8);return b}
 while(p<source.length){const n=source.readUInt32BE(p),name=source.toString('ascii',p+4,p+8),b=source.subarray(p,p+n+12);
  if(name==='IDAT')idat.push(source.subarray(p+8,p+8+n));
  else if(name==='IEND'){parts.push(chunk('IDAT',zlib.deflateSync(zlib.inflateSync(Buffer.concat(idat)),{level:9})),b)}
  else parts.push(b);
  p+=n+12;
 }
 const result=Buffer.concat(parts),a=PNG.decode(source),b=PNG.decode(result);
 if(!Buffer.from(a.data).equals(Buffer.from(b.data)))throw Error('Pixel change: '+file);
 fs.writeFileSync(file,result);
}
