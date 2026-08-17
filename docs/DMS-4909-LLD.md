# DMS-4909: Tour Availability Generator — Schedule Creation

## Low-Level Design (LLD)

**Jira Story:** [DMS-4909](https://disneyexperiences.atlassian.net/browse/DMS-4909)
**Epic:** DMS-2835 — Business Capabilities | Cast Workflow Management | Tour Booking & Management
**Related HLD:** DMS-4909 : Tour Slots Generator (High-Level Design)
**Document Format Reference:** *Ability to Manage Guide License Data* (LLD template)
**Status:** Draft — pending business confirmation on items listed in Section 19

---

## 1. Table of Contents

1. Table of Contents
2. Overview
   - 2.1 Purpose
   - 2.2 Background
3. Scope
   - 3.1 In Scope
   - 3.2 Out of Scope
4. Solution Architecture
   - 4.1 Component Overview
   - 4.2 Process Flow (Preview vs. Publish)
5. Data Model Diagram
   - 5.1 Existing Enterprise Tour Booking Data Model (Context)
   - 5.2 DMS-4909 Object Relationship Diagram
6. Core Salesforce Object Details
7. Detailed Data Model
   - 7.1 Location\_\_c (Existing — Referenced)
   - 7.2 Tour_Availability\_\_c (Existing — Extended)
   - 7.3 Tour_Availability_Slot\_\_c (Existing — Extended)
8. LWC Design — Tour Availability Generator
   - 8.1 Input Fields & Conditional Behavior
   - 8.2 Schedule Preview Grid
9. Validation Rules
10. Slot Generation Logic
    - 10.1 Algorithm
    - 10.2 Worked Example
    - 10.3 Lunch Block Handling
    - 10.4 Duplicate / Re-generation Handling
11. Apex Design
    - 11.1 Apex Classes
    - 11.2 Key Method Signatures
    - 11.3 Asynchronous Processing (Batch Apex)
12. Automation / Scheduled Jobs
13. Permission Sets
14. Reporting
15. Uniqueness Rules
16. Flexi Pages & Compact Layout
17. Acceptance Criteria Traceability Matrix
18. Security & Compliance Considerations
19. Open Items / Assumptions Requiring Business Confirmation
20. Appendix
    - 20.1 Jira Stories
    - 20.2 List of Figures
    - 20.3 Referenced Documents

---

## 2. Overview

### 2.1 Purpose

Enable Business Admins and Operations users to configure and generate a **projected tour availability schedule** for one or more pre-configured tour locations, across a date range, so that guide/tour capacity can be previewed before slots are made available for booking. The feature is delivered as a single-screen Lightning Web Component (LWC) that captures scheduling parameters, previews the generated schedule in place, and (per the HLD) persists the schedule via an asynchronous Batch Apex process on a separate Publish action.

### 2.2 Background

This LLD is derived from the DMS-4909 HLD ("Tour Slots Generator") and the story's acceptance criteria (UAC1–UAC19), reconciled against four business decisions confirmed on 2026-08-17:

| # | Question | Business Decision |
|---|---|---|
| 1 | Capacity model: Guide-Shift-driven (per mock-up) vs. flat Online/Onsite capacity entry (per HLD)? | **HLD model confirmed** — capacity is entered directly as Online Capacity / Onsite Capacity values, not derived from Guide Shifts. Guide Shift UI/logic is **not** part of this story. |
| 2 | Is Lunch Block still in scope? | **Yes** — to be fully specified in this LLD. |
| 3 | Online Tour Booking toggle behavior | When **unchecked**, the screen shows a single **Tour Slots** view/field (no Online/Onsite split). When **checked**, both **Online** and **Onsite** capacity fields/columns are displayed. |
| 4 | Is Online ≤ Onsite validation still required? | **Yes.** |

Items raised during HLD review that remain **unanswered** are tracked in Section 19 and have been handled with explicit, clearly-labeled assumptions so this LLD can move forward without blocking development.

---

## 3. Scope

### 3.1 In Scope

- Single-screen LWC: Location selection (tree, existing component/data), scheduling parameter form, and in-place Schedule Preview panel.
- Onsite tour type generation only (the "Onsite" tab in the mock-up). The **Event/Group tab is explicitly out of scope** for DMS-4909 and is tracked under a separate story; this LLD's data model additions must remain compatible with that story reusing the same objects (`Tour_Availability__c` / `Tour_Availability_Slot__c`).
- Date range, Operating Hours, Tour Duration, Slot Interval, Lunch Block, Online Tour Booking toggle, and Online/Onsite capacity capture.
- Client-side (preview) slot generation logic executed without persisting data.
- Server-side (publish) slot persistence via Batch Apex, writing `Tour_Availability__c` and `Tour_Availability_Slot__c` records.
- Validation rules per UAC1–UAC10.
- Duplicate-generation protection at Location + Availability Date grain.

### 3.2 Out of Scope

- Event/Group tour configuration (separate story).
- Guide Shift management / guide-occupancy-based capacity calculation (superseded by business decision #1 above).
- Actual guest-facing booking flow / slot consumption (Booked Online/Onsite Slots are read here as existing fields but are written to by the booking engine elsewhere).
- Editing/overriding individual generated slot values directly in the preview grid (treated as read-only preview; see Section 19, Item 3).

---

## 4. Solution Architecture

### 4.1 Component Overview

```
+--------------------------------------+
|  Tour Availability Generator (LWC)   |
|  - Location Tree (existing component)|
|  - Config Form                       |
|  - Schedule Preview Grid             |
+--------------------------------------+
              |  (1) Generate & Preview  -> client-side JS computation only, no Apex/DML
              |  (2) Publish             -> Apex call
              v
+--------------------------------------+
|  TourAvailabilityGeneratorController |
|  (Apex, with sharing)                |
|  - validateRequest()                 |
|  - previewSchedule()  [read-only]    |
|  - publishSchedule()  [enqueues Job] |
+--------------------------------------+
              |
              v
+--------------------------------------+
|  TourSlotGenerationBatch             |
|  (Database.Batchable, Queueable      |
|   fallback for small volumes)        |
+--------------------------------------+
              |
   -----------------------------
   |                           |
   v                           v
Tour_Availability__c    Tour_Availability_Slot__c
(1 per Location+Date)   (1 per generated time slot)
```

### 4.2 Process Flow (Preview vs. Publish)

1. User opens the Tour Availability Generator LWC.
2. User selects one or more Locations from the existing Location tree.
3. User enters Start Date, End Date, Operating Start/End Time, Tour Duration, Slot Interval, optionally enables Lunch Block (Lunch Start/End) and Online Tour Booking (Online/Onsite Capacity).
4. Client-side validation runs on every field change; **Generate & Preview Schedule** stays disabled until all required fields are valid (UAC1–UAC3, UAC6, UAC10).
5. On **Generate & Preview Schedule** click: slot generation logic (Section 10) runs **entirely client-side in the LWC** (no Apex/DML) and renders the Schedule Preview panel in place (UAC17, UAC19).
6. The preview does **not** persist any records (per story assumption "Schedule Preview is a projection/preview only").
7. A separate **Publish** action (introduced by the HLD, not present in the current mock-ups — see Section 19, Item 4) invokes `TourAvailabilityGeneratorController.publishSchedule()`, which validates duplicates (Section 10.4) and enqueues `TourSlotGenerationBatch` to persist `Tour_Availability__c` and `Tour_Availability_Slot__c` records asynchronously.
8. On batch completion, a success/failure notification is surfaced to the user (Platform Event or polling, per Section 11.3).

---

## 5. Data Model Diagram

### 5.1 Existing Enterprise Tour Booking Data Model (Context)

The following objects already exist in the org (per the provided Tour Booking data model architecture diagram) and establish the relationships that `Tour_Availability__c` and `Tour_Availability_Slot__c` must remain consistent with:

```
Location__c ──< Tour_Availability__c ──< Tour_Availability_Slot__c ──< Tour__c
     │                                                                    │
     ├──< Voyage__c ─────────────────────────────────────────────────────┤
     ├──< Team__c ──< Team_Schedules__c                                  │
     │           └──< Team_Cast_Member__c                                │
     └──< Incentive Type ──< Tour_Incentive__c                           │
                                                                          │
Person Account (Account) ──< Tour_Guest__c ──────────────────────────────┤
Contact (Type=Driver) ──< Vehicle_Schedules__c ──< Transportation_Requests__c
Tour_Household__c ────────────────────────────────────────────────────────┘
```

**Key takeaway:** `Team__c` / `Team_Cast_Member__c` model actual guide/cast assignment elsewhere in the platform (used during live Tour execution), which is a **separate concern** from the flat-capacity slot generation this story implements — consistent with business decision #1 (no guide-driven capacity in this story). No changes to `Team__c`, `Team_Cast_Member__c`, `Tour__c`, `Voyage__c`, `Tour_Incentive__c`, or `Tour_Guest__c` are required by DMS-4909.

### 5.2 DMS-4909 Object Relationship Diagram

```
+----------------------+
|     Location__c      |   (existing — no changes)
+----------------------+
| Id                    |
| Name                  |
| Active__c             |
| Channel__c (assumed)  |  <-- see Section 19, Item 6
+----------------------+
           |
           | 1 : M
           v
+--------------------------------------+
|         Tour_Availability__c         |   (existing object — EXTENDED)
+--------------------------------------+
| Id                                    |
| Location__c (Lookup)                  |
| Availability_Date__c                  |
| Operating_Start_Time__c               |
| Operating_End_Time__c                 |
| Tour_Duration__c              [NEW]   |
| Slot_Interval__c              [NEW]   |
| Lunch_Block_Needed__c         [NEW]   |
| Lunch_Start_Time__c           [NEW]   |
| Lunch_End_Time__c             [NEW]   |
| Online_Tour_Booking_Enabled__c [NEW]  |
| Total_Slots__c                        |
| Slot_Type__c (Onsite/Event)           |
| Generation_Status__c          [NEW]   |
| Location_Date_Key__c                  |
+--------------------------------------+
           |
           | 1 : M
           v
+--------------------------------------+
|     Tour_Availability_Slot__c        |   (existing object — EXTENDED)
+--------------------------------------+
| Id                                    |
| Tour_Availability__c (Lookup/MD)      |
| Slot_Start_DateTime__c                |
| Slot_End_DateTime__c                  |
| Total_Online_Capacity__c              |
| Total_Onsite_Capacity__c              |
| Booked_Online_Slots__c                |
| Booked_Onsite_Slots__c                |
| Remaining_Online_Slots__c     [NEW, formula] |
| Remaining_Onsite_Slots__c     [NEW, formula] |
| Is_Lunch_Block__c             [NEW]   |
| Status__c (Open/Closed)               |
+--------------------------------------+
```

---

## 6. Core Salesforce Object Details

| Object Name | API Name | Description | Standard/Custom | Change Type |
|---|---|---|---|---|
| Location | `Location__c` | Master data for a bookable tour/resort location. | Custom | No change |
| Tour Availability | `Tour_Availability__c` | Represents a single day's operating schedule for a specific location (one record per Location + Availability Date). | Custom | Extend (new fields) |
| Tour Availability Slot | `Tour_Availability_Slot__c` | Represents an individual generated time slot under a Tour Availability record. | Custom | Extend (new fields) |

**Note:** The HLD refers to the slot object as `Tour_Slot__c`. The org's actual data model (per the provided ERD) names this object `Tour_Availability_Slot__c`. This LLD uses the **actual existing API name**; the HLD should be corrected to avoid confusion during build.

---

## 7. Detailed Data Model

### 7.1 Location\_\_c (Existing — Referenced)

No schema changes required. Referenced read-only by the LWC's Location tree and by `Tour_Availability__c.Location__c`.

| Field Label | API Name | Data Type | Standard/Custom | Required | Remarks |
|---|---|---|---|---|---|
| Name | `Name` | Text | Standard | Yes | Location display name |
| Active | `Active__c` | Checkbox | Custom | Yes | Only Active locations are selectable in the tree |
| Channel | `Channel__c` *(assumed)* | Picklist/Lookup | Custom | — | Drives the channel grouping shown in the mock-up tree (Walt Disney World, Disneyland, Aulani, Virtual). **Assumed to exist; confirm actual field — see Section 19, Item 6.** |

### 7.2 Tour_Availability\_\_c (Existing — Extended)

**Purpose:** Represents a day's operating schedule for a specific location. One record is created per Location + Availability Date combination during Publish.

**Relationship:** `Location__c` (1) —< `Tour_Availability__c` (Many)

| Field Label | API Name | Data Type | Standard/Custom | Required | Field Level Security | Field Tracking | Remarks/Description |
|---|---|---|---|---|---|---|---|
| Location | `Location__c` | Lookup(Location\_\_c) | Custom | Yes | Edit (Business Admin/Ops) | Yes | Parent location |
| Availability Date | `Availability_Date__c` | Date | Custom | Yes | Edit | Yes | Date for which slots are generated |
| Operating Start Time | `Operating_Start_Time__c` | Time | Custom | Yes | Edit | Yes | Must be earlier than Operating End Time (UAC3) |
| Operating End Time | `Operating_End_Time__c` | Time | Custom | Yes | Edit | Yes | Must be later than Operating Start Time (UAC3) |
| Tour Duration (mins) | `Tour_Duration__c` **[NEW]** | Number(4,0) | Custom | Yes | Edit | Yes | Drives slot end time and final-slot cutoff (Section 10) |
| Slot Interval | `Slot_Interval__c` **[NEW]** | Picklist | Custom | Yes | Edit | Yes | Values: `15 Minutes`, `30 Minutes`, `60 Minutes` (UAC12–16) |
| Lunch Block Needed | `Lunch_Block_Needed__c` **[NEW]** | Checkbox | Custom | No (default unchecked) | Edit | Yes | Reveals Lunch Start/End on the UI (UAC5) |
| Lunch Start Time | `Lunch_Start_Time__c` **[NEW]** | Time | Custom | Conditional (if Lunch Block Needed = true) | Edit | Yes | Must fall within Operating Start–End window (UAC6) |
| Lunch End Time | `Lunch_End_Time__c` **[NEW]** | Time | Custom | Conditional (if Lunch Block Needed = true) | Edit | Yes | Must be > Lunch Start and within Operating window (UAC6) |
| Online Tour Booking Enabled | `Online_Tour_Booking_Enabled__c` **[NEW]** | Checkbox | Custom | No (default unchecked) | Edit | Yes | Drives split Onsite/Online capacity capture & display (Business Decision #3) |
| Total Slots | `Total_Slots__c` | Number(4,0) | Custom | System-calculated | Read | Yes | Count of generated slots for the day |
| Slot Type | `Slot_Type__c` | Picklist | Custom | Yes | Edit | Yes | Values: `Onsite`, `Event`. This story only creates `Onsite` records; `Event` is populated by the separate Event/Group story sharing this object. |
| Generation Status | `Generation_Status__c` **[NEW]** | Picklist | Custom | System-managed | Read | Yes | Values: `Published`. (Preview does not create a record; see Section 19, Item 4 for open scope question on whether a `Draft` status is needed.) |
| Location + Date Key | `Location_Date_Key__c` | Text(255), External ID, Unique | Custom | System-managed | Read | No | Composite key (`Location__c` + `Availability_Date__c`) used to enforce the uniqueness constraint (Section 15) |

### 7.3 Tour_Availability_Slot\_\_c (Existing — Extended)

**Purpose:** Represents an individual bookable time slot generated under a Tour Availability record.

**Relationship:** `Tour_Availability__c` (1) —< `Tour_Availability_Slot__c` (Many)

| Field Label | API Name | Data Type | Standard/Custom | Required | Field Level Security | Field Tracking | Remarks/Description |
|---|---|---|---|---|---|---|---|
| Tour Availability | `Tour_Availability__c` | Lookup/Master-Detail | Custom | Yes | Edit | Yes | Parent Tour Availability record |
| Slot Start DateTime | `Slot_Start_DateTime__c` | DateTime | Custom | Yes | Edit | Yes | Slot start |
| Slot End DateTime | `Slot_End_DateTime__c` | DateTime | Custom | Yes | Edit | Yes | Slot start + Tour Duration |
| Total Online Capacity | `Total_Online_Capacity__c` | Number(4,0) | Custom | Conditional (if Online Tour Booking Enabled = true) | Edit | Yes | 0 when Online Tour Booking is disabled at the parent (Business Decision #3) |
| Total Onsite Capacity | `Total_Onsite_Capacity__c` | Number(4,0) | Custom | Yes | Edit | Yes | Always captured; sole visible capacity field when Online Tour Booking is disabled |
| Booked Online Slots | `Booked_Online_Slots__c` | Number(4,0), default 0 | Custom | System-managed | Read (booking engine writes) | Yes | Owned by the booking engine, not this generator |
| Booked Onsite Slots | `Booked_Onsite_Slots__c` | Number(4,0), default 0 | Custom | System-managed | Read | Yes | Owned by the booking engine |
| Remaining Online Slots | `Remaining_Online_Slots__c` **[NEW]** | Formula (Number) | Custom | N/A | Read | No | `Total_Online_Capacity__c - Booked_Online_Slots__c` |
| Remaining Onsite Slots | `Remaining_Onsite_Slots__c` **[NEW]** | Formula (Number) | Custom | N/A | Read | No | `Total_Onsite_Capacity__c - Booked_Onsite_Slots__c` |
| Is Lunch Block | `Is_Lunch_Block__c` **[NEW]** | Checkbox | Custom | System-managed | Read | Yes | True when this slot overlaps the parent's Lunch window; capacities forced to 0 (UAC7) |
| Status | `Status__c` | Picklist | Custom | System-managed | Read | Yes | Values: `Open`, `Closed`. Lunch-block slots are set to `Closed`. |

---

## 8. LWC Design — Tour Availability Generator

### 8.1 Input Fields & Conditional Behavior

| Field | Component | Default | Conditional Behavior |
|---|---|---|---|
| Tour Locations | Tree (existing component, checkbox multi-select, grouped by Channel) | none selected | Generate button disabled until ≥ 1 selected (UAC1) |
| Start Date | `lightning-input type="date"` | none | Must be ≤ today + 90 days (business rule) and ≤ End Date (UAC2) |
| End Date | `lightning-input type="date"` | none | Must be ≥ Start Date (UAC2) |
| Opening Time | `lightning-input type="time"` | none | Must be < Closing Time (UAC3) |
| Closing Time | `lightning-input type="time"` | none | Must be > Opening Time (UAC3) |
| Tour Duration | `lightning-combobox` | 60 mins | Drives slot end time (UAC11) |
| Tour Slot Increment | `lightning-combobox` (15/30/60 min) | 30 mins | Drives slot cadence (UAC12–16) |
| Lunch Block Needed? | `lightning-input type="toggle"` | unchecked | When checked, reveals Lunch Start / Lunch End (UAC5) |
| Lunch Start / Lunch End | `lightning-input type="time"` | none | Conditionally required + validated (UAC6) |
| Online Tour Booking | `lightning-input type="toggle"` | unchecked | **Unchecked:** form shows a single **Onsite Capacity** input and the preview renders a single **Tour Slots** column (UAC9). **Checked:** form shows both **Online Capacity** and **Onsite Capacity** inputs and the preview splits into **Onsite** / **Online** columns (UAC8). |
| Onsite Capacity | `lightning-input type="number"` | none | Always required |
| Online Capacity | `lightning-input type="number"` | none | Required only when Online Tour Booking is enabled; must be ≤ Onsite Capacity (UAC10, Business Decision #4) |
| Generate & Preview Schedule | `lightning-button variant="brand"` | disabled | Enabled only when all required fields above are valid |

### 8.2 Schedule Preview Grid

- Renders in the right-hand panel of the same screen (no navigation) immediately after client-side generation (UAC17).
- One row per generated time slot (per Section 10.2's worked example), rendered for a single representative day (see Section 19, Item 5 for the open question on multi-day preview).
- **Online Tour Booking disabled:** single `TOUR SLOTS` column showing `Total_Onsite_Capacity__c` (or 0 for lunch-blocked slots).
- **Online Tour Booking enabled:** two columns, `ONSITE` and `ONLINE`, showing `Total_Onsite_Capacity__c` and `Total_Online_Capacity__c` respectively (0 for lunch-blocked slots).
- Editing input fields after a preview (e.g., changing Onsite Capacity) does not clear other field values; only the preview panel re-renders on the next Generate click (UAC19).

---

## 9. Validation Rules

| ID | Rule | Trigger Point | Message (indicative) |
|---|---|---|---|
| VR-01 | At least one Tour Location must be selected | Client-side (LWC), disables Generate button | "Select at least one Tour Location to continue." |
| VR-02 | Start Date ≤ End Date | Client-side + Apex (defense in depth) | "End Date must be on or after Start Date." |
| VR-03 | Start Date ≤ TODAY + 90 days | Client-side + Apex | "Start Date cannot be more than 90 days in the future." |
| VR-04 | Opening Time < Closing Time | Client-side + Apex | "Closing Time must be later than Opening Time." |
| VR-05 | If Lunch Block Needed = true: Lunch Start and Lunch End are populated, Lunch End > Lunch Start, both within [Opening Time, Closing Time] | Client-side + Apex | "Enter a valid Lunch Start and Lunch End within the operating hours." |
| VR-06 | If Online Tour Booking Enabled = true: Online Capacity ≤ Onsite Capacity | Client-side + Apex | "Online Tour Booking Slots cannot exceed Total Onsite Slots." |
| VR-07 | Tour Duration > 0 | Client-side + Apex | "Tour Duration must be greater than zero." |
| VR-08 | Onsite Capacity ≥ 0; Online Capacity ≥ 0 (when applicable) | Client-side + Apex | "Capacity values cannot be negative." |
| VR-09 | No existing `Tour_Availability__c` for the same Location + Availability Date (on Publish only) | Apex (`publishSchedule`), enforced via `Location_Date_Key__c` unique field | "A schedule already exists for <Location> on <Date>. Regeneration is not currently supported." |

VR-01 through VR-08 are enforced identically on the client (for responsive UX) and re-validated in Apex before Publish, since Apex must never trust client-only validation (defense in depth, per input-validation best practice).

---

## 10. Slot Generation Logic

### 10.1 Algorithm

```
FOR EACH selected Location L:
  FOR EACH Date D from Start Date to End Date:
    IF Tour_Availability already exists for (L, D):
      SKIP (or raise VR-09 on Publish)
    Create/compute Tour_Availability record for (L, D):
      Operating_Start_Time, Operating_End_Time, Tour_Duration,
      Slot_Interval, Lunch_Block fields, Online_Tour_Booking_Enabled

    slotStart = Operating_Start_Time
    WHILE (slotStart + Tour_Duration) <= Operating_End_Time:
      slotEnd = slotStart + Tour_Duration
      isLunch = Lunch_Block_Needed AND
                (slotStart < Lunch_End_Time) AND (slotEnd > Lunch_Start_Time)

      IF isLunch:
        onsiteCapacity = 0
        onlineCapacity = 0
        status = "Closed"
      ELSE:
        onsiteCapacity = input Onsite Capacity
        onlineCapacity = Online_Tour_Booking_Enabled ? input Online Capacity : 0
        status = "Open"

      Create Tour_Availability_Slot(
        Slot_Start_DateTime = D + slotStart,
        Slot_End_DateTime   = D + slotEnd,
        Total_Onsite_Capacity = onsiteCapacity,
        Total_Online_Capacity = onlineCapacity,
        Is_Lunch_Block = isLunch,
        Status = status
      )

      slotStart = slotStart + Slot_Interval
```

**Note on Slot Interval vs. Tour Duration:** the HLD's worked example conflates these two values inconsistently. This LLD implements Slot Interval strictly as the **step size** for `slotStart` (per UAC12–16, tested at 15/30/60 minutes) and Tour Duration strictly as the **length** of each slot. This resolves the HLD's internal contradiction but should be explicitly confirmed with the HLD author (Section 19, Item 1).

### 10.2 Worked Example

Given: Opening 08:30 AM, Closing 04:00 PM, Tour Duration = 60 mins, Slot Interval = 30 mins, Lunch 12:30 PM–01:30 PM, Onsite Capacity = 5, Online Capacity = 2 (Online Tour Booking enabled):

| Slot | Onsite | Online | Status |
|---|---|---|---|
| 08:30–09:30 | 5 | 2 | Open |
| 09:00–10:00 | 5 | 2 | Open |
| 09:30–10:30 | 5 | 2 | Open |
| ... | ... | ... | ... |
| 12:00–01:00 | 0 | 0 | Closed (overlaps lunch) |
| 12:30–01:30 | 0 | 0 | Closed (overlaps lunch) |
| 01:00–02:00 | 0 | 0 | Closed (overlaps lunch) |
| 01:30–02:30 | 5 | 2 | Open |
| ... | ... | ... | ... |
| Final slot begins at Closing Time − Tour Duration = 03:00 PM | 5 | 2 | Open |

### 10.3 Lunch Block Handling

A slot is treated as a lunch-block slot (`Is_Lunch_Block__c = true`, capacities forced to 0, `Status__c = Closed`) whenever its `[Slot_Start, Slot_End)` interval **overlaps** `[Lunch_Start_Time, Lunch_End_Time)`, satisfying UAC7 ("all time slots falling within the Lunch Start–Lunch End window appear ... as 0 Tour Slots"). The slot row is still generated and displayed — it is not omitted from the preview or from persisted records.

### 10.4 Duplicate / Re-generation Handling

Per HLD Section 7 and VR-09: if a `Tour_Availability__c` already exists for a Location + Date being published, generation for that specific Location/Date is blocked and the user is notified. **Overwrite/replace of existing availability is explicitly deferred** as a future enhancement per the HLD, and is not implemented in this story. See Section 19, Item 7 for the open question on desired UX when a partial date range overlaps existing availability (e.g., 5 of 7 days already exist).

---

## 11. Apex Design

### 11.1 Apex Classes

| Class | Type | Responsibility |
|---|---|---|
| `TourAvailabilityGeneratorController` | `with sharing`, `@AuraEnabled` controller | Entry point for the LWC; delegates validation and orchestrates preview/publish |
| `TourAvailabilityValidationService` | `with sharing` service class | Implements VR-01–VR-09 server-side |
| `TourSlotGenerationService` | `with sharing` service class | Pure slot-generation logic (Section 10), reusable by both preview (if ever server-rendered) and the batch job |
| `TourSlotGenerationBatch` | `Database.Batchable<SObject>`, `Database.Stateful` | Iterates selected Location + Date combinations, bulk-inserts `Tour_Availability__c` and `Tour_Availability_Slot__c` records in governor-limit-safe chunks |
| `TourAvailabilityGeneratorControllerTest` / `TourSlotGenerationBatchTest` | Test classes | ≥ 90% coverage, bulk (200+ record) test scenarios |

### 11.2 Key Method Signatures

```apex
public with sharing class TourAvailabilityGeneratorController {

    @AuraEnabled
    public static ValidationResult validateRequest(GenerationRequest request) { }

    @AuraEnabled
    public static Id publishSchedule(GenerationRequest request) {
        // Enqueues TourSlotGenerationBatch, returns AsyncApexJob Id
    }
}
```

`GenerationRequest` (Apex inner class / wrapper) mirrors the LWC form: `locationIds`, `startDate`, `endDate`, `openingTime`, `closingTime`, `tourDurationMinutes`, `slotIntervalMinutes`, `lunchBlockNeeded`, `lunchStart`, `lunchEnd`, `onlineTourBookingEnabled`, `onsiteCapacity`, `onlineCapacity`.

All input (dates, times, numeric capacities) is treated as untrusted and re-validated server-side in `TourAvailabilityValidationService` before any DML — the client-side checks in Section 9 are a UX convenience only, not a security boundary. No dynamic SOQL/DML string concatenation is used; all queries use bind variables.

### 11.3 Asynchronous Processing (Batch Apex)

- `TourSlotGenerationBatch.start()` returns a `QueryLocator`/iterable over the `(Location, Date)` pairs requested.
- `execute()` processes one Location+Date per governor-limit-safe chunk, builds `Tour_Availability__c` + child `Tour_Availability_Slot__c` records in bulk-safe lists, and performs DML in batches (per HLD Section 9 design consideration).
- `finish()` publishes a Platform Event (or updates a tracking record) so the LWC can surface a success/failure toast without polling indefinitely.
- Chosen over a plain `Queueable` for volumes spanning many locations × a 90-day range × sub-hour slot intervals, which can exceed single-transaction DML/heap limits.

---

## 12. Automation / Scheduled Jobs

| Name | Type | Trigger | Purpose |
|---|---|---|---|
| *(Name TBD)* | Scheduled Apex / Flow | Every 24 hours | Implements the story's business rule "Clone the Schedule every 24 hours." **Mechanism and exact semantics are not yet defined — see Section 19, Item 8.** |

---

## 13. Permission Sets

| Permission Set | Grants | Assigned To |
|---|---|---|
| `DVC_Tour_Availability_Management` *(new, proposed)* | Read/Create on `Tour_Availability__c`, `Tour_Availability_Slot__c`; Read on `Location__c`; access to the Tour Availability Generator LWC tab/Flexi Page | Business Admin, Operations (via existing DVC permission set group — confirm mapping, Section 19 Item 9) |

No profile-level access is granted; access is exclusively via permission set, consistent with the pattern used in the Guide License LLD reference document.

---

## 14. Reporting

- Use standard/custom report types on `Tour_Availability__c` and `Tour_Availability_Slot__c` (e.g., "Tour Availability with Slots") to allow Operations to report on generated capacity, lunch-blocked slots, and Onsite vs. Online capacity split by Location and Date.
- New fields flagged `Yes` for "Auto add to custom report type" in Section 7 tables should be included by default in these report types.

---

## 15. Uniqueness Rules

- **`Location__c` + `Availability_Date__c` must be unique** on `Tour_Availability__c`, enforced via the `Location_Date_Key__c` external ID/unique text field (populated by a `before insert/update` trigger or Flow that concatenates `Location__c` + `Availability_Date__c`), mirroring the composite-key pattern used for `DVC_Unique_SRS__c` in the Guide License reference LLD.
- This prevents duplicate availability generation for the same Location/Date (HLD Section 7, VR-09).

---

## 16. Flexi Pages & Compact Layout

| Item | Change |
|---|---|
| Tour Availability Generator App Page | New Lightning App Page (or embedded Utility/Tab) hosting the LWC described in Section 8. |
| Tour Availability Record Page | No changes anticipated beyond standard related-list exposure of child `Tour_Availability_Slot__c` records. |
| Compact Layout | No changes anticipated; default layout sufficient for admin review of generated availability. |

---

## 17. Acceptance Criteria Traceability Matrix

| UAC | Summary | LLD Coverage |
|---|---|---|
| UAC1 | Generate disabled with no location selected | Section 8.1 (Tree component + button disable logic), VR-01 |
| UAC2 | Date range validation | VR-02 |
| UAC3 | Opening/Closing time validation | VR-04 |
| UAC4 | Guide-driven capacity | **Superseded by Business Decision #1** — capacity is entered directly (Section 7.3), not guide-derived |
| UAC5 | Lunch Block reveal | Section 8.1 |
| UAC6 | Lunch Block validation | VR-05 |
| UAC7 | Lunch reflected as 0 in preview | Section 10.3 |
| UAC8 | Online Tour Booking indicator reveals fields | Section 8.1, Business Decision #3 |
| UAC9 | Online unchecked → Onsite-only display | Section 8.1/8.2, Business Decision #3 |
| UAC10 | Online ≤ Onsite validation | VR-06, Business Decision #4 |
| UAC11 | Tour Duration drives interval length | Section 10.1 |
| UAC12 | Tour Slot Increment field (15/30/60) | Section 7.2 (`Slot_Interval__c`) |
| UAC13–15 | 60/30/15-minute slot generation | Section 10.1–10.2 |
| UAC16 | Slot cadence matches selected increment | Section 10.1 |
| UAC17 | In-place preview update | Section 8.2, Section 4.2 step 5 |
| UAC18 | Multi-location generation | Section 10.1 (outer loop over Locations) |
| UAC19 | Field persistence during session | Section 8.2 (LWC component state retained across re-generation) |
| BR-1 | Start Date ≤ today + 90 days | VR-03 |
| BR-2 | Clone schedule every 24 hours | Section 12 (mechanism open — Section 19, Item 8) |

---

## 18. Security & Compliance Considerations

- All Apex classes use `with sharing` to respect org sharing rules; no `without sharing` escalation is required for this feature.
- Field-Level Security and object permissions are granted exclusively through the `DVC_Tour_Availability_Management` permission set (Section 13) — no direct profile grants.
- All user-supplied input (dates, times, numeric capacities, Location Ids) is re-validated server-side in `TourAvailabilityValidationService` before use in any SOQL/DML; no dynamic SOQL is constructed from raw user input.
- No PII/PHI/PCI data is introduced by this feature (`Tour_Availability__c` / `Tour_Availability_Slot__c` contain only scheduling/capacity metadata).
- Batch Apex respects governor limits via chunked DML (Section 11.3); no unbounded queries against user-controlled date ranges are executed without the 90-day cap (VR-03) acting as a natural volume guard.

---

## 19. Open Items / Assumptions Requiring Business Confirmation

These items were raised during HLD review and remain **unanswered**. This LLD makes an explicit, labeled assumption for each so design/build can proceed; please confirm or correct each before or during implementation.

| # | Topic | Assumption Made in This LLD | Needs Confirmation From |
|---|---|---|---|
| 1 | Slot Interval vs. Tour Duration semantics (HLD's example is self-contradictory) | Slot Interval = step size between slot starts; Tour Duration = length of each slot (Section 10.1) | Business / HLD author |
| 2 | Slot generation model: overlapping slots (HLD's literal example) vs. non-overlapping, occupancy-blocked slots (mock-up) | Overlapping slots are generated at every Slot Interval step, each independently capacitated (per flat-capacity model, Business Decision #1) | Business |
| 3 | Are generated preview slot values editable inline, or strictly read-only? | Read-only preview (Section 3.2, Out of Scope) | Product/UX |
| 4 | Is "Publish" (persisting records via Batch Apex) in scope for DMS-4909, given the mock-ups show no Publish button? | Assumed **in scope**, since the HLD explicitly designs it; `Generation_Status__c` currently only models `Published`. If Publish is deferred to another story, remove Section 4.2 step 7 and the Batch Apex components from this story's build. | Product/Business |
| 5 | Does the Schedule Preview render one representative day (per HLD Section 5: "Preview 1 day slot generated on the UI") or every day in the selected range? | One representative day rendered in the LWC preview grid; full range is only materialized at Publish time | Product/UX |
| 6 | Does `Location__c` already have a Channel/grouping field to support the tree's grouping (Walt Disney World, Disneyland, Aulani, Virtual)? | Assumed to exist as `Channel__c`; not verified against actual org metadata | Salesforce Admin/Architect |
| 7 | Desired behavior when only part of a multi-day range already has existing `Tour_Availability__c` records | Assumed: block the entire publish and list conflicting Location/Date pairs to the user (no partial publish) | Business |
| 8 | Mechanism and exact semantics of "Clone the Schedule every 24 hours" | Not yet designed beyond a placeholder Scheduled Apex/Flow (Section 12) | Business |
| 9 | Confirm `DVC Business Admin` / Operations permission set group mapping for the new `DVC_Tour_Availability_Management` permission set | Assumed analogous to the Guide License LLD's `DVC_License_Management` pattern | Salesforce Admin |
| 10 | Timezone handling across multi-timezone locations (WDW, Disneyland, Aulani, Virtual) | Not yet resolved; `Operating_Start_Time__c`/`Lunch_*_Time__c` are Time fields with no explicit timezone context in this LLD | Business/Architect |

---

## 20. Appendix

### 20.1 Jira Stories

| Jira Story | Summary |
|---|---|
| DMS-4909 | Tour Availability Generator — Schedule Creation (this story) |
| DMS-4987 | Clone of DMS-4909 (per issue links) |
| DMS-2835 | Parent Epic — Cast Workflow Management \| Tour Booking & Management |
| *(TBD)* | Event/Group tab story (referenced as out of scope, exact key not yet provided) |

### 20.2 List of Figures

1. Figure 1 — Solution Architecture (Section 4.1)
2. Figure 2 — Existing Enterprise Tour Booking Data Model (Section 5.1)
3. Figure 3 — DMS-4909 Object Relationship Diagram (Section 5.2)

### 20.3 Referenced Documents

- DMS-4909 HLD: "Tour Slots Generator"
- DMS-4909 Jira export (acceptance criteria, field inventory, business rules)
- Tour Availability Generator UI mock-ups (Onsite mode; Online Tour Booking enabled mode)
- Tour Booking data model architecture diagram (ERD)
- "Ability to Manage Guide License Data" LLD (used as structural/format reference for this document)
