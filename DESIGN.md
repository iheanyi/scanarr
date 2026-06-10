---
name: Scanarr
description: A sharp self-hosted manga reader and library manager with quiet controls and strong cover-led content.
colors:
  midnight-panel-bg: "#060914"
  midnight-panel-surface: "#101827"
  midnight-panel-surface-2: "#19243a"
  midnight-panel-border: "#2b3854"
  midnight-panel-border-soft: "#3b4b68"
  midnight-panel-text: "#f2f6ff"
  midnight-panel-muted: "#a8b5cc"
  midnight-panel-muted-2: "#77849e"
  midnight-panel-accent: "#93a7ff"
  midnight-panel-accent-foreground: "#070a18"
  midnight-panel-accent-strong: "#c0cbff"
  semantic-success: "#77d7ba"
  semantic-warning: "#f2b86d"
  semantic-danger: "#ff7892"
  semantic-info: "#7fc7ff"
typography:
  display:
    fontFamily: "Geist, Inter, ui-sans-serif, system-ui, sans-serif"
    fontSize: "3rem"
    fontWeight: 600
    lineHeight: 1
    letterSpacing: "-0.025em"
  headline:
    fontFamily: "Geist, Inter, ui-sans-serif, system-ui, sans-serif"
    fontSize: "1.875rem"
    fontWeight: 600
    lineHeight: 1.15
    letterSpacing: "-0.02em"
  title:
    fontFamily: "Geist, Inter, ui-sans-serif, system-ui, sans-serif"
    fontSize: "1.125rem"
    fontWeight: 600
    lineHeight: 1.3
  body:
    fontFamily: "Geist, Inter, ui-sans-serif, system-ui, sans-serif"
    fontSize: "0.875rem"
    fontWeight: 400
    lineHeight: 1.6
  label:
    fontFamily: "Geist Mono, ui-monospace, SFMono-Regular, Menlo, Consolas, monospace"
    fontSize: "0.6875rem"
    fontWeight: 600
    lineHeight: 1.2
    letterSpacing: "0.18em"
rounded:
  sm: "4px"
  md: "6px"
  lg: "8px"
  xl: "12px"
  full: "9999px"
spacing:
  xs: "4px"
  sm: "8px"
  md: "16px"
  lg: "24px"
  xl: "32px"
components:
  button-primary:
    backgroundColor: "{colors.midnight-panel-accent}"
    textColor: "{colors.midnight-panel-accent-foreground}"
    rounded: "{rounded.lg}"
    padding: "0 16px"
    height: "40px"
  button-ghost:
    backgroundColor: "{colors.midnight-panel-bg}"
    textColor: "{colors.midnight-panel-text}"
    rounded: "{rounded.lg}"
    padding: "0 16px"
    height: "40px"
  input-default:
    backgroundColor: "{colors.midnight-panel-surface}"
    textColor: "{colors.midnight-panel-text}"
    rounded: "{rounded.lg}"
    padding: "10px 16px"
    height: "40px"
  chip-default:
    backgroundColor: "{colors.midnight-panel-surface}"
    textColor: "{colors.midnight-panel-muted}"
    rounded: "{rounded.full}"
    padding: "4px 10px"
---

# Design System: Scanarr

## Overview

**Creative North Star: "Reader Control Room"**

Scanarr is a product UI for managing a personal manga library, not a marketing surface. The design should feel like a tuned control room around the reader's collection: dark, compact, fast to scan, and confident enough to handle sources, downloads, progress, and admin state without turning into a generic SaaS dashboard.

The system uses quiet controls and strong content. Manga covers, series titles, chapter progress, and source state should carry the emotional weight. Buttons, filters, chips, and panels should be precise, familiar, and restrained so the user can move from discovery to reading without fighting the chrome.

**Key Characteristics:**

- Cover-led: manga art gets the visual attention before decorative UI does.
- Restrained color: periwinkle marks action and command state, not decoration.
- Flat by default: depth comes from tonal surfaces, borders, and cover treatment.
- Dense but legible: lists, grids, filters, and controls can be compact when state remains clear.
- Product-first: every flourish must support browsing, library management, downloading, or reading.

## Colors

The palette is **Midnight Panel**: near-black navy surfaces, a muted periwinkle command accent, and state colors tuned for dark UI.

### Primary

- **Panel Periwinkle** (#93a7ff): Primary actions, current selection, focus emphasis, and command moments that need immediate recognition.
- **Panel Periwinkle Strong** (#c0cbff): Hover and elevated emphasis for the primary action color.
- **Midnight Ink** (#070a18): Text on periwinkle fills. Keep this dark enough to preserve contrast.

### Secondary

- **Download Mint** (#77d7ba): Successful downloads, completed status, and positive confirmation.
- **Queue Amber** (#f2b86d): Pending work, queued downloads, and warnings that require attention without alarm.
- **Failure Rose** (#ff7892): Failed downloads, destructive actions, and error states.
- **Reader Blue** (#7fc7ff): Informational links and neutral progress cues.

### Neutral

- **Midnight Base** (#060914): App background and primary shell.
- **Panel Navy** (#101827): Main card, sidebar, and hero panel surface.
- **Raised Navy** (#19243a): Inputs, selected rows, cover placeholders, and higher surface steps.
- **Blue Steel Border** (#2b3854): Default perimeter border.
- **Soft Blue Steel** (#3b4b68): Hover borders and higher-contrast dividers.
- **Page Ink** (#f2f6ff): Primary text.
- **Shelf Text** (#a8b5cc): Secondary text and metadata.
- **Muted Shelf Text** (#77849e): Tertiary metadata, placeholders, and low-emphasis labels.

### Named Rules

**The Cover Owns Color Rule.** Manga covers are allowed to be the most colorful part of most screens. The interface should use accent color sparingly so cover art remains dominant.

**The One Command Color Rule.** Panel Periwinkle is for action, selection, and focus. Do not use it as generic decoration.

## Typography

**Display Font:** Geist, with Inter and system sans fallbacks  
**Body Font:** Geist, with Inter and system sans fallbacks  
**Label/Mono Font:** Geist Mono, with system monospace fallbacks

**Character:** The typography is product-native: compact, high clarity, and slightly technical without becoming a terminal UI.

### Hierarchy

- **Display** (600, 48px, 1 line-height): Large page titles and series detail hero titles only.
- **Headline** (600, 30px, 1.15 line-height): Section headers and important page framing.
- **Title** (600, 18px, 1.3 line-height): Card titles, panel headings, and series names in dense contexts.
- **Body** (400, 14px, 1.6 line-height): Descriptions, explanatory copy, and metadata that needs more than one line.
- **Label** (600, 11px, 0.18em letter spacing): Short labels, chips, and system markers. Keep uppercase labels short.

### Named Rules

**The Product Scale Rule.** Use fixed rem sizes for app UI. Avoid fluid display type on task surfaces.

**The Short Label Rule.** Uppercase tracked text is allowed only for short labels, not sentence copy.

## Elevation

Scanarr uses cover-first depth. The UI itself is mostly flat, with depth created through tonal surface steps, full-perimeter borders, and occasional inset highlights. Manga covers, cover tiles, and reader pages can carry stronger depth because they are content, not chrome.

### Shadow Vocabulary

- **Flat Surface** (`box-shadow: none`): Default for panels, cards, buttons, and app shell.
- **Inset Surface Line** (`inset 0 1px 0 rgba(255, 255, 255, 0.04)`): Subtle separation on panels and metric blocks.
- **Cover Depth** (`0 20px 50px rgba(0, 0, 0, 0.28)`): Cover tiles and media-first surfaces.

### Named Rules

**The Flat Chrome Rule.** Do not add ambient shadows to ordinary product panels. Raise the surface tone or border instead.

**The Content Depth Rule.** Depth belongs to covers, reader pages, overlays, and active media surfaces.

## Components

### Buttons

Buttons are quiet, precise controls with consistent height and radius.

- **Shape:** Rounded rectangle, 8px radius.
- **Primary:** Panel Periwinkle fill, Midnight Ink text, 40px height, 16px horizontal padding.
- **Secondary / Ghost:** Panel Navy or Midnight Base fill, Page Ink text, full hairline border.
- **Hover / Focus:** Hover strengthens the border or fill. Focus uses a 2px focus ring from `--ds-focus`.
- **Disabled:** Lower opacity and no pointer events.

### Chips

Chips are low-height status and metadata markers.

- **Style:** Rounded full, 1px border, compact padding, muted text.
- **State:** Semantic variants use soft fills with colored text. Do not rely on color alone, keep status words visible.

### Cards / Containers

Containers should feel like app surfaces, not decorative cards.

- **Corner Style:** 24px to 32px for major panels, 12px to 16px for compact cards.
- **Background:** Use Panel Navy or Raised Navy depending on hierarchy.
- **Shadow Strategy:** Flat by default. Use borders, tonal changes, and inset lines instead.
- **Border:** Full-perimeter 1px border. Never use thick side stripes.
- **Internal Padding:** 16px to 24px for panels, 12px to 16px for compact cards.

### Inputs / Fields

Inputs match the button radius and height vocabulary.

- **Style:** 40px height, 8px radius, Raised Navy or Panel Navy fill, Blue Steel Border perimeter.
- **Placeholder:** Muted Shelf Text, not low-contrast gray.
- **Focus:** Periwinkle border plus focus ring.
- **Disabled / Error:** Disabled dims text and surface. Error uses Failure Rose text, border, and explicit message copy.

### Navigation

Navigation is stable and conventional.

- **Sidebar:** Darker shell surface with active item using tonal fill and clear text.
- **Mobile:** Native drawer behavior, same visual language as sidebar.
- **Active State:** Full-item background or border treatment, never a side stripe.

### Series Cover

The cover is the signature content component.

- **Aspect:** Default manga covers use 2:3.
- **Frame:** Shared cover shell can be framed or bare depending on parent.
- **Fallback:** Book icon centered on Raised Navy.
- **Behavior:** Cover hover can scale image slightly, but the cover tile maintains the same aspect and alignment.

### Progress

Progress is compact and state-colored.

- **Track:** Border or surface color.
- **Fill:** Semantic color, usually Reader Blue for neutral progress or Download Mint for complete state.
- **Motion:** 150 to 250ms state transition. Respect reduced motion.

## Do's and Don'ts

### Do:

- **Do** keep Panel Periwinkle rare and tied to action, selection, and focus.
- **Do** let covers and manga artwork carry most of the color on browse and library screens.
- **Do** use full-perimeter 1px borders for selected, active, warning, and hover states.
- **Do** preserve WCAG AA contrast for body text, metadata, placeholders, and controls.
- **Do** use semantic color with text labels or icons so color is never the only signal.
- **Do** keep app UI familiar: standard buttons, selects, search fields, drawers, and side navigation.

### Don't:

- **Don't** make Scanarr look like a generic SaaS dashboard.
- **Don't** turn the palette into neon cyberpunk, even when using Panel Pulse or Acid Zine.
- **Don't** make the library feel like an editorial luxury magazine.
- **Don't** make controls look like a harsh terminal-first developer tool.
- **Don't** use border-left or border-right greater than 1px as an accent marker.
- **Don't** add decorative gradients, gradient text, or glass effects as default chrome.
- **Don't** add color randomly. Every colored element needs a role.
