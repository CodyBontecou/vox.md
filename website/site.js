/* Vox.md site behaviour: sidebar scroll-spy (docs + legal) and docs search.
   No dependencies; everything degrades to plain links without JavaScript. */
(function () {
  'use strict';

  /* ---------------------------------------------------------- scroll-spy */
  function initScrollSpy() {
    var nav = document.querySelector('.docs-sidebar, .side-nav');
    if (!nav) return;
    var links = Array.prototype.slice.call(nav.querySelectorAll('a[href^="#"]'));
    var items = links.map(function (link) {
      var id = decodeURIComponent(link.getAttribute('href').slice(1));
      return { link: link, target: document.getElementById(id) };
    }).filter(function (item) { return item.target; });
    if (!items.length) return;

    var list = nav.querySelector('ol, ul');
    var current = null;
    var ticking = false;

    function setActive(item) {
      if (item === current) return;
      if (current) current.link.removeAttribute('aria-current');
      current = item;
      if (!item) return;
      item.link.setAttribute('aria-current', 'true');
      // Keep the active chip visible when the list scrolls horizontally (phone width).
      if (list && list.scrollWidth > list.clientWidth + 1) {
        var l = item.link.offsetLeft - list.offsetLeft;
        if (l < list.scrollLeft || l + item.link.offsetWidth > list.scrollLeft + list.clientWidth) {
          list.scrollTo({ left: Math.max(0, l - 16), behavior: 'auto' });
        }
      }
    }

    function update() {
      ticking = false;
      var line = Math.min(160, window.innerHeight * 0.3);
      var active = items[0];
      for (var i = 0; i < items.length; i++) {
        if (items[i].target.getBoundingClientRect().top - line <= 0) active = items[i];
        else break;
      }
      // At the very bottom, the last section is the current one.
      if (window.innerHeight + window.scrollY >= document.documentElement.scrollHeight - 2) {
        active = items[items.length - 1];
      }
      setActive(active);
    }

    window.addEventListener('scroll', function () {
      if (!ticking) { ticking = true; window.requestAnimationFrame(update); }
    }, { passive: true });
    window.addEventListener('resize', update);
    links.forEach(function (link) {
      link.addEventListener('click', function () {
        var match = items.filter(function (i) { return i.link === link; })[0];
        if (match) setActive(match);
      });
    });
    update();
  }

  /* --------------------------------------------------------- docs search */
  function initDocsSearch() {
    var input = document.getElementById('docs-search-input');
    var results = document.getElementById('docs-search-results');
    if (!input || !results) return;
    var labels = document.documentElement.dataset;

    // Index every titled section and subsection on the page.
    var index = [];
    var headings = document.querySelectorAll('.docs-section[id] > h2, .docs-section h3[id], .docs-section h4[id]');
    Array.prototype.forEach.call(headings, function (h) {
      var section = h.closest('.docs-section');
      var id = h.id || section.id;
      var labelEl = section.querySelector('.docs-section-label');
      var group = labelEl ? labelEl.textContent.replace(/^\s*\d+\s*\/\s*/, '').trim() : '';
      // Body text: following siblings until the next heading of the same or higher level.
      var text = '';
      var level = h.tagName === 'H2' ? 2 : (h.tagName === 'H3' ? 3 : 4);
      for (var n = h.nextElementSibling; n; n = n.nextElementSibling) {
        if (/^H[2-4]$/.test(n.tagName) && Number(n.tagName[1]) <= level) break;
        if (level === 2 && n.tagName === 'H3') break;
        text += ' ' + n.textContent;
      }
      index.push({
        id: id,
        title: h.textContent.trim(),
        group: level === 2 ? (group || labels.searchSection || 'Section') : group,
        body: text.replace(/\s+/g, ' ').trim().toLowerCase()
      });
    });
    // Sidebar entries that leave the page (e.g. dedicated guides).
    Array.prototype.forEach.call(document.querySelectorAll('.docs-sidebar a:not([href^="#"]), .docs-category-card:not([href^="#"])'), function (a) {
      var title = (a.querySelector('strong') || a).textContent.trim();
      if (index.some(function (e) { return e.href === a.getAttribute('href'); })) return;
      index.push({ href: a.getAttribute('href'), title: title, group: labels.searchGuide || 'Guide', body: (a.textContent || '').toLowerCase() });
    });

    var matches = [];
    var selected = -1;

    function render(query) {
      var q = query.trim().toLowerCase();
      results.innerHTML = '';
      selected = -1;
      if (!q) { close(); return; }
      var terms = q.split(/\s+/);
      matches = index.map(function (e) {
        var t = e.title.toLowerCase();
        var score = 0;
        for (var i = 0; i < terms.length; i++) {
          var term = terms[i];
          if (t.indexOf(term) !== -1) score += t.indexOf(term) === 0 ? 6 : 4;
          else if (e.body.indexOf(term) !== -1) score += 1;
          else return null;
        }
        return { e: e, score: score };
      }).filter(Boolean).sort(function (a, b) { return b.score - a.score; }).slice(0, 8);

      if (!matches.length) {
        var li = document.createElement('li');
        li.className = 'empty';
        li.textContent = (labels.searchEmpty || 'No matches for “{query}”').replace('{query}', query.trim());
        results.appendChild(li);
      }
      matches.forEach(function (m, i) {
        var li = document.createElement('li');
        li.setAttribute('role', 'presentation');
        var a = document.createElement('a');
        a.href = m.e.href || ('#' + m.e.id);
        a.id = 'docs-search-option-' + i;
        a.setAttribute('role', 'option');
        var strong = document.createElement('strong');
        strong.textContent = m.e.title;
        var small = document.createElement('small');
        small.textContent = m.e.group;
        a.appendChild(strong);
        a.appendChild(small);
        a.addEventListener('mousedown', function (ev) { ev.preventDefault(); });
        a.addEventListener('click', function () { close(); input.blur(); });
        li.appendChild(a);
        results.appendChild(li);
      });
      results.hidden = false;
      input.setAttribute('aria-expanded', 'true');
      if (matches.length) select(0);
    }

    function select(i) {
      var options = results.querySelectorAll('a[role="option"]');
      if (!options.length) return;
      selected = (i + options.length) % options.length;
      Array.prototype.forEach.call(options, function (o, j) { o.setAttribute('aria-selected', j === selected ? 'true' : 'false'); });
      input.setAttribute('aria-activedescendant', options[selected].id);
      options[selected].scrollIntoView({ block: 'nearest' });
    }

    function close() {
      results.hidden = true;
      input.setAttribute('aria-expanded', 'false');
      input.removeAttribute('aria-activedescendant');
    }

    function go() {
      var options = results.querySelectorAll('a[role="option"]');
      var target = options[selected >= 0 ? selected : 0];
      if (!target) return;
      close();
      input.blur();
      var href = target.getAttribute('href');
      if (href.charAt(0) === '#') {
        var el = document.getElementById(href.slice(1));
        if (el) {
          history.replaceState(null, '', href);
          el.scrollIntoView({ block: 'start' });
          if (!el.hasAttribute('tabindex')) el.setAttribute('tabindex', '-1');
          el.focus({ preventScroll: true });
        }
      } else {
        window.location.href = href;
      }
    }

    input.addEventListener('input', function () { render(input.value); });
    input.addEventListener('focus', function () { if (input.value.trim()) render(input.value); });
    input.addEventListener('blur', function () { window.setTimeout(close, 120); });
    input.addEventListener('keydown', function (ev) {
      if (ev.key === 'ArrowDown') { ev.preventDefault(); select(selected + 1); }
      else if (ev.key === 'ArrowUp') { ev.preventDefault(); select(selected - 1); }
      else if (ev.key === 'Enter') { ev.preventDefault(); go(); }
      else if (ev.key === 'Escape') { input.value = ''; close(); input.blur(); }
    });
    var form = input.closest('form');
    if (form) form.addEventListener('submit', function (ev) { ev.preventDefault(); go(); });

    // "/" focuses search unless the user is already typing somewhere.
    document.addEventListener('keydown', function (ev) {
      if (ev.key !== '/' || ev.metaKey || ev.ctrlKey || ev.altKey) return;
      var t = ev.target;
      if (t && (t.isContentEditable || /^(INPUT|TEXTAREA|SELECT)$/.test(t.tagName))) return;
      ev.preventDefault();
      input.focus();
      input.select();
    });
  }

  function init() { initScrollSpy(); initDocsSearch(); }
  if (document.readyState === 'loading') document.addEventListener('DOMContentLoaded', init);
  else init();
})();
