/* Gootd - dust and the copy control. Nothing in here reveals content:
   every word and control is drawn and clickable before this file runs. */

(() => {
  'use strict';

  const reduced = window.matchMedia('(prefers-reduced-motion: reduce)');

  /* ── dust ─────────────────────────────────────────────────────────────
     The same field the app paints behind its own window, from the same
     fixed seed and the same density: one mote per ~900px of surface. */

  const sky = document.getElementById('dust');
  const sctx = sky.getContext('2d', { alpha: true });
  const start = performance.now();
  let motes = [], sw = 0, sh = 0;

  function rng(seed) {
    let s = BigInt(seed);
    const m = (1n << 64n) - 1n;
    return () => {
      s = (s * 6364136223846793005n + 1442695040888963407n) & m;
      return Number((s >> 11n) & 0x1FFFFFn) / 0x200000;
    };
  }

  function buildDust() {
    sw = window.innerWidth;
    sh = window.innerHeight;
    sky.style.width = sw + 'px';
    sky.style.height = sh + 'px';
    const dpr = Math.min(window.devicePixelRatio || 1, 2);
    sky.width = Math.max(1, Math.round(sw * dpr));
    sky.height = Math.max(1, Math.round(sh * dpr));
    sctx.setTransform(dpr, 0, 0, dpr, 0, 0);
    sctx.fillStyle = '#fff';

    const next = rng('0x243F6A8885A308D3');
    const count = Math.max(18, Math.round((sw * sh) / 900));
    motes = new Array(count);
    for (let i = 0; i < count; i++) {
      motes[i] = {
        x: next() * sw,
        y: next() * sh,
        r: 0.35 + next() * 0.55,
        // Biased dim. A field of equally bright points reads as a pattern
        // rather than as depth.
        b: 0.12 + Math.pow(next(), 1.7) * 0.40,
        v: 0.10 + next() * 0.55,
        p: next() * Math.PI * 2
      };
    }
  }

  function paintDust(t) {
    sctx.clearRect(0, 0, sw, sh);
    for (let i = 0; i < motes.length; i++) {
      const s = motes[i];
      const y = (s.y + t * s.v * 3) % (sh + 4) - 2;
      sctx.globalAlpha = s.b * (0.82 + 0.18 * Math.sin(t * 0.7 + s.p));
      sctx.beginPath();
      sctx.arc(s.x, y, s.r, 0, Math.PI * 2);
      sctx.fill();
    }
    sctx.globalAlpha = 1;
  }

  buildDust();
  paintDust(0);

  let resizeTimer;
  window.addEventListener('resize', () => {
    clearTimeout(resizeTimer);
    resizeTimer = setTimeout(() => { buildDust(); paintDust(clock()); }, 120);
  });

  const clock = () => (performance.now() - start) / 1000;

  if (!reduced.matches) {
    const loop = () => { paintDust(clock()); requestAnimationFrame(loop); };
    requestAnimationFrame(loop);
  }

  /* ── copy ─────────────────────────────────────────────────────────────
     The label says what it does and then says what happened. The block's
     width is held by a hidden copy of the longer word, so nothing moves. */

  const copy = document.getElementById('copy');
  const copyLabel = document.getElementById('copy-l');
  const cmdText = document.getElementById('cmd-text');
  let copyTimer = null;

  function fallbackCopy(text) {
    const box = document.createElement('textarea');
    box.value = text;
    box.setAttribute('readonly', '');
    box.style.cssText = 'position:fixed;top:0;left:-9999px;opacity:0';
    document.body.appendChild(box);
    box.select();
    let ok = false;
    try { ok = document.execCommand('copy'); } catch (e) { ok = false; }
    document.body.removeChild(box);
    return ok;
  }

  function said(word) {
    copyLabel.textContent = word;
    copy.classList.add('is-done');
    clearTimeout(copyTimer);
    copyTimer = setTimeout(() => {
      copyLabel.textContent = 'Copy';
      copy.classList.remove('is-done');
    }, 1900);
  }

  copy.addEventListener('click', async (e) => {
    e.stopPropagation();
    const text = cmdText.textContent.trim();
    try {
      await navigator.clipboard.writeText(text);
      said('Copied');
    } catch (err) {
      said(fallbackCopy(text) ? 'Copied' : 'Press ⌘C');
    }
  });

})();
