# Lightning Web Component (LWC) Development

## When this applies

This skill applies when creating or modifying Lightning Web Components in **dev/sandbox orgs** where write access is enabled.

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

## SLDS (Salesforce Lightning Design System)

Use SLDS utility classes for styling instead of custom CSS where possible:
- `slds-p-around_medium` — padding
- `slds-m-bottom_small` — margin
- `slds-text-color_error` — red error text
- `slds-text-heading_medium` — heading size
- `slds-grid` / `slds-col` — grid layout

Use `<lightning-*>` base components (button, card, icon, spinner, input, datatable, etc.) for consistent look and feel.
