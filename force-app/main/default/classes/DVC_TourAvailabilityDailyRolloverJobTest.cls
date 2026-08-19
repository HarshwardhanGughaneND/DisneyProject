@isTest
private class DVC_TourAvailabilityDailyRolloverJobTest {

    private static DVC_Tour_Availability__c createTemplateAvailability(Id locationId, Date theDate) {
        DVC_Tour_Availability__c availability = new DVC_Tour_Availability__c(
            DVC_Tour_Location__c = locationId,
            DVC_Availability_Date__c = theDate,
            DVC_Operating_Start_Time__c = Time.newInstance(8, 30, 0, 0),
            DVC_Operating_End_Time__c = Time.newInstance(16, 0, 0, 0),
            DVC_Tour_Duration__c = 90,
            DVC_Slot_Interval__c = '30 Minutes',
            DVC_Lunch_Block_Needed__c = true,
            DVC_Lunch_Start_Time__c = Time.newInstance(12, 30, 0, 0),
            DVC_Lunch_End_Time__c = Time.newInstance(13, 30, 0, 0),
            DVC_Online_Tour_Booking_Enabled__c = true,
            DVC_Slot_Type__c = DVC_TourAvailabilityConstants.SLOT_TYPE_ONSITE,
            DVC_Location_Date_Key__c = DVC_TourSlotGenerationService.buildLocationDateKey(
                locationId, theDate, DVC_TourAvailabilityConstants.SLOT_TYPE_ONSITE)
        );
        insert availability;

        insert new DVC_Tour_Guide_Shift__c(
            DVC_Tour_Availability__c = availability.Id,
            DVC_Shift_Start_Time__c = Time.newInstance(8, 30, 0, 0),
            DVC_Shift_End_Time__c = Time.newInstance(16, 0, 0, 0),
            DVC_Number_of_Guides__c = 2
        );

        insert new DVC_Tour_Availability_Slot__c(
            DVC_Tour_Availability__c = availability.Id,
            DVC_Slot_Start_DateTime__c = DateTime.newInstance(theDate, Time.newInstance(8, 30, 0, 0)),
            DVC_Slot_End_DateTime__c = DateTime.newInstance(theDate, Time.newInstance(9, 0, 0, 0)),
            DVC_Total_Onsite_Capacity__c = 2,
            DVC_Total_Online_Capacity__c = 1,
            DVC_Slot_Status__c = DVC_TourAvailabilityConstants.SLOT_STATUS_OPEN
        );

        return availability;
    }

    @isTest
    static void testRollForwardCreatesNextDayFromTemplate() {
        Location loc = DVC_TourAvailabilityTestDataFactory.createResortLocation('Beach Club');
        Date templateDate = Date.today();
        createTemplateAvailability(loc.Id, templateDate);

        Test.startTest();
        new DVC_TourAvailabilityDailyRolloverJob().rollForward();
        Test.stopTest();

        Date expectedNewDate = templateDate.addDays(1);
        List<DVC_Tour_Availability__c> rolledForward = [
            SELECT Id, DVC_Tour_Duration__c, DVC_Slot_Interval__c, DVC_Online_Tour_Booking_Enabled__c
            FROM DVC_Tour_Availability__c
            WHERE DVC_Tour_Location__c = :loc.Id AND DVC_Availability_Date__c = :expectedNewDate
        ];
        System.assertEquals(1, rolledForward.size(), 'Expected exactly one new Availability record for the next day');
        System.assertEquals(90, rolledForward[0].DVC_Tour_Duration__c);
        System.assertEquals('30 Minutes', rolledForward[0].DVC_Slot_Interval__c);
        System.assertEquals(true, rolledForward[0].DVC_Online_Tour_Booking_Enabled__c);

        List<DVC_Tour_Guide_Shift__c> shifts = [
            SELECT Id, DVC_Number_of_Guides__c FROM DVC_Tour_Guide_Shift__c
            WHERE DVC_Tour_Availability__c = :rolledForward[0].Id
        ];
        System.assertEquals(1, shifts.size());
        System.assertEquals(2, shifts[0].DVC_Number_of_Guides__c);

        List<DVC_Tour_Availability_Slot__c> slots = [
            SELECT Id, DVC_Total_Online_Capacity__c FROM DVC_Tour_Availability_Slot__c
            WHERE DVC_Tour_Availability__c = :rolledForward[0].Id
        ];
        System.assertEquals(15, slots.size(), 'Expected the same Combo 1 pattern (15 rows) to be replicated forward');

        Boolean foundClonedOnlineCapacity = false;
        for (DVC_Tour_Availability_Slot__c slot : slots) {
            if (slot.DVC_Total_Online_Capacity__c == 1) {
                foundClonedOnlineCapacity = true;
                break;
            }
        }
        System.assert(foundClonedOnlineCapacity, 'Expected the Online Capacity value (1) to be cloned from the prior day\'s existing slot');
    }

    @isTest
    static void testRollForwardDoesNothingWhenHorizonAlreadyCovered() {
        Location loc = DVC_TourAvailabilityTestDataFactory.createResortLocation('Beach Club');
        Date templateDate = Date.today().addDays(DVC_TourAvailabilityConstants.MAX_START_DATE_DAYS_IN_FUTURE);
        createTemplateAvailability(loc.Id, templateDate);

        Test.startTest();
        new DVC_TourAvailabilityDailyRolloverJob().rollForward();
        Test.stopTest();

        Integer totalAvailabilities = [SELECT COUNT() FROM DVC_Tour_Availability__c WHERE DVC_Tour_Location__c = :loc.Id];
        System.assertEquals(1, totalAvailabilities, 'No new record should be created once the 90-day horizon is already fully covered');
    }

    @isTest
    static void testRollForwardSkipsWhenNextDayAlreadyExists() {
        Location loc = DVC_TourAvailabilityTestDataFactory.createResortLocation('Beach Club');
        Date templateDate = Date.today();
        createTemplateAvailability(loc.Id, templateDate);
        createTemplateAvailability(loc.Id, templateDate.addDays(1)); // next day already published manually

        Test.startTest();
        new DVC_TourAvailabilityDailyRolloverJob().rollForward();
        Test.stopTest();

        Integer totalAvailabilities = [SELECT COUNT() FROM DVC_Tour_Availability__c WHERE DVC_Tour_Location__c = :loc.Id];
        System.assertEquals(2, totalAvailabilities, 'The pre-existing next-day record must not be duplicated (Section 15 uniqueness)');
    }

    @isTest
    static void testJobCanBeScheduled() {
        Test.startTest();
        String jobId = System.schedule('DVC Tour Availability Daily Rollover Test',
            DVC_TourAvailabilityDailyRolloverJob.CRON_EXPRESSION, new DVC_TourAvailabilityDailyRolloverJob());
        Test.stopTest();

        System.assertNotEquals(null, jobId);
        CronTrigger trigger = [SELECT Id, CronExpression, State FROM CronTrigger WHERE Id = :jobId];
        System.assertEquals(DVC_TourAvailabilityDailyRolloverJob.CRON_EXPRESSION, trigger.CronExpression);
    }
}
