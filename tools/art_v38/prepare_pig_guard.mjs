#!/usr/bin/env node
// Offline target-grid export; accepted Riko pixels/palette are never rewritten.
import fs from 'node:fs';
import path from 'node:path';
import crypto from 'node:crypto';
import {PNG} from '../art_v36/png_core96.mjs';
import {cleanup,formNormals} from '../art_v36/prepare_rico96.mjs';
const [sourcePath,out]=process.argv.slice(2);
if(!out)throw Error('Usage: prepare_pig_guard.mjs source.png output_dir');
const raw=fs.readFileSync(sourcePath),sha=b=>crypto.createHash('sha256').update(b).digest('hex');
const recipe=JSON.parse(fs.readFileSync(new URL('./pig_guard_form_normals.json',import.meta.url)));
if(sha(raw)!==recipe.source_sha256)throw Error('Use source paired with authored form recipe');
const asset=cleanup(raw,PNG,{coreHeight:173,sourceAlpha:240}),normal=formNormals(asset,recipe,PNG);
fs.mkdirSync(out,{recursive:true});
for(const [name,bytes]of [['pig_guard_idle.png',asset.encoded],['pig_guard_idle_n.png',normal.encoded],['pig_guard_palette.png',PNG.encode(128,1,new Uint8Array(asset.palette.flat()),{rgb:true})]])fs.writeFileSync(path.join(out,name),bytes);
fs.writeFileSync(path.join(out,'pixel_export.json'),JSON.stringify({...asset.report,source_sha256:sha(raw),creation_method:'reference-based concept, median target-grid sampling, restrained128-color palette and dark1px contour',resampled_from_concept:true,normal_source:'authored clipped ellipsoid fields/cloth folds and shallow shield curvature; approximate form normals, not albedo luminance or3D sculpt bake',normal_unit_max_error:normal.maxUnitError,normal_unique_vectors:normal.uniqueVectors,albedo_sha256:sha(asset.encoded),normal_sha256:sha(normal.encoded)},null,2)+'\n');
console.log('PIG_GUARD96_EXPORTED',JSON.stringify(asset.report));
