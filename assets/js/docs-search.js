(function() {
  'use strict';

  var searchIndex = null;
  var input = document.getElementById('docs-search-input');
  var resultsContainer = document.getElementById('docs-search-results');
  if (!input || !resultsContainer) return;

  // Load the search index JSON
  var baseUrl = document.querySelector('meta[name="baseurl"]');
  var base = baseUrl ? baseUrl.content : '';
  fetch(base + '/search-index.json')
    .then(function(r) { return r.json(); })
    .then(function(data) { searchIndex = data; })
    .catch(function() { /* search unavailable */ });

  function normalize(str) {
    return str.toLowerCase().replace(/[^\w\s]/g, ' ');
  }

  function search(query) {
    if (!searchIndex || !query) return [];
    var terms = normalize(query).split(/\s+/).filter(Boolean);
    if (terms.length === 0) return [];

    var scored = [];
    for (var i = 0; i < searchIndex.length; i++) {
      var doc = searchIndex[i];
      var titleLower = normalize(doc.title);
      var descLower = normalize(doc.description);
      var bodyLower = normalize(doc.body);
      var score = 0;

      for (var t = 0; t < terms.length; t++) {
        var term = terms[t];
        if (titleLower.indexOf(term) !== -1) score += 10;
        if (descLower.indexOf(term) !== -1) score += 5;
        if (bodyLower.indexOf(term) !== -1) score += 1;
      }

      if (score > 0) {
        scored.push({ doc: doc, score: score });
      }
    }

    scored.sort(function(a, b) { return b.score - a.score; });
    return scored.slice(0, 8);
  }

  function getSnippet(body, query) {
    var terms = normalize(query).split(/\s+/).filter(Boolean);
    var bodyLower = normalize(body);
    var pos = -1;
    for (var i = 0; i < terms.length; i++) {
      pos = bodyLower.indexOf(terms[i]);
      if (pos !== -1) break;
    }
    if (pos === -1) return '';
    var start = Math.max(0, pos - 40);
    var end = Math.min(body.length, pos + 80);
    var snippet = body.substring(start, end).replace(/\n/g, ' ').replace(/[#*_\[\]()]/g, '');
    return (start > 0 ? '...' : '') + snippet.trim() + (end < body.length ? '...' : '');
  }

  function render(results, query) {
    if (results.length === 0) {
      resultsContainer.innerHTML = '<div class="docs-search-empty">No results found</div>';
      resultsContainer.hidden = false;
      return;
    }

    var html = '';
    for (var i = 0; i < results.length; i++) {
      var doc = results[i].doc;
      var snippet = getSnippet(doc.body, query);
      html += '<a href="' + base + doc.url + '" class="docs-search-result">';
      html += '<div class="docs-search-result-title">' + escapeHtml(doc.title) + '</div>';
      html += '<div class="docs-search-result-group">' + escapeHtml(doc.group) + '</div>';
      if (snippet) {
        html += '<div class="docs-search-result-snippet">' + escapeHtml(snippet) + '</div>';
      }
      html += '</a>';
    }
    resultsContainer.innerHTML = html;
    resultsContainer.hidden = false;
  }

  function escapeHtml(str) {
    var div = document.createElement('div');
    div.textContent = str;
    return div.innerHTML;
  }

  var debounceTimer;
  input.addEventListener('input', function() {
    clearTimeout(debounceTimer);
    var query = input.value.trim();
    if (!query) {
      resultsContainer.hidden = true;
      return;
    }
    debounceTimer = setTimeout(function() {
      var results = search(query);
      render(results, query);
    }, 150);
  });

  // Close results on click outside
  document.addEventListener('click', function(e) {
    if (!input.contains(e.target) && !resultsContainer.contains(e.target)) {
      resultsContainer.hidden = true;
    }
  });

  // Reopen on focus if there's a query
  input.addEventListener('focus', function() {
    if (input.value.trim() && resultsContainer.children.length > 0) {
      resultsContainer.hidden = false;
    }
  });

  // Keyboard: Escape closes, / focuses
  document.addEventListener('keydown', function(e) {
    if (e.key === '/' && document.activeElement !== input && !e.metaKey && !e.ctrlKey) {
      e.preventDefault();
      input.focus();
    }
    if (e.key === 'Escape' && document.activeElement === input) {
      input.blur();
      resultsContainer.hidden = true;
    }
  });
})();
