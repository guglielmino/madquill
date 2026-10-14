# Markdown Quick Look Plugin (macOS, Native Rendering Only) — Implementation Plan

## 1) Goal

Build a Finder Quick Look preview for Markdown files in the current folder’s project, using **only native Apple/macOS rendering capabilities** (no third-party Markdown engines, no JS Markdown parser dependencies).

---

## 2) Investigation summary (what to build and why)

### 2.1 Current Apple-recommended architecture

For modern macOS, custom Quick Look support is implemented via a **Quick Look Preview Extension** (App Extension), not legacy generator plugins as the primary path for new development.

Key points validated during investigation:

- `QLPreviewProvider` is available for **data-based** preview extensions (macOS 12+), with `QLIsDataBasedPreview`, `QLSupportedContentTypes`, and `NSExtensionPrincipalClass` configuration in extension `Info.plist`.
- `NSAttributedString(markdown:options:baseURL:)` is available on **macOS 12+** and provides native Markdown parsing/rendering input.
- Quick Look preview extensions are bundled inside a host macOS app (extension target + app target).

### 2.2 Native Markdown rendering strategy

To satisfy “native Mac functionality only,” we should render Markdown with:

- `NSAttributedString(markdown:options:baseURL:)`
- Display through AppKit-native UI (`NSTextView` inside an `NSScrollView`) in the preview extension.

This avoids external Markdown libraries and avoids web-based Markdown engines.

### 2.3 Compatibility decision

Because both `QLPreviewProvider` (data-based path) and native Markdown initializer have clean support from macOS 12+, the practical baseline should be:

- **Minimum deployment target: macOS 12.0**

If older macOS support is later required, that becomes a separate scope with fallback behavior.

---

## 3) Scope and constraints

### In scope

- Finder Quick Look preview for Markdown files (`.md`, optionally `.markdown`).
- Native parsing and rendering only.
- Packaging as signed macOS app + embedded Quick Look extension.

### Out of scope (for first version)

- Mermaid/KaTeX/code-highlighting via third-party engines.
- Editing Markdown from Quick Look.
- Custom thumbnail extension (we focus on preview; thumbnails can be phase 2).

---

## 4) High-level design

## 4.1 Targets

1. **Host macOS app target**
2. **Quick Look Preview Extension target**

### 4.2 Extension rendering flow

1. Quick Look provides file URL (`preparePreviewOfFile(...)` / provider callback depending on chosen extension template path).
2. Extension reads file bytes safely and decodes UTF-8 (with explicit error handling).
3. Convert Markdown string to `NSAttributedString` using native initializer.
4. Present attributed content in read-only `NSTextView`.
5. Show explicit error UI if parsing/loading fails (no silent fallback).

### 4.3 Content type registration

Register supported Markdown UTIs in extension `Info.plist` under `QLSupportedContentTypes`.

Primary target:
- Markdown UTI(s) associated with `.md`/`.markdown`.

Potentially include both common identifiers if needed by Finder behavior:
- `net.daringfireball.markdown`
- (and/or system markdown type where applicable)

---

## 5) Detailed implementation plan

## Phase A — Scaffold project and extension

1. Create Xcode macOS app project (Swift, AppKit).
2. Add target: **Quick Look Preview Extension**.
3. Confirm extension bundle appears under host app `PlugIns/`.

Deliverable: project builds with both targets.

## Phase B — Configure extension metadata

1. In extension `Info.plist`:
   - Set `NSExtensionPointIdentifier` for Quick Look preview extension.
   - Set `NSExtensionPrincipalClass` to extension controller/provider class.
   - Add `QLSupportedContentTypes` with Markdown UTI(s).
2. If using data-based provider path, set `QLIsDataBasedPreview = true`.

Deliverable: extension is discoverable for Markdown files.

## Phase C — Implement native Markdown preview

1. Add preview controller/provider Swift file.
2. Read file content from provided URL with robust error propagation.
3. Parse with:
   - `NSAttributedString(markdown:options:baseURL:)`
4. Render in:
   - `NSTextView` (non-editable, selectable)
   - `NSScrollView` for long docs
5. Use system colors/fonts and respect appearance mode.

Deliverable: readable rendered Markdown in Quick Look panel.

## Phase D — Error handling and UX hardening

1. Add explicit UI for:
   - unreadable file
   - parse failure
   - unsupported encoding
2. Add max-size guardrail (e.g., very large files) with clear message instead of hangs.
3. Ensure all failures are surfaced in logs/UI (no silent blank preview).

Deliverable: predictable behavior under bad inputs.

## Phase E — Build, signing, and activation

1. Build host app + extension in Debug.
2. Install/run host app once to register extension.
3. Reload Quick Look services as needed (`qlmanage -r`).
4. Verify extension picked for `.md`.

Deliverable: working local registration path.

## Phase F — Validation matrix

Test files:
1. Small Markdown with headings/lists/links
2. Medium file with code blocks
3. Large file near guardrail threshold
4. Invalid UTF-8 / malformed markdown text
5. Empty file

Checks:
- Finder spacebar Quick Look opens preview
- Rendering is native and stable
- Dark/light mode appearance acceptable
- Errors displayed clearly when expected

Deliverable: test checklist pass report.

---

## 6) Suggested file layout (expected)

- `/<project-root>/[HostApp]/...`
- `/<project-root>/[QuickLookExtension]/Preview[Controller|Provider].swift`
- `/<project-root>/[QuickLookExtension]/Info.plist`

(Actual names depend on Xcode template choices.)

---

## 7) Implementation decisions to lock before coding

1. **Extension style**
   - View-based controller vs data-based provider.
   - Recommendation: choose the template that gives the cleanest AppKit text rendering path in current Xcode; keep logic native either way.
2. **Minimum macOS target**
   - Recommendation: macOS 12.0 (clean native Markdown API support).
3. **Supported extensions**
   - Recommendation: `.md` first; optionally include `.markdown`.

---

## 8) Risks and mitigations

1. **UTI mismatch prevents activation**
   - Mitigation: verify exact UTI mapping and test with `mdls` + Finder preview behavior.
2. **Large file performance**
   - Mitigation: file size checks, async load path, and guarded rendering.
3. **Extension not reloading during development**
   - Mitigation: run host app after build, use `qlmanage -r`, relaunch Finder if necessary.

---

## 9) Acceptance criteria

Done means:

1. Spacebar on `.md` in Finder opens our Quick Look preview.
2. Markdown is rendered using only Apple-native APIs (no third-party parser/renderer).
3. Failure states are explicit and user-visible.
4. Build/run steps are reproducible locally.

---

## 10) Execution order (checklist)

1. Create app + extension targets.
2. Configure extension plist and content types.
3. Implement native Markdown parse/render pipeline.
4. Add error/size guards.
5. Register and validate with Finder Quick Look.
6. Run validation matrix and adjust.

---

## 11) Implementation status (2026-10-14)

Implemented in this repository:

- ✅ Phase A — Project scaffolded with host macOS app + Quick Look preview extension.
- ✅ Phase B — Extension `Info.plist` configured with:
  - `com.apple.quicklook.preview`
  - `QLIsDataBasedPreview = true`
  - `QLSupportedContentTypes` for Markdown UTIs.
- ✅ Phase C — Native Markdown pipeline implemented:
  - `NSAttributedString(markdown:options:baseURL:)`
  - Returned via `QLPreviewReply` as HTML payload.
- ✅ Phase D — Guardrails and explicit error UX implemented:
  - max file-size guard
  - UTF-8 validation
  - explicit error preview rendering + logging.

Created project assets:

- [project.yml](./project.yml)
- [MadQuillApp](./MadQuillApp)
- [MarkdownQuickLookExtension](./MarkdownQuickLookExtension)
