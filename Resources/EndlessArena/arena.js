"use strict";
const canvas=document.querySelector("canvas"), ctx=canvas.getContext("2d");
const el=id=>document.getElementById(id), panel=document.querySelector("section");
const args=new URLSearchParams(location.hash.slice(1));
const words=window.arenaSettings?.labels||JSON.parse(args.get("labels")||'["Endless Arena","Level","Wave","Best","Play","Pause","Game over","Multishot","Blast","Pierce","Rapid fire","Move"]');
const [arena,levelText,waveText,bestText,playText,pauseText,over,multi,blast,pierce,rapid,move]=words;
const themes=[
 ["🌿","#182c2c","#264441","#437967","#9de2a6"],
 ["🌋","#321e29","#512c35","#9f4c40","#ff995c"],
 ["❄","#192d42","#28455b","#518099","#a8f3ff"],
 ["⚡","#231d39","#3c3050","#715c96","#e9aaff"],
 ["🏜","#382e29","#544333","#956d44","#ffda85"]
];
const weapons=[multi,blast,pierce,rapid,"♥"];
const keys=new Set(), width=720,height=400;
canvas.width=width;canvas.height=height;
let player,enemies,bullets,hostile,drops,level,wave,budget,spawn,clock,cooldown,kills,mods,mode="ready",theme,best=window.arenaSettings?.best||Number(args.get("best"))||0,active=false;
let lives=3;
let particles=[],last=0,lag=0,flash=0;
const clamp=(v,a,b)=>Math.max(a,Math.min(b,v)), rand=(a,b)=>a+Math.random()*(b-a);
const rect=(x,y,w,h,color)=>{ctx.fillStyle=color;ctx.fillRect(Math.round(x),Math.round(y),w,h)};
function reset(){
 player={x:width/2,y:height/2,hp:100,shield:0};enemies=[];bullets=[];hostile=[];drops=[];particles=[];mods=[0,0,0,0];lives=3;level=wave=1;kills=clock=cooldown=0;active=false;beginWave();
}
function record(){
 const current=(level-1)*4+wave;
 if(active&&current>best){
  best=current;document.title="ClawdArena/"+best;
  window.webkit?.messageHandlers?.record?.postMessage(best);
 }
}
function beginWave(){
 theme=themes[(level-1)%themes.length];spawn=.7;budget=3+wave+Math.min(30,level*2);
 hostile=[];bullets=[];
 if(wave===4){addEnemy(true);cue("Boss")}
 record();
}
function addEnemy(boss=false, origin=null){
 const edge=Math.floor(rand(0,4));
 const x=edge===0?8:edge===1?width-8:rand(18,width-18),y=edge===2?35:edge===3?height-12:rand(48,height-25);
 const kind=boss?(level-1)%8:origin?0:Math.floor(rand(0,Math.min(8,3+level)));
 const size=boss?16:origin?3:kind===4?10:rand(4,8);
 const hp=boss?80+level*35:(9+size+level*3)*(kind===4?1.8:origin?0.55:1);
 enemies.push({x:origin?.x??x,y:origin?.y??y,size,hp,max:hp,boss,kind,age:0,fire:2,phase:rand(0,6),dx:0,dy:0});
}
let audio=null;
const volume=window.arenaSettings?.volume??Number(args.get("volume")||0);
const muted=new Set(window.arenaSettings?.muted||JSON.parse(args.get("muted")||"[]"));
const notes={Fire:[280,140,.042],Hit:[130,67,.09],Pickup:[523,1046,.18],Boss:[147,73,.45],Victory:[440,880,.35],Revive:[330,990,.3],Defeat:[330,65,.48]};
const lastSound={};
function cue(name){
 if(!audio||volume<=0||muted.has("arcade"+name)||audio.state!=="running")return;
 const now=audio.currentTime;
 if(now-(lastSound[name]??-1)<.09)return;
 lastSound[name]=now;
 const [from,to,duration]=notes[name],tone=audio.createOscillator(),gain=audio.createGain();
 tone.type=name==="Fire"?"triangle":"sine";
 tone.frequency.setValueAtTime(from,now);tone.frequency.exponentialRampToValueAtTime(to,now+duration);
 gain.gain.setValueAtTime(Math.max(.0002,volume*.14),now);gain.gain.exponentialRampToValueAtTime(.0001,now+duration);
 tone.connect(gain);gain.connect(audio.destination);tone.start(now);tone.stop(now+duration);
}
function burst(x,y,color,count){
 for(let i=0;i<count;i++)particles.push({x,y,dx:rand(-48,48),dy:rand(-48,48),life:rand(.12,.4),color});
}
function damage(n){
 if(player.shield>0||mode!=="play")return;
 cue("Hit");player.hp=Math.max(0,player.hp-n);player.shield=.8;flash=.15;
 if(!player.hp){
  lives--;
  if(lives===0){mode="dead";cue("Defeat");show(over);record();return}
  cue("Revive");player.hp=100;player.x=width/2;player.y=height/2;player.shield=2.5;
  hostile=[];burst(player.x,player.y,"#ffcc93",28);
 }
}
function advance(dt){
 clock+=dt;player.shield-=dt;flash-=dt;
 let x=Number(keys.has("KeyD")||keys.has("ArrowRight"))-Number(keys.has("KeyA")||keys.has("ArrowLeft"));
 let y=Number(keys.has("KeyS")||keys.has("ArrowDown"))-Number(keys.has("KeyW")||keys.has("ArrowUp"));
 const norm=Math.hypot(x,y)||1;
 if(x||y){active=true;record()}
 player.x=clamp(player.x+x/norm*95*dt,8,width-8);player.y=clamp(player.y+y/norm*95*dt,32,height-12);
 spawn-=dt;if(budget&&spawn<=0){addEnemy();budget--;spawn=Math.max(.24,1.05-level*.045)}
 cooldown-=dt;
 const closest=enemies.reduce((a,b)=>!a||distance(b,player)<distance(a,player)?b:a,null);
 if(closest&&cooldown<=0){
  const aim=Math.atan2(closest.y-player.y,closest.x-player.x),count=1+mods[0];
  for(let i=0;i<count;i++){const angle=aim+(i-(count-1)/2)*.13;
   bullets.push({x:player.x,y:player.y,dx:Math.cos(angle)*245,dy:Math.sin(angle)*245,life:2.8,left:1+mods[2],hits:new Set()})}
  cue("Fire");cooldown=.42/(1+mods[3]*.38);
 }
 for(const e of enemies){
  if(e.hp<=0)continue;
  e.age+=dt;const a=Math.atan2(player.y-e.y,player.x-e.x);
  let angle=a,speed=19+Math.min(68,level*2.2)+8-e.size;
  const beat=e.age+e.phase;
  e.fire-=dt;
  if(e.boss){
   speed+=7;
   switch(e.kind){
    case 0: if(e.fire<=0)volley(e,a,8,Math.PI*2/8);break; // radial sentinel
    case 1: angle+=Math.sin(beat*3)*.95;speed*=1.35;if(e.fire<=0)volley(e,a-.25,3,.25);break;
    case 2: [angle,speed]=charge(e,a,speed);break;
    case 3: if(distance(e,player)<105)angle+=1.65;if(e.fire<=0)volley(e,beat,12,Math.PI/6);break;
    case 4: if(e.fire<=0){if(enemies.length<36)addEnemy(false,{x:e.x,y:e.y});volley(e,a,1,0)}break;
    case 5: if(e.fire<=0){e.hp=Math.min(e.max,e.hp+level*2);burst(e.x,e.y,"#a4ebb0",12);volley(e,a-.42,5,.21)}break;
    case 6: angle+=1.0;if(e.fire<=0){volley(e,beat*2,4,Math.PI/2);e.fire=.55}break;
    case 7: if(e.fire<=0){burst(e.x,e.y,theme[4],14);e.x=clamp(player.x+Math.cos(beat)*110,12,width-12);e.y=clamp(player.y+Math.sin(beat)*110,35,height-12);volley(e,a,10,Math.PI/5)}break;
   }
  } else {
   switch(e.kind){
    case 0: speed*=1.2;break;
    case 1: angle+=Math.sin(beat*4)*.85;speed*=1.3;break;
    case 2: [angle,speed]=charge(e,a,speed);break;
    case 3: if(distance(e,player)<90)angle+=1.8;if(e.fire<=0)volley(e,a,1,0);break;
    case 4: speed*=.65;break;
    case 5: speed*=.9;break; // splits on defeat
    case 6: if(e.fire<=0){for(const ally of enemies)if(ally!==e&&ally.hp>0&&distance(e,ally)<48)ally.hp=Math.min(ally.max,ally.hp+4);burst(e.x,e.y,"#a4ebb0",5);e.fire=2}break;
    case 7: angle+=1.1;if(e.fire<=0)volley(e,a-.22,3,.22);break;
   }
  }
  e.x=clamp(e.x+Math.cos(angle)*speed*dt,4,width-4);e.y=clamp(e.y+Math.sin(angle)*speed*dt,20,height-5);
  if(distance(e,player)<e.size+6)damage(e.boss?18:9);
 }
 for(const b of bullets){
  fly(b,dt);
  for(const e of enemies){
   if(b.left<=0)break;
   if(e.hp<=0||b.hits.has(e)||distance(b,e)>e.size+3)continue;
   b.hits.add(e);b.left--;e.hp-=14;burst(b.x,b.y,theme[4],3);
   if(mods[1]){for(const other of enemies)if(other!==e&&distance(other,e)<26+mods[1]*8)other.hp-=7*mods[1];burst(e.x,e.y,"#ffad76",10)}
  }
 }
 for(const b of hostile){fly(b,dt);if(distance(b,player)<7){damage(12);b.life=0}}
 for(const e of enemies)if(e.hp<=0){kills++;burst(e.x,e.y,theme[4],12);
  if(!e.boss&&e.kind===5){addEnemy(false,{x:e.x-4,y:e.y});addEnemy(false,{x:e.x+4,y:e.y})}
  if(e.boss||kills%4===0||Math.random()<.10)drops.push({x:e.x,y:e.y,type:Math.floor(rand(0,5))})}
 enemies=enemies.filter(e=>e.hp>0);bullets=bullets.filter(b=>b.life>0&&b.left>0);hostile=hostile.filter(b=>b.life>0);
 for(const d of drops)if(distance(d,player)<17){if(d.type===4)player.hp=Math.min(100,player.hp+28);else mods[d.type]=Math.min(5,mods[d.type]+1);d.used=true;cue("Pickup");burst(d.x,d.y,"#ffeba8",10)}
 drops=drops.filter(d=>!d.used).slice(-100);
 for(const p of particles)fly(p,dt);particles=particles.filter(p=>p.life>0);
 if(!budget&&!enemies.length&&mode==="play"){if(wave===4){if(level%2===0)lives++;cue("Victory");level++;wave=1;player.hp=Math.min(100,player.hp+15)}else wave++;beginWave()}
}
function volley(e,start,count,step){
 for(let i=0;i<count;i++){const angle=start+i*step;
  hostile.push({x:e.x,y:e.y,dx:Math.cos(angle)*55,dy:Math.sin(angle)*55,life:7})}
 e.fire=Math.max(.9,2.7-level*.07);
}
function charge(e,angle,speed){
 const t=(e.age+e.phase)%3.6;
 if(t<2.25){e.target=angle;return [angle,speed*.8]}
 if(t<2.85){e.target=angle;return [angle,0]}
 return [e.target??angle,speed*3.7];
}
function distance(a,b){return Math.hypot(a.x-b.x,a.y-b.y)}
function fly(p,dt){p.x+=p.dx*dt;p.y+=p.dy*dt;p.life-=dt}
function background(){
 rect(0,0,width,height,theme[1]);
 const index=(level-1)%themes.length;
 for(let i=0;i<80;i++){
  const x=(i*137+level*17)%width,y=(i*i*7+i*41+level*19)%height;
  if(index===0){rect(x,y,2,7,theme[2]);rect(x-3,y-2,4,4,theme[2]);rect(x+2,y-4,4,5,theme[2])}
  if(index===1){rect(x,y,12,2,theme[2]);rect(x+10,y-2,7,2,theme[3])}
  if(index===2){rect(x,y,4,9,theme[2]);rect(x+1,y-3,2,8,theme[3]);rect(x+5,y+3,3,5,theme[2])}
  if(index===3){rect(x,y,18,1,theme[2]);rect(x+18,y-7,1,8,theme[2]);rect(x+17,y-9,3,3,theme[3])}
  if(index===4){rect(x,y,16,2,theme[2]);rect(x+5,y-2,9,2,theme[2]);rect(x+9,y-4,3,2,theme[2])}
 }
}
function sprite(x,y,rows,color,scale=1){rows.forEach((r,j)=>[...r].forEach((c,i)=>{if(c!==" ")rect(x+(i-r.length/2)*scale,y+(j-rows.length/2)*scale,scale,scale,c==="x"?"#211c2a":color)}))}
const viruses=[[" #   # ","#######","##x#x##"," ##### "," # # # "],["   #   ","  ###  ","###x###"," ##### "," #   # "],["#     #"," ## ## ","###x###"," ##### ","##   ##"],[" ## ## ","#######","#x###x#"," ##### ","  # #  "],["  ###  "," ##### ","##x#x##","#######"," #   # "],[" #   # "," ### # ","##x#x##"," # ### "," #   # "],["   #   "," # # # ","###x###"," # # # ","   #   "],["#     #"," # # # ","  #x#  "," # # # ","#     #"]];
function draw(){
 background();
 for(const d of drops){rect(d.x-5,d.y-5,11,11,"#ffe5a3");ctx.fillStyle="#392b3f";ctx.font="bold 9px monospace";ctx.fillText(["Ⅲ","✹","»","ϟ","+"][d.type],d.x-3,d.y+3)}
 for(const e of enemies){sprite(e.x,e.y,viruses[e.kind],e.kind===2&&(e.age+e.phase)%3.6>2.25?"#fff3c4":e.boss?"#ff947d":[theme[4],"#f0bda3","#ed969c","#bcb0fc","#c8ae9d","#ffbb84","#88dea5","#e69edf"][e.kind],e.boss?4:Math.round(e.size/3));rect(e.x-e.size,e.y-e.size-4,e.size*2,2,"#493740");rect(e.x-e.size,e.y-e.size-4,Math.ceil(e.size*2*e.hp/e.max),2,"#9eeab2")}
 if(player.shield<=0||Math.floor(clock*12)%2===0)sprite(player.x,player.y,["  ######  "," ######## ","###x##x###"," ######## ","  ######  ","  # ## #  "],"#f0a283",2);
 for(const b of bullets)rect(b.x-2,b.y-1,5,2,"#ffe5ac");
 for(const b of hostile)rect(b.x-2,b.y-2,4,4,"#ff697e");
 for(const p of particles)rect(p.x,p.y,2,2,p.color);
 if(flash>0)rect(0,0,width,height,"#ff646422");
 el("sector").textContent=levelText+" "+level+" · "+waveText+" "+wave+"/4";
 el("stats").textContent="♥ ×"+lives+"   HP "+player.hp+"/100   ✦ "+kills;
 el("world").textContent=theme[0]+" "+String(level).padStart(2,"0");
 el("kit").textContent=mods.map((n,i)=>n?weapons[i]+" ×"+n:"").filter(Boolean).join(" · ");
}
function show(title){
 panel.hidden=false;document.querySelector("h1").textContent=title;
 el("hint").textContent=move+" · WASD / ↑ ↓ ← →";
 el("record").textContent=best?bestText+" · "+levelText+" "+Math.ceil(best/4)+" · "+waveText+" "+((best-1)%4+1):"";
 el("start").textContent="▶ "+playText;
}
function toggle(){
 const Audio=window.AudioContext||window.webkitAudioContext;
 if(volume>0&&Audio){audio??=new Audio();if(audio.state==="suspended")audio.resume().catch(()=>{})}
 if(mode==="play"){mode="paused";keys.clear();show(pauseText)}
 else {if(mode==="dead")reset();mode="play";panel.hidden=true;canvas.focus()}
}
el("start").onclick=toggle;el("pause").onclick=toggle;
document.addEventListener("keydown",e=>{if(["Space","Escape"].includes(e.code)){e.preventDefault();if(!e.repeat)toggle()}else if(/^(Arrow(Left|Right|Up|Down)|Key[WASD])$/.test(e.code)){e.preventDefault();keys.add(e.code)}});
document.addEventListener("keyup",e=>keys.delete(e.code));
window.addEventListener("blur",()=>{keys.clear();if(mode==="play")toggle()});
function frame(time){lag+=Math.min(.12,(time-last)/1000);last=time;
 while(lag>=1/60){if(mode==="play")advance(1/60);lag-=1/60}draw();requestAnimationFrame(frame)}
reset();show(arena);requestAnimationFrame(frame);
