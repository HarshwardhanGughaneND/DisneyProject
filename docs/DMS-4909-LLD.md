# DMS-4909: Tour Availability Generator — Schedule Creation

## Low-Level Design (LLD) — Revision 2

**Jira Story:** [DMS-4909](https://disneyexperiences.atlassian.net/browse/DMS-4909)
**Epic:** DMS-2835 — Business Capabilities | Cast Workflow Management | Tour Booking & Management
**Source of Truth for This Revision:** Jira story text (description, Field Inventory, Acceptance Criteria, Business Rules) + the two UI mock-up screenshots + business Q&A dated 2026-08-17 (Section 19)
**Document Format Reference:** *Ability to Manage Guide License Data* (LLD template)
**Status:** Draft — one open item pending business (Section 20, Item 1)

> **Revision note:** Revision 1 of this LLD was aligned to a separate HLD document ("Tour Slots Generator") that proposed a flat, admin-entered Online/Onsite capacity model. Per explicit direction on 2026-08-17, that HLD has been set aside for this revision. This LLD is built strictly from the DMS-4909 story text, its Acceptance Criteria, the two UI mock-ups, and direct business clarification — restoring the **guide-shift-driven capacity model** that the story and mock-ups actually describe.

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
   - 4.2 Process Flow (Preview → Publish → Daily Auto-Extension)
5. Data Model Diagram
6. Core Salesforce Object Details
7. Detailed Data Model
   - 7.1 Location (Standard Object — Referenced)
   - 7.2 Tour_Availability\_\_c (New/Extended)
   - 7.3 Tour_Guide_Shift\_\_c (New)
   - 7.4 Tour_Availability_Slot\_\_c (New/Extended)
8. LWC Design — Tour Availability Generator
   - 8.1 Input Fields & Conditional Behavior
   - 8.2 Schedule Preview Grid
9. Validation Rules
10. Slot Generation Logic (Guide-Driven)
    - 10.1 Algorithm
    - 10.2 Worked Example
    - 10.3 Lunch Block Handling
    - 10.4 Online Capacity Handling
    - 10.5 Multi-Location Handling
11. Publish & Persistence Design
    - 11.1 Apex Classes
    - 11.2 Duplicate / Re-generation Handling
12. Rolling 90-Day Auto-Extension ("Clone") Job
13. Permission Sets
14. Reporting
15. Uniqueness Rules
16. Flexi Pages & Compact Layout
17. Acceptance Criteria Traceability Matrix
18. Security & Compliance Considerations
19. Decision Log (Business Q&A — 2026-08-17)
20. Open Items / Assumptions Still Pending
21. Appendix
    - 21.1 Jira Stories
    - 21.2 List of Figures
    - 21.3 Referenced Documents

---

## 2. Overview

### 2.1 Purpose

Enable Business Admins and Operations users to configure and generate a **projected tour availability schedule** for one or more pre-configured tour locations, across a date range, driven by Guide Shift staffing, so that guide/tour capacity can be previewed before being published for booking. The screen is a single-pane LWC: on-screen preview computation happens entirely client-side (no records created), and a distinct **Publish** action persists the schedule to Salesforce.

### 2.2 Background

As Business Admin, I want to configure and generate a projected tour availability schedule for one or more pre-configured tour locations, so that I can preview guide capacity and slot availability across a date range before publishing it for booking. As Operations, I need to manage availability.

Tour Locations are selected (not created) from a location tree already configured elsewhere. The user provides Availability Date Range, Opening/Closing Time, Guide Shifts, Lunch Block, Tour Duration, and Tour Slot Increment, then clicks **Generate & Preview Schedule**; the preview renders in the same screen (no navigation).

---

## 3. Scope

### 3.1 In Scope

- Single-screen LWC: Tour Location tree, "Onsite" configuration form, and in-place Schedule Preview grid.
- Guide Shifts as a **repeatable list** (add/remove shift rows, each with a time range and a guide-count stepper), driving slot capacity via guide-occupancy logic.
- Lunch Block configuration and its effect on generated slots (0 capacity).
- Online Tour Booking toggle, with a separate, admin-entered, editable **Online Capacity** input, capped ≤ the guide-derived **Onsite Capacity** for each slot (read-only).
- Client-side (LWC) preview computation with **no backend objects created** during preview.
- A **Publish** action that persists the generated schedule (`Tour_Availability__c`, `Tour_Guide_Shift__c`, `Tour_Availability_Slot__c`) to Salesforce via Apex.
- A backend, schedule-independent **daily rolling-window auto-extension job** that keeps published availability continuously covering a 90-day horizon per location.
- Validation rules per UAC1–UAC10 and the two story business rules.
- Duplicate-publish protection at Location + Availability Date grain.

### 3.2 Out of Scope

- The **Event/Group** tab and its configuration/generation logic — tracked as a **separate story**. This LLD implements the **Onsite** tab only; if a tab switcher is built, "Event/Group" is a stub pointing to that other story.
- Exact multi-shift validation rules (overlap handling, max shift count, gap handling) — **pending business clarification** (Section 20, Item 1). This LLD implements a reasonable default (Section 10.1) that must be revisited once confirmed.
- Any changes to the guest-facing booking engine that consumes `Booked_Online_Slots__c` / `Booked_Onsite_Slots__c`.
- Per-location distinct configuration in a single generation run (Section 10.5) — one shared configuration is applied to all selected locations.

---

## 4. Solution Architecture

### 4.1 Component Overview

```
+---------------------------------------------+
|   Tour Availability Generator (LWC)          |
|   - Location Tree (existing component)       |
|   - Config Form (Guide Shifts, Lunch, Online) |
|   - Schedule Preview Grid (client-computed)   |
+---------------------------------------------+
     |                                   |
     | (1) Generate & Preview            | (2) Publish
     | 100% client-side JS,              | Apex call
     | no Apex / no DML                  v
     |                        +--------------------------------------+
     |                        |  TourAvailabilityPublishController    |
     |                        |  (Apex, with sharing)                 |
     |                        |  - validatePublishRequest()           |
     |                        |  - publishSchedule()                  |
     |                        +--------------------------------------+
     |                                       |
     |                                       v
     |                        +--------------------------------------+
     |                        |  TourSlotGenerationBatch              |
     |                        |  (Database.Batchable, bulk-safe DML)  |
     |                        +--------------------------------------+
     |                                       |
     |                    ---------------------------------------
     |                    |                  |                  |
     v                    v                  v                  v
(preview only,     Tour_Availability__c  Tour_Guide_Shift__c  Tour_Availability_Slot__c
 no persistence)   (1 per Location+Date) (child, per shift)   (child, per generated slot)

+--------------------------------------+
|  TourAvailabilityDailyRolloverJob     |   <- Scheduled Apex, runs every 24 hours
|  (Section 12)                         |      independent of the LWC/Publish flow
+--------------------------------------+
```

### 4.2 Process Flow (Preview → Publish → Daily Auto-Extension)

1. User opens the Tour Availability Generator LWC and selects one or more Tour Locations from the tree (grouped by channel).
2. User completes the Onsite configuration form: Start/End Date, Opening/Closing Time, one or more Guide Shifts (time range + guide count, add/remove rows), optional Lunch Block (Lunch Start/End), Tour Duration, Tour Slot Increment, and optionally enables Online Tour Booking with an Online Capacity value.
3. Client-side validation (Section 9) gates the **Generate & Preview Schedule** button.
4. On click, the LWC runs the guide-driven slot generation algorithm (Section 10) **entirely in-browser** and renders the Schedule Preview grid in place — **no Apex call, no records created** (per business decision, Section 19 Q0).
5. The admin may adjust the editable **Online Capacity** value per row directly in the preview grid (Onsite remains read-only, guide-derived) and re-generate as needed; other field values persist across re-generation (UAC19).
6. When satisfied, the admin clicks **Publish** (new action, added per business decision — see Section 20, Item 2 for the still-needed UI/AC detail). This calls `TourAvailabilityPublishController.publishSchedule()`, which re-validates everything server-side and enqueues `TourSlotGenerationBatch` to persist `Tour_Availability__c`, `Tour_Guide_Shift__c`, and `Tour_Availability_Slot__c` records for every selected Location × Date in the range.
7. Independently of the interactive flow, `TourAvailabilityDailyRolloverJob` runs once every 24 hours and extends each location's published availability forward by one day, maintaining a continuously rolling 90-day horizon (Section 12).

---

## 5. Data Model Diagram

```
+---------------------------+
|   Location (Standard)     |   <- existing, no changes
+---------------------------+
| Id                         |
| Name                       |
| LocationType               |  Values include: Channel, Resorts, Suite
| ParentLocationId           |  Resort-type records point to their parent Channel record
+---------------------------+
             |
             | 1 : M  (Resorts are selectable in the Tour Location tree, grouped by parent Channel)
             v
+--------------------------------------+
|         Tour_Availability__c         |   NEW/EXTENDED
+--------------------------------------+
| Id                                    |
| Location__c (Lookup -> Location)      |
| Availability_Date__c                  |
| Operating_Start_Time__c               |
| Operating_End_Time__c                 |
| Tour_Duration__c                      |
| Slot_Interval__c                      |
| Lunch_Block_Needed__c                 |
| Lunch_Start_Time__c                   |
| Lunch_End_Time__c                     |
| Online_Tour_Booking_Enabled__c        |
| Online_Capacity_Input__c              |
| Total_Slots__c                        |
| Slot_Type__c (Onsite / Event)         |
| Location_Date_Key__c (unique)         |
+--------------------------------------+
        |                        |
        | 1 : M                  | 1 : M
        v                        v
+---------------------------+   +--------------------------------------+
|   Tour_Guide_Shift__c     |   |     Tour_Availability_Slot__c         |
+---------------------------+   +--------------------------------------+
| Id                         |   | Id                                    |
| Tour_Availability__c       |   | Tour_Availability__c                  |
| Shift_Start_Time__c        |   | Slot_Start_DateTime__c                |
| Shift_End_Time__c          |   | Slot_End_DateTime__c                  |
| Number_of_Guides__c        |   | Total_Onsite_Capacity__c (read-only)  |
+---------------------------+   | Total_Online_Capacity__c (editable)   |
                                 | Booked_Online_Slots__c                |
                                 | Booked_Onsite_Slots__c                |
                                 | Remaining_Online_Slots__c (formula)   |
                                 | Remaining_Onsite_Slots__c (formula)   |
                                 | Is_Lunch_Block__c                     |
                                 | Status__c (Open / Closed)             |
                                 +--------------------------------------+
```

**Note on Location:** per business confirmation (Q10), Tour Locations are **standard Salesforce `Location` records**, not a custom `Location__c` object. WDW, Disneyland, and Aulani are `Location` records with `LocationType = Channel`; the individual bookable resorts/tour sites are `Location` records with `LocationType = Resorts`, related to their parent Channel record. The Tour Location tree groups Resort-type records under their parent Channel record.

---

## 6. Core Salesforce Object Details

| Object Name | API Name | Description | Standard/Custom | Change Type |
|---|---|---|---|---|
| Location | `Location` | Standard object; Channel and Resort location master data. | Standard | No change |
| Tour Availability | `Tour_Availability__c` | One record per Location + Availability Date; stores operating hours, duration, interval, lunch, and online settings for that day. | Custom | New/Extend |
| Tour Guide Shift | `Tour_Guide_Shift__c` | One record per configured guide shift under a Tour Availability record. | Custom | **New** |
| Tour Availability Slot | `Tour_Availability_Slot__c` | One record per generated time slot. | Custom | New/Extend |

---

## 7. Detailed Data Model

### 7.1 Location (Standard Object — Referenced)

No schema changes required beyond what already exists. Referenced read-only by the LWC's Tour Location tree.

| Field Label | API Name | Data Type | Standard/Custom | Remarks |
|---|---|---|---|---|
| Location Name | `Name` | Text | Standard | Display name in the tree |
| Location Type | `LocationType` | Picklist | Standard (custom values) | `Channel` (WDW, Disneyland, Aulani, Virtual) vs. `Resorts` (individual bookable tour locations) vs. `Suite` (used elsewhere in the Tour Booking model) |
| Parent Location | `ParentLocationId` | Lookup(Location) | Standard | Links a `Resorts`-type record to its parent `Channel`-type record, driving the tree's grouping |

### 7.2 Tour_Availability\_\_c (New/Extended)

**Purpose:** Represents one day's operating schedule for one location; created only at Publish time (no record exists for preview-only generation).

**Relationship:** `Location` (1) —< `Tour_Availability__c` (Many)

| Field Label | API Name | Data Type | Standard/Custom | Required | Field Level Security | Field Tracking | Remarks/Description |
|---|---|---|---|---|---|---|---|
| Location | `Location__c` | Lookup(Location) | Custom | Yes | Edit | Yes | Parent location (standard object) |
| Availability Date | `Availability_Date__c` | Date | Custom | Yes | Edit | Yes | One day within the published range |
| Operating Start Time | `Operating_Start_Time__c` | Time | Custom | Yes | Edit | Yes | Must be < Operating End Time (UAC3) |
| Operating End Time | `Operating_End_Time__c` | Time | Custom | Yes | Edit | Yes | Must be > Operating Start Time (UAC3) |
| Tour Duration (mins) | `Tour_Duration__c` | Number(4,0) | Custom | Yes | Edit | Yes | Default 60; drives guide-occupancy window (Section 10.1) |
| Slot Interval | `Slot_Interval__c` | Picklist | Custom | Yes | Edit | Yes | Values: `15 Minutes`, `30 Minutes`, `60 Minutes`; default `30 Minutes` (UAC12–16) |
| Lunch Block Needed | `Lunch_Block_Needed__c` | Checkbox | Custom | No (default unchecked) | Edit | Yes | Reveals Lunch Start/End on the UI (UAC5) |
| Lunch Start Time | `Lunch_Start_Time__c` | Time | Custom | Conditional | Edit | Yes | Must be within Operating window (UAC6) |
| Lunch End Time | `Lunch_End_Time__c` | Time | Custom | Conditional | Edit | Yes | Must be > Lunch Start, within Operating window (UAC6) |
| Online Tour Booking Enabled | `Online_Tour_Booking_Enabled__c` | Checkbox | Custom | No (default unchecked) | Edit | Yes | Unchecked → single Tour Slots view; checked → Onsite + Online (UAC8/UAC9) |
| Online Capacity Input | `Online_Capacity_Input__c` | Number(4,0) | Custom | Conditional (if Online enabled) | Edit | Yes | Admin-entered starting value seeded onto every non-zero slot's `Total_Online_Capacity__c`; must be ≤ the guide-derived Onsite capacity (UAC10) |
| Total Slots | `Total_Slots__c` | Number(4,0) | Custom | System-calculated | Read | Yes | Count of generated child slots |
| Slot Type | `Slot_Type__c` | Picklist | Custom | Yes | Edit | Yes | This story only creates `Onsite` records; `Event` is populated by the separate Event/Group story reusing this object |
| Location + Date Key | `Location_Date_Key__c` | Text(255), External ID, Unique | Custom | System-managed | Read | No | Composite key enforcing uniqueness (Section 15) |

### 7.3 Tour_Guide_Shift\_\_c (New)

**Purpose:** Represents a single configured guide shift (time range + guide count) under a Tour Availability record. Supports the repeatable "Add Shift" UI shown in the mock-ups.

**Relationship:** `Tour_Availability__c` (1) —< `Tour_Guide_Shift__c` (Many)

| Field Label | API Name | Data Type | Standard/Custom | Required | Field Level Security | Field Tracking | Remarks/Description |
|---|---|---|---|---|---|---|---|
| Tour Availability | `Tour_Availability__c` | Master-Detail | Custom | Yes | Edit | Yes | Parent day's schedule |
| Shift Start Time | `Shift_Start_Time__c` | Time | Custom | Yes | Edit | Yes | Start of this guide shift |
| Shift End Time | `Shift_End_Time__c` | Time | Custom | Yes | Edit | Yes | End of this guide shift |
| Number of Guides | `Number_of_Guides__c` | Number(3,0) | Custom | Yes | Edit | Yes | **Default 2** (confirmed, overriding the story's Field Inventory default of 1); minimum 1; drives Onsite capacity for slots covered by this shift |

### 7.4 Tour_Availability_Slot\_\_c (New/Extended)

**Purpose:** Represents an individual generated time slot.

**Relationship:** `Tour_Availability__c` (1) —< `Tour_Availability_Slot__c` (Many)

| Field Label | API Name | Data Type | Standard/Custom | Required | Field Level Security | Field Tracking | Remarks/Description |
|---|---|---|---|---|---|---|---|
| Tour Availability | `Tour_Availability__c` | Master-Detail | Custom | Yes | Edit | Yes | Parent day's schedule |
| Slot Start DateTime | `Slot_Start_DateTime__c` | DateTime | Custom | Yes | Edit | Yes | Slot start |
| Slot End DateTime | `Slot_End_DateTime__c` | DateTime | Custom | Yes | Edit | Yes | Slot start + Tour Duration |
| Total Onsite Capacity | `Total_Onsite_Capacity__c` | Number(4,0) | Custom | System-computed | **Read-only** in the Generator UI (Q6) | Yes | Guide-derived; this **is** the "Total Onsite Slots" referenced in UAC9 — not a separate input (Q3) |
| Total Online Capacity | `Total_Online_Capacity__c` | Number(4,0) | Custom | Conditional | **Editable** per row in the preview grid (Q6) | Yes | Seeded from `Online_Capacity_Input__c`, capped ≤ `Total_Onsite_Capacity__c` for that row; admin can adjust per slot before Publish (UAC10) |
| Booked Online Slots | `Booked_Online_Slots__c` | Number(4,0), default 0 | Custom | System-managed | Read (booking engine writes) | Yes | Owned by the booking engine, not this generator |
| Booked Onsite Slots | `Booked_Onsite_Slots__c` | Number(4,0), default 0 | Custom | System-managed | Read | Yes | Owned by the booking engine |
| Remaining Online Slots | `Remaining_Online_Slots__c` | Formula (Number) | Custom | N/A | Read | No | `Total_Online_Capacity__c - Booked_Online_Slots__c` |
| Remaining Onsite Slots | `Remaining_Onsite_Slots__c` | Formula (Number) | Custom | N/A | Read | No | `Total_Onsite_Capacity__c - Booked_Onsite_Slots__c` |
| Is Lunch Block | `Is_Lunch_Block__c` | Checkbox | Custom | System-managed | Read | Yes | True when this slot overlaps the Lunch window; capacities forced to 0 (UAC7) |
| Status | `Status__c` | Picklist | Custom | System-managed | Read | Yes | Values: `Open`, `Closed`. Lunch-block slots are `Closed`. |

---

## 8. LWC Design — Tour Availability Generator

### 8.1 Input Fields & Conditional Behavior

| Field | Component | Default | Conditional Behavior |
|---|---|---|---|
| Tour Locations | Tree (existing component, multi-select, grouped by parent Channel `Location`) | none selected | Generate button disabled until ≥ 1 selected (UAC1) |
| Start Date | `lightning-input type="date"` | none | ≤ today + 90 days and ≤ End Date (UAC2, BR-1) |
| End Date | `lightning-input type="date"` | none | ≥ Start Date (UAC2) |
| Opening Time | `lightning-input type="time"` | none | < Closing Time (UAC3) |
| Closing Time | `lightning-input type="time"` | none | > Opening Time (UAC3) |
| Guide Shifts | Repeatable row list: `lightning-input type="time"` (start/end) + stepper (guide count) + delete icon + "+ Add Shift" button | One row, **2 guides** (confirmed default), matching the Shift Time to Opening–Closing | ≥ 1 shift required; ≥ 1 guide per shift; overlap/gap rules pending business (Section 20, Item 1) |
| Lunch Block Needed? | `lightning-input type="toggle"` | unchecked | Reveals Lunch Start / Lunch End (UAC5) |
| Lunch Start / Lunch End | `lightning-input type="time"` | none | Conditionally required + validated (UAC6) |
| Tour Duration | `lightning-combobox` | 60 mins | Drives guide-occupancy window (UAC11) |
| Tour Slot Increment | `lightning-combobox` (15/30/60 min) | 30 mins | Drives slot cadence (UAC12–16) |
| Online Tour Booking | `lightning-input type="toggle"` | unchecked | **Unchecked:** single **Tour Slots** column/view, guide-derived only. **Checked:** reveals an **Online Capacity** numeric input; preview splits into **Onsite** (read-only) and **Online** (editable) columns (UAC8/UAC9). |
| Online Capacity | `lightning-input type="number"` | none | Visible only when Online Tour Booking is enabled; must be ≤ guide-derived Onsite capacity (UAC10) |
| Generate & Preview Schedule | `lightning-button variant="brand"` | disabled | Enabled only when all required fields above are valid; triggers client-side generation only (no Apex call) |
| Publish | `lightning-button variant="brand"` *(new — see Section 20, Item 2)* | disabled until a preview has been generated | Invokes Apex to persist the schedule (Section 11) |

### 8.2 Schedule Preview Grid

- Renders in place immediately after client-side generation (UAC17); no navigation/reload.
- Rendered as **one single, generic grid** even when multiple locations are selected (Q5) — since all selected locations share the same entered configuration (Guide Shifts, hours, duration, interval, lunch, online settings), the grid shows one representative pattern of generated slots for that shared configuration; at Publish, this same configuration is persisted separately per selected Location × Date (Section 10.5).
- **Online Tour Booking disabled:** single `TOUR SLOTS` column showing the guide-derived `Total_Onsite_Capacity__c` (read-only) — 0 for lunch-blocked or guide-occupied slots.
- **Online Tour Booking enabled:** two columns:
  - `ONSITE` — guide-derived, **read-only** (Q6).
  - `ONLINE` — seeded from the admin's Online Capacity input, **editable per row** (Q6), still constrained to ≤ the row's Onsite value (UAC10) even after manual edit.
- Editing any configuration field after a preview does not clear other field values; only the preview panel refreshes on the next Generate click (UAC19).

---

## 9. Validation Rules

| ID | Rule | Enforced | Message (indicative) |
|---|---|---|---|
| VR-01 | At least one Tour Location must be selected | Client (LWC) | "Select at least one Tour Location to continue." |
| VR-02 | Start Date ≤ End Date | Client + Apex (Publish) | "End Date must be on or after Start Date." |
| VR-03 | Start Date ≤ TODAY + 90 days | Client + Apex | "Start Date cannot be more than 90 days in the future." |
| VR-04 | Opening Time < Closing Time | Client + Apex | "Closing Time must be later than Opening Time." |
| VR-05 | Each Guide Shift: Shift End > Shift Start; ≥ 1 guide | Client + Apex | "Enter a valid shift time range and guide count." |
| VR-06 | If Lunch Block Needed = true: Lunch Start and Lunch End populated, Lunch End > Lunch Start, both within [Opening, Closing] | Client + Apex | "Enter a valid Lunch Start and Lunch End within the operating hours." |
| VR-07 | If Online Tour Booking Enabled = true: Online Capacity ≤ guide-derived Onsite Capacity, for the initial input and for any subsequent per-row edit | Client + Apex | "Online Tour Booking Slots cannot exceed Total Onsite Slots." |
| VR-08 | Tour Duration > 0 | Client + Apex | "Tour Duration must be greater than zero." |
| VR-09 | Capacities are non-negative | Client + Apex | "Capacity values cannot be negative." |
| VR-10 | No existing `Tour_Availability__c` for the same Location + Availability Date (checked only on Publish) | Apex (`publishSchedule`), via `Location_Date_Key__c` unique field | "A schedule already exists for \<Location\> on \<Date\>. Regeneration is not currently supported." |

VR-01–VR-09 are enforced identically on the client (for responsive UX during preview) and re-validated in Apex before any DML at Publish time, since Apex must never trust client-only validation.

---

## 10. Slot Generation Logic (Guide-Driven)

### 10.1 Algorithm

```
FOR EACH selected Location L:
  Guide_Shifts = the configured list of shifts (Shift_Start, Shift_End, Number_of_Guides)

  slotStart = Operating_Start_Time
  nextAvailableTime = Operating_Start_Time   // tracks when guides next free up

  WHILE (slotStart + Tour_Duration) <= Operating_End_Time:
    slotEnd = slotStart + Tour_Duration

    // Determine active shift(s) covering this slot's start time
    activeShifts = Guide_Shifts WHERE Shift_Start <= slotStart AND slotEnd <= Shift_End
    guideCapacity = SUM(Number_of_Guides for activeShifts)   // default: shifts don't overlap; see Section 20, Item 1

    isLunch = Lunch_Block_Needed AND (slotStart < Lunch_End_Time) AND (slotEnd > Lunch_Start_Time)

    IF guideCapacity == 0 OR isLunch:
      onsiteCapacity = 0
    ELSE IF slotStart >= nextAvailableTime:
      onsiteCapacity = guideCapacity
      nextAvailableTime = slotStart + Tour_Duration   // guides occupied until this tour completes
    ELSE:
      onsiteCapacity = 0   // guides still occupied by the previous tour

    onlineCapacity = (Online_Tour_Booking_Enabled AND onsiteCapacity > 0)
                       ? MIN(Online_Capacity_Input, onsiteCapacity)
                       : 0

    status = (onsiteCapacity == 0) ? "Closed" : "Open"

    RENDER/CREATE slot:
      Slot_Start = slotStart, Slot_End = slotEnd,
      Total_Onsite_Capacity = onsiteCapacity,
      Total_Online_Capacity = onlineCapacity,
      Is_Lunch_Block = isLunch,
      Status = status

    slotStart = slotStart + Slot_Interval
```

This directly reproduces the behavior confirmed in the mock-ups: a slot only shows non-zero capacity when it aligns with a guide-availability boundary (start of shift, or `Tour_Duration` after the last tour started), and the "0" values previously mis-rendered as "C" are exactly the guide-occupied and lunch-blocked slots.

### 10.2 Worked Example

Given: Opening 08:30 AM, Closing 04:00 PM, Tour Duration = 90 mins, Slot Interval = 30 mins, one Guide Shift 08:30 AM–04:00 PM with 2 guides, Lunch 12:30 PM–01:30 PM, Online Tour Booking enabled with Online Capacity input = 1:

| Slot Start | Onsite (read-only) | Online (editable, seeded) | Status | Reason |
|---|---|---|---|---|
| 08:30 AM | 2 | 1 | Open | Shift start; guides free |
| 09:00 AM | 0 | 0 | Closed | Guides occupied (tour ends 10:00) |
| 09:30 AM | 0 | 0 | Closed | Guides occupied |
| 10:00 AM | 2 | 1 | Open | Guides free again |
| 10:30 AM | 0 | 0 | Closed | Guides occupied |
| 11:00 AM | 0 | 0 | Closed | Guides occupied |
| 11:30 AM | 2 | 1 | Open | Guides free again |
| 12:00 PM | 0 | 0 | Closed | Overlaps Lunch |
| 12:30 PM | 0 | 0 | Closed | Overlaps Lunch |
| 01:00 PM | 0 | 0 | Closed | Overlaps Lunch |
| 01:30 PM | 2 | 1 | Open | Guides free (occupancy timer resumes after lunch) |
| ... | ... | ... | ... | ... |

This matches the confirmed mock-up pattern exactly (Section 10.4/UAC13–16 apply the same logic at 15/60-minute increments).

### 10.3 Lunch Block Handling

A slot is a lunch-block slot whenever its `[Slot_Start, Slot_End)` interval overlaps `[Lunch_Start_Time, Lunch_End_Time)`. It is still generated and shown as a row with 0/0 capacity and `Status = Closed` (UAC7) — never omitted from the grid.

### 10.4 Online Capacity Handling

- `Online_Capacity_Input__c` is a single value entered once per generation run (Q4), seeded onto every slot's `Total_Online_Capacity__c` where `Total_Onsite_Capacity__c > 0`, capped at that slot's Onsite value (VR-07).
- The admin can further edit the Online value **per row** directly in the preview grid (Q6); the Onsite column stays read-only/guide-derived.
- Zero-capacity (guide-occupied or lunch-blocked) slots always show Online = 0 regardless of the input value.

### 10.5 Multi-Location Handling

Per Q5, one shared configuration (Locations, dates, hours, shifts, duration, interval, lunch, online settings) is entered once and applied identically to every selected Location. The preview grid shows a **single, generic** rendering of that shared pattern. At Publish (Section 11), the same configuration is persisted independently per selected Location × Date, producing one `Tour_Availability__c` (+ children) per Location per Date.

---

## 11. Publish & Persistence Design

### 11.1 Apex Classes

| Class | Type | Responsibility |
|---|---|---|
| `TourAvailabilityPublishController` | `with sharing`, `@AuraEnabled` | Entry point for the LWC's Publish action; re-validates (VR-01–VR-10) and enqueues the batch |
| `TourSlotGenerationService` | `with sharing` service class | Implements the Section 10.1 algorithm server-side (mirrors the LWC's client-side logic so Publish never trusts client-computed values) |
| `TourSlotGenerationBatch` | `Database.Batchable<SObject>`, `Database.Stateful` | Iterates selected Location × Date pairs; bulk-inserts `Tour_Availability__c`, `Tour_Guide_Shift__c`, and `Tour_Availability_Slot__c` in governor-limit-safe chunks |
| Test classes | `@isTest` | ≥ 90% coverage; bulk (200+ record) scenarios covering guide-occupancy edge cases, lunch overlap, and duplicate-date rejection |

All Apex uses `with sharing`; all inputs are re-validated server-side; no dynamic SOQL/DML is built from raw user input.

### 11.2 Duplicate / Re-generation Handling

If a `Tour_Availability__c` already exists for a Location + Date being published, that Location/Date combination is rejected (VR-10) and reported back to the user; no partial silent overwrite occurs. Overwrite/replace of existing availability remains a future enhancement (not built in this story).

---

## 12. Rolling 90-Day Auto-Extension ("Clone") Job

Per business clarification (Q9), the story's "Clone the Schedule every 24 hours" rule is a **backend-only** concern, decoupled from the interactive Generator screen:

- **Problem:** Business Rule BR-1 caps `Start Date` at `TODAY + 90 days` at the moment of Publish. Since "today" advances every day, a schedule published once (e.g., covering Day 0 → Day 90) would fall one day short of the 90-day horizon on each subsequent day unless something extends it.
- **Solution — `TourAvailabilityDailyRolloverJob`** (Scheduled Apex, runs once every 24 hours):
  1. For each Location with at least one previously published `Tour_Availability__c` record (i.e., an active recurring schedule):
  2. Find the latest `Availability_Date__c` currently published for that Location.
  3. Compute `targetEndDate = TODAY + 90`.
  4. For each date from `(latestPublishedDate + 1)` through `targetEndDate` that doesn't already exist (normally just one day, but the loop tolerates a missed run):
     - Clone the configuration (Operating Hours, Tour Duration, Slot Interval, Lunch Block settings, Online Tour Booking Enabled + `Online_Capacity_Input__c`, and all `Tour_Guide_Shift__c` child rows) from the most recent `Tour_Availability__c` for that Location.
     - Create a new `Tour_Availability__c` for the new date and run the Section 10.1 algorithm (via `TourSlotGenerationService`) to generate its `Tour_Availability_Slot__c` children.
  5. `Location_Date_Key__c` uniqueness (Section 15) prevents duplicate creation if the job is ever re-run for a date already covered.
- **Effect:** every published location's availability horizon rolls forward automatically by one day, every day, with no manual admin action required — satisfying the business rule's intent as clarified.

---

## 13. Permission Sets

| Permission Set | Grants | Assigned To |
|---|---|---|
| `DVC_Tour_Availability_Management` *(new, proposed)* | Read/Create/Edit on `Tour_Availability__c`, `Tour_Guide_Shift__c`, `Tour_Availability_Slot__c`; Read on `Location`; access to the Tour Availability Generator LWC | Business Admin, Operations |

No profile-level access is granted; access is exclusively via permission set.

---

## 14. Reporting

Use custom report types on `Tour_Availability__c` with related `Tour_Guide_Shift__c` and `Tour_Availability_Slot__c` to allow Operations to report on published capacity, lunch-blocked slots, and Onsite vs. Online capacity by Location and Date. Fields marked for Field Tracking (Section 7) support historical audit reporting on schedule changes.

---

## 15. Uniqueness Rules

- **`Location__c` + `Availability_Date__c` must be unique** on `Tour_Availability__c`, enforced via the `Location_Date_Key__c` external ID/unique text field (populated by a `before insert/update` trigger or Flow concatenating both values).
- Prevents duplicate publishing for the same Location/Date, both from the interactive Publish action and from the daily rollover job (Section 12).

---

## 16. Flexi Pages & Compact Layout

| Item | Change |
|---|---|
| Tour Availability Generator App Page | New Lightning App Page/Tab hosting the LWC described in Section 8. |
| Tour Availability Record Page | Standard related-list exposure of child `Tour_Guide_Shift__c` and `Tour_Availability_Slot__c` records; no custom layout changes anticipated. |
| Compact Layout | No changes anticipated. |

---

## 17. Acceptance Criteria Traceability Matrix

| UAC | Summary | LLD Coverage |
|---|---|---|
| UAC1 | Generate disabled with no location selected | Section 8.1, VR-01 |
| UAC2 | Date range validation | VR-02 |
| UAC3 | Opening/Closing time validation | VR-04 |
| UAC4 | Guide count/shifts drive slot capacity | Section 10.1 (guide-occupancy algorithm) |
| UAC5 | Lunch Block reveal | Section 8.1 |
| UAC6 | Lunch Block validation | VR-06 |
| UAC7 | Lunch reflected as 0 in preview | Section 10.3 |
| UAC8 | Online Tour Booking indicator reveals fields | Section 8.1, Section 10.4 |
| UAC9 | Online unchecked → Onsite-only display | Section 8.1/8.2 |
| UAC10 | Online ≤ Onsite validation | VR-07, Section 10.4 |
| UAC11 | Tour Duration drives interval length | Section 10.1 |
| UAC12 | Tour Slot Increment field (15/30/60) | Section 7.2 (`Slot_Interval__c`) |
| UAC13–15 | 60/30/15-minute slot generation | Section 10.1–10.2 |
| UAC16 | Slot cadence matches selected increment | Section 10.1 |
| UAC17 | In-place preview update | Section 8.2, Section 4.2 step 4 |
| UAC18 | Multi-location generation | Section 10.5 |
| UAC19 | Field persistence during session | Section 8.2, Section 4.2 step 5 |
| BR-1 | Start Date ≤ today + 90 days | VR-03 |
| BR-2 | Clone schedule every 24 hours | Section 12 |

---

## 18. Security & Compliance Considerations

- All Apex classes use `with sharing`; no sharing escalation required.
- Field-Level Security and object permissions are granted exclusively through `DVC_Tour_Availability_Management` (Section 13).
- All user-supplied input (dates, times, guide counts, capacities, Location Ids) is re-validated server-side in `TourSlotGenerationService`/`TourAvailabilityPublishController` before any DML; the client-side checks in Section 9 are a UX convenience only, not a security boundary.
- No dynamic SOQL is constructed from raw user input.
- No PII/PHI/PCI data is introduced by this feature (scheduling/capacity metadata only).
- `TourSlotGenerationBatch` uses chunked DML to respect governor limits; the 90-day cap (VR-03) and the daily rollover design (Section 12, one day at a time) naturally bound volume per execution.

---

## 19. Decision Log (Business Q&A — 2026-08-17)

| # | Question | Decision |
|---|---|---|
| Q0 | Is this story preview-only, or does it need backend persistence? | Preview is a pure client-side (LWC) compute-and-render exercise with **no custom objects created**. Once the user clicks **Publish**, the data is stored to the backend. |
| Q1 | Is the capacity model guide-driven? | **Yes** — confirmed, superseding the HLD's flat-capacity approach. |
| Q2 | Guide Shift multiplicity rules (overlap, max count, gap handling) | **Pending** — tagged to business for clarification (Section 20, Item 1). |
| Q3 | Is "Total Onsite Slots" just the display label for the guide-derived number? | **Yes.** |
| Q4 | How is Online capacity derived? | A **separate numeric input** the admin enters directly per generation, capped ≤ the guide-derived Onsite capacity (UAC10); Onsite is always populated based on guides. |
| Q5 | Multi-location preview: combined or per-location breakdown? | **Single generic preview grid** (Section 10.5). |
| Q6 | Are preview numbers editable? | **Onsite is read-only; Online is editable** (per row, in the preview grid). |
| Q7 | Unresolved Jira comment thread (rename "Guides" to "Slots", "discuss Ship") | Already reflected in the mock-up; no further action needed — field labels follow the mock-up as-is. |
| Q8 | Guide Shift default value conflict (Field Inventory: 1 vs. mock-up: 2) | **Default is 2** (confirmed). |
| Q9 | Does "clone every 24 hours" apply to this preview-only story? | **No** — it's backend-only logic. If a schedule is published for Today → Today+90, then on each subsequent day the system must auto-generate the newly-in-range day (Today+91, then +92, etc.) so the 90-day booking horizon keeps rolling forward without manual admin action. Implemented as `TourAvailabilityDailyRolloverJob` (Section 12). |
| Q10 | Tour Location data source | **Standard Salesforce `Location` object.** WDW, Disneyland, Aulani are `Location` records with `LocationType = Channel`; related child `Location` records with `LocationType = Resorts` are the actual bookable tour locations. |
| Q11 | Timezone handling | **Single US org timezone** for now (no per-location timezone conversion). |
| Q12 | Onsite/Event-Group tab scope | Event/Group is explicitly called out as a **separate story**; this LLD implements Onsite only. |

---

## 20. Open Items / Assumptions Still Pending

| # | Topic | Current Assumption (until confirmed) | Owner |
|---|---|---|---|
| 1 | Guide Shift multiplicity rules: can shifts overlap? Is there a max count? How are gaps between shifts (or before the first/after the last shift) handled? | No overlap allowed; unlimited shifts; gaps produce 0-capacity zones (guides simply not on duty) | Business (already tagged by requester) |
| 2 | Exact UI/UX and acceptance criteria for the new **Publish** button/flow (not shown in current mock-ups) | Publish button placed alongside "Generate & Preview Schedule," disabled until a preview exists, with a success/failure toast on completion (Section 4.2 step 6, Section 11) | Product/UX |
| 3 | Exact time-of-day and monitoring/alerting for `TourAvailabilityDailyRolloverJob` | Runs once daily at a fixed off-peak time (e.g., midnight org time); failure alerting mechanism (email/Platform Event) not yet defined | Business/Architect |
| 4 | Whether Online Capacity input applies as a single flat value across all non-zero slots, or should support different values across the day | Single flat value seeded across all non-zero slots, then individually editable per row post-generation (Section 10.4) | Product (can revisit if business wants per-shift online defaults) |

---

## 21. Appendix

### 21.1 Jira Stories

| Jira Story | Summary |
|---|---|
| DMS-4909 | Tour Availability Generator — Schedule Creation (this story) |
| DMS-4987 | Clone of DMS-4909 (per issue links) |
| DMS-2835 | Parent Epic — Cast Workflow Management \| Tour Booking & Management |
| *(TBD)* | Event/Group tab story (referenced as out of scope, exact key not yet provided) |

### 21.2 List of Figures

1. Figure 1 — Solution Architecture (Section 4.1)
2. Figure 2 — DMS-4909 Data Model Diagram (Section 5)

### 21.3 Referenced Documents

- DMS-4909 Jira export (description, Field Inventory, Acceptance Criteria, Business Rules)
- Tour Availability Generator UI mock-ups (Onsite mode; Online Tour Booking enabled mode)
- "Ability to Manage Guide License Data" LLD (used as structural/format reference for this document)
- DMS-4909 HLD "Tour Slots Generator" (superseded for this revision; retained for historical reference in git history)
