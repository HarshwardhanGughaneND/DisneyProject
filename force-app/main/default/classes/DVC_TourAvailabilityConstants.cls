/**
 * DVC_TourAvailabilityConstants
 *
 * Centralized constants for the DMS-4909 Tour Availability Generator feature, so picklist
 * values, map lookups, and tunable limits are defined exactly once. See docs/DMS-4909-LLD.md.
 */
public with sharing class DVC_TourAvailabilityConstants {

    // DVC_Tour_Availability__c.DVC_Slot_Type__c values
    public static final String SLOT_TYPE_ONSITE = 'Onsite';
    public static final String SLOT_TYPE_EVENT = 'Event';

    // DVC_Tour_Availability_Slot__c.DVC_Slot_Status__c values.
    // NOTE: placeholder values pending business confirmation - see LLD Section 20, Item 6.
    public static final String SLOT_STATUS_OPEN = 'Open';
    public static final String SLOT_STATUS_CLOSED = 'Closed';

    // DVC_Tour_Availability__c.DVC_Slot_Interval__c picklist values -> minutes
    public static final Map<String, Integer> SLOT_INTERVAL_MINUTES = new Map<String, Integer>{
        '15 Minutes' => 15,
        '30 Minutes' => 30,
        '60 Minutes' => 60
    };

    // Business Rule BR-1: Start Date cannot be more than 90 days in the future.
    public static final Integer MAX_START_DATE_DAYS_IN_FUTURE = 90;

    // Number of Location+Date+SlotType units processed per DVC_TourSlotGenerationBatch.execute()
    // chunk. Kept conservative since each unit can fan out into many child Slot records.
    public static final Integer BATCH_SCOPE_SIZE = 5;

    // Standard Location object LocationType value that this story restricts selection to.
    public static final String LOCATION_TYPE_RESORT = 'Resort';

    private DVC_TourAvailabilityConstants() {
        // Static-only utility class.
    }
}
