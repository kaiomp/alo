// Video, community link and the two forms. No tracking, no cookies.

const TURNSTILE_SITEKEY = '0x4AAAAAAFoUAdybZ0uiYS-g';
// Cloudflare's public test key, always passes; used on localhost only.
const TURNSTILE_TESTE = '1x00000000000000000000AA';
const LOCAL = ['localhost', '127.0.0.1'].includes(location.hostname);

const MENSAGENS = {
  nome: 'Escreva seu nome.',
  contato: 'Deixe um e-mail ou um WhatsApp para a gente falar com você.',
  email: 'Confira o e-mail.',
  whatsapp: 'Confira o número do WhatsApp, com DDD.',
  consentimento: 'Marque a caixa de concordância para enviar.',
  robo: 'Só um instante: estamos confirmando que você não é um robô. Tente de novo em alguns segundos.',
  verificacao: 'Não conseguimos confirmar que você não é um robô. Tente de novo.',
  muitas_tentativas: 'Muitos envios seguidos. Espere um minuto e tente de novo.',
  rede: 'Sem conexão com o servidor. Confira a internet e tente de novo.',
  padrao: 'Algo deu errado do nosso lado. Tente de novo em instantes.',
};

/* Videos start muted while on screen and pause when they leave, like a feed.
   With reduced motion or Data Saver nothing starts by itself: the poster stays,
   and the overview keeps its play button. */
const CALMO = matchMedia('(prefers-reduced-motion: reduce)').matches || navigator.connection?.saveData === true;
const OLHO = 'IntersectionObserver' in window;
const MAX_CLIPES = 2;

const filme = document.getElementById('filme');
if (filme) {
  const som = document.getElementById('som');
  const rotulo = som.querySelector('span');
  const atualizar = () => {
    som.setAttribute('aria-pressed', String(!filme.muted));
    rotulo.textContent = filme.muted ? 'Ouvir com som' : 'Tirar o som';
  };
  const comSom = () => {
    filme.muted = false;
    filme.currentTime = 0;
    filme.play().catch(() => {});
  };
  som.addEventListener('click', () => (filme.muted ? comSom() : (filme.muted = true)));
  filme.addEventListener('volumechange', atualizar);
  document.querySelectorAll('[data-ver-video]').forEach((a) => a.addEventListener('click', comSom));

  // A pause the viewer made sticks; a pause made by scrolling away does not.
  let pausouSozinho = false;
  let pausaNossa = false;
  filme.addEventListener('pause', () => {
    if (!pausaNossa && !filme.ended) pausouSozinho = true;
    pausaNossa = false;
  });
  filme.addEventListener('play', () => (pausouSozinho = false));

  if (!CALMO && OLHO) {
    new IntersectionObserver(([e]) => {
      if (e.intersectionRatio >= 0.6) {
        if (filme.paused && !filme.ended && !pausouSozinho) filme.play().catch(() => {});
      } else if (!filme.paused) {
        pausaNossa = true;
        filme.pause();
      }
    }, { threshold: [0, 0.6] }).observe(filme);
  }
}

/* Short silent loops in the part cards. preload="none" keeps them unloaded until they first
   play; at most MAX_CLIPES play at once, the most visible ones. */
const clipes = [...document.querySelectorAll('video[data-clipe]')];
if (clipes.length && !CALMO && OLHO) {
  const vistos = new Map();
  const escolher = () => {
    const tocar = [...vistos]
      .filter(([, r]) => r >= 0.5)
      .sort((x, y) => y[1] - x[1])
      .slice(0, MAX_CLIPES)
      .map(([v]) => v);
    for (const v of clipes) {
      if (tocar.includes(v)) {
        if (v.paused) v.play().catch(() => {});
      } else if (!v.paused) v.pause();
    }
  };
  const olho = new IntersectionObserver((es) => {
    for (const e of es) vistos.set(e.target, e.intersectionRatio);
    escolher();
  }, { threshold: [0, 0.25, 0.5, 0.75, 1] });
  clipes.forEach((v) => olho.observe(v));
}

/* Community link from config.js; without it the "em breve" text stays. */
const comunidade = window.ALO_CONFIG?.comunidade;
if (comunidade?.startsWith('https://')) {
  document.querySelectorAll('[data-comunidade]').forEach((el) => {
    const a = document.createElement('a');
    a.className = 'botao botao--ipe';
    a.href = comunidade;
    a.target = '_blank';
    a.rel = 'noopener';
    a.textContent = 'Entrar no grupo do WhatsApp';
    el.replaceChildren(a);
  });
}

/* Forms. Turnstile (the anti-robot check) loads only when a form comes near. */
const formularios = [...document.querySelectorAll('form[data-rota]')];
let turnstilePedido = false;

function carregarTurnstile() {
  if (turnstilePedido) return;
  turnstilePedido = true;
  window.aloTurnstile = () => {
    for (const form of formularios) {
      const caixa = form.querySelector('[data-turnstile]');
      form.dataset.widget = window.turnstile.render(caixa, {
        sitekey: LOCAL ? TURNSTILE_TESTE : TURNSTILE_SITEKEY,
        language: 'pt-br',
        theme: 'light',
        appearance: 'interaction-only',
        size: form.clientWidth < 300 ? 'compact' : 'flexible',
      });
    }
  };
  const s = document.createElement('script');
  s.src = 'https://challenges.cloudflare.com/turnstile/v0/api.js?render=explicit&onload=aloTurnstile';
  s.async = true;
  document.head.append(s);
}

function conferir(form) {
  const c = form.elements;
  if (c.nome && c.nome.value.trim().length < 2) return 'nome';
  if (c.email) {
    if (!c.email.value.trim() && !c.whatsapp.value.trim()) return 'contato';
    if (!c.email.checkValidity()) return 'email';
    const digitos = c.whatsapp.value.replace(/\D/g, '').length;
    if (c.whatsapp.value.trim() && (digitos < 10 || digitos > 15)) return 'whatsapp';
  }
  if (c.contato && c.contato.value.trim().length < 5) return 'contato';
  if (c.consentimento && !c.consentimento.checked) return 'consentimento';
  return null;
}

function dados(form) {
  const d = {};
  for (const [k, v] of new FormData(form)) {
    if (k === 'ajuda') (d.ajuda ??= []).push(v);
    else if (k === 'cf-turnstile-response') d.token = v;
    else if (k !== 'consentimento') d[k] = v;
  }
  if (form.elements.consentimento) d.consentimento = form.elements.consentimento.checked;
  return d;
}

function mostrar(form, codigo) {
  const campo = form.elements[codigo] ?? (codigo === 'contato' ? form.elements.email : null);
  const el = campo instanceof HTMLElement ? campo : null;
  form.querySelector('[data-alerta]').textContent = el?.dataset.erro || MENSAGENS[codigo] || MENSAGENS.padrao;
  if (el) {
    el.setAttribute('aria-invalid', 'true');
    el.focus();
  }
}

/* Personal invite link. Only the first name goes in it; the server cleans it again. */
const LETRA = 'A-Za-zÀ-ÖØ-öø-ÿ';
const NOME = new RegExp(`^[${LETRA}]+(?:['-][${LETRA}]+)*$`);

function prepararConvite(caixa, nomeCompleto) {
  const primeiro = nomeCompleto.trim().split(/\s+/)[0] || '';
  const valido = primeiro.length >= 2 && primeiro.length <= 24 && NOME.test(primeiro);
  const link = `${location.origin}/convite${valido ? `?de=${encodeURIComponent(primeiro)}` : ''}`;
  const texto = 'Te chamei para o Alô: livre, aberto, sem dono. Feito no Brasil.';
  const e = encodeURIComponent;
  const destinos = {
    whatsapp: `https://wa.me/?text=${e(`${texto} ${link}`)}`,
    telegram: `https://t.me/share/url?url=${e(link)}&text=${e(texto)}`,
    x: `https://twitter.com/intent/tweet?text=${e(texto)}&url=${e(link)}`,
  };
  caixa.querySelectorAll('[data-rede]').forEach((a) => (a.href = destinos[a.dataset.rede]));

  const compartilhar = caixa.querySelector('[data-compartilhar]');
  if (navigator.share) {
    compartilhar.hidden = false;
    compartilhar.addEventListener('click', () => navigator.share({ title: 'Alô', text: texto, url: link }).catch(() => {}));
  }
  const copiar = caixa.querySelector('[data-copiar]');
  copiar.addEventListener('click', async () => {
    try {
      await navigator.clipboard.writeText(link);
      copiar.textContent = 'Link copiado!';
    } catch {
      copiar.textContent = link;
    }
  });
}

for (const form of formularios) {
  const botao = form.querySelector('[type=submit]');
  form.addEventListener('focusin', carregarTurnstile, { once: true });
  if ('IntersectionObserver' in window) {
    const olho = new IntersectionObserver(([e]) => {
      if (e.isIntersecting) {
        carregarTurnstile();
        olho.disconnect();
      }
    }, { rootMargin: '600px' });
    olho.observe(form);
  } else carregarTurnstile();

  form.addEventListener('submit', async (ev) => {
    ev.preventDefault();
    form.querySelector('[data-alerta]').textContent = '';
    form.querySelectorAll('[aria-invalid]').forEach((c) => c.removeAttribute('aria-invalid'));

    const erro = conferir(form);
    if (erro) return mostrar(form, erro);
    const d = dados(form);
    if (!d.token) return mostrar(form, 'robo');

    botao.disabled = true;
    try {
      const res = await fetch(form.dataset.rota, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify(d),
      });
      if (res.ok) {
        const ok = form.parentElement.querySelector('[data-sucesso]');
        form.hidden = true;
        ok.hidden = false;
        if (form.elements.nome) prepararConvite(ok, form.elements.nome.value);
        ok.focus();
        return;
      }
      const r = await res.json().catch(() => ({}));
      mostrar(form, r.erro === 'campo' ? r.campo : r.erro);
    } catch {
      mostrar(form, 'rede');
    } finally {
      botao.disabled = false;
      // Each token works once; get a fresh one for the next try.
      if (form.dataset.widget) window.turnstile?.reset(form.dataset.widget);
    }
  });
}
