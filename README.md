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
- **Resources** — two tabs, **Add** and **Saved**, matching the Jobs layout.
  Add has three forms: labeled About Me notes (same shape as the browser
  extension's About Me tab — title + content, add as many as you want,
  instead of one big text field), websites (fetched once, content saved as
  context), and quick notes. Saved lists everything from both — each item
  collapsed to just its title, click to expand and see the full content
  (and a Remove button), so a long list of notes doesn't turn into a wall
  of text. All of it feeds into every AI call the same way as before.
- **Jobs** — two tabs, **Saved Jobs** and **Apply Job**. Saved Jobs shows
  every job you've logged in a real table (same columns, same order, as the
  browser extension's own Jobs tab: title, company, date, location,
  requirements, link, results) — Date is the day the job was saved
  (`YYYY-MM-DD`, always computed in UTC so the same timestamp shows the same
  date on both sides), Link is a small "open" button instead of the raw URL
  (some job links are enormous), Results is editable right in the table,
  rows are removable. Apply Job is a short form (title, company, location, link,
  requirements) for logging a new one; saving jumps you back to Saved Jobs
  so you see it land. "Upload from extension" reads an `applied jobs.json`
  file saved by the browser extension's Save this job / Export and adds
  those rows in, skipping ones already present by id — safe to re-upload the
  same file. **The same check runs automatically every time this app
  launches**: if there's an `applied jobs.json` sitting in Downloads, new
  rows in it get pulled in without asking, so saving a job from the browser
  and then opening this app is enough to see it here. "Export Word + JSON"
  writes `applied jobs.docx` (the same landscape table format) and
  `applied jobs.json` straight to your Downloads folder — no dialog,
  overwriting the previous export each time.
- **Prompts** — the exact instructions sent to the AI for each task (Parse
  CV, Generate cover letter, Tailor CV, Ask AI), editable and saved per task.
  Leave a box empty (or unchanged) and save to fall back to the built-in
  default — nothing is lost, since the default text is always shown until
  you actually type something different. Included in Settings → Backup
  export/import, same as everything else.
- **Settings** — API keys, models, appearance, and a running usage/cost
  summary.

## Seven providers, three independent tasks

OpenAI, Anthropic, Kimi (Moonshot), Gemini (Google), DeepSeek, Claude Code
(Terminal), and OpenAI Codex (Terminal) can all be configured simultaneously
in Settings → AI. Each of the seven provider sections there is credentials
only — an API key, or CLI setup/login status for the two terminal
providers — nothing else.

Which provider (and which of that provider's models) actually gets used is
set separately, per task, at the top of Settings → AI:

- **Rebuild / tailor CV** — used by Generate's "Generate tailored CV" button.
- **Rebuild / write cover letter** — used by Generate's "Generate cover
  letter" button.
- **Other** — Ask AI and CV parsing.

Each of the three has its own provider *and* model picker, independent of
the other two — you can, for example, tailor your CV with
`claude-opus-5` while writing cover letters with `gpt-4o-mini`, or run both
through the same provider but different models. (Unlike the browser
extension, this app never sends a PDF to the AI at all — CVs and cover
letters are extracted locally via PDFKit first — so Kimi's and DeepSeek's
lack of PDF support, a real limitation on the extension side, doesn't apply
here.)

**DeepSeek** is an open-weight model, but the API this app calls is not
free — it's billed per token, same as the other three HTTP providers above,
just at a lower rate. Only DeepSeek's own consumer chat app
(chat.deepseek.com) is free; that's a separate product this app doesn't use.

**Claude Code (Terminal)** and **OpenAI Codex (Terminal)** are different
from the other five — instead of an HTTP API call billed per token, they
shell out to the `claude`/`codex` CLI already logged into this Mac's
Terminal (`claude login` / `codex login`), so they run on your Claude
Pro/Max or ChatGPT Plus/Pro/Team subscription instead of an API key. Both
are Mac-app-only: the browser extension has no way to run a terminal
process itself (it reaches these two by launching this app in a headless
mode instead — see "Extension vs. app" below). Every call runs with
file/bash/web tool access switched off (`claude -p --tools ""` /
`codex exec -s read-only --ask-for-approval never`) from a fresh, empty
working directory each time — it's a plain text-in, text-out completion,
same shape as the other five providers, not an agent with access to your
filesystem. Since a GUI app doesn't inherit your Terminal's `PATH`, the app
looks for `claude`/`codex` at a few common install locations, then falls
back to asking your login shell (whatever `$SHELL` is) to resolve them the
way Terminal would — their sections in Settings → AI show whether each was
found, with a "Set up..." button (terminal + guide side by side) when not.
Because billing is flat-rate, not per-token, their usage summaries always
show $0 estimated cost — the token counts are still real, the dollar figure
just isn't meaningful the way it is for the other five providers.

Settings also shows a running **usage summary** per provider/model — total
tokens (exact, from each API response) and an estimated dollar cost. The
cost comes from a fixed price table in
[Usage.swift](Sources/CVAutoFill/Usage.swift), not fetched live from the
provider — treat it as a rough guide, not your actual bill.

## Appearance

Settings is split into three tabs: **Appearance**, **AI**, **Backup**.

Appearance has a Theme picker (System/Light/Dark), a button color picker
(defaults to the app's brand red, `#9E230B`; uses `.borderedProminent` so
the picked color actually fills the button background — plain `.automatic`
bordered buttons on macOS mostly ignore `.tint()` for their fill), and a
button style choice: **Normal** (standard macOS bordered buttons) or
**Glass** — macOS 26 "Tahoe"'s Liquid Glass button material. Verified
against the actual installed macOS 26 SDK rather than guessed; falls back
to Normal automatically on older macOS.

The same button color also fills the selected sidebar item's background
(macOS's native list-selection highlight ignores both `.tint()` and
`.listItemTint()` here — `.listRowBackground` is what actually replaces it).
A separate **selected menu text color** picker controls that row's text
color independently, for when the button color makes the default white text
hard to read.

A **window style** choice (Normal/Glass, same macOS 26 requirement as button
style) adds a Liquid Glass background behind the sidebar and the main
content panel individually. There's no whole-window glass option — wrapping
the entire `NavigationSplitView` in one glass shape broke this app's layout
when tried, so glass is scoped to each panel's own background instead.

## Extension vs. app

The browser extension can read the current browser tab — scrape a job
posting, scan a form to autofill, insert text into a page field. A native
app has none of that, so:

- There's no "autofill this page" here — that only makes sense inside a
  browser.
- Generate works from a **pasted job description** instead of scraping the
  current page.
- Storage is separate — a browser extension and a native app can't share
  storage directly. Settings → Backup (Export/Import) is how you move data
  between them (see below).
- One exception where they *do* talk to each other: the extension's Claude
  Code / OpenAI Codex "Terminal" providers work by launching this app's own
  executable as a Chrome/Firefox [Native Messaging](https://developer.chrome.com/docs/apps/nativeMessaging)
  host — see `NativeMessagingHost.swift` and the `@main` dispatch in
  `CVAutoFillApp.swift`. A browser extension can't run a process itself, so
  the browser launches this binary in a headless mode it detects from the
  extra command-line argument every native-messaging launch carries (a
  normal double-click never has one); it reuses the exact same
  `ClaudeCodeCLI`/`CodexCLI` code the GUI's own providers use, reads one
  JSON request from stdin, writes one response, and exits — a fresh,
  separate launch per request, not a connection to an already-open GUI
  window. Set up from the extension's side: `cv_autofill_extension/native-host/install.sh`.

## Where your data lives

- CV, cover letter, resources, about-me notes, applied jobs, usage stats:
  `~/Library/Application Support/Farhad's CV AutoFill/` as plain JSON/text
  files.
- API keys: macOS Keychain (service `com.farhadshad.cvautofill`), not a
  plain file.

This app's storage and the browser extension's (`chrome.storage.local`,
inside the browser's own profile) are completely separate — a browser
extension has no API to read/write an arbitrary native app's files, and a
native app has no access to browser extension storage either. Nothing here
syncs automatically between the two today; each keeps its own CV, jobs,
etc. independently. **Settings → Backup** (Export/Import) is the way to move
data between them manually — see that section above.

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
is the same image too, shown large (132px) with a running estimated token
spend (OpenAI + Anthropic combined, same estimate as the Settings usage
summary) above it.

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
  CVAutoFillApp.swift             @main CVAutoFillMain dispatches to either NativeMessagingHost.run()
                                   (headless) or the real CVAutoFillApp SwiftUI App (window sizing, appearance)
  NativeMessagingHost.swift       Chrome/Firefox native-messaging stdio loop for the extension's Terminal
                                   providers — reuses ClaudeCodeCLI/CodexCLI, one request/response then exit
  AppState.swift                  ObservableObject — loads/saves everything, builds AI clients
  Models.swift                    CVData/ResourceItem/AboutMeNote/JobItem/AppSettings (same shape as the extension's)
  Usage.swift                     Token/cost tracking, model catalog, price table
  Storage.swift                   Application Support JSON/text files + Keychain
  Prompts.swift                   Ported verbatim from the extension's background.js
  PromptOverrides.swift           Per-task prompt override model — nil means "use Prompts.swift's default"
  AIClient.swift                  OpenAI/Anthropic/Kimi/Gemini APIs, per-request provider+model — text
                                   prompts only, no PDF (CVs are extracted locally via DocumentIO.swift)
  ClaudeCodeCLI.swift              Shells out to the local `claude` CLI (Pro/Max login, --tools "" only) —
                                   what powers the Claude Code (Terminal) provider
  CodexCLI.swift                   Shells out to the local `codex` CLI (ChatGPT login, -s read-only) —
                                   what powers the OpenAI Codex (Terminal) provider
  ShellCommandRunner.swift         Runs an arbitrary command the user typed in the setup guide's terminal pane,
                                   streaming combined stdout+stderr live — distinct from ClaudeCodeCLI/CodexCLI,
                                   which run one fixed, tool-restricted completion call
  DocxWriter.swift                Ported from the extension's lib/docx-writer.js — CV template with photo/color
                                   embedding, plus generateJobs() for the applied-jobs table export
  DocxStyleExtractor.swift        Hand-rolled ZIP reader — pulls a photo + accent color out of an uploaded .docx
  DocumentIO.swift                PDFKit/NSAttributedString text extraction, CoreText PDF export
  ColorHex.swift                  Color <-> hex helpers for the accent-color picker
  Backup.swift                    Export/Import backup — reads/writes the extension's backup JSON shape
  JobsImport.swift                Parses the extension's applied-jobs.json array; shared by the manual
                                   upload button, launch-time auto-import, and Backup's savedJobs import
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
