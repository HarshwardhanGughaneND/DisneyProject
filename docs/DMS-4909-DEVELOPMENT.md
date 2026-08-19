# DMS-4909: Tour Availability Generator — Development Notes

This document accompanies `docs/DMS-4909-LLD.md` and describes the first implementation pass
of the feature under `force-app/main/default/`, built against our current working
understanding while several items are still pending formal business confirmation.

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

### Automation / Access
- `DVC_Tour_Availability_Generator` custom Tab + `DVC_Tour_Availability_Generator` App Page
  hosting the container LWC.
- `DVC_Tour_Availability_Management` permission set + `DVC_Tour_Availability_Management_PSG`
  permission set group — the only way to get access (no profile-level grants).
- `DVC_TourAvailabilityDailyRolloverJob` is **not scheduled automatically** by this deploy —
  after deployment, schedule it once (e.g., via Anonymous Apex, Setup UI, or a post-install
  script):
  ```apex
  System.schedule('DVC Tour Availability Daily Rollover', DVC_TourAvailabilityDailyRolloverJob.CRON_EXPRESSION, new DVC_TourAvailabilityDailyRolloverJob());
  ```

## Dependencies

### Nebula Logger (required)
`DVC_LoggerService` calls Nebula Logger's `Logger` class. Install the
[Nebula Logger](https://github.com/jongpie/NebulaLogger) unlocked/unmanaged package in the
target org **before** deploying this feature, or the `try/catch` fallback in
`DVC_LoggerService` will silently degrade to `System.debug` (the calling transaction is never
broken either way, but you won't get structured logs until Nebula Logger is installed).

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
   Event). (Item 3)
4. **Trailing partial block when Slot Interval doesn't evenly divide the operating window**
   (e.g., 60-minute interval over a 7.5-hour day) — currently silently dropped, no validation
   blocks the combination. (Item 7)
5. **`DVC_Slot_Status__c` picklist values** — implemented as `Open`/`Closed` as a working
   assumption; business has floated `Available`/`Booked` as an alternative. If changed, update
   the picklist, `DVC_TourAvailabilityConstants`, `DVC_TourSlotGenerationService`, and
   `dvcTourAvailabilityUtils.js` together. (Item 6)
6. **A tour starting before Lunch but running into it** — currently allowed (matches the
   reference mock-up), pending explicit business sign-off. (Item 9)

None of these block a first deployment/demo — they're flagged here so they're easy to find and
update once business responds, per the Decision Log/Open Items process already established in
the LLD.

## Testing

Apex test classes were written for every production class (aiming for meaningful assertions,
not just coverage percentage), including a test that reproduces the LLD's "Combo 1" worked
example exactly (`DVC_TourSlotGenerationServiceTest.testCombo1MatchesLldWorkedExample`). **These
have not yet been run against a live Salesforce org** (this development environment has no
org connectivity/Salesforce CLI available) — run `sf project deploy start` and
`sf apex run test` (or the equivalent in your CI) as the first validation step after pulling
this branch.

No LWC Jest tests were included in this pass; consider adding `sfdx-lwc-jest` coverage for
`dvcTourAvailabilityUtils.js` (the algorithm) as a follow-up, since it's the most business-critical
piece of client-side logic.
