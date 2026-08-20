/**
 * DVC_TourSlotGenerationBatch
 *
 * Bulk-safe, asynchronous persistence for a Publish action (docs/DMS-4909-LLD.md Section 11).
 * Expands the requested Location(s) x Date range into individual (Location, Date) units of
 * work using a custom Iterable (rather than a SOQL QueryLocator, since the units of work are
 * derived from the request payload, not an existing sObject query), then for each unit:
 *   1. Skips any Location+Date+Slot Type that already has a published DVC_Tour_Availability__c
 *      (VR-10 / duplicate-publish protection, LLD Section 11.2 and Section 15).
 *   2. Inserts the parent DVC_Tour_Availability__c record(s).
 *   3. Inserts the child DVC_Tour_Guide_Shift__c and DVC_Tour_Availability_Slot__c records,
 *      generated via DVC_TourSlotGenerationService (no business logic lives in this class).
 *
 * Database.Stateful is used so success/failure counts survive across chunks for the finish()
 * summary log.
 */
public with sharing class DVC_TourSlotGenerationBatch implements Database.Batchable<DVC_TourSlotGenerationBatch.LocationDateUnit>, Database.Stateful {

    private String serializedRequest;
    private Integer publishedCount = 0;
    private Integer skippedOrFailedCount = 0;
    private List<String> notes = new List<String>();

    public DVC_TourSlotGenerationBatch(String serializedRequest) {
        this.serializedRequest = serializedRequest;
    }

    /**
     * One (Location, Date) combination to generate a schedule for; Slot Type comes from the
     * shared request rather than being repeated per unit.
     */
    public class LocationDateUnit {
        public Id locationId;
        public Date theDate;
        public LocationDateUnit(Id locationId, Date theDate) {
            this.locationId = locationId;
            this.theDate = theDate;
        }
    }

    public Iterable<LocationDateUnit> start(Database.BatchableContext bc) {
        DVC_TourAvailabilityRequest request = deserializeRequest();
        List<LocationDateUnit> units = new List<LocationDateUnit>();

        if (request.locationIds == null || request.startDate == null || request.endDate == null) {
            return units;
        }

        for (Id locationId : request.locationIds) {
            for (Date theDate = request.startDate; theDate <= request.endDate; theDate = theDate.addDays(1)) {
                units.add(new LocationDateUnit(locationId, theDate));
            }
        }
        return units;
    }

    public void execute(Database.BatchableContext bc, List<LocationDateUnit> scope) {
        DVC_TourAvailabilityRequest request = deserializeRequest();
        String slotType = String.isBlank(request.slotType) ? DVC_TourAvailabilityConstants.SLOT_TYPE_ONSITE : request.slotType;

        Map<String, LocationDateUnit> unitByKey = new Map<String, LocationDateUnit>();
        for (LocationDateUnit unit : scope) {
            unitByKey.put(DVC_TourSlotGenerationService.buildLocationDateKey(unit.locationId, unit.theDate, slotType), unit);
        }

        Set<String> existingKeys = queryExistingKeys(unitByKey.keySet());

        List<DVC_Tour_Availability__c> availabilitiesToInsert = new List<DVC_Tour_Availability__c>();
        Map<String, Date> dateByKey = new Map<String, Date>();

        for (String key : unitByKey.keySet()) {
            if (existingKeys.contains(key)) {
                skippedOrFailedCount++;
                notes.add('Skipped (already published): ' + key);
                continue;
            }
            LocationDateUnit unit = unitByKey.get(key);
            DVC_Tour_Availability__c availability = DVC_TourSlotGenerationService.buildAvailabilityRecord(unit.locationId, unit.theDate, request);
            availabilitiesToInsert.add(availability);
            dateByKey.put(key, unit.theDate);
        }

        if (availabilitiesToInsert.isEmpty()) {
            return;
        }

        // Savepoint so a failure inserting children (shifts/slots) never leaves an orphaned
        // parent DVC_Tour_Availability__c with zero children — without this, the parent would
        // remain committed (Apex does not auto-rollback earlier successful DML in the same
        // try/catch) and the Location+Date+Slot Type would be permanently blocked from retry
        // by the DVC_Location_Date_Key__c uniqueness constraint (VR-10 / Section 11.2).
        Savepoint sp = Database.setSavepoint();
        try {
            // IMPORTANT: Security.stripInaccessible() returns CLONED records, not the same
            // instances passed in. We must reassign availabilitiesToInsert to that returned
            // list before inserting, otherwise the objects we go on to read .Id from below
            // (to populate child lookups) would never have their Ids populated by the insert.
            SObjectAccessDecision availabilityDecision = Security.stripInaccessible(AccessType.CREATABLE, availabilitiesToInsert);
            availabilitiesToInsert = (List<DVC_Tour_Availability__c>) availabilityDecision.getRecords();
            insert availabilitiesToInsert;

            List<DVC_Tour_Guide_Shift__c> shiftsToInsert = new List<DVC_Tour_Guide_Shift__c>();
            List<DVC_Tour_Availability_Slot__c> slotsToInsert = new List<DVC_Tour_Availability_Slot__c>();

            for (DVC_Tour_Availability__c availability : availabilitiesToInsert) {
                Date theDate = dateByKey.get(availability.DVC_Location_Date_Key__c);

                if (request.guideShifts != null) {
                    for (DVC_TourAvailabilityRequest.GuideShift shift : request.guideShifts) {
                        shiftsToInsert.add(new DVC_Tour_Guide_Shift__c(
                            DVC_Tour_Availability__c = availability.Id,
                            DVC_Shift_Start_Time__c = shift.shiftStartTime,
                            DVC_Shift_End_Time__c = shift.shiftEndTime,
                            DVC_Number_of_Guides__c = shift.numberOfGuides
                        ));
                    }
                }

                slotsToInsert.addAll(DVC_TourSlotGenerationService.buildSlotRecords(availability.Id, theDate, request));
            }

            if (!shiftsToInsert.isEmpty()) {
                SObjectAccessDecision shiftDecision = Security.stripInaccessible(AccessType.CREATABLE, shiftsToInsert);
                insert shiftDecision.getRecords();
            }
            if (!slotsToInsert.isEmpty()) {
                SObjectAccessDecision slotDecision = Security.stripInaccessible(AccessType.CREATABLE, slotsToInsert);
                insert slotDecision.getRecords();
            }

            publishedCount += availabilitiesToInsert.size();
        } catch (Exception ex) {
            Database.rollback(sp);
            DVC_LoggerService.logException(DVC_TourSlotGenerationBatch.class.getName(), 'execute', ex);
            skippedOrFailedCount += availabilitiesToInsert.size();
            notes.add('Chunk failed and rolled back: ' + ex.getMessage());
        }
    }

    public void finish(Database.BatchableContext bc) {
        // Exact success/failure UX (toast, Platform Event, etc.) is still pending business
        // sign-off on the Publish button's design (LLD Section 20, Item 2). For now, the
        // outcome is captured via Nebula Logger for admin/support visibility.
        DVC_LoggerService.logSummary(DVC_TourSlotGenerationBatch.class.getName(), 'finish',
            'Publish complete. Days published: ' + publishedCount + '. Skipped/failed: ' + skippedOrFailedCount
                + (notes.isEmpty() ? '' : ' Details: ' + String.join(notes, ' | ')));
    }

    private Set<String> queryExistingKeys(Set<String> candidateKeys) {
        Set<String> existing = new Set<String>();
        if (candidateKeys.isEmpty()) {
            return existing;
        }
        for (DVC_Tour_Availability__c record : [
            SELECT DVC_Location_Date_Key__c
            FROM DVC_Tour_Availability__c
            WHERE DVC_Location_Date_Key__c IN :candidateKeys
            WITH SECURITY_ENFORCED
        ]) {
            existing.add(record.DVC_Location_Date_Key__c);
        }
        return existing;
    }

    private DVC_TourAvailabilityRequest deserializeRequest() {
        return (DVC_TourAvailabilityRequest) JSON.deserialize(serializedRequest, DVC_TourAvailabilityRequest.class);
    }
}
