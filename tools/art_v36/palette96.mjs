// Shared deterministic palette helpers for offline art preparation.
export function makePalette(images,count=128){
 const histogram=new Map();
 for(const pixels of images)for(let i=0;i<pixels.length;i+=3){const c=Array.from(pixels.slice(i,i+3)),key=c.map(v=>v>>3).join(',');if(!histogram.has(key))histogram.set(key,{n:0,sum:[0,0,0]});const p=histogram.get(key);p.n++;for(let a=0;a<3;a++)p.sum[a]+=c[a]}
 function box(points){let lo=[255,255,255],hi=[0,0,0],n=0;for(const p of points){n+=p.n;for(let a=0;a<3;a++){lo[a]=Math.min(lo[a],p.c[a]);hi[a]=Math.max(hi[a],p.c[a])}}const ranges=hi.map((v,a)=>(v-lo[a])*[.9,1,.8][a]),axis=ranges.indexOf(Math.max(...ranges));return{points,n,axis,score:points.length>1?Math.sqrt(n)*ranges[axis]**2:0}}
 const boxes=[box([...histogram.values()].map(p=>({n:p.n,c:p.sum.map(v=>v/p.n)})))];
 while(boxes.length<count){let k=0;for(let i=1;i<boxes.length;i++)if(boxes[i].score>boxes[k].score)k=i;const b=boxes[k];if(!b.score)break;const points=b.points.slice().sort((a,c)=>a.c[b.axis]-c.c[b.axis]);let n=0,j=0;while(j<points.length-1&&n<b.n/2){n+=points[j].n;j++}j=Math.max(1,j);boxes.splice(k,1,box(points.slice(0,j)),box(points.slice(j)))}
 return boxes.map(b=>[0,1,2].map(a=>Math.round(b.points.reduce((s,p)=>s+p.c[a]*p.n,0)/b.n)));
}
export function quantizer(palette){const cache=new Map();return rgb=>{const key=rgb.join(',');if(cache.has(key))return cache.get(key);let best=0,d=Infinity;for(let i=0;i<palette.length;i++){const c=palette[i],e=2*(rgb[0]-c[0])**2+4*(rgb[1]-c[1])**2+(rgb[2]-c[2])**2;if(e<d){d=e;best=i}}cache.set(key,best);return best}}
export function sampleMedian(src,x,y,step=1){const values=[[],[],[]];for(const dy of [-.3,0,.3])for(const dx of [-.3,0,.3]){const xx=Math.max(0,Math.min(src.width-1,Math.floor(x+dx*step))),yy=Math.max(0,Math.min(src.height-1,Math.floor(y+dy*step))),i=(yy*src.width+xx)*4;for(let c=0;c<3;c++)values[c].push(src.data[i+c])}return values.map(a=>a.sort((a,b)=>a-b)[4])}
