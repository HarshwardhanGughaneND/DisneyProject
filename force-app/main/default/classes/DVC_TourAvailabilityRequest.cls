/**
 * DVC_TourAvailabilityRequest
 *
 * Shared request payload for the Tour Availability Generator (DMS-4909). One instance
 * represents the entire configuration entered on the `dvcTourAvailabilityConfigForm` LWC for
 * a single Generate/Publish action; it is JSON-serialized to travel through
 * `Database.executeBatch` (see DVC_TourSlotGenerationBatch) since Batchable constructor
 * arguments must be serializable to a simple state.
 *
 * See docs/DMS-4909-LLD.md Section 8.1 (Input Fields) and Section 10.1 (Algorithm).
 */
public with sharing class DVC_TourAvailabilityRequest {

    @AuraEnabled public List<Id> locationIds;
    @AuraEnabled public Date startDate;
    @AuraEnabled public Date endDate;
    @AuraEnabled public Time operatingStartTime;
    @AuraEnabled public Time operatingEndTime;
    @AuraEnabled public Integer tourDurationMinutes;
    @AuraEnabled public String slotInterval; // one of DVC_TourAvailabilityConstants.SLOT_INTERVAL_MINUTES keys
    @AuraEnabled public Boolean lunchBlockNeeded;
    @AuraEnabled public Time lunchStartTime;
    @AuraEnabled public Time lunchEndTime;
    @AuraEnabled public Boolean onlineTourBookingEnabled;
    @AuraEnabled public Decimal onlineCapacityInput; // transient - never persisted on DVC_Tour_Availability__c (LLD Section 10.4)
    @AuraEnabled public String slotType; // defaults to DVC_TourAvailabilityConstants.SLOT_TYPE_ONSITE when blank
    @AuraEnabled public List<GuideShift> guideShifts;

    /**
     * One repeatable Guide Shift row (LLD Section 7.3 / 8.1 "+ Add Shift" UI).
     */
    public class GuideShift {
        @AuraEnabled public Time shiftStartTime;
        @AuraEnabled public Time shiftEndTime;
        @AuraEnabled public Integer numberOfGuides;
    }
}
