export function segment(src,count,axis='x'){
 const N=src.width*src.height,labels=new Int32Array(N),queue=new Uint32Array(N),components=[];let id=0;
 for(let start=0;start<N;start++){
  if(labels[start]||src.data[start*4+3]<128)continue;
  id++;let head=0,tail=1;queue[0]=start;labels[start]=id;let x0=src.width,y0=src.height,x1=0,y1=0;
  while(head<tail){const p=queue[head++],x=p%src.width,y=Math.floor(p/src.width);x0=Math.min(x0,x);x1=Math.max(x1,x+1);y0=Math.min(y0,y);y1=Math.max(y1,y+1);
   for(let dy=-1;dy<=1;dy++)for(let dx=-1;dx<=1;dx++){if(!dx&&!dy)continue;const xx=x+dx,yy=y+dy;if(xx<0||xx>=src.width||yy<0||yy>=src.height)continue;const q=yy*src.width+xx;if(!labels[q]&&src.data[q*4+3]>=128){labels[q]=id;queue[tail++]=q}}
  }
  components.push({id,count:tail,bounds:[x0,y0,x1,y1]});
 }
 const objects=components.sort((a,b)=>b.count-a.count).slice(0,count).sort((a,b)=>a.bounds[axis==='x'?0:1]-b.bounds[axis==='x'?0:1]);
 if(objects.length!==count||objects.some(o=>o.count<1000))throw Error('Missing source components');
 return {labels,objects};
}
export function sampleObject(src,labels,object,spec){
 const [w,h]=spec.canvas,[x0,y0,x1,y1]=object.bounds,scale=spec.height/(y1-y0),left=spec.anchor[0]-(x1-x0)*scale/2,top=spec.anchor[1]-1-spec.height,rgba=new Uint8Array(w*h*4),core=new Uint8Array(w*h);
 for(let y=0;y<h;y++)for(let x=0;x<w;x++){
  const cx=x0+(x+.5-left)/scale,cy=y0+(y+.5-top)/scale,values=[[],[],[]];let n=0;
  for(const dy of [-.3,0,.3])for(const dx of [-.3,0,.3]){const xx=Math.floor(cx+dx/scale),yy=Math.floor(cy+dy/scale);if(xx<0||xx>=src.width||yy<0||yy>=src.height)continue;const p=yy*src.width+xx;if(labels[p]!==object.id)continue;n++;for(let c=0;c<3;c++)values[c].push(src.data[p*4+c])}
  if(n<5)continue;const i=y*w+x;core[i]=1;rgba[i*4+3]=255;for(let c=0;c<3;c++)rgba[i*4+c]=values[c].sort((a,b)=>a-b)[Math.floor(n/2)];
 }
 return {width:w,height:h,rgba,core,source_bounds:object.bounds,source_scale:scale,source_top:top};
}
export function outline(indices,core,w,h,color=1){
 const result=indices.slice();for(let y=0;y<h;y++)for(let x=0;x<w;x++){const i=y*w+x;if(core[i])continue;if((x>0&&core[i-1])||(x<w-1&&core[i+1])||(y>0&&core[i-w])||(y<h-1&&core[i+w]))result[i]=color}return result;
}
