/**
 * DVC_TourSlotGenerationService
 *
 * Pure, stateless slot-generation logic for the DMS-4909 Tour Availability Generator - the
 * server-side mirror of the same algorithm that must also run client-side in the
 * `dvcTourSchedulePreviewGrid` LWC for the disposable, no-DML "Generate & Preview" step
 * (docs/DMS-4909-LLD.md Section 10.1). This class performs NO DML; callers (Controller/Batch/
 * Scheduled Job) are responsible for inserting the sObjects this class builds.
 *
 * CORRECTED MODEL (see LLD Section 10.1): each generated `DVC_Tour_Availability_Slot__c` row is
 * a FIXED-WIDTH block of `DVC_Slot_Interval__c`, tiling the full operating window - it is NOT a
 * sliding window sized to the full Tour Duration. Tour Duration only controls how many
 * consecutive rows are blocked (zero capacity) after a tour starts. The Lunch-overlap check is
 * evaluated against each row's own Slot-Interval-wide window, not the full Tour Duration span of
 * a would-be tour - this is intentional and matches the reference mock-up exactly, but is one of
 * several points still pending formal business confirmation (LLD Section 20, Items 7-9).
 */
public with sharing class DVC_TourSlotGenerationService {

    /**
     * Builds (but does not insert) the parent DVC_Tour_Availability__c record for one
     * Location + Date, including the system-managed uniqueness key (LLD Section 15).
     */
    public static DVC_Tour_Availability__c buildAvailabilityRecord(Id locationId, Date theDate, DVC_TourAvailabilityRequest request) {
        String slotType = String.isBlank(request.slotType) ? DVC_TourAvailabilityConstants.SLOT_TYPE_ONSITE : request.slotType;
        Boolean lunchNeeded = request.lunchBlockNeeded == true;

        return new DVC_Tour_Availability__c(
            DVC_Tour_Location__c = locationId,
            DVC_Availability_Date__c = theDate,
            DVC_Operating_Start_Time__c = request.operatingStartTime,
            DVC_Operating_End_Time__c = request.operatingEndTime,
            DVC_Tour_Duration__c = request.tourDurationMinutes,
            DVC_Slot_Interval__c = request.slotInterval,
            DVC_Lunch_Block_Needed__c = lunchNeeded,
            DVC_Lunch_Start_Time__c = lunchNeeded ? request.lunchStartTime : null,
            DVC_Lunch_End_Time__c = lunchNeeded ? request.lunchEndTime : null,
            DVC_Online_Tour_Booking_Enabled__c = request.onlineTourBookingEnabled == true,
            DVC_Slot_Type__c = slotType,
            DVC_Location_Date_Key__c = buildLocationDateKey(locationId, theDate, slotType)
        );
    }

    /**
     * Deterministic composite key = Location + Date + Slot Type (LLD Section 15). Uses a
     * manually-built ISO date string (rather than Date.format(), which is locale-dependent) so
     * the key is stable across users/locales.
     */
    public static String buildLocationDateKey(Id locationId, Date theDate, String slotType) {
        return String.valueOf(locationId) + '_' + isoDate(theDate) + '_' + slotType;
    }

    /**
     * Generates the full set of fixed-Slot-Interval-width slot rows for one Location + Date,
     * given an already-inserted (or about-to-be-inserted) parent Id.
     */
    public static List<DVC_Tour_Availability_Slot__c> buildSlotRecords(Id parentAvailabilityId, Date theDate, DVC_TourAvailabilityRequest request) {
        List<DVC_Tour_Availability_Slot__c> slots = new List<DVC_Tour_Availability_Slot__c>();

        Integer slotIntervalMinutes = DVC_TourAvailabilityConstants.SLOT_INTERVAL_MINUTES.get(request.slotInterval);
        Integer tourDurationMinutes = request.tourDurationMinutes;
        if (slotIntervalMinutes == null || tourDurationMinutes == null
                || request.operatingStartTime == null || request.operatingEndTime == null) {
            return slots;
        }

        Integer operatingStartMinutes = toMinutes(request.operatingStartTime);
        Integer operatingEndMinutes = toMinutes(request.operatingEndTime);

        Boolean lunchNeeded = request.lunchBlockNeeded == true
            && request.lunchStartTime != null && request.lunchEndTime != null;
        Integer lunchStartMinutes = lunchNeeded ? toMinutes(request.lunchStartTime) : null;
        Integer lunchEndMinutes = lunchNeeded ? toMinutes(request.lunchEndTime) : null;

        Integer nextAvailableMinutes = operatingStartMinutes;
        Integer rowStartMinutes = operatingStartMinutes;

        // ASSUMPTION pending business confirmation (LLD Section 20, Item 7): if the operating
        // window is not evenly divisible by Slot Interval, the trailing partial block is simply
        // dropped - no row is generated for it.
        while (rowStartMinutes + slotIntervalMinutes <= operatingEndMinutes) {
            Integer rowEndMinutes = rowStartMinutes + slotIntervalMinutes;

            Integer guideCapacity = guideCapacityAt(rowStartMinutes, request.guideShifts);

            Boolean isLunchRow = lunchNeeded
                && rowStartMinutes < lunchEndMinutes
                && rowEndMinutes > lunchStartMinutes;

            Integer onsiteCapacity;
            if (guideCapacity == 0 || isLunchRow) {
                onsiteCapacity = 0;
                // nextAvailableMinutes is deliberately NOT advanced here - a lunch-blocked row
                // does not count as a tour start, even when guides were otherwise free.
            } else if (rowStartMinutes >= nextAvailableMinutes) {
                onsiteCapacity = guideCapacity;
                nextAvailableMinutes = rowStartMinutes + tourDurationMinutes;
            } else {
                onsiteCapacity = 0; // guides still occupied by an earlier tour
            }

            Integer onlineCapacity = 0;
            if (request.onlineTourBookingEnabled == true && onsiteCapacity > 0 && request.onlineCapacityInput != null) {
                onlineCapacity = Math.min(request.onlineCapacityInput.intValue(), onsiteCapacity);
            }

            slots.add(new DVC_Tour_Availability_Slot__c(
                DVC_Tour_Availability__c = parentAvailabilityId,
                DVC_Slot_Start_DateTime__c = toDateTime(theDate, rowStartMinutes),
                DVC_Slot_End_DateTime__c = toDateTime(theDate, rowEndMinutes),
                DVC_Total_Onsite_Capacity__c = onsiteCapacity,
                DVC_Total_Online_Capacity__c = onlineCapacity,
                DVC_Booked_Online_Slots__c = 0,
                DVC_Booked_Onsite_Slots__c = 0,
                DVC_Is_Lunch_Block__c = isLunchRow,
                DVC_Slot_Status__c = onsiteCapacity > 0
                    ? DVC_TourAvailabilityConstants.SLOT_STATUS_OPEN
                    : DVC_TourAvailabilityConstants.SLOT_STATUS_CLOSED
            ));

            rowStartMinutes += slotIntervalMinutes;
        }

        return slots;
    }

    /**
     * Sum of guides across every configured shift covering `rowStartMinutes`.
     * ASSUMPTION pending business confirmation (LLD Section 20, Item 1): shifts do not overlap;
     * if they do, their guide counts are simply summed.
     */
    private static Integer guideCapacityAt(Integer rowStartMinutes, List<DVC_TourAvailabilityRequest.GuideShift> guideShifts) {
        Integer total = 0;
        if (guideShifts == null) {
            return total;
        }
        for (DVC_TourAvailabilityRequest.GuideShift shift : guideShifts) {
            if (shift.shiftStartTime == null || shift.shiftEndTime == null || shift.numberOfGuides == null) {
                continue;
            }
            Integer shiftStartMinutes = toMinutes(shift.shiftStartTime);
            Integer shiftEndMinutes = toMinutes(shift.shiftEndTime);
            if (shiftStartMinutes <= rowStartMinutes && rowStartMinutes < shiftEndMinutes) {
                total += shift.numberOfGuides;
            }
        }
        return total;
    }

    private static Integer toMinutes(Time t) {
        return (t.hour() * 60) + t.minute();
    }

    private static Time toMinutesTime(Integer totalMinutes) {
        Integer clamped = Math.mod(totalMinutes, 24 * 60);
        Integer hour = clamped / 60;
        Integer minute = Math.mod(clamped, 60);
        return Time.newInstance(hour, minute, 0, 0);
    }

    private static DateTime toDateTime(Date theDate, Integer totalMinutes) {
        return DateTime.newInstance(theDate, toMinutesTime(totalMinutes));
    }

    private static String isoDate(Date theDate) {
        return String.valueOf(theDate.year())
            + '-' + String.valueOf(theDate.month()).leftPad(2, '0')
            + '-' + String.valueOf(theDate.day()).leftPad(2, '0');
    }
}
