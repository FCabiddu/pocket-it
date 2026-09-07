# Design Compass — shared reference

Single source of truth for the design knowledge used by `mvp-builder` (to build) and `ux-ui-designer` (to judge). Neither agent should embed this content inline — both read this file. If a principle changes, change it here once.

This file is pure reference: the *facts* of good design. Each agent keeps its own *framing* (the builder's anti-repetition rules, the designer's scoring rubric) in its own file.

---

## Layout, Typography & Colour

### Layout archetypes

Every page commits to one archetype. Choose the one that best fits the project's industry, tone, and content. Read all 25 before deciding — the right choice will feel obvious. **Do not default to the first option.** (When auditing: identify which archetype the page is *trying* to be, then judge whether it executes it — or whether another row fits the content better. A page with no discernible archetype is the most common failure.)

| # | Archetype | When to use | Key traits |
|---|---|---|---|
| 1 | **Full-viewport hero + scroll narrative** | Brand studios, agencies, creative services | 100vh hero, transparent nav turns opaque on scroll, sections alternate dark/light |
| 2 | **Editorial grid** | Portfolio, magazine, music, art | Asymmetric CSS Grid, mixed-size cells spanning 2–3 columns/rows, type bleeds into gutters |
| 3 | **Centered minimalist** | Luxury goods, personal brand, type-forward | Everything center-aligned, extreme vertical whitespace, typography IS the design |
| 4 | **Split-screen** | Product showcase, feature reveal, before/after | Left: bold statement. Right: supporting detail. Alternates on scroll |
| 5 | **One-pager anchored nav** | Restaurants, events, local services, landing pages | Smooth-scroll anchors, active-section highlight in sticky nav, no page transitions |
| 6 | **Newspaper broadsheet** | News, journalism, text-heavy, editorial | Multi-column text, column rules, banner headline above the fold, serif dominant |
| 7 | **Big type manifesto** | Manifestos, causes, bold personal brands | Single enormous headline fills the viewport, rest of page is negative space and restraint |
| 8 | **Card mosaic / bento grid** | SaaS dashboards, feature grids, portfolios | Asymmetric bento tiles at varying sizes, no gaps, images full-bleed inside tiles |
| 9 | **Dark luxe catalogue** | High-end fashion, jewellery, premium products | Full-bleed product imagery, minimal metadata, cinematic pacing between items |
| 10 | **Horizontal scroll gallery** | Photography, art, sequential storytelling | Page scrolls horizontally; vertical scroll drives it via JS; each panel is a scene |
| 11 | **Floating cards** | Productivity tools, apps, consumer software | White background, cards with strong drop shadows, tight grid, Apple-like spaciousness |
| 12 | **Stripe-style SaaS** | Developer tools, B2B, subscription services | Gradient hero, alternating text+image feature rows, testimonials, pricing table |
| 13 | **Retro pop / Risograph** | Food, culture, youth brands, music merch | Flat bold colours, thick outlines, halftone dots, sticker-style decoration, off-register layers |
| 14 | **Swiss / International style** | Architecture, design agencies, institutions | Strict modular grid, one red accent, Helvetica-esque sans, function over decoration |
| 15 | **Brutalist raw** | Underground culture, art, provocative brands | Oversized borders, raw HTML aesthetic, monospace type, intentionally broken grid |
| 16 | **Blueprint / technical draft** | Engineering, craft, maker culture, DIY | Grid-lined background, measurement annotations, technical drawing aesthetic, blueprint blue |
| 17 | **Wabi-sabi minimalist** | Wellness, ceramics, handmade, Japanese aesthetics | Asymmetric, intentionally imperfect, earthy textures, dominant negative space, no sharp edges |
| 18 | **Night market / street food** | Food stalls, pop-ups, ramen bars, taco shops | Neon on dark, energetic composition, overlapping type layers, vibrant controlled chaos |
| 19 | **Film poster / theatrical** | Events, theatre, concerts, screenings | Centered vertical composition, dramatic perspective lines, vertical title type, ink textures |
| 20 | **Storybook scroll** | Children's brands, indie games, whimsical products | Illustrated sections flow top to bottom, hand-drawn CSS shapes woven between copy |
| 21 | **Glassmorphism dark** | Music apps, crypto, creative tech | Frosted glass cards (backdrop-filter blur) on gradient/mesh backgrounds, glowing accents |
| 22 | **Café / menu board** | Coffee shops, restaurants, bakeries, local food | Vertical list-style menu sections, handwritten-style display font, category dividers, texture |
| 23 | **Sticky sidebar + scroll content** | Docs, portfolios with case studies, guides | Fixed left column (nav/labels), right column scrolls independently, two-column always visible |
| 24 | **Portfolio case study** | Freelancers, designers, agencies showcasing one project | Wide imagery, narrow caption columns, process timeline, before/after comparisons |
| 25 | **Zine / collage** | Indie brands, experimental art, counterculture | Overlapping elements, rotated text, mixed type scales, torn-edge SVG shapes, deliberate DIY feel |

### Typography principles (Godly / Awwwards level)

- **Display size**: enormous — `clamp(4rem, 12vw, 12rem)`. Type is a visual element, not just content.
- **Weight contrast**: pair 900-weight headline with 300-weight body in the same section. Extremes create tension.
- **Eyebrow labels**: always `text-transform: uppercase; letter-spacing: 0.25em; font-size: 0.7rem`. Never large.
- **Display line-height**: tighten to `0.88`–`1.0` for headlines. Default browser line-height is for body copy, not display.
- **Type pairs that work**: Playfair Display + Space Grotesk · Fraunces + Inter · Bebas Neue + DM Sans · Editorial New + Neue Haas Grotesk (approximate with Inter) · Monument Extended + Satoshi
- Pick one Google Font for the display role; use system-ui or a second Google Font for body.
- **Do NOT default to Playfair Display** — it is overused. Choose from: Fraunces, Cormorant Garamond, DM Serif Display, Libre Baskerville, Abril Fatface, Bebas Neue, Archivo Black, Space Grotesk, Unbounded, Syne, Cabinet Grotesk. The display font must feel like a brand decision, not a safe fallback.

### Colour principles

- **Never use pure black or white.** Near-black: `#080808` / `#0d0d0d`. Near-white: `#fafaf8` / `#f5f3ef`.
- **One accent colour only.** Used for one key element — CTA, a hover state, a decorative line. Not scattered.
- **Dark backgrounds** feel premium for creative industries (tattoo, fashion, music, architecture).
- **Light backgrounds** feel clean for SaaS, productivity, health — and are equally premium; don't reach for dark just because it feels "premium".
- Monochromatic with a single warm or cool bias reads more sophisticated than multiple colours.
- **Do NOT default to near-black base + amber accent** — that combination is exhausted. Derive the palette from the industry row and any reference material.

### Industry design DNA

Before picking (or judging) an archetype, find the industry row. Every decision must be consistent with it.

| Industry | Preferred archetypes | Colour direction | Type direction | Hard avoids |
|---|---|---|---|---|
| Restaurant / trattoria | #5, #18, #22 | Warm: cream, terracotta, olive, wine | Display serif or condensed (Fraunces, Abril Fatface) | Cold blues, clean sans-only, tech feel |
| Café / coffee bar | #22, #5, #16 | Espresso, warm cream, rust, forest | Slab or rounded grotesque | Luxury dark, neon |
| Street food / takeaway | #13, #18, #25 | Bold flat primaries, black outlines | Condensed grotesque (Bebas Neue, Archivo Black) | Delicate serif, pastels |
| Tattoo / body art | #15, #9, #21 | Near-black base, one vivid accent (electric blue, blood red, acid yellow) | Condensed gothic or display sans | Pastels, rounded friendly fonts |
| Beauty / hair / nails | #3, #17, #9 | Blush, sand, sage, champagne | Elegant thin serif (Cormorant Garamond, DM Serif Display) | Heavy grotesque, dark dramatic |
| Wellness / spa / yoga | #17, #3, #20 | Sage, warm linen, soft terracotta, stone | Lightweight serif + light sans | Loud accent colours, heavy weights |
| Fitness / gym / PT | #7, #4, #12 | High contrast: near-black + vivid (electric blue, neon green, red) | Heavy grotesque (Archivo Black, Unbounded) | Serif, pastels |
| Architecture / interior design | #14, #23, #2 | Monochrome with one precise accent (warm grey, dusty rose, forest) | Helvetica-adjacent (Inter) at controlled weights | Decorative serifs, multiple colours |
| Craft / handmade / ceramics | #17, #25, #20 | Natural: warm white, ink blue, clay, linen | Mixed-weight serif + handwritten feel (Cormorant, Fraunces) | Tech feel, cold tones, heavy grotesque |
| Music / DJ / venue | #21, #19, #10 | Dark: near-black + one electric accent (neon pink, acid yellow) | Display sans or condensed (Bebas Neue, Syne) | Warm serif, pastels |
| Tech / SaaS / startup | #12, #8, #11 | Cool: slate, midnight blue + electric accent (mint, cyan, indigo) | Modern grotesque (Space Grotesk, Syne) | Traditional serif, warm tones |
| Creative agency / studio | #2, #14, #1 | Monochrome or bold two-tone (black + one primary) | Strong contrast: ultra-heavy + ultra-light | Safe mid-weights, multiple accent colours |
| Legal / finance / consulting | #3, #23, #6 | Restrained: navy, slate, warm white | Classic serif + clean sans | Playful fonts, loud colours |
| Publisher / book & game studio | #1, #2, #20 (+ signature moments #16 book, #18 box, #25 shelf, #24 ground) | Warm paper: cream, ivory, ink, one cover-derived accent (oxblood, forest, mustard) | Editorial: display serif headlines (Fraunces, Playfair) + readable text serif or humanist sans | Cold SaaS blues, stock-photo people, flat cover grids without an object in 3D |

If the industry doesn't match a row, find its closest neighbour and adjust for tone.

### Decorative elements — lift a flat page to premium

Not animations — static or near-static elements that add visual richness. Every premium page uses at least one; a page relying on bare whitespace reads as unfinished, not minimal.

- **Grain overlay** — fixed `<div class="grain">` (`position: fixed; inset: 0; pointer-events: none; z-index: 999; opacity: 0.045`) filled with an inline SVG `<feTurbulence>` noise filter. Always on dark backgrounds; drop to `0.02` on light.
- **Oversized decorative type** — a word at `font-size: clamp(8rem, 20vw, 20rem)`, `opacity: 0.05`, `position: absolute`, behind content. Felt, not read. Use the brand name, a category word, or a single letter.
- **Section numerals** — a large two-digit number (`01`, `02`) at `clamp(5rem, 10vw, 10rem)`, `opacity: 0.07`, absolute in the section corner. Editorial rhythm.
- **Accent lines** — deliberate `1px`/`2px` lines as separators, callout markers, pull-quote accents. Never a generic `<hr>` replacement.
- **Angled or curved section dividers** — inline SVG `<svg viewBox="0 0 1440 60" preserveAspectRatio="none">` with a diagonal/curved `<path>` between contrasting sections. Breaks the flat stacked-rectangle look.
- **Mixed text-image grid cells** — some cells pure colour + text, others full-bleed images; variable spans (`grid-row: span 2`, `grid-column: span 2`). Breaks the equal-tile look.

---

## Animation Catalogue — award-winning techniques

Study all of these. A page should use **3–5** that serve its specific personality — not all, not none. Restraint is the mark of quality. `ux-ui-designer` Mode C picks from this list **by number** (Design Spec §6 Motion System) — keep the numbering stable. Site-wide narrative animations (books, boxes, 3D, scroll scenes) are a separate class — see **Signature Moments** below (#16–#27).

### 1. Split-text line reveal
**Effect:** Each text line slides up from beneath a hidden overflow — cinematic "curtain rise."
**How:** Wrap each line: `<span class="line"><span class="line-inner">text</span></span>`. Outer: `overflow: hidden; display: block`. Inner: starts `translateY(110%)`, animates to `translateY(0)` via `@keyframes` or `IntersectionObserver` + CSS transition. Stagger lines with `animation-delay` or `transition-delay`.
**Use for:** Hero headline, section titles. **GPU safe:** Yes — only `transform`.

### 2. Clip-path wipe reveal
**Effect:** Content appears as if a curtain is pulled away — horizontal or vertical wipe.
**How:** Start `clip-path: inset(0 100% 0 0)`, animate to `clip-path: inset(0 0% 0 0)`. Pure CSS `@keyframes` or triggered by `IntersectionObserver`. Works on images, text blocks, coloured panels.
**Use for:** Images, section intros, label eyebrows. **GPU safe:** Yes — `clip-path` is composited.

### 3. Scroll-reveal fade + translate
**Effect:** Elements drift into view as the user scrolls — subtle but essential for rhythm.
**How:** `.reveal { opacity: 0; transform: translateY(40px); transition: opacity 0.7s ease, transform 0.7s ease; }` — `IntersectionObserver` adds `.visible` → `.reveal.visible { opacity: 1; transform: none; }`. Stagger children with `transition-delay: calc(var(--i) * 0.1s)` where `--i` is set inline as a CSS custom property.
**Use for:** Cards, grid items, paragraphs, any secondary content. **GPU safe:** Yes.

### 4. Background fill sweep (hover)
**Effect:** A coloured background fills a button or card from bottom to top on hover — feels physical.
**How:** `::before` pseudo-element with `position: absolute; inset: 0; transform: scaleY(0); transform-origin: bottom; transition: transform 0.35s ease`. On `:hover::before` → `transform: scaleY(1)`. Set `z-index: -1` so it sits behind text. Also transition `color` on the parent.
**Use for:** CTAs, nav links, card hover states. **GPU safe:** Yes.

### 5. Magnetic element
**Effect:** A button or icon physically deflects toward the mouse cursor — feels alive.
**How:** On `mousemove` over the element, calculate offset from center: `const x = (e.clientX - rect.left - rect.width/2) * 0.3`. Apply `el.style.transform = translate(${x}px, ${y}px)`. On `mouseleave`, reset `transform` (CSS `transition` handles the spring-back).
**Use for:** Primary CTAs, social icons, floating elements. **GPU safe:** Yes.

### 6. Scroll progress bar
**Effect:** A thin bar at the top of the viewport grows as the user reads — signals depth.
**How:** Fixed element: `position: fixed; top: 0; left: 0; height: 2px; width: 100%; transform: scaleX(0); transform-origin: left`. JS `scroll` listener: `bar.style.transform = scaleX(${window.scrollY / (document.body.scrollHeight - window.innerHeight)})`.
**Use for:** Any long-scroll page. **GPU safe:** Yes — only `transform`.

### 7. SVG stroke draw
**Effect:** SVG paths appear to be drawn by hand in real time.
**How:** Get path length: `const len = path.getTotalLength()`. Set `stroke-dasharray: len; stroke-dashoffset: len`. When in viewport, add class that transitions `stroke-dashoffset` to `0`.
**Use for:** Logo reveals, decorative dividers, icons, signature-style elements. **GPU safe:** Yes.

### 8. Infinite marquee ticker
**Effect:** Content scrolls horizontally in an infinite loop — adds kinetic energy to a section.
**How:** Duplicate list items so total width is ~2×. Animate `transform: translateX(-50%)` from `translateX(0)` with `animation: marquee Xs linear infinite`. Parent: `overflow: hidden`. Pure CSS, zero JS.
**Use for:** Client logos, tag clouds, announcement bars, style lists. **GPU safe:** Yes.

### 9. Grayscale-to-colour on hover
**Effect:** Images desaturate to grayscale by default and bloom into colour on hover — draws attention intentionally.
**How:** `img { filter: grayscale(1); transition: filter 0.5s ease; }` `img:hover { filter: grayscale(0); }`. Pure CSS.
**Use for:** Portfolio galleries, team/artist photos, product images. **GPU safe:** Yes.

### 10. Text scramble / glitch on hover
**Effect:** Text rapidly cycles through random characters before resolving — technical, edgy, memorable.
**How:** On `mouseenter`, JS iterates over each character, replacing with a random char from a set (`!@#$%^&*`), then restores originals one by one with `setTimeout`. ~15 JS lines total. No library needed.
**Use for:** Navigation links, card titles, CTA buttons — sparingly, max one or two elements. **GPU safe:** Yes — only `textContent` changes.

### 11. CSS scroll-driven animation (modern, no JS)
**Effect:** Any CSS property tied directly to scroll position — no JS event listeners.
**How:** `@keyframes fadeIn { from { opacity: 0; } to { opacity: 1; } }` then on the element: `animation: fadeIn linear; animation-timeline: scroll(); animation-range: 0% 20%;`. Wrap in `@supports (animation-timeline: scroll())` for a JS fallback.
**Use for:** Hero opacity, section reveals, sticky element transitions. **GPU safe:** Yes.

### 12. Parallax layers
**Effect:** Elements move at different speeds creating depth on scroll.
**How:** JS `scroll` listener reads `window.scrollY`. Each layer gets `transform: translateY(scrollY * rate)` where `rate` varies per element (0.1 = slow, 0.5 = fast). Use `will-change: transform` on parallax elements. Never parallax text that must be readable.
**Use for:** Hero background image, decorative shapes, floating badges. **GPU safe:** Yes — only `transform`.

### 13. Clip-path polygon morph (hover)
**Effect:** An element's shape morphs between two polygon clip-path values on hover — surreal, tactile.
**How:** `clip-path: polygon(0 0, 100% 0, 100% 100%, 0 100%)` base. On `:hover`: `clip-path: polygon(5% 0, 100% 3%, 95% 100%, 0 97%)`. CSS `transition: clip-path 0.4s ease`. Both must have the same number of points.
**Use for:** Image cards, feature blocks, hero media. **GPU safe:** Yes.

### 14. Cursor ambient glow
**Effect:** A soft radial gradient follows the cursor — depth and responsiveness on dark backgrounds without any visible UI element.
**How:** `<div class="cursor-glow"></div>` — `position: fixed; pointer-events: none; width: 700px; height: 700px; border-radius: 50%; background: radial-gradient(circle, rgba(VAR_ACCENT, 0.12), transparent 70%); transform: translate(-50%, -50%); transition: transform 0.12s ease`. JS `mousemove`: `glow.style.left = e.clientX + 'px'; glow.style.top = e.clientY + 'px'`. Replace `VAR_ACCENT` with the project's accent colour.
**Use for:** Dark-background sites — tattoo, music, tech, creative agency. Skip entirely on light backgrounds. **GPU safe:** Yes.

### 15. Staggered grid entrance
**Effect:** Grid items cascade into view in reading order — a choreographed arrival that makes a grid feel intentional rather than dumped.
**How:** Set `--i` as an inline CSS custom property on each grid child matching its DOM index (`style="--i:0"`, `--i:1`, etc.). `.grid-item { opacity: 0; transform: translateY(30px); }` `.grid-item.visible { opacity: 1; transform: none; transition: opacity 0.5s ease calc(var(--i) * 0.08s), transform 0.5s ease calc(var(--i) * 0.08s); }` One `IntersectionObserver` on the grid parent, adds `.visible` to all children at once — the `--i` delay creates the cascade.
**Use for:** Service cards, portfolio grids, bento grids, feature lists. Do not use alongside #3 (scroll-reveal) on the same elements. **GPU safe:** Yes.

### Universal animation rules
- Pick only what the page *needs* — restraint is the mark of quality. Both a barren page and an over-animated one are failures.
- Never animate the same property two different ways on the same element.
- Every animation must have a clear purpose: welcome the user, reveal hierarchy, reward interaction, or signal state.
- `transform` and `opacity` only — never animate `width`, `height`, `top`, `left`, `margin`, or `padding`.
- No dead `@keyframes` blocks — every block must be referenced by at least one selector. Prefer CSS transitions for single-element effects.
- Do NOT reflexively pair the marquee ticker (#8) + scroll progress bar (#6). That combo is overused. Consider #14 (cursor glow) for dark backgrounds and #15 (staggered grid entrance) whenever there is a card/grid section.

---

## Signature Moments — site-wide narrative animation

The catalogue above is micro-motion: it makes a page feel finished. A **signature moment** is what makes a site *memorable* — one narrative, often 3D or physical-metaphor animation that the whole site is built around: a book that opens, a box whose lid lifts, a product you can turn, a scene that plays as you scroll. Premium sites have **one or two**, on the surfaces that matter (home hero, flagship product page), never one per section. Numbering continues from the catalogue so Mode C picks **by number**; each entry states its library so the TAD (7.4/7.5) can approve it with a bundle budget. Cost = gzipped JS added + effort (S ≤ 1 day, M 2–3 days, L a week or more, assets excluded). Every library below is lazy-loaded below the fold (`next/dynamic` / `import()`, `ssr: false` for anything WebGL) and never ships to the "where not to animate" surfaces.

### 16. Book that opens (CSS 3D)
**Use for:** Publisher / book-studio home hero, a single title's product page, "look inside" teaser.
**Physical metaphor:** A hardcover on a table; the cover swings open on the spine, the first page shows.
**Technique + library:** No library. `perspective: 1500px` on the wrapper, book `transform-style: preserve-3d`, cover `transform-origin: left; transform: rotateY(-25deg)` at rest → `rotateY(-150deg)` open, `backface-visibility: hidden`, spine and page-block as extra faces, a shadow on `opacity`. Triggered on mount (hero) or on first intersection; hover only as a secondary tease.
**Cost:** 0 KB · S.
**Fallback:** reduced-motion → book rendered at its resting angle, cover closed, no transition; no-WebGL n/a; mobile → same, smaller `perspective`, no hover tease.
**Assets:** front cover ≥ 1200px, spine (or spine colour + title text), first-page or endpaper image, optional back cover.

### 17. Real page leafing (page-flip library)
**Use for:** "Sfoglia le prime pagine" preview, a catalogue or lookbook, a gamebook / choose-your-path demo.
**Physical metaphor:** Leafing through a real paperback with a finger — the page curls, follows the drag, snaps.
**Technique + library:** `page-flip` (StPageFlip, MIT, no deps, ~10 KB gz, touch + mouse, image or HTML pages, soft/hard pages) via `react-pageflip` (MIT wrapper, unmaintained but small — vendor it if it breaks). Client-only: mount after hydration, `ssr: false`. **Never turn.js** (non-commercial BSD, main-thread DOM thrash).
**Cost:** ~10–12 KB gz · M.
**Fallback:** reduced-motion → no curl, pages swap on click with a cross-fade; no-JS → the same pages as a plain vertical image list; mobile → single-page (portrait) mode, swipe.
**Assets:** page spreads as images (≥ 1600px wide per spread, one per page) or the HTML of each page; page count ≤ 12 for a preview.

### 18. Box that lifts its lid (CSS 3D)
**Use for:** Board-game / puzzle / collectors' edition product hero, unboxing teaser, "what's in the box" section.
**Physical metaphor:** The lid rises and tilts back, the contents fade up from inside.
**Technique + library:** No library. Six-face box in CSS (`preserve-3d`, each face a `rotateX/Y` + `translateZ`) textured with the box art; lid is a second `preserve-3d` group with `transform-origin` on its back edge, `rotateX(-110deg) translateY(-20px)` when open; contents (cards, pieces, a booklet) staggered `translateY` + `opacity` from inside. Trigger on intersection or a "Apri la scatola" button — a button makes the moment consented and keyboard-reachable.
**Cost:** 0 KB · M.
**Fallback:** reduced-motion → box shown open with contents visible, no motion; mobile → lid opens, contents fade without stagger.
**Assets:** top, front and one side face of the box (flat scans, ≥ 1200px), 2–4 cut-out contents images (transparent PNG/WebP).

### 19. 3D product turntable (`<model-viewer>` glTF)
**Use for:** A physical product worth turning in the hand — box, miniature, device, packaging; AR "see it on your table".
**Physical metaphor:** The object on a turntable; drag to rotate, pinch to zoom.
**Technique + library:** `@google/model-viewer` (Apache-2.0 web component, three.js bundled, ~70 KB gz on bundlephobia — measure in the real build; budget 100–250 KB). `<model-viewer src=".glb" poster=".webp" loading="lazy" reveal="interaction" camera-controls auto-rotate alt="…" interaction-prompt="auto">`. Register the element client-only (`next/dynamic`, `ssr: false`); the `poster` is what SSR renders, so LCP stays an image.
**Cost:** ~70–250 KB gz (lazy, below the fold or after the poster) · M (L if the model must be made).
**Fallback:** reduced-motion → `auto-rotate` off, poster stays until the user interacts; no-WebGL → the component shows the poster; mobile → poster + tap to load, `auto-rotate` off, no AR button unless tested.
**Assets:** glTF/GLB ≤ 3 MB (Draco/meshopt compressed, ≤ 2048px textures), poster render, alt text; a photogrammetry or 3D-modelled asset — the client rarely has one, budget it.

### 20. Scroll-pinned storytelling scene (GSAP ScrollTrigger)
**Use for:** "How it works" / "the story of the series" / a product's 3-step reveal — one scene the user scrolls *through*.
**Physical metaphor:** A stage that stays put while props enter, move and exit as you turn the crank.
**Technique + library:** `gsap` + `ScrollTrigger` (Standard "No Charge" GSAP licence since 3.13 — free for commercial use, all plugins; core ~27 KB gz + ScrollTrigger ~14 KB gz). `pin: true, scrub: 0.5–1, end: "+=200%"` on the section; a timeline of `transform`/`opacity`/`clip-path` steps. Client-only: `useGSAP` with a scope ref, `gsap.matchMedia()` for the reduced-motion and mobile branches; never run during SSR; kill triggers on unmount.
**Cost:** ~40 KB gz · M.
**Fallback:** reduced-motion → no pin, the steps stacked vertically in their final state; mobile → shorter `end`, fewer steps, or the same unpinned stack; no-JS → the stacked steps.
**Assets:** 3–5 layered images (transparent cut-outs) or an inline SVG scene; the copy of each step.

### 21. Scroll-scrubbed image sequence (canvas + ScrollTrigger)
**Use for:** A product that transforms — box opening frame by frame, a book unfolding, a device turning (the Apple product-page technique).
**Physical metaphor:** A flip-book you drive with the scroll wheel.
**Technique + library:** `gsap` + `ScrollTrigger` scrubbing a frame index, each frame drawn to a `<canvas>` (clear before draw); preload frames with `Promise.all`, `pin` the canvas, `scrub: true`. Serve frames as WebP/AVIF ≤ 1600px, 60–120 frames, two sizes (mobile / desktop) chosen at load.
**Cost:** ~40 KB gz JS + 3–8 MB of frames (lazy, below the fold) · L.
**Fallback:** reduced-motion → first and last frame only, cross-fade on intersection; mobile → the small frame set or a poster + short MP4 with `playsinline muted`; no-JS → the last frame as an `<img>`.
**Assets:** a rendered or photographed sequence (3D render or turntable rig) — the client almost never has it; budget production before promising this.

### 22. Self-drawing illustrations (SVG stroke / Lottie / Rive)
**Use for:** Storybook and children's brands, indie games, editorial sites — a map that draws itself, a mascot that reacts, a logo that assembles.
**Physical metaphor:** An ink pen drawing the line in front of you.
**Technique + library:** Three tiers, pick the lowest that works. (a) Catalogue #7 SVG stroke draw, 0 KB, for line art. (b) Lottie for After-Effects animations: `@lottiefiles/dotlottie-web` (MIT, ~33 KB gz JS + a lazily fetched WASM renderer; `.lottie` files 40–70 % smaller than JSON) or `lottie-web` (MIT, ~60 KB gz). (c) Rive for interactive state machines (mascot follows cursor, reacts to hover/scroll): `@rive-app/canvas` (MIT, ~200 KB gz incl. WASM; `canvas-lite` smaller) — only when interaction is the point.
**Cost:** 0 / ~35 / ~200 KB gz · S / S / M (plus the illustrator's time in the tool).
**Fallback:** reduced-motion → final frame rendered (Lottie/Rive `autoplay=false` and seek to end; SVG stroke fully drawn); no-JS → a static SVG/PNG; mobile → same asset, cap to one instance in view.
**Assets:** SVG line art; or `.lottie`/`.json` export from After Effects (Bodymovin); or a `.riv` file with named state-machine inputs.

### 23. Shared-element page morph (View Transitions)
**Use for:** Catalogue → product detail: the cover in the grid grows into the hero of its page; series list → series page.
**Physical metaphor:** Picking the book off the shelf and bringing it to your face.
**Technique + library:** No library. `view-transition-name: cover-{id}` on the card image and the same name on the detail hero; same-document transitions via the framework's mechanism (Next.js `ViewTransition`, Astro `<ClientRouter>`, `document.startViewTransition`), cross-document via `@view-transition { navigation: auto }`. Same-document is Baseline (Chrome 111, Safari 18, Firefox 133+); cross-document is Chrome 126 / Safari 18.2, Firefox behind a flag — progressive enhancement, never a dependency.
**Cost:** 0 KB · S.
**Fallback:** unsupported browser → plain navigation; reduced-motion → transition duration 0 via `@media (prefers-reduced-motion: reduce) { ::view-transition-group(*) { animation: none } }`.
**Assets:** none beyond consistent cover images (same aspect ratio in list and detail).

### 24. Ambient ground (paper grain, slow gradient drift)
**Use for:** Every publisher / craft / editorial site — the "table" the objects sit on; the quiet layer that makes 16–18 feel physical.
**Physical metaphor:** Paper under the book, afternoon light moving across the desk.
**Technique + library:** No library. Compass "Grain overlay" (SVG `feTurbulence`, `opacity` 0.02–0.045) + one very slow background drift: a `radial-gradient`/`conic-gradient` layer on a pseudo-element animated on `transform: translate/rotate` over 30–60 s, `opacity` ≤ 0.4, one instance per page, `will-change: transform`. Optional paper texture as a tiled WebP ≤ 40 KB.
**Cost:** 0 KB · S.
**Fallback:** reduced-motion → gradient static, grain stays (it does not move); mobile → drift off if the page already has a 3D moment in view.
**Assets:** none, or one paper-texture tile.

### 25. Shelf / carousel with depth (CSS 3D perspective)
**Use for:** A series or catalogue browser: 5–12 covers on a shelf, the active one facing you, the others angled away (Cover-Flow lineage).
**Physical metaphor:** Running a finger along the spines on a shelf.
**Technique + library:** No library. Track `perspective: 1200px`, each item `transform: translateX(calc(var(--d) * 60%)) rotateY(calc(var(--d) * -35deg)) scale(calc(1 - abs(var(--d)) * 0.15))` where `--d` is its distance from the active index; keyboard arrows and scroll-snap move the active index; a drop shadow under the shelf via `opacity`. Works with Embla/Keen only if the project already has one — the transform is the effect, not the slider.
**Cost:** 0 KB · M.
**Fallback:** reduced-motion → items still angled but index changes without transition; mobile → flat horizontal scroll-snap row, no `rotateY`; no-JS → the same flat row.
**Assets:** covers at one aspect ratio, ≥ 600px wide, `alt` per title.

### 26. Smooth-scroll spine (Lenis)
**Use for:** Only as the carrier of #20/#21 or archetype #10 (horizontal scroll) on a marketing site — it makes scrubbed scenes feel weighted. Never on an app, docs or anything read repeatedly.
**Physical metaphor:** Inertia — the page has mass.
**Technique + library:** `lenis` (MIT, ~5 KB gz) wrapping native scroll (sticky, anchors and assistive tech keep working); `lerp` 0.08–0.12; feed `ScrollTrigger.update` from Lenis's `scroll` event and drive Lenis from `gsap.ticker`. Client-only.
**Cost:** ~5 KB gz · S.
**Fallback:** reduced-motion → Lenis disables smoothing by default, keep that; mobile → off (native scroll), unless a scrubbed scene needs it and is tested on a real device.
**Assets:** none.

### 27. Full WebGL scene (React Three Fiber + drei, or Spline)
**Use for:** The one hero that *is* the brand — a floating product with real lighting, an explorable diorama. Only when 16–21 cannot tell the story and the client funds the 3D asset.
**Physical metaphor:** The object in a lit room, not a photo of it.
**Technique + library:** `three` + `@react-three/fiber` + `@react-three/drei` (all MIT; three ~155 KB gz + fiber/drei ~30–60 KB gz, tree-shaken) — `useGLTF`, `Environment`, `PresentationControls`, `Float`. Or `@splinetool/react-spline` (MIT; runtime ~270 KB gz + a 1–5 MB scene, `@splinetool/react-spline/next` renders a blurred placeholder on the server) when the designer builds the scene in Spline and no code control is needed. Both: `next/dynamic` with `ssr: false`, mount on intersection, `<Canvas dpr={[1, 1.5]} frameloop="demand">`, a `<noscript>`/poster fallback carrying the same headline and CTA.
**Cost:** ~200–450 KB gz + scene assets · L.
**Fallback:** reduced-motion → static camera, no idle animation (or the poster); no-WebGL / low-end (`navigator.hardwareConcurrency ≤ 4`, `deviceMemory ≤ 4`) → poster image; mobile → poster by default, load the scene only on tap.
**Assets:** an optimised GLB (≤ 3 MB, Draco/meshopt, baked lighting or an HDRI ≤ 1 MB) or a Spline scene exported at "Performance" quality; poster render; alt text.

### Signature-moment rules
- **One or two per site**, on the home hero and/or the flagship product page. A third dilutes both.
- **Metaphor first.** The moment must be the product's own physics (a book opens, a box lifts, an object turns). A generic particle field or floating blobs is decoration, not a signature.
- **CSS 3D before WebGL.** #16, #18, #24, #25 cost 0 KB and cover most publishers and object brands; reach for #19/#27 only when the object has to be turned freely.
- **Every moment has a poster.** The server renders an image (or the final CSS state); the moment enhances it after hydration. LCP is never the animation.
- **Assets are the real cost.** Frame sequences, GLBs and Rive files are produced, not found — write them in the Design Spec's assets line so the TAD and the client budget them.
- **Reduced-motion and no-JS states are designed, not defaulted** — each entry's fallback is written into the spec and implemented as a branch, never left to the library.

Sources: [StPageFlip](https://github.com/Nodlik/StPageFlip) · [react-pageflip](https://github.com/Nodlik/react-pageflip) · [turn.js licence](https://github.com/blasten/turn.js) · [GSAP licence](https://gsap.com/licensing/) · [GSAP 3.13 free](https://gsap.com/blog/3-13/) · [GSAP image-sequence helper](https://gsap.com/docs/v3/HelperFunctions/helpers/imageSequenceScrub/) · [model-viewer](https://modelviewer.dev/) · [model-viewer on web.dev](https://web.dev/articles/model-viewer) · [R3F + Next.js](https://github.com/pmndrs/react-three-next) · [three.js production fallbacks](https://appscale.blog/en/blog/threejs-production-3d-web-2026-webgpu-realtime-standards) · [Lottie vs Rive sizes](https://unicornicons.com/blog/lottie-vs-rive-performance) · [rive-wasm](https://github.com/rive-app/rive-wasm) · [View Transitions support](https://css-tricks.com/cross-document-view-transitions-part-1/) · [Lenis](https://github.com/darkroomengineering/lenis) · [react-spline](https://github.com/splinetool/react-spline) · [Spline optimisation](https://docs.spline.design/doc/how-to-optimize-your-scene/doczPMIye7Ko) · [CSS 3D book](https://scastiel.dev/animated-3d-book-css/) · [Codrops CSS 3D books](https://tympanus.net/codrops/2013/07/11/animated-books-with-css-3d-transforms/) · sizes from bundlephobia (gsap 3.15, @google/model-viewer 4.3, page-flip 2.0, lenis 1.3, @lottiefiles/dotlottie-web 0.80, @splinetool/runtime 2.0).

---

## Accessibility baseline — WCAG 2.1 AA (mandatory floor)

This is not optional and does not scale down. **Every** output — an `mvp-builder` static site, every Flow B frontend — meets WCAG 2.1 Level AA as a floor (a superset of WCAG 2.0 A/AA). The `ux-ui-designer` Design Spec *adds depth* on top (per-component ARIA/keyboard contracts for complex widgets); it never replaces this floor, and its absence never lowers it. There is no per-project opt-out — accessibility here is baseline engineering, and in many jurisdictions a legal requirement.

**Perceivable**
- Text contrast ≥ **4.5:1** (≥ 3:1 for large text ≥ 24px, or ≥ 18.66px bold); non-text UI/graphical contrast ≥ **3:1**. Check every text/background and control/adjacent pair.
- Never signal meaning by **colour alone** — pair with text, icon, or shape.
- Real, descriptive `alt` on informative images; `alt=""` on decorative ones. Captions/transcripts for media.
- Usable at **200% zoom** and reflow to **320px** width without loss of content or 2-D scrolling.

**Operable**
- **Fully keyboard-operable**, in a logical focus order, with **no keyboard traps**.
- A **visible focus indicator** on every interactive element (`:focus-visible`) — never `outline: none` without a replacement.
- Skip-to-content link on multi-section pages; interactive target size ≥ 24×24 CSS px (≥ 44×44 for primary touch targets).
- Honour `prefers-reduced-motion`; no content flashing more than 3×/second; provide pause/stop for auto-moving content.

**Understandable**
- Visible labels (or accessible names) and instructions on all controls; inputs use `<label>`, not placeholder-as-label.
- Clear error identification and correction guidance on forms; consistent, predictable navigation; `lang` set on the document.

**Robust**
- **Semantic HTML first** (`<button>`, `<nav>`, `<main>`, `<h1>`…) before ARIA; only reach for ARIA when no native element fits, and keep it valid.
- Icon-only controls carry an accessible name (`aria-label`). Async status changes announced via `aria-live` / appropriate roles.

Treat this list as a hard checklist: a page that fails any item is not done.
