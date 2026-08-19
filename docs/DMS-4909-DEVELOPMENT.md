# DMS-4909: Tour Availability Generator — Development Notes

This document accompanies `docs/DMS-4909-LLD.md` and describes the implementation under
`force-app/main/default/`, built against our current working understanding while several items
are still pending formal business confirmation.

## What's implemented

### Data model
- `DVC_Tour_Availability__c`, `DVC_Tour_Guide_Shift__c`, `DVC_Tour_Availability_Slot__c` — full
  field set per LLD Section 7 (note: `DVC_Total_Slots__c` and `DVC_Online_Capacity_Input__c`
  were intentionally **not** created, per business direction to drop them from the parent
  object).
- `DVC_Tour_Location__c` on `DVC_Tour_Availability__c` uses a lookup filter restricting
  selection to standard `Location` records where `LocationType = 'Resort'`.
- Uniqueness on `DVC_Tour_Availability__c` is enforced via `DVC_Location_Date_Key__c`
  (Location + Date + Slot Type composite, external ID + unique).
- Every field the LLD marks "Field Tracking: Yes" has `trackHistory=true` (both custom objects
  also have object-level `enableHistory=true`). The two formula fields
  (`DVC_Remaining_Online_Slots__c` / `DVC_Remaining_Onsite_Slots__c`) are deliberately excluded —
  Salesforce does not support history tracking on formula fields.

### Apex
| Class | Purpose |
|---|---|
| `DVC_TourAvailabilityConstants` | Picklist values, slot-interval-to-minutes map, tunables |
| `DVC_TourAvailabilityException` | Expected/user-facing business-rule failures |
| `DVC_LoggerService` | Thin adapter around **Nebula Logger** — see Dependencies below |
| `DVC_TourAvailabilityRequest` | Shared request payload (LWC ↔ Apex ↔ Batch ↔ Scheduled job) |
| `DVC_TourAvailabilityValidationService` | Server-side re-validation, VR-01–VR-09 |
| `DVC_TourSlotGenerationService` | The core, DML-free slot-generation algorithm (LLD Section 10.1) |
| `DVC_TourLocationTreeController` | Read-only data provider for the Location Tree LWC |
| `DVC_TourAvailabilityPublishController` | `@AuraEnabled` entry point for the Publish action |
| `DVC_TourSlotGenerationBatch` | Bulk-safe, async persistence at Publish time |
| `DVC_TourAvailabilityDailyRolloverJob` | Scheduled Apex implementing the 90-day rolling-window "clone" rule |
| `DVC_TourAvailabilityTestDataFactory` | Shared `@isTest` data builders |
| `*Test` classes | One test class per production class above |

**Transaction integrity:** `DVC_TourSlotGenerationBatch.execute()` and
`DVC_TourAvailabilityDailyRolloverJob.rollForward()` both wrap their parent-then-children insert
sequence in a `Database.setSavepoint()` / `Database.rollback()` pair. Without this, a failure
inserting child Guide Shift/Slot records would leave an orphaned parent
`DVC_Tour_Availability__c` with zero children — permanently un-retryable, since
`DVC_Location_Date_Key__c`'s uniqueness constraint would treat that Location+Date+Slot Type as
already published forever.

**Field-level security:** in addition to the object-level `isCreateable()` check in
`DVC_TourAvailabilityPublishController.hasPublishPermission()`, every DML insert in
`DVC_TourSlotGenerationBatch` and `DVC_TourAvailabilityDailyRolloverJob` runs the record list
through `Security.stripInaccessible(AccessType.CREATABLE, ...)` first. **Important implementation
detail:** `stripInaccessible()` returns *cloned* records, not the same instances passed in — the
calling code always reassigns its local list variable to the returned
`SObjectAccessDecision.getRecords()` list *before* inserting, otherwise the original (un-inserted)
objects would never have their `Id` populated for use when building child records.

**Daily rollover catch-up:** per LLD Section 12 step 4, `rollForward()` loops from
`(latestPublishedDate + 1)` through the 90-day horizon for each location — not just a single day
— so a single run fully catches up a location even if one or more prior scheduled runs were
missed (org downtime, job deployed after a period of inactivity, etc.).

### LWC
| Component | Role |
|---|---|
| `dvcTourAvailabilityGenerator` | Main container — owns shared state, Generate/Publish actions |
| `dvcTourLocationTree` | Child — multi-select Location tree, grouped by Channel |
| `dvcTourAvailabilityConfigForm` | Child — all config fields, repeatable Guide Shifts |
| `dvcTourSchedulePreviewGrid` | Child — renders the preview grid, Onsite read-only / Online editable |
| `dvcTourAvailabilityUtils` | JS-only module: client-side mirror of the Apex slot-generation algorithm |

"Generate & Preview Schedule" never calls Apex (per Decision Log Q0) — it runs
`dvcTourAvailabilityUtils.generatePreviewSlots()` entirely in the browser. **Any change to the
algorithm must be made in both `DVC_TourSlotGenerationService.cls` and
`dvcTourAvailabilityUtils.js` together**, or the preview will stop matching what gets Published.
This is now enforced by a shared, hand-verified set of test fixtures (LLD Section 10.6 Combos 1,
4, 6) duplicated across `DVC_TourSlotGenerationServiceTest.cls` (Apex) and
`dvcTourAvailabilityUtils.test.js` (Jest) — if you change the algorithm in one place, update the
fixtures in both test files.

**Config form fixes worth knowing about:**
- The form emits its defaults once on `connectedCallback()`, so `currentConfig` in the container
  is never empty even if a user accepts every default and clicks Generate without touching a
  field.
- The default (first) Guide Shift row inherits Opening/Closing Time once those are set, but only
  if the user hasn't already edited that row's own start/end time — matching the LLD's stated
  default behavior without clobbering manual edits.
- Every input (including the conditionally-rendered Lunch Start/End and Online Capacity fields)
  is a fully controlled input (`value=`/`checked=` bound to tracked state), so toggling Lunch
  Block / Online Tour Booking off and back on no longer shows a blank field while silently still
  submitting a stale value underneath.
- `reportValidity()` now implements the actual VR-02/VR-03/VR-04/VR-05/VR-06/VR-08/VR-09
  business-rule checks from LLD Section 9 client-side (via `setCustomValidity`), with the exact
  user-facing messages from the LLD — not just native HTML5 `required`/`min` constraints. VR-07
  (Online ≤ Onsite) can only be evaluated per-slot after generation, so it's enforced in the
  preview grid and again server-side, not at the config-form level. The container now calls
  `reportValidity()` before **both** Generate and Publish (previously only before Generate).
- Guide Shift rows have distinguishing per-row labels ("Shift 1 Start Time", "Shift 2 Start
  Time", ...) for screen-reader users, computed via a `renumberShifts()` helper re-run on every
  add/remove/edit.

**A real, previously-undetected bug was caught by running the new Jest suite (see Testing
below):** `dvcTourSchedulePreviewGrid.js` originally declared `@api onlineEnabled = false;` —
LWC reserves any public property name starting with `on` for event handlers, so this would have
**failed to compile/deploy entirely** (`LWC1108`). It's been renamed to `isOnlineBookingEnabled`
throughout (the child component, and the container's corresponding getter/attribute binding).
This is a strong argument for running `npm run test:unit` before every deploy, even though it
only exercises plain JS modules today — the LWC compiler step alone would have caught this.

### Automation / Access
- `DVC_Tour_Availability_Generator` custom Tab + `DVC_Tour_Availability_Generator` App Page
  hosting the container LWC.
- `DVC_Tour_Availability_Management` permission set + `DVC_Tour_Availability_Management_PSG`
  permission set group — the only way to get access (no profile-level grants). The two
  `Remaining_Online_Slots__c`/`Remaining_Onsite_Slots__c` formula fields now also have explicit
  `readable=true` field permissions (previously missing).
- `DVC_TourAvailabilityDailyRolloverJob` is **not scheduled automatically** by this deploy —
  Salesforce has no metadata type to declaratively schedule Apex on deploy. Run
  `scripts/apex/schedule-daily-rollover-job.apex` once per org immediately after deploying (e.g.
  `sf apex run --file scripts/apex/schedule-daily-rollover-job.apex --target-org <alias>`). The
  script is idempotent — it aborts any existing job with the same name before rescheduling, so
  it's also safe to re-run after changing `CRON_EXPRESSION`.

## Dependencies

### Nebula Logger (required, hard compile-time dependency)
`DVC_LoggerService` calls Nebula Logger's `Logger` class **directly, resolved at compile time**.
Install the [Nebula Logger](https://github.com/jongpie/NebulaLogger) unlocked/unmanaged package
in the target org **before** deploying this feature. If it isn't installed, the deploy will
**fail to compile** — it does not "silently degrade" to `System.debug` (that fallback only
guards against a *runtime* failure of an already-compiled `Logger` call, e.g. a misconfigured
logging level, not against the package being absent). This isn't declared in
`sfdx-project.json`'s `packageDirectories[].dependencies` yet because we don't have the real
installed package version Id (`04t...`) for this org and a placeholder/invalid Id would break
`sf org create scratch` for every developer — see the `$comment_dependencies` note in
`sfdx-project.json` for how to wire it up once the real Id is known.

### Standard `Location` object schema assumption
`DVC_TourLocationTreeController` assumes the standard Location object's self-lookup field
`ParentLocationId` has relationship name `ParentLocation` (used in `ParentLocation.Name` in the
SOQL query). Verify this against the actual org schema before first deploy; update the query if
the org uses a different relationship name.

## Deliberately NOT implemented yet (pending business confirmation)

These map directly to `docs/DMS-4909-LLD.md` Section 20 (Open Items):

1. **Guide Shift overlap/max-count/gap rules** — currently shifts are simply summed if they
   overlap, with no cap on count. (Item 1)
2. **Publish button UX** — the Publish button exists and calls Apex, but there's no
   success/failure toast polling for the async batch job yet beyond an immediate "submitted"
   toast; no Platform Event/notification on batch completion. (Item 2)
3. **Daily rollover job monitoring/alerting** — runs at a hardcoded 2:00 AM cron, logs a summary
   via Nebula Logger on completion, but has no dedicated failure alerting (email, Platform
   Event). Also note: it runs synchronously (not itself batched) across all locations in a single
   scheduled-Apex transaction — fine for a small number of published locations, but worth
   revisiting (e.g. chunking via `Database.Batchable`) if that number grows large. (Item 3)
4. **Trailing partial block when Slot Interval doesn't evenly divide the operating window**
   (e.g., 60-minute interval over a 7.5-hour day) — currently silently dropped, no validation
   blocks the combination. (Item 7)
5. **`DVC_Slot_Status__c` picklist values** — implemented as `Open`/`Closed` as a working
   assumption; business has floated `Available`/`Booked` as an alternative. If changed, update
   the picklist, `DVC_TourAvailabilityConstants`, `DVC_TourSlotGenerationService`, and
   `dvcTourAvailabilityUtils.js` together. (Item 6)
6. **A tour starting before Lunch but running into it** — currently allowed (matches the
   reference mock-up), pending explicit business sign-off. (Item 9)
7. **Custom report types** (LLD Section 14) — not yet built.

None of these block a first deployment/demo — they're flagged here so they're easy to find and
update once business responds, per the Decision Log/Open Items process already established in
the LLD.

## Testing

### Apex
Test classes exist for every production class, aiming for meaningful assertions rather than
just coverage percentage, including tests that reproduce the LLD's "Combo 1/4/6" worked examples
exactly (`DVC_TourSlotGenerationServiceTest`), a multi-day catch-up scenario for the rollover job
(`DVC_TourAvailabilityDailyRolloverJobTest.testRollForwardCatchesUpMultipleMissedDays`), and
per-VR coverage in `DVC_TourAvailabilityValidationServiceTest`. **These have not yet been run
against a live Salesforce org** — this development environment has no org
connectivity/Salesforce CLI available, so they've only been reviewed by careful manual
inspection, not executed. Run `sf project deploy start` and `sf apex run test` (or the equivalent
in your CI) as the **first validation step** after pulling this branch into an environment with
org access, before assuming any Apex class is deploy-ready.

### LWC (Jest)
`npm install && npm run test:unit` runs `sfdx-lwc-jest` against every LWC in
`force-app/main/default/lwc/`. As of this pass, `dvcTourAvailabilityUtils.test.js` gives the
client-side slot-generation algorithm the same Combo 1/4/6 coverage as its Apex counterpart, plus
edge-case coverage (missing config, invalid Opening/Closing order, Online-capacity capping). This
was run and verified passing in this environment (Node 22, all 7 tests green) — and in the
process caught the real `LWC1108` compile bug described above, which a code-only review had
missed. `dvcTourAvailabilityConfigForm`, `dvcTourAvailabilityGenerator`,
`dvcTourLocationTree`, and `dvcTourSchedulePreviewGrid` do not yet have their own Jest test
files (only exercised indirectly by successfully compiling) — adding component-level tests for
these (especially the config form's new `reportValidity()` business-rule checks) is a natural
next increment.

## Post-deploy checklist

1. Install Nebula Logger in the target org (see Dependencies above).
2. `sf project deploy start` (or your CI's deploy step).
3. `sf apex run test` — run the full Apex test suite for the first time against a real org.
4. `npm install && npm run test:unit` — run the Jest suite (can also run before deploy, since it
   has no org dependency).
5. Run `scripts/apex/schedule-daily-rollover-job.apex` once to schedule the rollover job.
6. Assign the `DVC_Tour_Availability_Management_PSG` permission set group to Business
   Admin/Operations users.
