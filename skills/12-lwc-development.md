# Lightning Web Component (LWC) Development

## When this applies

This skill applies when creating or modifying Lightning Web Components in **dev/sandbox orgs** where write access is enabled. The bot creates LWC bundles via `create_lwc` and updates via `update_lwc` (requires `writeApex`).

## Start with the metadata

Before editing or generating an LWC, **read its `.js-meta.xml` first**. The metadata file declares where the component can run, which form factors it supports, and what `@api` properties the parent passes in. Editing the JS or HTML without checking the metadata first is how you ship a desktop-only LWC for a customer who needs mobile.

Check:
- **`<targets>`** — record page (`lightning__RecordPage`), app page, home page, tab, quick action (`lightning__RecordAction`), Experience Cloud
- **Target object restrictions** — `<objects><object>Account</object></objects>` limits which objects the LWC can be placed on
- **Form factors** — `<supportedFormFactor type="Large"/>` (desktop) and `<supportedFormFactor type="Small"/>` (phone). Mobile is opt-in.
- **Public `@api` properties** — what the parent page or quick action passes in (`recordId`, configuration values, custom App Builder properties)
- **Whether it is a direct placement or a child of a host component** — host components pass through different properties than direct page placements

For form factor and record page placement, also see `14-record-pages-and-flexipages.md` (Activation Chain, Quick Action Visibility Matrix) and `15-mobile-development.md` (form factor metadata).

## Review gate by change type

Different LWC changes need different review lenses. Match the gate to the work — don't run the same checklist for every edit.

| Change type | Required review |
|---|---|
| **JavaScript** | Imports, state, events, wire/Apex contract, error handling |
| **HTML template** | Template syntax (no JS expressions), getters used for computed state, conditional rendering, accessibility |
| **CSS** | Scope (`:host`), responsiveness, mobile webview behavior, SLDS hook usage |
| **`js-meta.xml`** | Targets, form factors, object restrictions, `@api` properties exposed to App Builder |
| **Apex-backed UI** | Apex controller signature, sharing/CRUD/FLS, DTO shape, permissions |
| **Wired Apex / UI API** | Reactive params defined, `cacheable=true`, stored wire result, all four states (not-ready / loading / data / error) handled |
| **Imperative Apex** | Mutations only; control disabled while running; awaited completion; post-DML refresh chain |
| **Record form** (`lightning-record-edit-form`) | Object/field API names, field access, required fields, compound fields, `onsuccess` refresh, `onerror` field-level surfacing |
| **Navigation** | `NavigationMixin` + PageReference type, runtime support (LEX / console / mobile / Experience Cloud), URL state public-safety |
| **Files / photos / PDFs** | `ContentVersion` / `ContentDocument` / `ContentDocumentLink` model, latest-version handling, refresh after upload (see `15-mobile-development.md` for mobile handoff) |

When reporting back, name the gate. A wire-cacheability change reviewed under the "JavaScript" gate will miss caching and refresh issues.

## Template rules — CRITICAL

LWC HTML templates have STRICT rules — no JavaScript expressions of any kind. Violations cause instant deploy failures (LWC1058).

### Absolute rules

1. **NO JS expressions in templates** — no ternary, no comparison, no concatenation, no arithmetic
2. **NO expressions in `if:true` / `if:false`** — must be a simple property or getter reference, NEVER a comparison like `{x==='value'}`
3. **NO string concatenation in attributes** — use computed getters instead
4. **NO inline style expressions** — use a getter that returns the full style string
5. **NO deep property access on potentially null objects** — wrap in `<template if:true={obj}>` before accessing `{obj.prop}`
6. **NO emoji or Unicode symbols in HTML templates** — characters like the recycle symbol, checkmarks, warning signs, or X marks cause compile failures. Use plain text ("Refresh", "OK", "Warning") or SLDS icons (`<lightning-icon>`) instead
7. **NO HTML entities or special characters** in button labels or text content — stick to plain ASCII text
8. **Static inline styles MUST be quoted** — `style="color: red; font-weight: bold"` is OK, but dynamic styles MUST use a getter: `style={myStyle}`
9. **NEVER use `update_apex_class` for LWC files** — use `update_lwc` to modify existing LWC components. `update_apex_class` is only for `.cls` Apex files

### These patterns ALWAYS cause LWC1058 deploy failure

Every one of these is an instant deploy failure. The `if:true` / `if:false` directive ONLY accepts a simple property or getter — never a comparison, function call, or expression of any kind.

```html
<!-- DEPLOY FAILURE: comparison operator in if:true -->
<template if:true={result.tier==='Healthy'}>    <!-- LWC1058 ERROR -->
<template if:true={count > 0}>                  <!-- LWC1058 ERROR -->
<template if:true={items.length}>               <!-- LWC1058 ERROR -->

<!-- CORRECT: always use a boolean getter -->
<template if:true={isHealthy}>                  <!-- OK -->
<template if:true={hasItems}>                   <!-- OK -->
```

```html
<!-- DEPLOY FAILURE: ternary expression -->
<p>{hasItems ? 'Items found' : 'No items'}</p>  <!-- LWC1058 ERROR -->

<!-- CORRECT: use if:true/if:false -->
<template if:true={hasItems}><p>Items found</p></template>
<template if:false={hasItems}><p>No items</p></template>
```

```html
<!-- DEPLOY FAILURE: concatenation in attribute -->
<div style={"width: " + score + "%"}></div>     <!-- LWC1058 ERROR -->
<div class={"slds-" + variant}></div>            <!-- LWC1058 ERROR -->

<!-- CORRECT: use a getter -->
<div style={barStyle}></div>
```

```html
<!-- DEPLOY FAILURE: emoji in template -->
<button>🔄 Refresh</button>                     <!-- COMPILE ERROR -->
<span>✔ Healthy</span>                          <!-- COMPILE ERROR -->

<!-- CORRECT: plain text or SLDS icon -->
<button>Refresh</button>
<lightning-icon icon-name="utility:check" size="x-small"></lightning-icon> Healthy
```

## Style attributes — common deploy failures

```html
<!-- DEPLOY FAILURE: dynamic style without getter -->
<div style={`color: ${myColor}`}></div>              <!-- LWC1058 ERROR -->
<span style={"color: " + color + ";"}>text</span>    <!-- LWC1058 ERROR -->

<!-- OK: static inline style (must be properly quoted) -->
<div style="color: red; font-weight: bold">text</div>

<!-- OK: dynamic style via getter -->
<div style={computedStyle}>text</div>
```

```javascript
// In JS — getter returns the full style string:
get computedStyle() { return `color: ${this.myColor}; font-weight: bold;`; }
```

For iteration where each item needs a different style, compute the style string in the JS getter/map — not in the template:

```javascript
// CORRECT pattern for per-item styles
get factorValues() {
    return this.factors.map(f => ({
        ...f,
        barStyle: `width: ${f.pct}%; background: ${f.color};`,
        valueStyle: `color: ${f.color}; font-weight: 600;`,
    }));
}
```

```html
<!-- Then in template, just bind the pre-computed style -->
<div style={factor.barStyle}></div>
<span style={factor.valueStyle}>{factor.value}</span>
```

## The pattern: move ALL logic to JS getters

Every conditional, every computed style, every dynamic value should be a getter in the JS controller.

```javascript
// One getter per conditional:
get isHealthy() { return this.result?.tier === 'Healthy'; }
get isNeedsAttention() { return this.result?.tier === 'Needs Attention'; }
get isAtRisk() { return this.result?.tier === 'At Risk'; }
get hasAttention() { return this.result?.attentionItems?.length > 0; }
get hasResult() { return !!this.result; }

// Dynamic styles — must return the full style string:
get barStyle() { return `width: ${this.score}%`; }
get circleStyle() { return `border-color: ${this.scoreColor}`; }
get scoreCardClass() { return this.isAtRisk ? 'card-danger' : 'card-normal'; }

// Safe property access:
get displayScore() { return this.result ? this.result.score : '--'; }
get displayTier() { return this.result ? this.result.tier : ''; }
```

## Template reference

```html
<!-- Conditionals -->
<template if:true={booleanProp}>shown when true</template>
<template if:false={booleanProp}>shown when false</template>

<!-- Iteration (key is required) -->
<template for:each={items} for:item="item">
    <div key={item.id}>{item.name}</div>
</template>

<!-- Dynamic style (must be a getter returning a string) -->
<div style={computedStyle}>...</div>

<!-- Dynamic class (must be a getter returning a string) -->
<div class={computedClass}>...</div>

<!-- Event handler -->
<button onclick={handleClick}>Click</button>

<!-- Disabled attribute -->
<button onclick={handleClick} disabled={isDisabled}>Click</button>

<!-- SLDS icons (use instead of emoji) -->
<lightning-icon icon-name="utility:refresh" size="x-small"></lightning-icon>
<lightning-icon icon-name="utility:check" size="x-small"></lightning-icon>
<lightning-icon icon-name="utility:warning" size="x-small"></lightning-icon>
<lightning-icon icon-name="utility:error" size="x-small"></lightning-icon>
```

## Component structure

### JS controller pattern
```javascript
import { LightningElement, api, track } from 'lwc';
import myApexMethod from '@salesforce/apex/MyController.myMethod';

export default class MyComponent extends LightningElement {
    @api recordId;        // passed in from record page context
    @track data = null;   // reactive tracked property
    @track loading = false;
    @track error = null;

    connectedCallback() {
        this.loadData();
    }

    async loadData() {
        this.loading = true;
        this.error = null;
        try {
            this.data = await myApexMethod({ recordId: this.recordId });
        } catch (e) {
            this.error = e.body ? e.body.message : e.message;
        }
        this.loading = false;
    }

    handleRefresh() {
        this.loadData();
    }

    // Getters for template conditionals
    get hasData() { return !!this.data; }
    get hasError() { return !!this.error; }
}
```

### HTML template pattern
```html
<template>
    <lightning-card title="My Component" icon-name="standard:account">
        <template if:true={loading}>
            <lightning-spinner alternative-text="Loading"></lightning-spinner>
        </template>
        <template if:true={hasError}>
            <p class="slds-text-color_error">{error}</p>
        </template>
        <template if:true={hasData}>
            <div class="slds-p-around_medium">
                <!-- content here -->
            </div>
        </template>
        <div slot="footer">
            <lightning-button label="Refresh" onclick={handleRefresh}></lightning-button>
        </div>
    </lightning-card>
</template>
```

### JS-meta.xml template
```xml
<?xml version="1.0" encoding="UTF-8"?>
<LightningComponentBundle xmlns="http://soap.sforce.com/2006/04/metadata">
    <apiVersion>62.0</apiVersion>
    <isExposed>true</isExposed>
    <targets>
        <target>lightning__RecordPage</target>
    </targets>
    <targetConfigs>
        <targetConfig targets="lightning__RecordPage">
            <objects>
                <object>Account</object>
            </objects>
        </targetConfig>
    </targetConfigs>
</LightningComponentBundle>
```

## Choosing your data layer

LWC components have four ways to read or save data. Pick the one that matches the requirement — **don't reflex to imperative Apex**.

### Decision matrix

| Need | Default choice | Why |
|---|---|---|
| Read one record / object metadata | LDS or UI API wire adapter (`getRecord`, `getObjectInfo`) | Standard security, cache, error, and refresh behavior |
| Edit a simple record form | `lightning-record-edit-form` | Standard validation, field-level errors, LDS cache updates, less custom Apex |
| Read aggregate, shaped, or multi-object server data | `@AuraEnabled(cacheable=true)` wired Apex | Read-only DTOs that need Apex shaping |
| Save, delete, call out, generate files, or run a click-driven action | Imperative Apex | Mutations and one-shot commands should not be wired |
| Coordinate several data sources | Explicit JS orchestration | Avoids hidden refresh order and stale UI |

### Use platform features before custom Apex

Use LDS / UI API / `lightning-record-edit-form` when:
- Reading or editing a focused record
- Saving simple field updates
- Using object metadata
- Relying on standard validation rules and field-level errors

Use Apex when:
- The UI needs **multiple objects** in one view
- You need **server-side security or token validation** the platform doesn't enforce
- The data is **aggregate** or shaped (counts, rollups, joined data)
- You need **callouts** or external storage
- You need **complex permission checks** beyond CRUD/FLS

When the user says *"build me an LWC that shows X"*, ask whether `lightning-record-edit-form` or an LDS wire adapter would solve it before generating an Apex controller. The cheapest LWC is the one with no Apex behind it.

## Wire vs imperative Apex

If you do need Apex, picking wired vs imperative is a load-bearing choice. They behave differently and the failure modes are different.

### Wire is reactive, not a command

Wired Apex is a **reactive data source**. The wire adapter reruns when its parameters change. It is *not* a button you press to fetch data on demand.

```javascript
import { wire } from 'lwc';
import getAccounts from '@salesforce/apex/AccountController.getAccounts';

@wire(getAccounts, { industry: '$selectedIndustry' })
wiredAccounts;  // reruns automatically when this.selectedIndustry changes
```

### Wire rules
- **Wire adapters are reactive, not commands.** A wired method that the user "presses" is the wrong shape — use imperative.
- **Reactive parameters must be defined** before the wire fires. An undefined `$param` blocks invocation. Initialize defaults explicitly so the wire doesn't sit waiting.
- **Wired data is read-only.** Copy before mutating for local UI state — direct mutation of wired data is undefined behavior.
- **Store the full wired result object** if you might need `refreshApex` later. Without the stored result, you can't refresh:
  ```javascript
  @wire(getAccounts, { industry: '$selectedIndustry' })
  handleResult(result) {
      this.wiredResult = result;  // store for later refreshApex
      if (result.data) this.accounts = result.data;
      if (result.error) this.error = this.reduceError(result.error);
  }
  ```
- **Handle all four states**: not-ready (params undefined), loading, data, error. Don't show a blank component when params aren't set yet — show a placeholder.
- **Don't chain side effects directly inside wire handlers** without a guard. Wires can fire multiple times — guard against duplicate execution.
- **Don't wire a method unless `cacheable=true`.** Apex methods with DML or callouts cannot be `cacheable`, and uncacheable methods cannot be wired.

### Imperative Apex rules

Use imperative Apex for mutations, non-cacheable reads, callouts, and explicit user actions.

- **Disable the initiating control** while the operation runs. Mobile users tap twice routinely.
- **Await the server result** before showing a success toast. Show success on the actual completion, not on the request being sent.
- **Refresh every affected data source** after DML — wired Apex (via `refreshApex`), LDS records (via `notifyRecordUpdateAvailable`), parent components (custom event), related lists, page-level participants. See "Refresh after data changes" below.
- **Reduce errors** into user-safe messages; keep technical detail in logs.
- **Don't assume a successful Apex promise means everything is done.** Async side effects (rollups, record-triggered Flows, file generation, email alerts) may still be running when the Apex call returns. For those, refresh based on a durable status field, not on the imperative call's resolution.

### Common wire failure patterns

| Pattern | Why it breaks |
|---|---|
| Wiring a mutation method | Mutations aren't `cacheable`; the wire never fires |
| Wiring then fighting stale cache | Wires cache by parameter signature; can't easily force-refresh without `refreshApex` and a stored result |
| Calling imperative Apex and refreshing only the current component | Related lists, parent state, page-level data stay stale |
| Showing a success toast before server completion | User thinks it worked; it didn't |
| Reusing a stale wired result after reactive params changed | The wire fired again but the code is holding the old result |
| Missing the not-ready state | Component shows empty UI when params are undefined, not a loading state |

## Refresh after data changes

The single biggest source of "weird stale UI" bugs in LWC is incomplete refresh after a save or update. Use the right mechanism for the right data source.

### Refresh map

| Changed data | Refresh mechanism |
|---|---|
| Wired Apex result | Stored wire result + `refreshApex(this.wiredResult)` |
| LDS record consumers | `notifyRecordUpdateAvailable([{ recordId }])` from `lightning/uiRecordApi` |
| Parent component state | Custom event with a clear contract — `dispatchEvent(new CustomEvent('refresh', { bubbles: true, composed: true }))` |
| Page-level participants (Lightning record page) | `RefreshEvent` from `lightning/refresh` |
| File upload / generated document | Refresh file list AND parent record state AND any async status indicator |

A single save often needs **multiple refreshes** — the wire that fed the form, the LDS record on the page, the parent component holding aggregate state.

### Save flow pattern

```javascript
import { refreshApex } from '@salesforce/apex';
import { notifyRecordUpdateAvailable } from 'lightning/uiRecordApi';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';

async handleSave() {
    this.isSaving = true;
    try {
        await saveRecord({ recordId: this.recordId, payload: this.payload });

        this.dispatchEvent(new ShowToastEvent({
            title: 'Saved',
            message: 'The record was updated.',
            variant: 'success'
        }));

        // Refresh affected data sources, in order:
        await refreshApex(this.wiredResult);
        await notifyRecordUpdateAvailable([{ recordId: this.recordId }]);
        this.dispatchEvent(new CustomEvent('refreshrequested', {
            bubbles: true,
            composed: true
        }));
    } catch (error) {
        this.dispatchEvent(new ShowToastEvent({
            title: 'Save failed',
            message: this.reduceError(error),
            variant: 'error'
        }));
    } finally {
        this.isSaving = false;
    }
}
```

### Rules
- **A toast is not a refresh strategy.** A success toast tells the user the action completed; it does not refresh anything.
- **Refresh in dependency order.** Stale data in a parent is worse than a delayed paint.
- **Don't dispatch refresh events before the Apex transaction finishes.** The event fires immediately; the transaction may still be running.
- **For async side effects** (file generation, rollup recompute, email send), refresh after the durable status field updates — don't refresh on the imperative Apex completion.

## Navigation

Use `NavigationMixin` with a PageReference. **Never hardcode** Lightning URLs like `/lightning/r/Account/...` — they break in Salesforce mobile, console, Experience Cloud, and namespaced packages.

```javascript
import { NavigationMixin } from 'lightning/navigation';

export default class MyComponent extends NavigationMixin(LightningElement) {
    handleViewRecord() {
        this[NavigationMixin.Navigate]({
            type: 'standard__recordPage',
            attributes: {
                recordId: this.accountId,
                objectApiName: 'Account',
                actionName: 'view'
            }
        });
    }
}
```

### PageReference types

| Target | PageReference type | Notes |
|---|---|---|
| Record view / edit / clone | `standard__recordPage` | Verify recordId, object API name, supported `actionName` |
| Object list / home | `standard__objectPage` | Verify object access |
| File preview | Platform-supported file navigation when available | Validate desktop / mobile / Experience Cloud separately |
| Named app or page | `standard__navItemPage` | Don't assume LEX routes work in Experience Cloud |
| External web handoff | `standard__webPage` | Don't put private data in URL state |

### URL state safety
- **Never put tokens, raw payloads, customer data, or private notes in URL parameters.** URLs leak through browser history, server logs, screenshots, and shared links.
- If the target needs sensitive context, store it server-side (custom metadata, Apex-managed cache) and pass an opaque key, not the data itself.

### Anti-pattern: hardcoded URLs

```javascript
// BAD — breaks in mobile, Experience Cloud, console, namespaced contexts
window.location.href = `/lightning/r/Account/${this.accountId}/view`;

// GOOD — works everywhere via NavigationMixin
this[NavigationMixin.Navigate]({
    type: 'standard__recordPage',
    attributes: { recordId: this.accountId, objectApiName: 'Account', actionName: 'view' }
});
```

## Toasts and error handling

Every user action needs clear loading, success, and error states.

### `ShowToastEvent` patterns

```javascript
import { ShowToastEvent } from 'lightning/platformShowToastEvent';

showToast(title, message, variant = 'info') {
    this.dispatchEvent(new ShowToastEvent({ title, message, variant }));
}
```

Variant guidance:
- **`success`** — the operation completed and the durable result is in place. NOT "the request was sent."
- **`warning`** — the operation completed but with caveats the user should know (partial success, fallback used, deprecated path)
- **`error`** — the operation failed or produced no durable result
- **`info`** — neutral notification, rarely the right choice in user-facing UI

### Reduce errors before showing

Apex errors come back with stack traces, internal field names, raw IDs, and SOQL fragments. Strip those before the user sees them:

```javascript
reduceError(error) {
    if (!error) return 'Something went wrong. Please try again.';
    if (Array.isArray(error.body)) {
        return error.body.map(e => e.message).filter(Boolean).join(', ');
    }
    if (error.body?.message) return error.body.message;
    if (error.message) return error.message;
    return 'Something went wrong. Please try again.';
}
```

### Rules
- **Show success only after the operation that matters has actually completed.** Not after the request was sent. Not after local state updated.
- **Disable the initiating control** while the operation runs.
- **Keep raw Apex errors, debug logs, IDs, and private data out of toasts** — toasts are user-facing.
- **A toast is not a refresh strategy** — see "Refresh after data changes."
- **Show admin warnings for misconfiguration** instead of silent empty UI. If a required custom metadata record is missing, render a banner that says so — don't render a blank component.

## SLDS (Salesforce Lightning Design System)

Use SLDS utility classes for styling instead of custom CSS where possible:
- `slds-p-around_medium` — padding
- `slds-m-bottom_small` — margin
- `slds-text-color_error` — red error text
- `slds-text-heading_medium` — heading size
- `slds-grid` / `slds-col` — grid layout

Use `<lightning-*>` base components (button, card, icon, spinner, input, datatable, etc.) for consistent look and feel.

## Dark mode and theming

Salesforce supports Light, Dark, and System theme modes. The user's theme choice in Salesforce is **independent** of their OS theme — they may pick Dark in Salesforce while their OS is on Light, or vice versa.

### Use SLDS global hooks for custom surfaces

```css
:host {
    --card-bg: var(--slds-g-color-surface-container-1, var(--lwc-colorBackgroundAlt, #ffffff));
    --card-fg: var(--slds-g-color-on-surface-1, #181818);
    --card-border: var(--slds-g-color-border-1, #d8dde6);
}

.card {
    background-color: var(--card-bg);
    color: var(--card-fg);
    border: 1px solid var(--card-border);
}
```

The `--slds-g-color-*` hooks resolve to whatever Salesforce theme the user has chosen. The fallback chain (`--slds-g-color-... → --lwc-... → hex literal`) covers older orgs that don't have the new SLDS variables yet.

### Don't rely on `prefers-color-scheme`

```css
/* WRONG — Salesforce theme is independent of OS theme */
@media (prefers-color-scheme: dark) {
    .card { background: #181818; }
}
```

A user in Salesforce Light theme on a macOS Dark OS will see a dark card on a light page. Use SLDS hooks instead — they reflect the actual Salesforce theme.

### Rules
- **Reference SLDS color hooks**, not hex literals or `prefers-color-scheme` media queries
- **Test on both Light and Dark Salesforce themes** when generating components with custom CSS
- **For non-color theming** (font sizes, density), prefer SLDS utility classes over custom CSS
