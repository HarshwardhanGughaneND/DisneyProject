@isTest
private class DVC_TourAvailabilityPublishControllerTest {

    @isTest
    static void testValidatePublishRequestReturnsNoErrorsForValidRequest() {
        Location loc = DVC_TourAvailabilityTestDataFactory.createResortLocation('Beach Club');
        DVC_TourAvailabilityRequest request = DVC_TourAvailabilityTestDataFactory.buildCombo1Request(loc.Id);

        Test.startTest();
        List<String> errors = DVC_TourAvailabilityPublishController.validatePublishRequest(request);
        Test.stopTest();

        System.assertEquals(0, errors.size(), 'Expected no validation errors: ' + errors);
    }

    @isTest
    static void testPublishScheduleEnqueuesBatchForValidRequest() {
        Location loc = DVC_TourAvailabilityTestDataFactory.createResortLocation('Beach Club');
        DVC_TourAvailabilityRequest request = DVC_TourAvailabilityTestDataFactory.buildCombo1Request(loc.Id);

        Test.startTest();
        Id jobId = DVC_TourAvailabilityPublishController.publishSchedule(request);
        Test.stopTest();

        System.assertNotEquals(null, jobId, 'Expected an AsyncApexJob Id to be returned');

        List<DVC_Tour_Availability__c> published = [
            SELECT Id
            FROM DVC_Tour_Availability__c
            WHERE DVC_Tour_Location__c = :loc.Id
        ];
        System.assertEquals(1, published.size(), 'Expected exactly one published Tour Availability record');

        List<DVC_Tour_Availability_Slot__c> slots = [
            SELECT Id FROM DVC_Tour_Availability_Slot__c WHERE DVC_Tour_Availability__c = :published[0].Id
        ];
        System.assertEquals(15, slots.size(), 'Expected 15 slot rows for the Combo 1 configuration');
    }

    @isTest
    static void testPublishScheduleThrowsAuraHandledExceptionForInvalidRequest() {
        Location loc = DVC_TourAvailabilityTestDataFactory.createResortLocation('Beach Club');
        DVC_TourAvailabilityRequest request = DVC_TourAvailabilityTestDataFactory.buildCombo1Request(loc.Id);
        request.locationIds = new List<Id>(); // force VR-01 failure

        Test.startTest();
        Boolean threw = false;
        try {
            DVC_TourAvailabilityPublishController.publishSchedule(request);
        } catch (AuraHandledException ex) {
            threw = true;
        }
        Test.stopTest();

        System.assert(threw, 'Expected publishSchedule to throw an AuraHandledException for an invalid request');
    }

    @isTest
    static void testPublishScheduleRejectsDuplicatePublish() {
        Location loc = DVC_TourAvailabilityTestDataFactory.createResortLocation('Beach Club');
        DVC_TourAvailabilityRequest request = DVC_TourAvailabilityTestDataFactory.buildCombo1Request(loc.Id);

        Test.startTest();
        DVC_TourAvailabilityPublishController.publishSchedule(request);
        // Re-publish the exact same Location + Date + Slot Type - should be silently skipped,
        // not duplicated (VR-10 / LLD Section 11.2).
        DVC_TourAvailabilityPublishController.publishSchedule(request);
        Test.stopTest();

        List<DVC_Tour_Availability__c> published = [
            SELECT Id FROM DVC_Tour_Availability__c WHERE DVC_Tour_Location__c = :loc.Id
        ];
        System.assertEquals(1, published.size(), 'A duplicate publish for the same Location/Date/Slot Type must not create a second record');
    }
}
