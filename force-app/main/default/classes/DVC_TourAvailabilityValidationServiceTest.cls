@isTest
private class DVC_TourAvailabilityValidationServiceTest {

    @isTest
    static void testValidRequestProducesNoErrors() {
        Location loc = DVC_TourAvailabilityTestDataFactory.createResortLocation('Beach Club');
        DVC_TourAvailabilityRequest request = DVC_TourAvailabilityTestDataFactory.buildCombo1Request(loc.Id);

        Test.startTest();
        List<String> errors = DVC_TourAvailabilityValidationService.validate(request);
        Test.stopTest();

        System.assertEquals(0, errors.size(), 'A fully valid request should produce no validation errors: ' + errors);
    }

    @isTest
    static void testNullRequestIsRejected() {
        Test.startTest();
        List<String> errors = DVC_TourAvailabilityValidationService.validate(null);
        Test.stopTest();

        System.assertEquals(1, errors.size());
    }

    @isTest
    static void testMissingLocationIsRejected() {
        DVC_TourAvailabilityRequest request = DVC_TourAvailabilityTestDataFactory.buildCombo1Request(null);
        request.locationIds = new List<Id>();

        List<String> errors = DVC_TourAvailabilityValidationService.validate(request);

        System.assert(hasErrorContaining(errors, 'Tour Location'), 'Expected a Tour Location required error: ' + errors);
    }

    @isTest
    static void testEndDateBeforeStartDateIsRejected() {
        Location loc = DVC_TourAvailabilityTestDataFactory.createResortLocation('Beach Club');
        DVC_TourAvailabilityRequest request = DVC_TourAvailabilityTestDataFactory.buildCombo1Request(loc.Id);
        request.startDate = Date.today().addDays(5);
        request.endDate = Date.today().addDays(1);

        List<String> errors = DVC_TourAvailabilityValidationService.validate(request);

        System.assert(hasErrorContaining(errors, 'End Date'), 'Expected an End Date ordering error: ' + errors);
    }

    @isTest
    static void testStartDateBeyond90DaysIsRejected() {
        Location loc = DVC_TourAvailabilityTestDataFactory.createResortLocation('Beach Club');
        DVC_TourAvailabilityRequest request = DVC_TourAvailabilityTestDataFactory.buildCombo1Request(loc.Id);
        request.startDate = Date.today().addDays(91);
        request.endDate = Date.today().addDays(95);

        List<String> errors = DVC_TourAvailabilityValidationService.validate(request);

        System.assert(hasErrorContaining(errors, '90 days'), 'Expected a 90-day cap error: ' + errors);
    }

    @isTest
    static void testClosingTimeBeforeOpeningTimeIsRejected() {
        Location loc = DVC_TourAvailabilityTestDataFactory.createResortLocation('Beach Club');
        DVC_TourAvailabilityRequest request = DVC_TourAvailabilityTestDataFactory.buildCombo1Request(loc.Id);
        request.operatingStartTime = Time.newInstance(16, 0, 0, 0);
        request.operatingEndTime = Time.newInstance(8, 30, 0, 0);

        List<String> errors = DVC_TourAvailabilityValidationService.validate(request);

        System.assert(hasErrorContaining(errors, 'Closing Time'), 'Expected a Closing Time ordering error: ' + errors);
    }

    @isTest
    static void testMissingGuideShiftIsRejected() {
        Location loc = DVC_TourAvailabilityTestDataFactory.createResortLocation('Beach Club');
        DVC_TourAvailabilityRequest request = DVC_TourAvailabilityTestDataFactory.buildCombo1Request(loc.Id);
        request.guideShifts = new List<DVC_TourAvailabilityRequest.GuideShift>();

        List<String> errors = DVC_TourAvailabilityValidationService.validate(request);

        System.assert(hasErrorContaining(errors, 'Guide Shift'), 'Expected a Guide Shift required error: ' + errors);
    }

    @isTest
    static void testInvalidLunchWindowIsRejected() {
        Location loc = DVC_TourAvailabilityTestDataFactory.createResortLocation('Beach Club');
        DVC_TourAvailabilityRequest request = DVC_TourAvailabilityTestDataFactory.buildCombo1Request(loc.Id);
        request.lunchStartTime = Time.newInstance(13, 30, 0, 0);
        request.lunchEndTime = Time.newInstance(12, 30, 0, 0); // end before start

        List<String> errors = DVC_TourAvailabilityValidationService.validate(request);

        System.assert(hasErrorContaining(errors, 'Lunch'), 'Expected a Lunch window error: ' + errors);
    }

    @isTest
    static void testZeroDurationIsRejected() {
        Location loc = DVC_TourAvailabilityTestDataFactory.createResortLocation('Beach Club');
        DVC_TourAvailabilityRequest request = DVC_TourAvailabilityTestDataFactory.buildCombo1Request(loc.Id);
        request.tourDurationMinutes = 0;

        List<String> errors = DVC_TourAvailabilityValidationService.validate(request);

        System.assert(hasErrorContaining(errors, 'Tour Duration'), 'Expected a Tour Duration error: ' + errors);
    }

    @isTest
    static void testNegativeOnlineCapacityIsRejected() {
        Location loc = DVC_TourAvailabilityTestDataFactory.createResortLocation('Beach Club');
        DVC_TourAvailabilityRequest request = DVC_TourAvailabilityTestDataFactory.buildCombo1Request(loc.Id);
        request.onlineTourBookingEnabled = true;
        request.onlineCapacityInput = -1;

        List<String> errors = DVC_TourAvailabilityValidationService.validate(request);

        System.assert(hasErrorContaining(errors, 'negative'), 'Expected a negative capacity error: ' + errors);
    }

    private static Boolean hasErrorContaining(List<String> errors, String fragment) {
        for (String error : errors) {
            if (error.contains(fragment)) {
                return true;
            }
        }
        return false;
    }
}
