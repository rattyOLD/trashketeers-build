// Correct only the star inside Riko's existing patch. Keep its leather/ring.
// A fixed five-tip glyph prevents the emblem from morphing between frames.
export const STAR9=[
 '....#....',
 '...###...',
 '...###...',
 '#########',
 '.#######.',
 '..#####..',
 '..##.##..',
 '.##...##.',
 '.#.....#.'
];
export function fixBadge(asset,PNG){
 const palette=asset.palette,w=asset.width,x0=82,y0=112;
 function nearest(rgb){let best=1,d=Infinity;for(let i=1;i<palette.length;i++){const c=palette[i],e=c.reduce((s,v,j)=>s+(v-rgb[j])**2,0);if(e<d){d=e;best=i}}return best}
 const dark=nearest([55,35,25]),gold=[nearest([149,99,36]),nearest([202,147,49]),nearest([232,187,84])];
 const original=asset.indices.slice();
 for(let y=0;y<15;y++)for(let x=0;x<15;x++){
  const i=(y0+y)*w+x0+x;if(!asset.indices[i])continue;
  if(Math.hypot(x+.5-7.5,y+.5-7.5)<=5.25)asset.indices[i]=dark;
 }
 for(let y=0;y<9;y++)for(let x=0;x<9;x++)if(STAR9[y][x]==='#'){
  const i=(y0+3+y)*w+x0+3+x;if(!asset.indices[i])throw Error('Badge lies outside sleeve');
  asset.indices[i]=gold[y<3?2:y>5?0:1];
 }
 const badge=new Uint8Array(15*15),alpha=palette.map((_,i)=>i?255:0);let changed=0;
 for(let y=0;y<15;y++)for(let x=0;x<15;x++){
  const i=(y0+y)*w+x0+x;if(Math.hypot(x+.5-7.5,y+.5-7.5)<=7.2)badge[y*15+x]=asset.indices[i];
  if(asset.indices[i]!==original[i])changed++;
 }
 asset.encoded=PNG.encode(asset.width,asset.height,asset.indices,{palette,alpha});
 asset.rgba=PNG.decode(asset.encoded).data;
 asset.report.visible_colors=new Set([...asset.indices].filter(Boolean).map(i=>palette[i].join(','))).size;
 asset.report.canonical_badge={origin_px:[x0,y0],size_px:[15,15],star_mask:STAR9,changed_pixels:changed,
  method:'existing leather/ring preserved; only inner star corrected to fixed five-tip target-grid glyph',frame_rule:'translation only; no independent scaling, shearing or regeneration'};
 return {encoded:PNG.encode(15,15,badge,{palette,alpha}),indices:badge,palette,origin:[x0,y0]};
}
