@isTest
private class DVC_TourSlotGenerationBatchTest {

    @isTest
    static void testBatchPublishesOneAvailabilityPerLocationPerDate() {
        Location beachClub = DVC_TourAvailabilityTestDataFactory.createResortLocation('Beach Club');
        Location boardwalk = DVC_TourAvailabilityTestDataFactory.createResortLocation('Boardwalk Villas');

        DVC_TourAvailabilityRequest request = DVC_TourAvailabilityTestDataFactory.buildCombo1Request(beachClub.Id);
        request.locationIds = new List<Id>{ beachClub.Id, boardwalk.Id };
        request.startDate = Date.today().addDays(1);
        request.endDate = Date.today().addDays(3); // 3 days x 2 locations = 6 Availability records

        Test.startTest();
        Database.executeBatch(new DVC_TourSlotGenerationBatch(JSON.serialize(request)), 5);
        Test.stopTest();

        List<DVC_Tour_Availability__c> published = [
            SELECT Id, DVC_Tour_Location__c, DVC_Availability_Date__c
            FROM DVC_Tour_Availability__c
        ];
        System.assertEquals(6, published.size(), 'Expected one DVC_Tour_Availability__c per Location per Date (2 locations x 3 days)');

        List<DVC_Tour_Guide_Shift__c> shifts = [SELECT Id FROM DVC_Tour_Guide_Shift__c];
        System.assertEquals(6, shifts.size(), 'Expected one Guide Shift child per Availability record (single shift configured)');

        List<DVC_Tour_Availability_Slot__c> slots = [SELECT Id FROM DVC_Tour_Availability_Slot__c];
        System.assertEquals(6 * 15, slots.size(), 'Expected 15 slot rows per Availability record (Combo 1 pattern)');
    }

    @isTest
    static void testBatchSkipsAlreadyPublishedLocationDateSlotType() {
        Location loc = DVC_TourAvailabilityTestDataFactory.createResortLocation('Beach Club');
        DVC_TourAvailabilityRequest request = DVC_TourAvailabilityTestDataFactory.buildCombo1Request(loc.Id);

        Test.startTest();
        Database.executeBatch(new DVC_TourSlotGenerationBatch(JSON.serialize(request)), 5);
        Database.executeBatch(new DVC_TourSlotGenerationBatch(JSON.serialize(request)), 5);
        Test.stopTest();

        List<DVC_Tour_Availability__c> published = [SELECT Id FROM DVC_Tour_Availability__c WHERE DVC_Tour_Location__c = :loc.Id];
        System.assertEquals(1, published.size(), 'Re-running the batch for the same Location/Date/Slot Type must not create duplicates (VR-10)');
    }

    @isTest
    static void testBatchHandlesEmptyLocationListGracefully() {
        DVC_TourAvailabilityRequest request = new DVC_TourAvailabilityRequest();
        request.locationIds = new List<Id>();
        request.startDate = Date.today();
        request.endDate = Date.today();

        Test.startTest();
        Database.executeBatch(new DVC_TourSlotGenerationBatch(JSON.serialize(request)), 5);
        Test.stopTest();

        System.assertEquals(0, [SELECT COUNT() FROM DVC_Tour_Availability__c], 'No records should be created when no locations are supplied');
    }
}
