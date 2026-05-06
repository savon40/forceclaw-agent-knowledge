# Mobile Development

## Core rule

**Salesforce mobile is a different runtime, not a narrow desktop browser.** A component that works perfectly on desktop Lightning can fail on mobile because of webview lifecycle, permission prompts, focus/blur timing, file handling, viewport, scroll lock, or media APIs.

When the user mentions mobile — phones, tablets, the Salesforce mobile app, "responsive", "on the go", offline use, field workers — the bot must treat mobile as a **separate review surface** with its own checklist. Do not assume desktop success implies mobile success.

For mobile **record-page** behavior (FlexiPage assignment, quick action visibility on mobile, form factor in `js-meta.xml`), see `14-record-pages-and-flexipages.md`. This skill covers runtime/component behavior.

## Current capabilities

### What ForceClaw can do
- Create/update LWC bundles via `create_lwc` and `update_lwc` (sandbox/dev only, requires `writeApex`)
- Inspect `js-meta.xml` `supportedFormFactors` and `targets` via `get_lwc_source`
- Query `FlexiPage` and friends to identify the mobile-specific FlexiPage for an object

### What ForceClaw cannot do
- **Run on a real device.** No mobile preview, no headless test on the Salesforce mobile app. Mobile behavior is something the bot writes for and the user verifies.
- **Run mobile lint locally.** `@salesforce/eslint-plugin-lwc-mobile` and `@salesforce/eslint-plugin-lwc-graph-analyzer` are local Node tools. ForceClaw operates via APIs. If a user wants those checks, they run them in their own dev environment.

When the bot generates a mobile-targeted component, the Slack summary must say something like *"I built this for mobile but couldn't test it on a device — please verify on the Salesforce mobile app."* Do not claim mobile-readiness from static review alone.

## What differs from desktop

A non-exhaustive list of the things mobile changes:

| Layer | Mobile difference |
|---|---|
| Webview lifecycle | `connectedCallback`, `renderedCallback`, and `disconnectedCallback` can fire on different timing than desktop. Mobile may unmount + remount more aggressively. |
| Permission prompts | Camera, microphone, location, file access prompts pause and can change focus and visibility state mid-flow |
| Focus / blur | Mobile blur often fires **before** click — menus that close on blur will close before the user's tap registers |
| Viewport | `100vh` is unreliable; iOS counts the address bar differently than Android. Use `dvh` or `env(safe-area-inset-*)` |
| File picker | Native file picker UI on mobile, often doesn't return a usable blob path the same way desktop does |
| Popup tabs | New-tab/popup behavior is unreliable in the Salesforce mobile webview |
| Media autoplay | `autoplay` is gated on user gesture; muted autoplay sometimes works, often doesn't |
| `getUserMedia` | Acquisition succeeds but the preview frame may not paint until after the visibility recovers from the permission prompt |
| Scroll lock | Modal scroll-lock that works on desktop can leave mobile stuck after close |
| Touch | Touch events fire before mouse events; double-handling causes ghost clicks |
| Lightning action rendering | Mobile action bar and overflow behave differently from desktop quick action header |

If a feature touches any of these, treat mobile as a first-class review.

## Webview lifecycle

The mobile webview can mount, unmount, and remount components more aggressively than desktop. Practical rules:

- **Don't assume `renderedCallback` runs once.** It can fire multiple times. Idempotency is required.
- **Don't assume `connectedCallback` is the last thing that runs before user interaction.** Permission prompts, navigation transitions, and orientation changes can interrupt.
- **Always implement `disconnectedCallback` for components that hold resources** — media tracks, intervals, observers, event listeners. The bot should generate this even if the desktop version "didn't need it."
- **Visibility recovery is its own event.** After a permission prompt, after switching apps and coming back, after orientation change, the component may need to re-paint. Don't gate on `connectedCallback` alone.

## Camera and media

`getUserMedia()` resolving successfully proves only that the camera was acquired. It does **not** prove:
- The component mounted into the DOM
- The visible preview element painted a frame
- The overlay is on top of other UI
- Closing the component restored normal interaction

### Required for camera flows
1. **Open a visible shell first**, then request camera access. Acquiring before the shell is mounted leaves the privacy indicator on with no visible UI.
2. **Treat permission prompts as lifecycle interruptions** — the component may lose focus, lose visibility, or be remounted between the request and the response.
3. **Confirm the first preview frame painted** before claiming "ready." Wait for `loadedmetadata` or `playing` events on the video element, not just the `getUserMedia` promise resolving.
4. **On every close path** (close button, cancel, error, `disconnectedCallback`):
   - Call `track.stop()` on every track
   - Set `video.srcObject = null`
   - Release scroll/touch locks
   - Reset any media element state
5. **Reset media elements between sessions.** A re-opened camera should not inherit state from the previous session.

### Common camera failure
> "The privacy indicator is on but the component shows blank UI."

Cause: camera was acquired before the visible shell mounted. The fix is to mount the shell first, paint a preview placeholder, then request the camera.

## File and PDF handling

### Blob URLs are unreliable on mobile
Blob URLs and `URL.createObjectURL()` outputs work on desktop but can fail in the Salesforce mobile webview — file preview and download handoffs intermittently break. The mobile webview can't always pass the blob to a system viewer.

**Use durable URLs for mobile file handoff.** Concretely:
1. Save the file as a `ContentVersion` record
2. Get the resulting `ContentDocumentId` back
3. Navigate to the file via Salesforce's standard file navigation, OR
4. Expose a server-backed authorized URL that the mobile shell can hand to a system browser

### Don't return huge base64 payloads from one Apex call
Mobile users are often on metered networks and lower-spec devices. A 50MB base64 string in a single Apex response will:
- Hit Apex heap limits (`String_TOO_LONG` or heap exceeded)
- Slow the LWC re-render to a crawl on first paint
- Burn the user's data

For large generated artifacts (PDFs, photo-laden reports), generate the file as a `ContentVersion` server-side and hand the LWC a `ContentDocumentId`, not the bytes.

### PDF generation
- A generated PDF must become a **durable artifact** (a `ContentVersion`) before the UI claims "complete." A blob URL that opens a tab once and is never recoverable is not "done" on mobile.
- For Visualforce-generated PDFs, test inside the actual Lightning action context or mobile action context — not just by opening the page URL on desktop.
- If the PDF depends on photos, verify the **latest version** of each `ContentVersion` is processed before generation.

### File list refresh
- Custom LWC file lists must explicitly `refreshApex(this.wiredFiles)` after upload, delete, annotation, or new version.
- Standard Files related lists refresh on their own; Dynamic Related Lists usually do; custom LWC lists do not.
- Parent record state (file count, last-modified) may need its own refresh — `getRecordNotifyChange([recordId])` from `lightning/uiRecordApi`.

## Touch, focus, and blur

### Mobile blur fires before click
For menus, dropdowns, mention pickers, anything that closes on blur:
- **Start the selection on `pointerdown` or `mousedown`**, not `click`. The blur event from focus leaving the input fires before the click event registers, so a click handler will never run.
- Guard against duplicate touch + mouse events. iOS can fire both for the same tap. Use `event.preventDefault()` on `touchstart` to suppress the synthetic mouse events, or de-dupe by timestamp.
- Keep the menu open while a tap is in progress — explicit "is selecting" state instead of relying on focus.

### Mention menus and text insertion
- Commit the textarea value AND the caret position together. Setting one without the other leaves the cursor in the wrong place after insertion.
- Keep mention metadata (the `[user-id]` ranges or whatever format Apex expects) **aligned** to the exact body text being submitted. If the user edits between selecting a mention and submitting, the ranges have to shift with the text.
- Commit text on the same event handler that closes the menu — don't split across `pointerdown` (closes menu) and `click` (commits text), because click won't fire.

### Submit guards
- Disable the submit button while posting/uploading. Mobile users tap twice routinely.
- Show upload progress or at least a busy state. Mobile users have no devtools and lower-bandwidth connections — silent waiting feels broken.
- Avoid double-posts on Chatter, comments, or any user-generated content.

## Form factor metadata

In `js-meta.xml`, `supportedFormFactors` declares where the LWC can run:

```xml
<targets>
    <target>lightning__RecordPage</target>
    <target>lightning__RecordAction</target>
</targets>
<targetConfigs>
    <targetConfig targets="lightning__RecordPage">
        <supportedFormFactors>
            <supportedFormFactor type="Large"/>
            <supportedFormFactor type="Small"/>
        </supportedFormFactors>
    </targetConfig>
</targetConfigs>
```

| Form factor | Where it runs |
|---|---|
| `Large` | Desktop Lightning |
| `Small` | Salesforce mobile app on phone |

Two practical points:
- **Mobile is opt-in.** If `Small` is missing, the component will not appear on the phone — even if the FlexiPage references it. The component "isn't there" silently.
- **Quick actions need their own form factor in the action metadata too.** A component with `Small` listed but a quick action without phone support will still be hidden on mobile. (See Quick Action Visibility Matrix in `14-record-pages-and-flexipages.md`.)

When the bot creates an LWC and the user says it should work on mobile, set both `Small` and `Large` and tell the user explicitly in the Slack summary which form factors are configured.

## Common mobile failures

| Symptom | Likely cause | Fix |
|---|---|---|
| Component works on desktop, missing on phone | `supportedFormFactors` missing `Small` in `js-meta.xml` | Add `<supportedFormFactor type="Small"/>` |
| Privacy indicator on but blank UI | Camera acquired before the visible shell mounted | Mount and paint the shell first, then call `getUserMedia` |
| Camera works first time, blank on retake | Tracks not stopped + `srcObject` not cleared on close | Add cleanup in close path and `disconnectedCallback` |
| File generated but mobile preview never opens | Blob URL handoff failing in mobile webview | Save as `ContentVersion`, navigate to `ContentDocumentId` |
| PDF "downloads" but isn't anywhere later | Output was opened in a tab, never persisted | Save as a durable file before claiming completion |
| Mention menu closes when user taps a suggestion | Blur fires before click on mobile | Start selection on `pointerdown` / `mousedown` |
| Tapping a button posts twice | No submit guard, plus iOS firing touch + mouse | Disable on submit; de-dupe synthetic mouse events |
| File list stale after upload from mobile | Custom LWC list cached; no `refreshApex` | Add `refreshApex(this.wiredFiles)` after upload completes |
| `100vh` overflows on iOS | Address bar height not accounted for | Use `dvh` units or `env(safe-area-inset-*)` |
| Modal stays "open" after close — user can't scroll | Scroll lock not released on close | Remove scroll lock in close handler AND `disconnectedCallback` |
| Action exists on desktop but missing from mobile action bar | Phone form factor, action metadata, layout, Dynamic Actions | Walk Quick Action Visibility Matrix in `14-record-pages-and-flexipages.md` |
| Component renders but field updates aren't visible | Wired result cached; cacheable read used for what should refresh | Store wire result, call `refreshApex` on save; for record-level changes use `getRecordNotifyChange` |
| Heap exceeded on PDF generation from photos | Apex tried to base64-load all photos at once | Stream into a `ContentVersion` server-side; hand the LWC the `ContentDocumentId` |

## Pre-flight checklist for mobile-targeted components

Before generating an LWC the user expects to work on mobile:

- [ ] **Confirm form factor** — both `Large` and `Small`? Phone-only? Desktop-only?
- [ ] **Camera, file picker, or media in scope?** If yes, plan the shell-first / track-cleanup pattern explicitly
- [ ] **Generated files in scope?** Plan the `ContentVersion` durable-artifact pattern, not blob handoff
- [ ] **Menus, mention pickers, or focus-sensitive UI?** Plan `pointerdown`-based selection
- [ ] **Submits or posts?** Plan the disable-on-submit guard
- [ ] **Quick action?** Confirm the action metadata also supports phone (separate from the LWC's form factor)
- [ ] **Mobile FlexiPage assignment** — does the object's mobile FlexiPage need to be updated too? (See `14-record-pages-and-flexipages.md`)
- [ ] **`disconnectedCallback` cleanup** — anything held that needs to be released?

## Reference: mobile lint tools (informational)

These are local-Node tools the user can run themselves. ForceClaw does not invoke them server-side.

| Tool | What it catches |
|---|---|
| `@salesforce/eslint-plugin-lwc-mobile` | LWC patterns known to break on mobile (touch handling, viewport, file handling) |
| `@salesforce/eslint-plugin-lwc-graph-analyzer` | LDS wire-graph issues that cause offline/mobile data priming failures |
| `npm run lint:mobile` (project script) | Common project-level wrapper for the above |

If the user has a local Salesforce DX project and wants strong static checks on a mobile component, point them at these. Do not claim the bot ran them.

## Rules

- **Never claim a component is "mobile-ready" without device testing.** Static review and successful sandbox deploy do not prove mobile behavior. The Slack summary must say what was verified and what still needs device testing.
- **Always plan the cleanup path.** Anything that consumes a resource on mobile (media tracks, observers, scroll locks, intervals, event listeners) must have explicit cleanup in the close path and in `disconnectedCallback`.
- **Prefer durable file artifacts over blob URLs** for any file the user might want to preview, share, or open later.
- **Don't return huge payloads from a single Apex call.** Stream into `ContentVersion` server-side.
- **Treat mobile and desktop as independent** — when the user reports an issue on one, ask about the other before assuming the fix is the same.
