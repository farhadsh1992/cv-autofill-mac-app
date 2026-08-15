<p align="center">
  <img src="assets/logo.png" alt="Farhad's CV AutoFill logo" width="160" />
</p>

# Farhad's CV AutoFill (Mac app)

A native macOS app for managing your CV, cover letter, and job-application
context, and generating tailored application material with AI — OpenAI or
Anthropic (Claude), your choice, per request. Built with SwiftUI and Swift
Package Manager, no Xcode project file, no external dependencies.

This is a **standalone companion** to the [browser extension](https://github.com/farhadsh1992/cv-autofill-extension)
of the same name — same idea, same visual identity, but its own separate
local storage. The two don't share data (see "Extension vs. app" below for
why, and how to move data between them manually if you want to).

## What it does

- **Generate** — paste a job description, pick a provider/model, and get a
  cover letter draft (editable, copyable, exportable as a real PDF via
  native CoreText) or a tailored CV (re-emphasizes your real CV content for
  that job, downloads as a real `.docx` — never invents facts).
- **Ask AI** — a quick, CV-grounded question box for when you're stuck on an
  application question your CV doesn't obviously answer.
- **CV** — upload a PDF or Word `.docx` (extracted locally via PDFKit /
  `NSAttributedString`, no API call needed just to read the file), or paste
  text; parsed into structured JSON by AI, editable directly. If the
  `.docx` has an embedded photo and/or a theme accent color, both get
  pulled out automatically and reused in the tailored CV `.docx` from
  Generate, instead of a plain black-and-white template (`.docx` only —
  PDFs don't expose this the same structured way).
- **Cover letter** — a saved reference letter, used as a style/tone guide
  when generating new ones (never copied verbatim).
- **Resources** — free-form "about me" notes, plus links to your own
  websites (fetched once, content saved as extra context for every AI
  call above).
- **Settings** — API keys, models, appearance, and a running usage/cost
  summary.

## Both providers, at once

OpenAI and Anthropic can both be configured simultaneously in Settings —
both API keys, both model choices, live side by side. **Generate** has its
own provider/model picker so you choose which one to use per request; **Ask
AI** and CV parsing use whichever one is set as the "Default provider" in
Settings.

Settings also shows a running **usage summary** per provider/model — total
tokens (exact, from each API response) and an estimated dollar cost. The
cost comes from a fixed price table in
[Usage.swift](Sources/CVAutoFill/Usage.swift), not fetched live from the
provider — treat it as a rough guide, not your actual bill.

## Appearance

Settings has a Theme picker (System/Light/Dark), a button color picker
(defaults to the app's brand red, `#9E230B`), and a button style choice:
**Normal** (standard macOS bordered buttons) or **Glass** — macOS 26
"Tahoe"'s Liquid Glass button material. Verified against the actual
installed macOS 26 SDK rather than guessed; falls back to Normal
automatically on older macOS.

## Extension vs. app

The browser extension can read the current browser tab — scrape a job
posting, scan a form to autofill, insert text into a page field. A native
app has none of that, so:

- There's no "autofill this page" here — that only makes sense inside a
  browser.
- Generate works from a **pasted job description** instead of scraping the
  current page.
- Storage is separate. If you want to move data between the two, the JSON
  shapes match — copy `cv.json` / `cover-letter.txt` / `about-me.txt` /
  `resources.json` from one app's data folder into the other's (paths
  below).

## Where your data lives

- CV, cover letter, resources, about-me notes, usage stats:
  `~/Library/Application Support/Farhad's CV AutoFill/` as plain JSON/text
  files.
- API keys: macOS Keychain (service `com.farhadshad.cvautofill`), not a
  plain file.

## Build & run

Needs Xcode's command line tools (`swift`, `iconutil`). No Xcode project —
this is a plain SPM executable, bundled into a real `.app` by
`build_app.sh`.

```bash
./build_app.sh release
open "dist/Farhad's CV AutoFill.app"
```

`build_app.sh debug` builds faster for iterating. The script also:
- code-signs the bundle ad-hoc (`codesign --sign -`) so Gatekeeper doesn't
  complain about a completely unsigned app on your own Mac,
- copies the SPM-generated resource bundle (`CVAutoFill_CVAutoFill.bundle`,
  holding the sidebar logo) into `Contents/Resources/` — without this step
  the app still runs fine, it just won't find the bundled logo image.

## Icon

Same gold-and-crimson crest as the browser extension, used unmodified at
every size (no recoloring, no simplification). Source lives in the
[extension repo](https://github.com/farhadsh1992/cv-autofill-extension)'s
`icon-design/` folder (`logo_source.png` is the original artwork;
`AppIcon.icns`/`AppIcon.iconset` are generated from it) — the icon isn't
duplicated in this repo. The sidebar footer logo (`Sources/CVAutoFill/Resources/logo.png`)
is the same image too, resized to fit that small corner.

**This means `build_app.sh` expects the extension repo checked out as a
sibling directory** (`../cv_autofill_extension/icon-design/AppIcon.icns`,
same layout as this project's original monorepo). If you only clone this
repo on its own, the build still works, it just silently skips setting the
app icon — clone `cv-autofill-extension` next to this folder to get it.

## Files

```
Package.swift                    SPM manifest (macOS 13+, no dependencies)
build_app.sh                     Builds + bundles into dist/Farhad's CV AutoFill.app
Sources/CVAutoFill/
  CVAutoFillApp.swift             @main entry point, window sizing, appearance modifiers
  AppState.swift                  ObservableObject — loads/saves everything, builds AI clients
  Models.swift                    CVData/ResourceItem/AppSettings (same shape as the extension's)
  Usage.swift                     Token/cost tracking, model catalog, price table
  Storage.swift                   Application Support JSON/text files + Keychain
  Prompts.swift                   Ported verbatim from the extension's background.js
  AIClient.swift                  OpenAI Responses API / Anthropic Messages API, per-request provider+model
  DocxWriter.swift                Ported from the extension's lib/docx-writer.js, incl. photo/color embedding
  DocxStyleExtractor.swift        Hand-rolled ZIP reader — pulls a photo + accent color out of an uploaded .docx
  DocumentIO.swift                PDFKit/NSAttributedString text extraction, CoreText PDF export
  ColorHex.swift                  Color <-> hex helpers for the accent-color picker
  Resources/logo.png              Bundled app logo (shown in the sidebar footer)
  Views/                          One view per sidebar section, plus SidebarFooter in ContentView.swift
```

## Limitations

- Standalone storage (see "Extension vs. app" above).
- The generated tailored CV `.docx` is a clean, simple, single-style
  layout — it's a content rewrite of your real CV, not a visual clone of
  whatever template you originally uploaded. The one exception: an
  embedded photo and/or theme accent color from a `.docx` upload get
  carried over, nothing else about the layout.
- Photo/color extraction only works for `.docx` uploads — PDFs don't
  expose an embedded image or theme color the same structured way.
- Resource website fetching is a plain `URLSession` request + HTML-to-text
  pass — pages behind a login (most of LinkedIn) or rendered client-side
  will often come back mostly empty.
- Estimated API cost is exactly that — estimated, from a hardcoded price
  table that can drift out of date. Check your provider's dashboard for
  the real number.
- Glass button style needs macOS 26+; older macOS silently uses Normal.
- Not code-signed with a real Developer ID, just ad-hoc — fine for running
  on your own Mac, but macOS will warn if you copy the `.app` to another
  machine.

## License

[MIT](LICENSE)
