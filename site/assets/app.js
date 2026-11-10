(function () {
  // Project filter
  var btns = document.querySelectorAll('.filter button');
  btns.forEach(function (b) {
    b.addEventListener('click', function () {
      btns.forEach(function (x) { x.classList.toggle('on', x === b); });
      var f = b.getAttribute('data-f');
      document.querySelectorAll('.card').forEach(function (c) {
        c.hidden = !(f === 'all' || c.getAttribute('data-cat') === f);
      });
    });
  });

  // Theme toggle (v1 only); preference kept per browser, page works without it
  var t = document.getElementById('theme');
  if (t) {
    try { var saved = localStorage.getItem('theme'); if (saved) document.documentElement.dataset.theme = saved; } catch (e) {}
    t.addEventListener('click', function () {
      var next = document.documentElement.dataset.theme === 'dark' ? 'light' : 'dark';
      document.documentElement.dataset.theme = next;
      try { localStorage.setItem('theme', next); } catch (e) {}
    });
  }

  // Visitor counter (v1 only): same-origin API behind CloudFront /api/*
  var v = document.getElementById('visits');
  if (v) {
    fetch('/api/visits', { method: 'POST' })
      .then(function (r) { if (!r.ok) throw new Error(r.status); return r.json(); })
      .then(function (d) { v.textContent = Number(d.visits).toLocaleString(); })
      .catch(function () { v.textContent = 'n/a'; });
  }
})();
