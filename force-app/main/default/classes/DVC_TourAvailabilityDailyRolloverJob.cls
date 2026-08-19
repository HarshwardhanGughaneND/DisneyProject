/**
 * DVC_TourAvailabilityDailyRolloverJob
 *
 * Implements the "Clone the Schedule every 24 hours" business rule (docs/DMS-4909-LLD.md
 * Section 12), decoupled from the interactive Generator screen. Since a schedule can only be
 * Published up to 90 days out (BR-1 / VR-03), this job runs once daily and extends every
 * Location's published availability forward by exactly one day, so the 90-day booking horizon
 * keeps rolling forward without requiring an admin to manually regenerate every day.
 *
 * Schedule this job with, e.g.:
 *   System.schedule('DVC Tour Availability Daily Rollover', DVC_TourAvailabilityDailyRolloverJob.CRON_EXPRESSION, new DVC_TourAvailabilityDailyRolloverJob());
 *
 * NOTE: the exact time-of-day and monitoring/alerting approach are still pending business
 * confirmation (LLD Section 20, Item 3); 2:00 AM org time is used here as a reasonable
 * off-peak default.
 */
public with sharing class DVC_TourAvailabilityDailyRolloverJob implements Schedulable {

    public static final String CRON_EXPRESSION = '0 0 2 * * ?';

    public void execute(SchedulableContext sc) {
        try {
            rollForward();
        } catch (Exception ex) {
            DVC_LoggerService.logException(DVC_TourAvailabilityDailyRolloverJob.class.getName(), 'execute', ex);
        }
    }

    @TestVisible
    private void rollForward() {
        Date targetEndDate = Date.today().addDays(DVC_TourAvailabilityConstants.MAX_START_DATE_DAYS_IN_FUTURE);

        Map<String, DVC_Tour_Availability__c> latestByLocationAndSlotType = findLatestAvailabilityPerLocation();

        List<DVC_Tour_Availability__c> newAvailabilities = new List<DVC_Tour_Availability__c>();
        Map<String, DVC_TourAvailabilityRequest> requestByKey = new Map<String, DVC_TourAvailabilityRequest>();
        Map<String, Date> dateByKey = new Map<String, Date>();

        for (DVC_Tour_Availability__c templateRecord : latestByLocationAndSlotType.values()) {
            DVC_TourAvailabilityRequest request = toRequest(templateRecord);

            // Per LLD Section 12 step 4: loop from (latestPublishedDate + 1) through
            // targetEndDate — not just a single day — so the job self-corrects and catches
            // this location fully back up to the 90-day horizon even if one or more prior
            // scheduled runs were missed (org downtime, job deployed after inactivity, etc.).
            for (Date newDate = templateRecord.DVC_Availability_Date__c.addDays(1);
                    newDate <= targetEndDate;
                    newDate = newDate.addDays(1)) {

                DVC_Tour_Availability__c newAvailability = DVC_TourSlotGenerationService.buildAvailabilityRecord(
                    templateRecord.DVC_Tour_Location__c, newDate, request);

                newAvailabilities.add(newAvailability);
                requestByKey.put(newAvailability.DVC_Location_Date_Key__c, request);
                dateByKey.put(newAvailability.DVC_Location_Date_Key__c, newDate);
            }
        }

        if (newAvailabilities.isEmpty()) {
            return;
        }

        // Defensive re-check (Section 15 uniqueness) in case a manual Publish already covered
        // one of these dates since findLatestAvailabilityPerLocation() ran.
        List<DVC_Tour_Availability__c> toInsert = filterOutExisting(newAvailabilities);
        if (toInsert.isEmpty()) {
            return;
        }

        // Savepoint so a failure inserting children never leaves an orphaned parent record
        // with zero slots, permanently blocked from retry by the uniqueness constraint.
        Savepoint sp = Database.setSavepoint();
        try {
            // IMPORTANT: Security.stripInaccessible() returns CLONED records, not the same
            // instances passed in - reassign toInsert to that returned list before inserting,
            // otherwise insertChildren() below would read .Id from objects that were never
            // actually inserted (and so would never have their Ids populated).
            SObjectAccessDecision decision = Security.stripInaccessible(AccessType.CREATABLE, toInsert);
            toInsert = (List<DVC_Tour_Availability__c>) decision.getRecords();
            insert toInsert;
            insertChildren(toInsert, requestByKey, dateByKey);

            DVC_LoggerService.logSummary(DVC_TourAvailabilityDailyRolloverJob.class.getName(), 'rollForward',
                'Rolled forward ' + toInsert.size() + ' Tour Availability day(s) to maintain the 90-day horizon.');
        } catch (Exception ex) {
            Database.rollback(sp);
            DVC_LoggerService.logException(DVC_TourAvailabilityDailyRolloverJob.class.getName(), 'rollForward', ex);
        }
    }

    /**
     * One most-recent DVC_Tour_Availability__c per (Location, Slot Type), used as the template
     * to clone forward. Includes child Guide Shifts and (for the online capacity value only,
     * since it is not persisted on the parent - LLD Section 12) one existing open Slot.
     */
    private Map<String, DVC_Tour_Availability__c> findLatestAvailabilityPerLocation() {
        Map<String, DVC_Tour_Availability__c> latestByKey = new Map<String, DVC_Tour_Availability__c>();

        for (DVC_Tour_Availability__c availability : [
            SELECT Id, DVC_Tour_Location__c, DVC_Availability_Date__c, DVC_Operating_Start_Time__c,
                   DVC_Operating_End_Time__c, DVC_Tour_Duration__c, DVC_Slot_Interval__c,
                   DVC_Lunch_Block_Needed__c, DVC_Lunch_Start_Time__c, DVC_Lunch_End_Time__c,
                   DVC_Online_Tour_Booking_Enabled__c, DVC_Slot_Type__c,
                   (SELECT DVC_Shift_Start_Time__c, DVC_Shift_End_Time__c, DVC_Number_of_Guides__c
                    FROM DVC_Tour_Guide_Shifts__r),
                   (SELECT DVC_Total_Online_Capacity__c
                    FROM DVC_Tour_Availability_Slots__r
                    WHERE DVC_Total_Online_Capacity__c > 0
                    LIMIT 1)
            FROM DVC_Tour_Availability__c
            WHERE DVC_Availability_Date__c >= :Date.today()
            WITH SECURITY_ENFORCED
            ORDER BY DVC_Availability_Date__c DESC
        ]) {
            String key = availability.DVC_Tour_Location__c + '_' + availability.DVC_Slot_Type__c;
            if (!latestByKey.containsKey(key)) {
                latestByKey.put(key, availability); // first (i.e. latest, due to DESC order) wins
            }
        }
        return latestByKey;
    }

    private DVC_TourAvailabilityRequest toRequest(DVC_Tour_Availability__c templateRecord) {
        DVC_TourAvailabilityRequest request = new DVC_TourAvailabilityRequest();
        request.operatingStartTime = templateRecord.DVC_Operating_Start_Time__c;
        request.operatingEndTime = templateRecord.DVC_Operating_End_Time__c;
        request.tourDurationMinutes = templateRecord.DVC_Tour_Duration__c == null ? null : Integer.valueOf(templateRecord.DVC_Tour_Duration__c);
        request.slotInterval = templateRecord.DVC_Slot_Interval__c;
        request.lunchBlockNeeded = templateRecord.DVC_Lunch_Block_Needed__c;
        request.lunchStartTime = templateRecord.DVC_Lunch_Start_Time__c;
        request.lunchEndTime = templateRecord.DVC_Lunch_End_Time__c;
        request.onlineTourBookingEnabled = templateRecord.DVC_Online_Tour_Booking_Enabled__c;
        request.slotType = templateRecord.DVC_Slot_Type__c;

        request.guideShifts = new List<DVC_TourAvailabilityRequest.GuideShift>();
        for (DVC_Tour_Guide_Shift__c shift : templateRecord.DVC_Tour_Guide_Shifts__r) {
            DVC_TourAvailabilityRequest.GuideShift shiftWrapper = new DVC_TourAvailabilityRequest.GuideShift();
            shiftWrapper.shiftStartTime = shift.DVC_Shift_Start_Time__c;
            shiftWrapper.shiftEndTime = shift.DVC_Shift_End_Time__c;
            shiftWrapper.numberOfGuides = shift.DVC_Number_of_Guides__c == null ? null : Integer.valueOf(shift.DVC_Number_of_Guides__c);
            request.guideShifts.add(shiftWrapper);
        }

        // Online Capacity input is transient/not persisted on the parent (business decision,
        // LLD Section 10.4) - read it back from an existing open slot on the template day instead.
        request.onlineCapacityInput = (!templateRecord.DVC_Tour_Availability_Slots__r.isEmpty())
            ? templateRecord.DVC_Tour_Availability_Slots__r[0].DVC_Total_Online_Capacity__c
            : null;

        return request;
    }

    private List<DVC_Tour_Availability__c> filterOutExisting(List<DVC_Tour_Availability__c> candidates) {
        Set<String> candidateKeys = new Set<String>();
        for (DVC_Tour_Availability__c candidate : candidates) {
            candidateKeys.add(candidate.DVC_Location_Date_Key__c);
        }

        Set<String> existingKeys = new Set<String>();
        for (DVC_Tour_Availability__c existing : [
            SELECT DVC_Location_Date_Key__c
            FROM DVC_Tour_Availability__c
            WHERE DVC_Location_Date_Key__c IN :candidateKeys
            WITH SECURITY_ENFORCED
        ]) {
            existingKeys.add(existing.DVC_Location_Date_Key__c);
        }

        List<DVC_Tour_Availability__c> filtered = new List<DVC_Tour_Availability__c>();
        for (DVC_Tour_Availability__c candidate : candidates) {
            if (!existingKeys.contains(candidate.DVC_Location_Date_Key__c)) {
                filtered.add(candidate);
            }
        }
        return filtered;
    }

    private void insertChildren(List<DVC_Tour_Availability__c> insertedAvailabilities,
            Map<String, DVC_TourAvailabilityRequest> requestByKey, Map<String, Date> dateByKey) {
        List<DVC_Tour_Guide_Shift__c> shiftsToInsert = new List<DVC_Tour_Guide_Shift__c>();
        List<DVC_Tour_Availability_Slot__c> slotsToInsert = new List<DVC_Tour_Availability_Slot__c>();

        for (DVC_Tour_Availability__c availability : insertedAvailabilities) {
            DVC_TourAvailabilityRequest request = requestByKey.get(availability.DVC_Location_Date_Key__c);
            Date theDate = dateByKey.get(availability.DVC_Location_Date_Key__c);

            for (DVC_TourAvailabilityRequest.GuideShift shift : request.guideShifts) {
                shiftsToInsert.add(new DVC_Tour_Guide_Shift__c(
                    DVC_Tour_Availability__c = availability.Id,
                    DVC_Shift_Start_Time__c = shift.shiftStartTime,
                    DVC_Shift_End_Time__c = shift.shiftEndTime,
                    DVC_Number_of_Guides__c = shift.numberOfGuides
                ));
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
    }
}
