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
  S.files = d.files!==false;
  _check({status:"ok", canPlay:true});
  if(!S.files) setTimeout(function(){
    if(S.screen!=="sMain") return;
    modal("Game Files","Fail game GTA V belum ditambah. Tambah folder game (data/ dan b/) dari app Files untuk mula bermain.",
      [{t:"Later"},{t:"Add Files",red:true,f:function(){ call("action","files"); }}]);
  }, 900);
};
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
goMain=function(msg, kind){ _goMain(msg, kind); if(!msg) island("ok","Home"); renderPanel(); };   // iOS: no server connection on the home screen

/* latar video dari launcher.json: WKWebView main terus dari link */
var _applyContent=applyContent;
applyContent=function(c){
  _applyContent(c);
  if(S.bgc && S.bgc.video) H.bg({state:"ready", url:S.bgc.video, src:S.bgc.video});
};

/* ---------- Settings (iOS) ---------- */
IC.gr='<rect x="3" y="4" width="18" height="13" rx="2"/><path d="M8 21h8M12 17v4"/>';
IC.gm='<path d="M12 2l3 7h7l-5.5 4.5 2 7L12 16l-6.5 4.5 2-7L2 9h7z"/>';
IC.dv='<rect x="7" y="2" width="10" height="20" rx="2"/><path d="M11 18h2"/>';
function act(name){ return function(){ call("action", name); }; }
TABS=[
  {id:"gr",name:"Graphics",opts:[
    {k:"preset",n:"Graphics Preset",d:"Tahap grafik. Berkuat kuasa bila mula main.",t:"seg",v:["Battery","Smooth","Balanced","Sharp","High","Max"]},
    {k:"fps",n:"Frame Rate",d:"30 paling stabil. Unlocked sampai 120 pada skrin ProMotion.",t:"seg",v:["30","60","Unlocked"]},
    {k:"autoSmooth",n:"Auto Smooth",d:"Turunkan FPS bila frame lewat atau telefon panas, naik semula bila lega.",t:"sw"},
    {k:"framePacing",n:"Frame Pacing",d:"Setiap frame kekal sama lama di skrin bila FPS bawah kadar skrin.",t:"sw"},
    {k:"fillScreen",n:"Fill Screen",d:"Render ikut bentuk skrin, bukan 16:9.",t:"sw"},
    {n:"Advanced Settings",d:"Resolusi, memori enjin dan tetapan lain.",t:"btn",b:"OPEN",f:act("advanced")}]},
  {id:"c",name:"Controls",opts:[
    {n:"Edit Controls Layout",d:"Gerak, besar/kecilkan atau sorok butang skrin.",t:"btn",b:"EDIT",f:act("layout")},
    {k:"fireAims",n:"Fire Also Aims",d:"Tekan tembak terus bidik sekali.",t:"sw"},
    {k:"invertLook",n:"Invert Look",d:"Terbalikkan arah pandangan atas/bawah.",t:"sw"},
    {k:"gyroAim",n:"Gyro Aim",d:"Condongkan telefon untuk bidik.",t:"seg",v:["Off","Aiming","Always"]},
    {k:"hideTouch",n:"Hide Touch With Controller",d:"Sorok butang skrin bila guna controller.",t:"sw"}]},
  {id:"gm",name:"Game",opts:[
    {n:"Game Files",d:"Tambah atau tukar folder fail game GTA V.",t:"btn",b:"OPEN",f:act("files")},
    {n:"Cheat Menu",d:"Buka menu cheat (trainer). Story Mode dan Free Roam sahaja.",t:"btn",b:"OPEN",f:act("cheat")},
    {n:"Mod Manager",d:"Pasang .zip, .oiv atau .asi. Restart game selepas tukar mod.",t:"btn",b:"OPEN",f:act("mods")},
    {n:"Saves",d:"Backup dan restore save game.",t:"btn",b:"OPEN",f:act("saves")},
    {n:"Online Server",d:"Alamat server Online.",t:"btn",b:"OPEN",f:act("online")}]},
  {id:"l",name:"Launcher",opts:[
    {k:"music",n:"Launcher Music",d:"Main muzik latar dalam launcher.",t:"sw",local:true},
    {k:"fx",n:"Visual Effects",d:"Pilih Low kalau telefon kau perlahan atau cepat panas.",t:"seg",v:["High","Low"],local:true},
    {k:"fxmode",n:"Effect Style",d:"Gaya kesan latar launcher.",t:"seg",v:["Glitch","Terminal","Static","Grid"],local:true}]},
  {id:"dv",name:"Device",opts:[
    {n:"App Version",t:"info",k:"version"},
    {n:"Device",t:"info",k:"device"},
    {n:"Share Logs",d:"Hantar fail log kepada admin bila ada masalah.",t:"btn",b:"SHARE",f:act("logs")},
    {n:"Credits",d:"Berdasarkan Mugoat (iOSVN), Muguet (c22dev) dan GTA V Port (Kevin Erik). Lesen GPL-3.0 / MIT.",t:"btn",b:"VIEW",f:act("licenses")}]}
];
var _openSettings=openSettings;
openSettings=function(){ if(S.tab && !TABS.some(function(t){ return t.id===S.tab; })) S.tab=null; return _openSettings(); };
$("bSet").onclick=function(){ if(S.screen==="sMain"||S.screen==="sNews") openSettings(); };

renderPanel();
})();
