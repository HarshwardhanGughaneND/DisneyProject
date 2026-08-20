/**
 * DVC_TourAvailabilityValidationService
 *
 * Server-side re-validation of DVC_TourAvailabilityRequest against the validation rules in
 * docs/DMS-4909-LLD.md Section 9 (VR-01 through VR-09; VR-10 duplicate-key handling lives in
 * DVC_TourSlotGenerationBatch, since it needs to query existing records).
 *
 * SECURITY-REVIEW: this class treats every field on the incoming request as untrusted input
 * from the client (LWC) and never trusts client-side validation alone - all checks here are
 * re-run before any DML happens in DVC_TourAvailabilityPublishController / batch execution.
 */
public with sharing class DVC_TourAvailabilityValidationService {

    public static List<String> validate(DVC_TourAvailabilityRequest request) {
        List<String> errors = new List<String>();

        if (request == null) {
            errors.add('A schedule configuration is required.');
            return errors;
        }

        validateLocations(request, errors);
        validateDateRange(request, errors);
        validateOperatingHours(request, errors);
        validateGuideShifts(request, errors);
        validateLunchBlock(request, errors);
        validateDuration(request, errors);
        validateSlotInterval(request, errors);
        validateOnlineCapacity(request, errors);

        return errors;
    }

    private static void validateLocations(DVC_TourAvailabilityRequest request, List<String> errors) {
        // VR-01
        if (request.locationIds == null || request.locationIds.isEmpty()) {
            errors.add('Select at least one Tour Location to continue.');
        }
    }

    private static void validateDateRange(DVC_TourAvailabilityRequest request, List<String> errors) {
        if (request.startDate == null || request.endDate == null) {
            errors.add('Start Date and End Date are required.');
            return;
        }
        // VR-02
        if (request.endDate < request.startDate) {
            errors.add('End Date must be on or after Start Date.');
        }
        // VR-03 / BR-1
        if (request.startDate > Date.today().addDays(DVC_TourAvailabilityConstants.MAX_START_DATE_DAYS_IN_FUTURE)) {
            errors.add('Start Date cannot be more than ' + DVC_TourAvailabilityConstants.MAX_START_DATE_DAYS_IN_FUTURE + ' days in the future.');
        }
    }

    private static void validateOperatingHours(DVC_TourAvailabilityRequest request, List<String> errors) {
        // VR-04
        if (request.operatingStartTime == null || request.operatingEndTime == null
                || request.operatingStartTime >= request.operatingEndTime) {
            errors.add('Closing Time must be later than Opening Time.');
        }
    }

    private static void validateGuideShifts(DVC_TourAvailabilityRequest request, List<String> errors) {
        // VR-05. Overlap/gap/max-count rules are intentionally NOT enforced here - still pending
        // business confirmation (LLD Section 20, Item 1); only basic shape validity is checked.
        if (request.guideShifts == null || request.guideShifts.isEmpty()) {
            errors.add('At least one Guide Shift is required.');
            return;
        }
        for (DVC_TourAvailabilityRequest.GuideShift shift : request.guideShifts) {
            Boolean validTimes = shift.shiftStartTime != null && shift.shiftEndTime != null
                && shift.shiftStartTime < shift.shiftEndTime;
            Boolean validGuideCount = shift.numberOfGuides != null && shift.numberOfGuides >= 1;
            if (!validTimes || !validGuideCount) {
                errors.add('Enter a valid shift time range and guide count for every Guide Shift.');
                break;
            }
        }
    }

    private static void validateLunchBlock(DVC_TourAvailabilityRequest request, List<String> errors) {
        // VR-06
        if (request.lunchBlockNeeded != true) {
            return;
        }
        Boolean withinOperatingWindow = request.operatingStartTime != null && request.operatingEndTime != null
            && request.lunchStartTime != null && request.lunchEndTime != null
            && request.lunchStartTime >= request.operatingStartTime
            && request.lunchEndTime <= request.operatingEndTime;
        Boolean validLunchRange = request.lunchStartTime != null && request.lunchEndTime != null
            && request.lunchEndTime > request.lunchStartTime;

        if (!validLunchRange || !withinOperatingWindow) {
            errors.add('Enter a valid Lunch Start and Lunch End within the operating hours.');
        }
    }

    private static void validateDuration(DVC_TourAvailabilityRequest request, List<String> errors) {
        // VR-08
        if (request.tourDurationMinutes == null || request.tourDurationMinutes <= 0) {
            errors.add('Tour Duration must be greater than zero.');
        }
    }

    private static void validateSlotInterval(DVC_TourAvailabilityRequest request, List<String> errors) {
        if (String.isBlank(request.slotInterval)
                || !DVC_TourAvailabilityConstants.SLOT_INTERVAL_MINUTES.containsKey(request.slotInterval)) {
            errors.add('Select a valid Tour Slot Increment.');
        }
    }

    private static void validateOnlineCapacity(DVC_TourAvailabilityRequest request, List<String> errors) {
        // VR-09. VR-07 (online <= onsite) is structurally enforced per-slot at generation time
        // via MIN() in DVC_TourSlotGenerationService, since Onsite capacity is only known once
        // guide-occupancy is computed for that specific slot.
        if (request.onlineTourBookingEnabled == true
                && request.onlineCapacityInput != null
                && request.onlineCapacityInput < 0) {
            errors.add('Capacity values cannot be negative.');
        }
    }
}
