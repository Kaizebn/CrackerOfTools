/* hud.js — animation du HUD + connexion au backend (Étape 4).
   - Le cercle (anneaux + onde) tourne toujours.
   - Il RÉAGIT à ta voix : le backend envoie le NIVEAU du micro -> l'onde grandit.
   - Il change d'ÉTAT (veille / écoute / réflexion / action / erreur).
   - S'il n'y a pas de backend, il reste en animation d'ambiance. */
(() => {
  "use strict";
  const reduit = matchMedia("(prefers-reduced-motion:reduce)").matches;
  const canvas = document.getElementById("reacteur");
  const ctx = canvas.getContext("2d");
  const N = 96;
  const donnees = new Float32Array(N);

  const ETATS = {
    veille:    {couleur:"#ff2a3a", ampli:0.30, label:"VEILLE",    sous:"en ligne"},
    ecoute:    {couleur:"#ff5561", ampli:1.00, label:"ÉCOUTE",    sous:"je t'écoute"},
    reflexion: {couleur:"#ff7a3c", ampli:0.60, label:"RÉFLEXION", sous:"analyse…"},
    action:    {couleur:"#ffb03a", ampli:0.85, label:"ACTION",    sous:"exécution"},
    erreur:    {couleur:"#ff3355", ampli:0.45, label:"ERREUR",    sous:"souci"},
  };
  let etat = "veille";
  let niveauMic = 0;          // 0..1, envoyé par le backend quand tu parles

  const racine = document.documentElement;
  const elEtat = document.getElementById("etat");
  const elSous = document.getElementById("sous");
  function appliquerEtat(nom){
    if (!ETATS[nom]) return;
    etat = nom;
    racine.style.setProperty("--accent", ETATS[nom].couleur);
    elEtat.textContent = ETATS[nom].label;
    elSous.textContent = ETATS[nom].sous;
  }
  function accent(){ return getComputedStyle(racine).getPropertyValue("--accent").trim() || "#ff2a3a"; }

  // --- Journal ---
  const elLog = document.getElementById("log");
  function heure(){ return new Date().toTimeString().slice(0,8); }
  function loguer(texte, genre="sys"){
    const l = document.createElement("div");
    l.className = "ligne " + genre;
    l.innerHTML = `<span class="horo">${heure()}</span> ${texte}`;
    elLog.appendChild(l);
    while (elLog.children.length > 7) elLog.removeChild(elLog.firstChild);
  }

  // --- Connexion backend (WebSocket) ---
  let ws = null, connecte = false;
  function connecter(){
    try{ ws = new WebSocket("ws://127.0.0.1:8765"); }catch(_){ return; }
    ws.onopen = () => { connecte = true; loguer("backend connecté ✓","act"); };
    ws.onmessage = (e) => {
      let m; try{ m = JSON.parse(e.data); }catch(_){ return; }
      if (m.type === "etat") appliquerEtat(m.valeur);
      else if (m.type === "log") loguer(m.texte, m.genre || "sys");
      else if (m.type === "niveau") niveauMic = m.valeur;
    };
    ws.onclose = () => {
      if (connecte) loguer("backend déconnecté","sys");
      connecte = false; niveauMic = 0;
      setTimeout(connecter, 2000);
    };
    ws.onerror = () => { try{ ws.close(); }catch(_){} };
  }

  function redimensionner(){
    const dpr = Math.min(window.devicePixelRatio||1, 2);
    canvas.width = canvas.clientWidth*dpr;
    canvas.height = canvas.clientHeight*dpr;
    ctx.setTransform(dpr,0,0,dpr,0,0);
  }
  window.addEventListener("resize", redimensionner);

  function onde(t, energie){
    for (let i=0;i<N;i++){
      const a = i/N*Math.PI*2;
      const s = 0.5 + 0.5*Math.sin(t*0.0022 + a*3)*Math.sin(t*0.0011 + a*7);
      const cible = Math.abs(s) * energie;
      donnees[i] = donnees[i]*0.7 + cible*0.3;    // lissage
    }
  }

  function dessiner(now){
    const w = canvas.clientWidth, h = canvas.clientHeight;
    const cx = w/2, cy = h/2, R = Math.min(w,h)/2;
    const col = accent();
    // l'énergie de l'onde : voix (micro) si tu parles, sinon animation d'ambiance
    const energie = Math.max(ETATS[etat].ampli*0.55, niveauMic*1.4);
    ctx.clearRect(0,0,w,h);
    onde(now, energie);
    const rot = reduit ? 0 : now*0.00035;

    ctx.save(); ctx.translate(cx,cy); ctx.rotate(rot); ctx.strokeStyle=col;
    for (let k=0;k<12;k++){
      const a0=k*(Math.PI*2/12)+0.08, a1=a0+(Math.PI*2/12)-0.16;
      ctx.globalAlpha = k%3? .30 : .6; ctx.lineWidth=2;
      ctx.beginPath(); ctx.arc(0,0,R*0.94,a0,a1); ctx.stroke();
    }
    ctx.globalAlpha=1; ctx.restore();

    ctx.save(); ctx.translate(cx,cy); ctx.rotate(-rot*1.6); ctx.strokeStyle=col;
    ctx.globalAlpha=.35; ctx.lineWidth=1.5;
    ctx.beginPath(); ctx.arc(0,0,R*0.80,0.3,Math.PI*1.5); ctx.stroke();
    ctx.globalAlpha=.8; ctx.lineWidth=4;
    ctx.beginPath(); ctx.arc(0,0,R*0.80,Math.PI*1.7,Math.PI*1.95); ctx.stroke();
    ctx.globalAlpha=1; ctx.restore();

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

    // onde radiale (réagit à la voix)
    ctx.save(); ctx.translate(cx,cy); ctx.strokeStyle=col; ctx.lineCap="round";
    const rInt=R*0.46;
    for (let i=0;i<N;i++){
      const a=i/N*Math.PI*2 - Math.PI/2;
      const len=R*0.05 + donnees[i]*R*0.22;
      ctx.globalAlpha=0.35 + donnees[i]*0.6; ctx.lineWidth=2.6;
      ctx.beginPath();
      ctx.moveTo(Math.cos(a)*rInt, Math.sin(a)*rInt);
      ctx.lineTo(Math.cos(a)*(rInt+len), Math.sin(a)*(rInt+len));
      ctx.stroke();
    }
    ctx.globalAlpha=1; ctx.restore();

    const puls = 1 + (reduit?0:Math.sin(now*0.005)*0.06) + niveauMic*0.15;
    const g = ctx.createRadialGradient(cx,cy,0,cx,cy,R*0.34*puls);
    g.addColorStop(0,col);
    g.addColorStop(0.4,"color-mix(in srgb,"+col+" 40%, transparent)");
    g.addColorStop(1,"transparent");
    ctx.globalAlpha=.9; ctx.fillStyle=g;
    ctx.beginPath(); ctx.arc(cx,cy,R*0.34*puls,0,Math.PI*2); ctx.fill();
    ctx.globalAlpha=1;

    // le niveau micro redescend doucement s'il n'arrive plus rien
    niveauMic *= 0.92;

    requestAnimationFrame(dessiner);
  }

  document.getElementById("fermer").addEventListener("click", () => {
    if (window.pywebview && window.pywebview.api && window.pywebview.api.fermer){
      window.pywebview.api.fermer();
    }
  });

  redimensionner();
  appliquerEtat("veille");
  loguer("interface HUD démarrée","sys");
  loguer("recherche du backend…","sys");
  connecter();
  requestAnimationFrame(dessiner);
})();
