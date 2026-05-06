# Record Pages & FlexiPages

## Core rule

**A successful component deploy does not prove user visibility.** Whether a record page, button, field, or related list actually shows up depends on a chain of seven independent layers. If any one of them disagrees, the user sees nothing — even though the metadata deployed clean.

When a user asks *"I built it / deployed it / activated it, why isn't it showing up?"*, the answer is almost never the component itself. It's almost always assignment, activation, form factor, or permissions.

## Current capabilities (what ForceClaw can do today)

### Read-only / investigative
- Query `FlexiPage`, `FlexiPageRegion`, `FlexiPageComponentInstance` via Tooling API to inspect Lightning record pages
- Query `LightningPageVersion` to see active page versions
- Query `QuickActionDefinition` to inspect quick actions
- Query `PageLayout` and read its structure (`read_page_layout`, `list_page_layouts`)
- Query `Profile`, `PermissionSet`, `ProfileLayout` to see who has what page assignment
- Query `RecordType` to see record-type-driven page assignments

### Write
- Page layouts: `update_page_layout` (add/remove/move/reorder fields, add/remove sections, add quick actions to the platform action list)
- Compact layouts: `update_compact_layout`
- Quick actions: `create_quick_action`

### Not yet built (roadmap — `Bot_SF_Capabilities.md`)
- `update_flexipage` — modify Lightning record page regions, components, visibility filters
- `add_component_to_flexipage` — add an LWC, Screen Flow, field section, or related list to a FlexiPage region
- `set_flexipage_as_default` — set a FlexiPage as the org default for an object
- Dynamic Forms field section management

If the user asks for a FlexiPage write, **diagnose first using read-only tools**, explain what's needed, and tell them the write step isn't built yet. Do not pretend to do it. Do not deploy a payload that hasn't been requested.

## Investigation order — "I deployed it, why isn't it visible?"

Always walk this in order. Stop as soon as you find a layer that disagrees.

1. **Identify the user's actual context** — object API name, app, profile or permission set, record type, and form factor (desktop or phone). The user's record URL tells you most of this.
2. **Inspect the object's `View` / `Edit` / `New` action overrides** — if the override sends users to a different Lightning page or Visualforce page than the one being edited, nothing else matters.
3. **Inspect the active FlexiPage for the relevant form factor** — query `LightningPageVersion` to find the active version. Mobile may use a different FlexiPage than desktop.
4. **Inspect any custom Aura template** the FlexiPage uses — region names, lazy rendering, layout engine. A template region change can hide every component placed in that region.
5. **Inspect page layout assignment** by record type and profile — even on FlexiPage-driven pages, the page layout still drives related lists, action lists (when Dynamic Actions aren't enabled), and the Highlights Panel.
6. **Inspect compact layout assignment** — drives the Highlights Panel field set and the mobile header.
7. **Inspect quick actions, the platform action list, Dynamic Actions, and overflow** — `numVisibleActions` will hide actions in overflow without warning. Dynamic Actions completely replaces the layout's action list.
8. **Inspect component metadata** — for LWC quick actions, check the `js-meta.xml` `targets`, `targetConfigs`, and `supportedFormFactors`.
9. **Inspect permissions** — object CRUD, field-level security, Apex class access, custom permissions, component access. Missing FLS on a single field can silently hide a Dynamic Forms section.
10. **Reproduce or reason separately for desktop vs mobile** when both are supported.

## Activation chain — the seven layers

A component is visible only when **every** layer agrees.

| Layer | What to inspect | ForceClaw query / tool |
|---|---|---|
| Component metadata | LWC `js-meta.xml` targets (`lightning__RecordPage`, `lightning__RecordAction`, `lightning__AppPage`), target configs, `supportedFormFactors` | `get_lwc_source` |
| FlexiPage placement | `FlexiPageRegion`, `FlexiPageComponentInstance`, visibility filters, Dynamic Forms field sections, Dynamic Actions | Tooling API query on `FlexiPage`, `FlexiPageRegion` |
| Object override | View/Edit/New action overrides on the object, per form factor | Metadata API `read` on `CustomObject` |
| App / profile / record type assignment | Page activation: org default → app default → app + record type → app + profile + record type | Tooling API query on `LightningPageVersion`, `LightningPageDataAssignment` |
| Page layout assignment | Layout assignment per profile + record type, related lists, layout action list | `read_page_layout`, query `ProfileLayout` |
| Permissions | Object CRUD, FLS, Apex class access, custom permissions | `read_permission_set`, query `FieldPermissions`, `ObjectPermissions`, `SetupEntityAccess` |
| App navigation | App membership, tabs, App Launcher visibility | Tooling API query on `CustomApplication`, `CustomTab` |

## Page activation hierarchy

Salesforce resolves which Lightning record page a user sees in this order, **most-specific wins**:

1. **App + Profile + Record Type** — most specific
2. **App + Record Type**
3. **App default**
4. **Org default** — least specific

If the user is in the Sales app on the Customer record type with the Sales User profile, and there's a page assigned at the App+Profile+RecordType level, that wins — even if the org default was just changed.

Two practical consequences:
- Setting a new page as the org default does **not** override more-specific assignments. The user has to clear those first or set the page at the matching specificity.
- "Why does Joe see the new page but Sarah doesn't?" → almost always a profile-specific assignment that was missed.

## Standard vs custom components

### Use standard components when they already do the job
- **Highlights Panel** — record header tile with compact layout fields and actions
- **Path** — status-driven, picklist-backed (`Stage`, `Status`, `OpportunityStage`)
- **Activities** — tasks, events, calls, emails
- **Chatter** — feed (only if Chatter is enabled in the org)
- **Related List** — standard parent-child relationships
- **Dynamic Related List** — filtered/sorted related lists with custom columns
- **Record Detail** — full field display from page layout
- **Dynamic Forms** — field sections placed directly on the FlexiPage (not the page layout)

### Reach for a custom LWC when
- Data spans multiple objects in one view
- The UX needs custom state, modals, or a guided flow that standard components can't host
- The component needs server-side authorization or token checks
- A specific user workflow needs a focused operating surface (a "workspace" page)

Don't recommend a custom LWC just because the user asked for "something custom." Ask whether Dynamic Forms or a Dynamic Related List would solve it first — they cost zero Apex and zero maintenance.

## Quick action visibility — the matrix

A quick action is visible only when **every** layer agrees:

| Layer | Failure mode |
|---|---|
| **Component target** | LWC `js-meta.xml` doesn't expose `lightning__RecordAction`, or `supportedFormFactors` excludes phone |
| **Action metadata** | `QuickActionDefinition` points to a renamed/missing component, wrong type, or wrong subtype |
| **Layout actions** | Action isn't in the page layout's "Salesforce Mobile and Lightning Experience Actions" section AND Dynamic Actions isn't replacing the layout |
| **Dynamic Actions** | Dynamic Actions is enabled on the FlexiPage but the action isn't in the configured set, or a visibility filter excludes the user |
| **FlexiPage activation** | The user's app/profile/record type combination is hitting a different FlexiPage than the one with the action |
| **Permissions** | User lacks object CRUD, the LWC's required FLS, Apex class access, or a custom permission gating the action |
| **Runtime / form factor** | Action is configured for desktop but the user is on the mobile app, or vice versa |
| **Overflow** | Action exists and would be visible, but `numVisibleActions` pushed it past the visible count into overflow |

### LWC quick action rules
- **Screen actions** must own loading state, cancel state, validation, and completion handling — Salesforce won't manage these for you
- **Headless actions** must guard duplicate execution and surface recoverable errors via toast
- The `recordId` is **not guaranteed** to be present before the action context initializes — check before using
- Modal sizing must be set explicitly for both desktop and mobile
- Use `NavigationMixin` for post-completion navigation, not hardcoded URLs

## Dynamic Forms vs page layouts

Dynamic Forms field sections, the standard Record Detail panel, and page layout field sections **can coexist** on the same record page. When fields look wrong, identify which system is rendering them:

| Symptom | Likely source |
|---|---|
| Fields look like a flat list, no sections | Standard Record Detail panel reading from the page layout |
| Fields are in named sections directly on the FlexiPage | Dynamic Forms field sections in FlexiPage metadata |
| Fields appear on desktop but not mobile (or vice versa) | Different field-rendering system per form factor — `force:detailPanel` (desktop) vs `force:recordDetailPanelMobile` (mobile) |
| Fields are read-only despite FLS being correct | Custom LWC rendering the field, not standard `lightning-record-form` |
| Required asterisks missing | LWC bypassed `lightning-record-edit-form` and didn't recreate the required-field UX |

Adding a field via `update_page_layout` will **not** show up if the FlexiPage has switched that section to Dynamic Forms — the field has to be added to the FlexiPage's field section instead. (FlexiPage write tools are roadmap.)

## Mobile record pages

Mobile record pages often use a different FlexiPage and a different field-rendering system. A desktop fix can miss mobile entirely.

### Common mobile-specific failure modes
- **Small form factor uses a different FlexiPage** — the desktop FlexiPage was edited but the phone FlexiPage wasn't
- **Custom LWC doesn't support Small form factor** — `js-meta.xml` `supportedFormFactors` excludes phone
- **Field rendering uses `force:recordDetailPanelMobile`** — desktop's `force:detailPanel` config doesn't apply
- **Action appears only in overflow on mobile** — phone has tighter `numVisibleActions`
- **Action only works in Salesforce mobile native action bar** — different placement metadata than desktop
- **Modal/file/navigation behavior differs** — mobile webview has different lifecycle than desktop browser

When the user reports a record-page issue, **always ask whether they're on desktop or mobile**, and check the matching FlexiPage. Don't assume.

## Related lists — three independent systems

Standard related lists, Dynamic Related Lists, and Apex/LWC-backed custom lists do **not** share state.

| System | What drives it | What does NOT update it |
|---|---|---|
| **Standard related list** | Page layout related-list section, parent-child relationship | Adding a Dynamic Related List, updating a custom LWC, deleting a file via SOQL DML |
| **Dynamic Related List** | FlexiPage component instance with filter/sort/columns config | Page layout edits, standard related list reorders |
| **Custom LWC list** | Whatever the LWC's wired Apex returns | Standard list refreshes, file uploads/deletes (unless the LWC explicitly listens) |

Practical implications:
- A new file uploaded via `ContentVersion` insert will appear in a standard Files related list, but a custom LWC list will show stale data until the LWC's wire is refreshed (`refreshApex`)
- Adding a column to a Dynamic Related List does **not** affect a page layout related list with the same name
- Deleting a `ContentDocumentLink` may not refresh a custom LWC that's caching the list locally

## Common record-page failures

| Symptom | Likely cause | Fix |
|---|---|---|
| Quick action configured but not visible on desktop | Page layout, Dynamic Actions, overflow, or permissions disagree | Walk the Quick Action Visibility Matrix top to bottom |
| Quick action visible on desktop but not mobile | Phone form factor, Dynamic Actions, layout action list, or permissions differ from desktop | Inspect component target form factors, layout action list, Dynamic Actions, activation, permissions — all separately for phone |
| Field added to layout but doesn't show up on the page | FlexiPage has switched that section to Dynamic Forms | Add the field to the FlexiPage's field section instead (roadmap) |
| New Lightning page set as org default but only some users see it | More-specific App+Profile+RecordType assignments still pointing at the old page | Find and clear/update the more-specific assignments |
| Dynamic Forms field shows for some users, not others | FLS or custom permission gating | Check `FieldPermissions` for the user's permission sets |
| Component deployed clean but isn't on any page | Component metadata is correct but no FlexiPage references it | Add a `FlexiPageComponentInstance` (roadmap); for now, diagnose and report |
| Aura template region "missing" after FlexiPage edit | Region name changed in the template | Restore the region name or update the FlexiPage to use the new name |
| Related list refresh not happening after a record save | Custom LWC list, no explicit refresh logic | Add `refreshApex(this.wiredResult)` after the save completes |

## Pre-flight checklist before editing record-page metadata

Before you suggest or generate any record-page-related change:

- [ ] **Confirm the form factor** — desktop, phone, or both?
- [ ] **Confirm the user's app, profile, and record type** — page assignment resolves through these
- [ ] **Confirm whether the active page is FlexiPage-driven, layout-driven, or Aura-template-driven** — different edits, different deploy paths
- [ ] **Confirm whether Dynamic Actions is enabled** — if yes, layout action list edits won't help
- [ ] **Confirm whether fields render via Dynamic Forms or page layout** — different metadata files
- [ ] **Confirm permissions** — can the target user actually see the object/field/Apex class the action depends on?
- [ ] **Confirm that the same change doesn't need to happen on the matching mobile FlexiPage**

## Rules

- **Don't edit only the component when the root cause is assignment, activation, or permission metadata.** A successful LWC update against a hidden component changes nothing the user sees.
- **Don't edit profiles blindly to make an action visible.** Profile-level changes have org-wide blast radius. Diagnose first.
- **Don't deploy broad FlexiPage / layout / profile payloads.** Narrow scope. Surface only what the user asked for.
- **State explicitly when runtime activation can't be fully verified.** Validating the metadata isn't the same as confirming the user will see it. Tell the user what was validated and what still needs to be checked in their browser.
- **Always check both form factors** when a record-page change is requested, unless the user explicitly says desktop-only or phone-only.
