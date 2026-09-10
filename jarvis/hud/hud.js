/* hud.js — animation du HUD + connexion au backend (Étape 3).
   - Le cercle (anneaux + onde) tourne toujours.
   - Si le backend (serveur WebSocket) est là, le HUD RÉAGIT : état + journal.
   - S'il n'est pas là (HUD lancé seul), le HUD reste en animation d'ambiance. */
(() => {
  "use strict";
  const reduit = matchMedia("(prefers-reduced-motion:reduce)").matches;
  const canvas = document.getElementById("reacteur");
  const ctx = canvas.getContext("2d");
  const N = 84;
  const donnees = new Float32Array(N);

  // --- États : couleur + énergie de l'onde + libellé ---
  const ETATS = {
    veille:    {couleur:"#22e0d6", ampli:0.35, label:"VEILLE"},
    ecoute:    {couleur:"#2ff0e6", ampli:1.00, label:"ÉCOUTE"},
    reflexion: {couleur:"#79c8ff", ampli:0.60, label:"RÉFLEXION"},
    action:    {couleur:"#ff8a3c", ampli:0.85, label:"ACTION"},
    erreur:    {couleur:"#ff4d5e", ampli:0.45, label:"ERREUR"},
  };
  let etat = "veille";

  const racine = document.documentElement;
  const elEtat = document.getElementById("etat");
  function appliquerEtat(nom){
    if (!ETATS[nom]) return;
    etat = nom;
    racine.style.setProperty("--accent", ETATS[nom].couleur);
    elEtat.textContent = ETATS[nom].label;
  }
  function accent(){ return getComputedStyle(racine).getPropertyValue("--accent").trim() || "#22e0d6"; }

  // --- Journal ---
  const elLog = document.getElementById("log");
  function heure(){ return new Date().toTimeString().slice(0,8); }
  function loguer(texte, genre="sys"){
    const l = document.createElement("div");
    l.className = "ligne " + genre;
    l.innerHTML = `<span class="horo">${heure()}</span> ${texte}`;
    elLog.appendChild(l);
    while (elLog.children.length > 6) elLog.removeChild(elLog.firstChild);
  }

  // --- Connexion au backend (WebSocket) avec reconnexion auto ---
  let ws = null, connecte = false;
  function connecter(){
    try{
      ws = new WebSocket("ws://127.0.0.1:8765");
    }catch(_){ return; }
    ws.onopen = () => { connecte = true; loguer("backend connecté ✓","act"); };
    ws.onmessage = (e) => {
      let m; try{ m = JSON.parse(e.data); }catch(_){ return; }
      if (m.type === "etat") appliquerEtat(m.valeur);
      else if (m.type === "log") loguer(m.texte, m.genre || "sys");
    };
    ws.onclose = () => {
      if (connecte) loguer("backend déconnecté","sys");
      connecte = false;
      setTimeout(connecter, 2000);   // on réessaie toutes les 2 s
    };
    ws.onerror = () => { try{ ws.close(); }catch(_){} };
  }

  // --- Dimensionnement net ---
  function redimensionner(){
    const dpr = Math.min(window.devicePixelRatio||1, 2);
    canvas.width = canvas.clientWidth*dpr;
    canvas.height = canvas.clientHeight*dpr;
    ctx.setTransform(dpr,0,0,dpr,0,0);
  }
  window.addEventListener("resize", redimensionner);

  // --- Onde simulée (la vraie onde du micro arrivera à l'Étape 4) ---
  function onde(t){
    for (let i=0;i<N;i++){
      const a = i/N*Math.PI*2;
      const s = 0.5 + 0.5*Math.sin(t*0.0022 + a*3)*Math.sin(t*0.0011 + a*7);
      donnees[i] = donnees[i]*0.6 + Math.abs(s)*0.4;
    }
  }

  function dessiner(now){
    const w = canvas.clientWidth, h = canvas.clientHeight;
    const cx = w/2, cy = h/2, R = Math.min(w,h)/2;
    const col = accent();
    const ampli = ETATS[etat].ampli;
    ctx.clearRect(0,0,w,h);
    onde(now);
    const rot = reduit ? 0 : now*0.00035;

    // anneau extérieur segmenté
    ctx.save(); ctx.translate(cx,cy); ctx.rotate(rot); ctx.strokeStyle=col;
    for (let k=0;k<12;k++){
      const a0=k*(Math.PI*2/12)+0.08, a1=a0+(Math.PI*2/12)-0.16;
      ctx.globalAlpha = k%3? .30 : .6; ctx.lineWidth=2;
      ctx.beginPath(); ctx.arc(0,0,R*0.94,a0,a1); ctx.stroke();
    }
    ctx.globalAlpha=1; ctx.restore();

    // anneau intérieur, sens inverse
    ctx.save(); ctx.translate(cx,cy); ctx.rotate(-rot*1.6); ctx.strokeStyle=col;
    ctx.globalAlpha=.35; ctx.lineWidth=1.5;
    ctx.beginPath(); ctx.arc(0,0,R*0.80,0.3,Math.PI*1.5); ctx.stroke();
    ctx.globalAlpha=.8; ctx.lineWidth=4;
    ctx.beginPath(); ctx.arc(0,0,R*0.80,Math.PI*1.7,Math.PI*1.95); ctx.stroke();
    ctx.globalAlpha=1; ctx.restore();

    // graduations
    ctx.save(); ctx.translate(cx,cy); ctx.rotate(rot*0.5); ctx.strokeStyle=col;
    for (let k=0;k<60;k++){
      const a=k*(Math.PI*2/60);
      const long=(k%5===0)?R*0.05:R*0.025;
      ctx.globalAlpha=(k%5===0)?.55:.22; ctx.lineWidth=(k%5===0)?1.6:1;
      ctx.beginPath();
      ctx.moveTo(Math.cos(a)*R*0.86, Math.sin(a)*R*0.86);
      ctx.lineTo(Math.cos(a)*(R*0.86+long), Math.sin(a)*(R*0.86+long));
      ctx.stroke();
    }
    ctx.globalAlpha=1; ctx.restore();

    // onde radiale (énergie selon l'état)
    ctx.save(); ctx.translate(cx,cy); ctx.strokeStyle=col; ctx.lineCap="round";
    const rInt=R*0.46;
    for (let i=0;i<N;i++){
      const a=i/N*Math.PI*2 - Math.PI/2;
      const len=R*0.05 + donnees[i]*R*0.16*ampli;
      ctx.globalAlpha=0.35 + donnees[i]*0.6; ctx.lineWidth=2.4;
      ctx.beginPath();
      ctx.moveTo(Math.cos(a)*rInt, Math.sin(a)*rInt);
      ctx.lineTo(Math.cos(a)*(rInt+len), Math.sin(a)*(rInt+len));
      ctx.stroke();
    }
    ctx.globalAlpha=1; ctx.restore();

    // cœur lumineux
    const puls = 1 + (reduit?0:Math.sin(now*0.005)*0.06);
    const g = ctx.createRadialGradient(cx,cy,0,cx,cy,R*0.34*puls);
    g.addColorStop(0,col);
    g.addColorStop(0.4,"color-mix(in srgb,"+col+" 40%, transparent)");
    g.addColorStop(1,"transparent");
    ctx.globalAlpha=.9; ctx.fillStyle=g;
    ctx.beginPath(); ctx.arc(cx,cy,R*0.34*puls,0,Math.PI*2); ctx.fill();
    ctx.globalAlpha=1;

    requestAnimationFrame(dessiner);
  }

  // --- Bouton fermer : appelle le "pont" Python (window.pywebview.api) ---
  document.getElementById("fermer").addEventListener("click", () => {
    if (window.pywebview && window.pywebview.api && window.pywebview.api.fermer){
      window.pywebview.api.fermer();
    }
  });

  // --- Démarrage ---
  redimensionner();
  appliquerEtat("veille");
  loguer("démarrage de l'interface HUD…","sys");
  loguer("recherche du backend…","sys");
  connecter();
  requestAnimationFrame(dessiner);
})();
