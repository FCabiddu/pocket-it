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

Study all of these. A page should use **3–5** that serve its specific personality — not all, not none. Restraint is the mark of quality.

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
