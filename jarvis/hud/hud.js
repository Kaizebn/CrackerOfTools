/* hud.js — animation du HUD (Étape 2).
   Pour l'instant le HUD est "vivant" (anneaux + onde) mais PAS encore relié
   au backend : c'est le sujet de l'Étape 3. */
(() => {
  "use strict";
  const reduit = matchMedia("(prefers-reduced-motion:reduce)").matches;
  const canvas = document.getElementById("reacteur");
  const ctx = canvas.getContext("2d");
  const N = 84;
  const donnees = new Float32Array(N);

  function accent(){ return getComputedStyle(document.documentElement).getPropertyValue("--accent").trim() || "#22e0d6"; }

  // --- Journal ---
  const elLog = document.getElementById("log");
  function heure(){ return new Date().toTimeString().slice(0,8); }
  function loguer(texte, type="sys"){
    const l = document.createElement("div");
    l.className = "ligne " + type;
    l.innerHTML = `<span class="horo">${heure()}</span> ${texte}`;
    elLog.appendChild(l);
    while (elLog.children.length > 6) elLog.removeChild(elLog.firstChild);
  }

  // --- Dimensionnement net ---
  function redimensionner(){
    const dpr = Math.min(window.devicePixelRatio||1, 2);
    canvas.width = canvas.clientWidth*dpr;
    canvas.height = canvas.clientHeight*dpr;
    ctx.setTransform(dpr,0,0,dpr,0,0);
  }
  window.addEventListener("resize", redimensionner);

  // --- Onde simulée (l'onde réactive au micro arrivera à l'Étape 4) ---
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

    // onde radiale
    ctx.save(); ctx.translate(cx,cy); ctx.strokeStyle=col; ctx.lineCap="round";
    const rInt=R*0.46;
    for (let i=0;i<N;i++){
      const a=i/N*Math.PI*2 - Math.PI/2;
      const len=R*0.05 + donnees[i]*R*0.16;
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
  loguer("démarrage de l'interface HUD…","sys");
  loguer("cerveau : Ollama (local) — à connecter","sys");
  loguer("en attente du backend…","sys");
  requestAnimationFrame(dessiner);
})();
