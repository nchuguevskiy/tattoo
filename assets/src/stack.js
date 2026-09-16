// Three Memento-style polaroids: terminal "photos" with handwritten notes.
// Shared by hero.html (README) and social.html (GitHub social preview).
const polaroids = [
  {
    cls: "back left",
    photo: `
      <div class="line prompt">&gt; /compact</div>
      <div class="line ok">✓ Compacted</div>
      <div class="line hook">⎿ tattoo part 1/5</div>
      <div class="line hook">⎿ tattoo part 2/5</div>
      <div class="line hook">⎿ tattoo part 3/5</div>
      <div class="line dim">  …</div>`,
    note: `never push to <u>main</u>.<br>drafts only.`,
  },
  {
    cls: "back right",
    photo: `
      <div class="line dim">k6 · 500 rps · staging</div>
      <div class="line err">ERROR: deadlock detected</div>
      <div class="line dim">SELECT … FOR UPDATE</div>
      <div class="line">&nbsp;</div>
      <div class="line ok">INSERT … ON CONFLICT</div>
      <div class="line ok">DO NOTHING ✓</div>`,
    note: `FOR UPDATE = <u>dead end</u>.<br>don't go back.`,
  },
  {
    cls: "front",
    photo: `
      <div class="line dim">~/billing-api</div>
      <div class="line">context <span class="bar"><i></i></span> <span class="warn">97%</span></div>
      <div class="line">&nbsp;</div>
      <div class="line prompt">&gt; /tattoo</div>
      <div class="line"><span class="ok">●</span> Wrote tattoo/5f0c9a2e.md</div>
      <div class="line dim">  36 KB · now run /compact</div>`,
    note: `Postgres. <u>NOT</u> Redis.<br>Don't trust the summary.<br>Read your tattoo.`,
  },
];

document.getElementById("stack").innerHTML = polaroids
  .map(
    (p) => `
    <figure class="polaroid ${p.cls}">
      <span class="tape"></span>
      <div class="photo">${p.photo}</div>
      <figcaption>${p.note}</figcaption>
    </figure>`
  )
  .join("");
