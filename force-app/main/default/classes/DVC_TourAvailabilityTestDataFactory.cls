/**
 * DVC_TourAvailabilityTestDataFactory
 *
 * Shared test data builders for the DMS-4909 Tour Availability Generator test classes, so every
 * test class builds Location records and request payloads the same way (DRY, and easy to update
 * in one place if the standard Location object's required fields differ in a given org).
 */
@isTest
public class DVC_TourAvailabilityTestDataFactory {

    public static Location createResortLocation(String name) {
        Location loc = new Location(
            Name = name,
            LocationType = DVC_TourAvailabilityConstants.LOCATION_TYPE_RESORT
        );
        insert loc;
        return loc;
    }

    /**
     * Builds the exact "Combo 1" scenario from docs/DMS-4909-LLD.md Section 10.6:
     * Opening 08:30 AM - Closing 04:00 PM, one Guide Shift 08:30 AM-04:00 PM with 2 guides,
     * Tour Duration = 90 mins, Slot Interval = 30 mins, Lunch 12:30 PM-01:30 PM, Online off.
     * Expected result: 15 rows, 5 Open (08:30, 10:00, 11:30 AM, 01:30, 03:00 PM), 10 Closed
     * (2 of which are Lunch rows: 12:30 PM and 01:00 PM).
     */
    public static DVC_TourAvailabilityRequest buildCombo1Request(Id locationId) {
        DVC_TourAvailabilityRequest request = new DVC_TourAvailabilityRequest();
        request.locationIds = new List<Id>{ locationId };
        request.startDate = Date.today().addDays(1);
        request.endDate = Date.today().addDays(1);
        request.operatingStartTime = Time.newInstance(8, 30, 0, 0);
        request.operatingEndTime = Time.newInstance(16, 0, 0, 0);
        request.tourDurationMinutes = 90;
        request.slotInterval = '30 Minutes';
        request.lunchBlockNeeded = true;
        request.lunchStartTime = Time.newInstance(12, 30, 0, 0);
        request.lunchEndTime = Time.newInstance(13, 30, 0, 0);
        request.onlineTourBookingEnabled = false;
        request.onlineCapacityInput = null;
        request.slotType = DVC_TourAvailabilityConstants.SLOT_TYPE_ONSITE;

        DVC_TourAvailabilityRequest.GuideShift shift = new DVC_TourAvailabilityRequest.GuideShift();
        shift.shiftStartTime = request.operatingStartTime;
        shift.shiftEndTime = request.operatingEndTime;
        shift.numberOfGuides = 2;
        request.guideShifts = new List<DVC_TourAvailabilityRequest.GuideShift>{ shift };

        return request;
    }
}
