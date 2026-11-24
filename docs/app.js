'use strict';

(() => {
  const root = document.documentElement;
  const toggle = document.getElementById('theme-toggle');
  const label = document.getElementById('theme-label');
  function setTheme(theme) {
    root.dataset.theme = theme;
    const dark = theme === 'dark';
    toggle.setAttribute('aria-pressed', String(dark));
    toggle.setAttribute('aria-label', dark ? 'Ativar tema claro' : 'Ativar tema escuro');
    label.textContent = dark ? 'Tema claro' : 'Tema escuro';
  }
  let preferred;
  try { preferred = localStorage.getItem('laboratorio-2027-theme'); } catch (_) { /* Storage can be unavailable in private profiles. */ }
  if (!['light', 'dark'].includes(preferred)) {
    preferred = window.matchMedia && window.matchMedia('(prefers-color-scheme: dark)').matches ? 'dark' : 'light';
  }
  setTheme(preferred);
  toggle.addEventListener('click', () => {
    const theme = root.dataset.theme === 'dark' ? 'light' : 'dark';
    setTheme(theme);
    try { localStorage.setItem('laboratorio-2027-theme', theme); } catch (_) { /* Theme remains usable without persistence. */ }
  });

  const input = document.getElementById('program-search');
  const filters = [...document.querySelectorAll('[data-filter]')];
  const cards = [...document.querySelectorAll('.program-card')];
  const helpCard = document.querySelector('.help-card');
  const count = document.getElementById('results-count');
  const empty = document.getElementById('empty-state');
  let selected = 'todos';
  const normalize = value => value.toLocaleLowerCase('pt-BR').normalize('NFD').replace(/[\u0300-\u036f]/g, '');
  function updateResults() {
    const query = normalize(input.value.trim());
    let visible = 0;
    for (const card of cards) {
      const categoryMatches = selected === 'todos' || card.dataset.category === selected;
      const textMatches = !query || normalize(card.dataset.search + ' ' + card.textContent).includes(query);
      card.hidden = !(categoryMatches && textMatches);
      if (!card.hidden) visible++;
    }
    count.textContent = visible === 1 ? '1 programa encontrado' : `${visible} programas encontrados`;
    empty.hidden = visible !== 0;
    helpCard.hidden = Boolean(query) || selected !== 'todos';
    filters.forEach(button => {
      const active = button.dataset.filter === selected;
      button.classList.toggle('active', active);
      button.setAttribute('aria-pressed', String(active));
    });
  }
  input.addEventListener('input', updateResults);
  filters.forEach(button => button.addEventListener('click', () => {
    selected = button.dataset.filter;
    updateResults();
  }));
  document.getElementById('reset-search').addEventListener('click', () => {
    selected = 'todos';
    input.value = '';
    updateResults();
    input.focus();
  });
})();
