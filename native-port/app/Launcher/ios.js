/* Malay City iOS: adapts the Android launcher (index.html, kept as shipped in the APK) to the iOS app.
   Loaded right after the launcher's own script. The app (Swift, LauncherView.swift) provides window.MCNative
   before the page loads and answers through MCL.on(event, data), as the Android app does.
   Bahasa: tajuk dalam English, penerangan dalam Bahasa Melayu (macam APK). */
(function(){
"use strict";
if(!window.MCNative) return;                      // opened in a desktop browser: leave the APK demo as it is

/* ---------- tajuk lalai bila launcher.json tiada / medan kosong ---------- */
var DEF_HERO={label:"MALAY CITY · iOS", title:"YOUR CITY.", title2:"YOUR STORY.",
  text:"Kerja, bisnes, geng dan polis, semua dimainkan oleh pemain sebenar."};
heroData=function(){
  if(S.cstate==="loading") return {label:"LOADING…", t1:"LOADING", t2:"", text:""};
  var h=S.hero||{}, t=String(h.title||"").trim();
  return {label:String(h.label||"").trim()||DEF_HERO.label,
          t1:t||DEF_HERO.title, t2:t?String(h.title2||"").trim():DEF_HERO.title2,
          text:String(h.text||"").trim()||DEF_HERO.text};
};

/* ---------- log but: iOS semak fail game, bukan sambung server ---------- */
var _bootLine=bootLine;
bootLine=function(t, wait, err){ if(t==="CONNECT SERVER") t="CHECK GAME FILES"; return _bootLine(t, wait, err); };

/* ---------- mod permainan (diingat oleh app) ---------- */
var MODES=[
  {id:"story",    tag:"STORY",     name:"Story Mode", d:"Main cerita penuh Los Santos, simpan progress sendiri."},
  {id:"freeroam", tag:"FREE ROAM", name:"Free Roam",  d:"Bebas jelajah bandar tanpa misi. Sesuai untuk test grafik."},
  {id:"online",   tag:"ONLINE",    name:"Online",     d:"Masuk server roleplay guna nama watak anda."}];
function modeOf(id){ for(var i=0;i<MODES.length;i++) if(MODES[i].id===id) return MODES[i]; return null; }
S.mode=null; S.files=true; S.online={};

function ensureModeButton(){
  var b=$("modeSel"); if(b) return b;
  b=document.createElement("button"); b.id="modeSel"; b.className="btn cb glass fx";
  b.style.cssText="width:100%;height:34px;justify-content:space-between;padding:0 12px;font-size:12px;letter-spacing:.08em;flex:none";
  b.onclick=openModes;
  $("btnPlay").parentNode.insertBefore(b, $("btnPlay"));
  return b;
}
function srvText(){
  var o=S.online||{};
  if(o.online===false) return "● OFFLINE";
  if(o.players!=null && o.max!=null) return "● "+o.players+"/"+o.max+" ONLINE";
  return "● MALAY CITY";                         // tiada status server: jangan tunjuk nombor palsu
}
function renderPanel(){
  var b=ensureModeButton(), m=modeOf(S.mode), online=S.mode==="online";
  b.style.setProperty("--bd", m ? "" : "rgba(255,46,77,.9)");
  b.innerHTML='<span class="mono mut" style="font-size:10px;letter-spacing:.22em">MODE</span>'+
    '<span style="display:flex;align-items:center;gap:8px'+(m?'':';color:var(--red)')+'">'+esc(m?m.name.toUpperCase():"SELECT MODE")+
    '<svg class="ico" viewBox="0 0 24 24" style="width:14px;height:14px"><path d="M6 9l6 6 6-6"/></svg></span>';
  var hd=document.querySelector(".ppanel .hd");
  if(online) hd.innerHTML='<span>PLAYER_NAME</span><span class="red" id="srvMini">'+esc(srvText())+'</span>';
  else hd.innerHTML='<span>SINGLE_PLAYER</span><span class="mut" id="srvMini">● OFFLINE</span>';
  $("nickPill").style.display = online ? "" : "none";
  var play=$("btnPlay"), locked=!m;
  play.style.filter = locked ? "grayscale(1) brightness(.55)" : "";
  play.style.opacity = locked ? ".75" : "";
  var st=$("pStat");
  if(!m){ st.textContent="SELECT A MODE TO PLAY"; st.style.color="var(--red)"; }
  else if(!S.files){ st.textContent="GAME FILES MISSING // TAP PLAY TO ADD"; st.style.color="var(--red)"; }
  else { st.textContent = online ? "SERVER: "+String((S.settings&&S.settings.server)||"—").toUpperCase()+" // READY" : "FILES: OK // V"+String(S.version||"").toUpperCase()+" // READY"; st.style.color=""; }
  requestAnimationFrame(fitAll);
}
function setMode(id){
  if(!modeOf(id)) return;
  S.mode=id; call("setSetting","mode",id); renderPanel();
  island("ok","Mode: "+modeOf(id).name);
  if(id==="online") call("query");
}
function openModes(){
  if(S.playing) return;
  var pick=S.mode;
  modal("SELECT MODE","",[{t:"CANCEL"},{t:"SELECT",red:true,f:function(){ if(pick) setMode(pick); else island("warn","Select a mode first"); }}]);
  var p=$("mP"); p.style.display="none";
  var list=$("modeList"); if(!list){ list=document.createElement("div"); list.id="modeList"; p.parentNode.insertBefore(list, p.nextSibling); }
  list.style.cssText="display:flex;flex-direction:column;gap:8px;margin-top:2px";
  document.querySelector("#modal .box").style.width="min(470px,86vw)";
  function draw(){
    list.innerHTML="";
    MODES.forEach(function(m){
      var on=m.id===pick, e=document.createElement("button");
      e.className="btn cb fx "+(on?"hot":"glass");
      e.style.cssText="height:auto;padding:10px 14px;display:flex;flex-direction:column;align-items:flex-start;gap:3px;text-align:left;width:100%";
      e.innerHTML='<span class="mono" style="font-size:10px;letter-spacing:.2em;opacity:.85">['+esc(m.tag)+(on?" · SELECTED":"")+']</span>'+
        '<span style="font-size:15px;font-weight:800">'+esc(m.name)+'</span>'+
        '<span style="font-size:11.5px;font-weight:400;letter-spacing:0;text-transform:none;opacity:.85">'+esc(m.d)+'</span>';
      e.onclick=function(){ pick=m.id; draw(); };
      list.appendChild(e);
    });
  }
  draw();
}
/* modal() biasa (mesej lain) mesti tunjuk teks semula & sorok senarai mod */
var _modal=modal;
modal=function(title, text, btns){
  var l=$("modeList"); if(l) l.remove();
  $("mP").style.display=""; var bx=document.querySelector("#modal .box"); if(bx) bx.style.width="";
  return _modal(title, text, btns);
};

/* ---------- PLAY: mesti pilih mode; nama hanya untuk Online ---------- */
function iosPlay(){
  if(S.playing) return;
  if(!S.mode){ island("warn","Select a mode first"); openModes(); return; }
  var nick="";
  if(S.mode==="online"){
    nick=$("nick").value.trim();
    if(!NICK_RE.test(nick)){
      var p=$("nickPill"); p.classList.remove("bad"); void p.offsetWidth; p.classList.add("bad");
      island("err","Nama 3-20 aksara: huruf, nombor, _"); return;
    }
  }
  var sv=S.settings||{};
  if(sv.support==="low" && !S.lowAck){
    modal("NOT ENOUGH MEMORY", sv.supportNote||"Telefon ini mungkin tak cukup memori untuk GTA V.",
      [{t:"CANCEL"},{t:"TRY ANYWAY",red:true,f:function(){ S.lowAck=true; iosPlay(); }}]);
    return;
  }
  $("btnPlay").disabled=true; S.playing=true; music();
  island("spin","Starting game…");
  call("play", JSON.stringify({mode:S.mode, nick:nick}));
}
$("btnPlay").onclick=iosPlay;

/* ---------- acara dari app ---------- */
var _state=H.state;
H.state=function(d){
  _state(d);
  S.mode=modeOf(d.mode)?d.mode:null;
  S.files=d.files!==false;
  if(d.abi) $("ver").textContent="v"+S.version+" · "+d.abi;
  renderPanel();
};
var _check=H.check;
H.check=function(d){
  d=d||{};
  if("files" in d) S.files = d.files!==false;      // a deferred re-check (after the intro) carries no files flag
  _check({status:"ok", canPlay:true});
};
function askFiles(){
  if(S.files || S.filesAsked) return;
  S.filesAsked=true;
  setTimeout(function(){
    if(S.screen!=="sMain" || S.files) return;
    modal("Game Files","Fail game GTA V belum ditambah. Tambah folder game (data/ dan b/) dari app Files untuk mula bermain.",
      [{t:"Later"},{t:"Add Files",red:true,f:function(){ call("action","files"); }}]);
  }, 700);
}
var _settings=H.settings;
H.settings=function(d){ _settings(d); renderPanel(); };
H.files=function(d){ S.files=d.ok!==false; renderPanel(); };
H.query=function(d){
  S.online=d||{};
  var e=$("srvMini");
  if(e && S.mode==="online") e.textContent=srvText();
};
H.playError=function(d){
  S.playing=false; music(); $("btnPlay").disabled=false;
  var msg=(d&&d.message)||"Unable to start";
  if(msg.length>34){ island("err","Unable to start"); modal("Unable to Start", msg); return; }
  island("err", msg);
};
H.launched=function(){ island("spin","Loading…"); };   // Play stays locked while the game loads
/* game is on screen: stop launcher effects, music and video so the game gets the CPU/GPU */
H.sleep=function(){ S.bgd=true; music(); try{ fxStop(); }catch(e){}
  [].forEach.call(document.querySelectorAll("video"),function(v){ try{ v.pause(); }catch(e){} }); };
H.wake=function(){ S.bgd=false; music(); try{ if(!S.lowfx) fxStart(S.fxMode); }catch(e){}
  [].forEach.call(document.querySelectorAll("video.on"),function(v){ pplay(v); }); };
H.idle=function(){ S.playing=false; $("btnPlay").disabled=false; music(); island("ok","Home"); };
H.toast=function(d){ island((d&&d.kind)||"ok", (d&&d.text)||""); };

var _goMain=goMain;
goMain=function(msg, kind){ _goMain(msg, kind); if(!msg) island("ok","Home"); renderPanel(); askFiles(); };   // iOS: no server connection on the home screen

/* latar video dari launcher.json: WKWebView main terus dari link */
var _applyContent=applyContent;
applyContent=function(c){
  _applyContent(c);
  if(S.bgc && S.bgc.video) H.bg({state:"ready", url:S.bgc.video, src:S.bgc.video});
  // launcher.json "music": an mp3 link used when the app has no media/music.mp3
  var mu=String((c&&c.music)||"").trim(), el=$("music");
  if(el && /^https?:\/\//i.test(mu) && el.getAttribute("data-url")!==mu){ el.setAttribute("data-url",mu); el.src=mu; try{ el.load(); }catch(e){} music(); }
};

/* ---------- Settings: the original iOS app's settings, in the launcher's look ---------- */
(function(){ var st=document.createElement("style");
  st.textContent="#tabs{gap:3px;overflow-y:auto;min-height:0}#tabs::-webkit-scrollbar{width:0}#tabs .tab{height:31px;flex:none}#tabs .btn{flex:none}";
  document.head.appendChild(st); })();
IC.gr='<rect x="3" y="4" width="18" height="13" rx="2"/><path d="M8 21h8M12 17v4"/>';
IC.gy='<circle cx="12" cy="12" r="3"/><path d="M12 2v3M12 19v3M2 12h3M19 12h3"/>';
IC.gm='<path d="M12 2l3 7h7l-5.5 4.5 2 7L12 16l-6.5 4.5 2-7L2 9h7z"/>';
IC.dv='<rect x="7" y="2" width="10" height="20" rx="2"/><path d="M11 18h2"/>';
IC.l='<path d="M9 18V5l12-2v13"/><circle cx="6" cy="18" r="3"/><circle cx="18" cy="16" r="3"/>';
IC.on='<circle cx="12" cy="12" r="9"/><path d="M3 12h18M12 3a14 14 0 0 1 0 18M12 3a14 14 0 0 0 0 18"/>';
function act(name){ return function(){ call("action", name); }; }
function ch(k){ var c=(S.settings&&S.settings._choices)||{}; return c[k]||[]; }
function is(k, v){ return S.settings && String(S.settings[k])===v; }
function on(k){ return S.settings && (S.settings[k]===true || S.settings[k]==="true"); }
function buildTabs(){
  var f=S.settings||{}, fa=f.filesActions||[];
  TABS=[
  {id:"gr",name:"Graphics",opts:[
    {k:"preset",n:"Graphics Preset",d:"Tahap grafik. Disyorkan untuk iPhone ini: "+(f.recommended||"—")+". Preset lebih tinggi boleh kehabisan memori atau panas.",t:"pick",v:ch("preset")},
    {k:"resolution",n:"Resolution",d:(f.renderSize||"")+" · berkuat kuasa bila mula main.",t:"pick",v:ch("resolution")},
    {k:"fillScreen",n:"Fill Screen",d:"Render ikut bentuk skrin, bukan 16:9.",t:"sw"},
    {k:"ram",n:"Game Memory",d:"Lalai guna semua RAM. Kalau tak dapat masuk game atau selalu crash, pilih lebih rendah. Minimum 3 GB.",t:"pick",v:ch("ram"),custom:"Custom…",customAction:"ramCustom"},
    {k:"fps",n:"Frame Rate",d:"30 paling stabil. Unlocked sampai 120 pada skrin ProMotion.",t:"seg",v:["30","60","Unlocked"]},
    {k:"autoSmooth",n:"Auto Smooth",d:"Turunkan FPS bila frame lewat atau telefon panas, naik semula bila lega.",t:"sw"},
    {k:"framePacing",n:"Frame Pacing",d:"Setiap frame kekal sama lama di skrin bila FPS bawah kadar skrin.",t:"sw"}]},
  {id:"c",name:"Controls",opts:[
    {n:"Edit Controls Layout",d:f.layoutCustom?"Susun atur sendiri. Gerak, besar/kecilkan atau sorok butang.":"Gerak, besar/kecilkan atau sorok butang skrin.",t:"btn",b:"EDIT",f:act("layout")},
    {k:"lookSpeed",n:"Camera Stick Speed",d:"Laju kamera bila guna jari.",t:"slider",min:0.5,max:10,step:0.1},
    {k:"aimSpeed",n:"Aim Stick Speed",d:"Laju kamera semasa membidik.",t:"slider",min:0.5,max:10,step:0.1},
    {k:"buttonSize",n:"Button Size",d:"Saiz butang sentuh.",t:"slider",min:0.7,max:1.5,step:0.05},
    {k:"buttonOpacity",n:"Button Opacity",d:"Kelegapan butang sentuh.",t:"slider",min:0.2,max:1,step:0.05},
    {k:"targeting",n:"Targeting",d:"Cara bidik: lock-on, bantuan bidik atau bidik bebas.",t:"pick",v:ch("targeting")},
    {k:"fireAims",n:"Fire Also Aims",d:"Tekan tembak terus kunci sasaran dulu, macam GTA mobile klasik.",t:"sw"},
    {k:"invertLook",n:"Invert Look (Y)",d:"Tarik ke atas untuk pandang ke bawah.",t:"sw"},
    {k:"steeringButtons",n:"Steering Buttons",d:"Guna butang kiri/kanan untuk stereng kereta, motor dan bot.",t:"sw"},
    {k:"hideTouch",n:"Hide With Controller",d:"Sorok butang sentuh bila controller disambung.",t:"sw"},
    {k:"keyboardMouse",n:"Keyboard & Mouse",d:"Main guna kawalan PC (WASD, tetikus).",t:"sw"}]},
  {id:"gy",name:"Gyro",opts:[
    {k:"gyroAim",n:"Gyro Aim",d:"Gerakkan telefon untuk halus bidikan.",t:"pick",v:ch("gyroAim")},
    {k:"gyroSens",n:"Gyro Sensitivity",d:"Kepekaan gyro.",t:"slider",min:0.2,max:3,step:0.1,fmt:function(v){ return Number(v).toFixed(1)+"×"; },show:function(){ return !is("gyroAim",ch("gyroAim")[0]||"Off"); }},
    {k:"gyroInvert",n:"Invert Vertical",d:"Terbalikkan arah gyro atas/bawah.",t:"sw",show:function(){ return !is("gyroAim",ch("gyroAim")[0]||"Off"); }},
    {k:"tiltSteer",n:"Tilt Steering",d:"Condongkan telefon macam stereng. Assist tambah kawalan halus, Tilt ganti stereng sentuh.",t:"pick",v:ch("tiltSteer")},
    {k:"tiltLock",n:"Full Lock Angle",d:"Darjah condong untuk stereng penuh.",t:"slider",min:10,max:45,step:1,fmt:function(v){ return Math.round(v)+"°"; },show:function(){ return !is("tiltSteer",ch("tiltSteer")[0]||"Off"); }}]},
  {id:"gm",name:"Game",opts:[
    {n:"Game Folder",d:"Tambah atau tukar folder fail game GTA V (data/ dan b/).",t:"btn",b:"OPEN",f:act("files")},
    {k:"filesStatus",n:"Offline Game Files",d:"Simpan semua fail game dalam iPhone supaya tak perlu stream.",t:"info",show:function(){ return !!f.filesStatus; }},
    {n:"Download All Files",t:"btn",b:"DOWNLOAD",f:act("filesStart"),show:function(){ return fa.indexOf("start")>=0; }},
    {n:"Pause Download",t:"btn",b:"PAUSE",f:act("filesPause"),show:function(){ return fa.indexOf("pause")>=0; }},
    {n:"Resume Download",t:"btn",b:"RESUME",f:act("filesResume"),show:function(){ return fa.indexOf("resume")>=0; }},
    {n:"Cancel Download",t:"btn",b:"CANCEL",f:act("filesCancel"),show:function(){ return fa.indexOf("cancel")>=0; }},
    {n:"Remove Downloaded Files",t:"btn",b:"REMOVE",f:act("filesRemove"),show:function(){ return fa.indexOf("remove")>=0; }},
    {k:"pauseOnLeave",n:"Pause When Leaving",d:"Buka menu pause bila kau keluar dari app (panggilan, Control Center, tukar app).",t:"sw"},
    {n:"Cheat Menu (Trainer)",d:"Bertahan, senjata, panggil kenderaan, tukar cuaca… Story Mode dan Free Roam sahaja.",t:"btn",b:"OPEN",f:act("cheat")},
    {n:"Mod Manager",d:"Pasang .zip, .oiv atau .asi. Restart game selepas tukar mod.",t:"btn",b:"OPEN",f:act("mods")},
    {n:"Saves & Backup",d:"Lihat fail save, buat backup atau restore.",t:"btn",b:"OPEN",f:act("saves")}]},
  {id:"on",name:"Online",opts:[
    {k:"server",n:"Server",d:"IP atau hostname server, contoh 192.168.1.10:47520 (UDP). Berkuat kuasa bila mula main.",t:"text",ph:"IP / hostname:47520"},
    {k:"room",n:"Room",d:"Main sama bilik dan mode dengan kawan.",t:"text",ph:"room"},
    {k:"role",n:"Role",d:"Peranan watak, ditunjuk depan nama anda.",t:"pick",v:ch("role")},
    {k:"pvp",n:"PvP",d:"Boleh tembak pemain lain.",t:"sw"}]},
  {id:"l",name:"Launcher",opts:[
    {k:"music",n:"Launcher Music",d:"Main muzik latar dalam launcher.",t:"sw",local:true},
    {k:"fx",n:"Visual Effects",d:"Pilih Low kalau telefon kau perlahan atau cepat panas.",t:"seg",v:["High","Low"],local:true},
    {k:"fxmode",n:"Effect Style",d:"Gaya kesan latar launcher.",t:"seg",v:["Glitch","Terminal","Static","Grid"],local:true}]},
  {id:"dv",name:"Device",opts:[
    {n:"App Version",t:"info",k:"version"},
    {n:"Device",t:"info",k:"device"},
    {n:"iOS",t:"info",k:"iosVersion"},
    {n:"GPU",t:"info",k:"gpu",d:/Apple[3-6]\b/.test(f.gpu||"")?"GPU lama: sesetengah kesan mungkin nampak berbeza.":""},
    {n:"Memory for Apps",t:"info",k:"memLimit",d:"Memori yang iOS benarkan untuk app ini (bukan RAM penuh telefon)."},
    {n:"Support",t:"info",k:"supportText",d:f.supportNote||""},
    {n:"Share Logs",d:"Simpan atau hantar log run ini dan run sebelumnya kepada admin Malay City.",t:"btn",b:"SHARE",f:act("logs")},
    {k:"language",n:"Menu Language",d:"Bahasa untuk skrin menu iOS (fail game, mod, save).",t:"seg",v:ch("language")},
    {n:"Credits",d:"Berdasarkan Mugoat (iOSVN), Muguet (c22dev) dan GTA V Port (Kevin Erik). Lesen GPL-3.0 / MIT.",t:"btn",b:"VIEW",f:act("licenses")}]}
  ];
}
function fmtVal(o, v){ if(o.fmt) return o.fmt(v); var n=Number(v); return isFinite(n) ? (o.step<1 ? n.toFixed(o.step<0.1?2:1) : String(Math.round(n))) : "—"; }
function pickList(o){
  var cur=String(S.settings[o.k]==null?"":S.settings[o.k]), pick=cur;
  modal(o.n.toUpperCase(),"",[{t:"CANCEL"},{t:"SELECT",red:true,f:function(){
    if(o.custom && pick===o.custom){ call("action", o.customAction); return; }
    if(pick!==cur) setVal(o.k, pick, false); }}]);
  var p=$("mP"); p.style.display="none";
  var list=document.createElement("div"); list.id="modeList"; p.parentNode.insertBefore(list, p.nextSibling);
  list.style.cssText="display:flex;flex-direction:column;gap:6px;margin-top:2px;max-height:56vh;overflow-y:auto";
  function draw(){ list.innerHTML="";
    o.v.concat(o.custom?[o.custom]:[]).forEach(function(v){ var e=document.createElement("button"); e.className="btn cb fx "+(v===pick?"hot":"glass");
      e.style.cssText="height:38px;justify-content:flex-start;padding:0 14px;width:100%;font-size:13px;flex:none"; e.textContent=v;
      e.onclick=function(){ pick=v; draw(); }; list.appendChild(e); }); }
  draw();
}
renderTab=function(id){
  buildTabs();
  S.tab=id; renderTabs();
  var tab=tabsList().filter(function(x){return x.id===id;})[0]||tabsList()[0], body=$("setBody"); body.innerHTML="";
  tab.opts.forEach(function(o){
    if(o.show && !o.show()) return;
    var r=document.createElement("div"); r.className="opt";
    var l=document.createElement("div"); l.innerHTML='<div class="n">'+esc(o.n)+'</div>'+(o.d?'<div class="d">'+esc(o.d)+'</div>':"");
    r.appendChild(l);
    var cur=o.local?curVal(o):(o.k?S.settings[o.k]:null);
    if(o.t==="sw"){
      var v=cur===true||cur==="true", sw=document.createElement("button"); sw.className="sw cb fx"+(v?" on":""); sw.innerHTML="<i></i>";
      sw.onclick=function(){ setVal(o.k, !v, !!o.local); }; r.appendChild(sw);
    } else if(o.t==="seg"){
      var g=document.createElement("div"); g.className="seg";
      o.v.forEach(function(x){ var b=document.createElement("button"); b.className="btn cb fx"+(String(cur)===String(x)?" hot":" glass"); b.textContent=x; b.onclick=function(){ setVal(o.k,x,!!o.local); }; g.appendChild(b); });
      r.appendChild(g);
    } else if(o.t==="pick"){
      var pb=document.createElement("button"); pb.className="btn cb glass fx"; pb.style.cssText="flex:none;max-width:58%;overflow:hidden;text-overflow:ellipsis;white-space:nowrap";
      pb.textContent=(cur==null||cur===""?"—":String(cur))+" ▾"; pb.onclick=function(){ if(o.v.length) pickList(o); }; r.appendChild(pb);
    } else if(o.t==="slider"){
      var w=document.createElement("div"); w.style.cssText="display:flex;align-items:center;gap:10px;flex:none";
      var lab=document.createElement("div"); lab.className="mono"; lab.style.cssText="font-size:11px;min-width:42px;text-align:right"; lab.textContent=fmtVal(o,cur);
      var rg=document.createElement("input"); rg.type="range"; rg.min=o.min; rg.max=o.max; rg.step=o.step; rg.value=Number(cur)||o.min;
      rg.style.cssText="width:150px;accent-color:#ff2e4d";
      rg.oninput=function(){ lab.textContent=fmtVal(o,rg.value); };
      rg.onchange=function(){ setVal(o.k, rg.value, false); };
      w.appendChild(lab); w.appendChild(rg); r.appendChild(w);
    } else if(o.t==="text"){
      var tx=document.createElement("input"); tx.type="text"; tx.value=cur==null?"":String(cur); tx.placeholder=o.ph||"";
      tx.autocapitalize="off"; tx.autocomplete="off"; tx.spellcheck=false;
      tx.style.cssText="flex:none;width:210px;max-width:52%;height:32px;padding:0 10px;font-family:ui-monospace,Menlo,monospace;text-transform:none;letter-spacing:0;background:rgba(255,255,255,.06);border:1px solid rgba(255,255,255,.2);color:#fff;font-size:12px;border-radius:0;outline:none";
      tx.onkeydown=function(e){ if(e.key==="Enter") tx.blur(); };
      tx.onchange=function(){ setVal(o.k, tx.value.trim(), false); };
      r.appendChild(tx);
    } else if(o.t==="btn"){
      var b=document.createElement("button"); b.className="btn cb glass fx"; b.textContent=o.b||"OK"; b.onclick=o.f; r.appendChild(b);
    } else if(o.t==="info"){
      var i=document.createElement("div"); i.className="info"; i.textContent=(cur==null||cur==="")?"—":String(cur); r.appendChild(i);
    }
    body.appendChild(r);
  });
  repaintSettings(id);
};
/* iOS WebKit sometimes paints a freshly filled, clipped scroll box without its text until the next
   layout (the rows' controls show, their names do not). Force a layer and lay out again shortly. */
var repainting=false;
function repaintSettings(id){
  var body=$("setBody");
  body.style.webkitTransform="translateZ(0)"; void body.offsetHeight;
  requestAnimationFrame(function(){ body.style.webkitTransform=""; void body.offsetHeight; });
  if(repainting) return;
  repainting=true;
  setTimeout(function(){ if(S.screen==="sSet" && S.tab===id) renderTab(id); repainting=false; }, 140);
}
buildTabs();
var _openSettings=openSettings;
openSettings=function(){ if(S.tab && !TABS.some(function(t){ return t.id===S.tab; })) S.tab=null; return _openSettings(); };
$("bSet").onclick=function(){ if(S.screen==="sMain"||S.screen==="sNews") openSettings(); };

/* ---------- social: Discord / TikTok / Website always shown; a missing link says so ---------- */
var DEF_SOCIAL=[{name:"discord",url:""},{name:"tiktok",url:""},{name:"website",url:"https://malaycity.com"}];
socialList=function(){
  var have=(S.social||[]).slice(), out=[];
  DEF_SOCIAL.forEach(function(d){                    // Discord, TikTok, Website first, in that order
    var m=have.filter(function(x){ return String(x.name||"").toLowerCase()===d.name; })[0];
    out.push(m||d);
  });
  have.forEach(function(x){ if(DEF_SOCIAL.every(function(d){ return d.name!==String(x.name||"").toLowerCase(); })) out.push(x); });
  return out;
};
var _renderSocial=renderSocial;
renderSocial=function(){
  _renderSocial();
  var L=socialList().slice(0,6), bs=$("social").children;
  for(var i=0;i<bs.length && i<L.length;i++) if(!String(L[i].url||"").trim()) bs[i].onclick=function(){ island("warn","Link coming soon"); };
};
renderSocial();

renderPanel();
})();
