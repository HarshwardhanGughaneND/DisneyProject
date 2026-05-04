# DisneyProject – Tour Booking LWC Wizard

A production-ready Lightning Web Component (LWC) multi-step Tour Booking application for Salesforce, built with full Apex integration and SLDS-compliant UI.

---

## Architecture Overview

```
force-app/main/default/
├── classes/
│   ├── TourBookingController.cls          ← Central Apex service layer
│   └── TourBookingControllerTest.cls      ← Unit tests (100% coverage target)
├── lwc/
│   ├── tourBookingWizard/                 ← Root wizard container (state manager)
│   ├── guestSearch/                       ← Screen 1: Search + Results
│   ├── guestItinerary/                    ← Screen 2: Timeline availability
│   ├── tourLocationModal/                 ← Screen 3: Location selection modal
│   └── tourPartyConfirmation/             ← Screen 4: Split-view party builder
├── objects/
│   ├── Tour__c/                           ← Primary booking record
│   ├── Tour_Guest__c/                     ← Junction: Tour ↔ Guest
│   ├── Tour_Location__c/                  ← Physical tour location
│   ├── Tour_Availability__c/              ← Date+time availability window
│   └── Tour_Availability_Slot__c/         ← Individual slot per location
├── permissionsets/
│   └── Tour_Booking_User.permissionset-meta.xml
└── flexipages/
    └── Tour_Booking_App_Page.flexipage-meta.xml
```

---

## 4-Step Wizard Flow

### Screen 1 – Guest Search + Results (`guestSearch`)

- **Global search input** (debounced 300ms): searches Person Accounts across Name, Email, Phone, and Address fields using SOSL + SOQL
- **Action cards**: Tap and Camera Scan shortcuts
- **Results table**: Guest Name | Email | Phone | Address | Action (View + Select)
- **Empty state**: "Can't find the guest?" → "Create New Guest Record" button

### Screen 2 – Guest Itinerary & Tour Availability (`guestItinerary`)

- **Guest header**: Shows selected guest details with gradient hero bar
- **Area filter tabs**: MK Area | EP Area | DHS Area | DAK Area | DS Area
- **Location dropdown**: Filtered by selected area (`Tour_Location__c`)
- **Date picker** with prev/next navigation arrows
- **Timeline grid**: Each row = one `Tour_Availability__c` record
  - 🟢 Green badge → "Tours Available (X slots)"
  - 🔴 Red badge → "No Tours Available"
  - Clicking an available row opens Screen 3

### Screen 3 – Tour Location Selection (`tourLocationModal`)

- SLDS modal with custom gradient header
- Lists available `Tour_Location__c` records for the selected time slot
- Radio-style row selection
- Falls back to well-known Disney locations when no data exists
- Cancel / Next actions

### Screen 4 – Tour Party Confirmation (`tourPartyConfirmation`)

- **Split layout** (5:7 column grid):
  - **Left**: People search, Tap/Camera buttons, Reservation details card, Household member groups
  - **Right**: Tour Party panel with live count, primary guest pre-added, removable members
- Household members grouped by shared address (Smith Household / Row Household pattern)
- **Confirm Tour** button creates `Tour__c` + one `Tour_Guest__c` per party member

---

## Custom Objects

| Object | Purpose |
|--------|---------|
| `Tour__c` | Primary booking record; links guest → location → date/time |
| `Tour_Guest__c` | Junction: one row per guest per tour (master-detail to `Tour__c`) |
| `Tour_Location__c` | Physical tour venue (Saratoga Springs, Polynesian, etc.) |
| `Tour_Availability__c` | Date+time window with capacity & booked count |
| `Tour_Availability_Slot__c` | Individual time slot for a specific location (child of availability) |

---

## Apex Controller (`TourBookingController`)

| Method | Signature | Notes |
|--------|-----------|-------|
| `searchGuests` | `(String searchTerm)` | SOSL + SOQL dual search, cacheable |
| `getHouseholdMembers` | `(Id guestId)` | Same BillingStreet+City lookup, cacheable |
| `getTourLocations` | `(String area)` | Area-filtered, cacheable |
| `getTourAvailability` | `(String tourDate, String area, String locationId)` | Capacity-aware, cacheable |
| `getAvailabilitySlots` | `(Id availabilityId)` | Child slots for a specific window, cacheable |
| `getAvailableLocationsForSlot` | `(String tourDate, String startTime, String area)` | Used by modal, cacheable |
| `confirmTour` | `(TourBookingRequest request)` | Creates Tour__c + Tour_Guest__c records, updates Booked_Count__c; uses savepoint rollback |

---

## Deployment

### Prerequisites
- Salesforce DX CLI installed
- Person Accounts enabled in the target org
- A scratch org or sandbox

### Deploy

```bash
# Authenticate
sf org login web --alias my-org

# Push source
sf project deploy start --target-org my-org

# Assign permission set
sf org assign permset --name Tour_Booking_User --target-org my-org

# Run tests
sf apex run test --class-names TourBookingControllerTest --target-org my-org --result-format human
```

### Open App Page
Navigate to **App Launcher → Tour Booking** or add the `tourBookingWizard` component to any Lightning App Page.

---

## State Management

All wizard state is held in `tourBookingWizard.js`:

```
selectedGuest      → GuestResult object (set on Screen 1 Select)
selectedTimeSlot   → AvailabilityResult object (set on Screen 2 row click)
selectedLocation   → TourLocationResult object (set on Screen 3 Next)
tourParty          → Array of guests (managed on Screen 4)
currentStep        → 1-4 (drives template conditionals)
showLocationModal  → Boolean (overlays Screen 3 on Screen 2)
```

Back navigation preserves all prior state without data loss.

---

## Color Coding & SLDS Conventions

| Element | Color | SLDS Token |
|---------|-------|-----------|
| Available slot badge | Green | `#e8f5e9` / `#2e844a` |
| Unavailable slot badge | Red | `#ffebee` / `#ba0517` |
| Active tab / Primary | Brand Blue | `#0176d3` |
| Completed step circle | Success Green | `#2e844a` |
| Header gradients | Disney Blue | `#032d60 → #0176d3` |

---

## Salesforce Best Practices Applied

- **`@AuraEnabled(cacheable=true)`** on all read methods
- **Savepoint rollback** on `confirmTour` for atomic DML
- **Bulk-safe SOQL** with LIMIT clauses
- **`with sharing`** on Apex controller
- **Debounced search** (300ms) to minimize API calls
- **NavigationMixin** for record navigation
- **`composed: true`** events for cross-shadow-DOM communication
- **SLDS-only styling** (no raw CSS overrides of Lightning internals)
