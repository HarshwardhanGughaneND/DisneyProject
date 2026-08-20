@isTest
private class DVC_TourSlotGenerationServiceTest {

    @isTest
    static void testBuildAvailabilityRecordPopulatesKeyAndFields() {
        Location loc = DVC_TourAvailabilityTestDataFactory.createResortLocation('Beach Club');
        DVC_TourAvailabilityRequest request = DVC_TourAvailabilityTestDataFactory.buildCombo1Request(loc.Id);
        Date theDate = request.startDate;

        Test.startTest();
        DVC_Tour_Availability__c availability = DVC_TourSlotGenerationService.buildAvailabilityRecord(loc.Id, theDate, request);
        Test.stopTest();

        System.assertEquals(loc.Id, availability.DVC_Tour_Location__c);
        System.assertEquals(theDate, availability.DVC_Availability_Date__c);
        System.assertEquals(90, availability.DVC_Tour_Duration__c);
        System.assertEquals('30 Minutes', availability.DVC_Slot_Interval__c);
        System.assertEquals(true, availability.DVC_Lunch_Block_Needed__c);
        System.assertEquals(DVC_TourAvailabilityConstants.SLOT_TYPE_ONSITE, availability.DVC_Slot_Type__c);
        System.assert(availability.DVC_Location_Date_Key__c.startsWith(String.valueOf(loc.Id)));
        System.assert(availability.DVC_Location_Date_Key__c.endsWith('_Onsite'));
    }

    /**
     * Reproduces "Combo 1" from docs/DMS-4909-LLD.md Section 10.6 exactly:
     * 15 rows total, Open at 08:30, 10:00, 11:30 AM, 01:30, 03:00 PM (5 opens),
     * with Lunch rows at 12:30 PM and 01:00 PM.
     */
    @isTest
    static void testCombo1MatchesLldWorkedExample() {
        Location loc = DVC_TourAvailabilityTestDataFactory.createResortLocation('Beach Club');
        DVC_TourAvailabilityRequest request = DVC_TourAvailabilityTestDataFactory.buildCombo1Request(loc.Id);

        Test.startTest();
        // The parent Id isn't asserted on in this test, only used to populate the lookup field
        // on the (unsaved) slot sObjects - any valid Id works here, so we reuse the Location Id.
        List<DVC_Tour_Availability_Slot__c> slots = DVC_TourSlotGenerationService.buildSlotRecords(loc.Id, request.startDate, request);
        Test.stopTest();

        System.assertEquals(15, slots.size(), 'Expected 15 fixed 30-minute rows across an 08:30-16:00 window');

        List<Integer> expectedOnsite = new List<Integer>{ 2, 0, 0, 2, 0, 0, 2, 0, 0, 0, 2, 0, 0, 2, 0 };
        List<Boolean> expectedLunch = new List<Boolean>{
            false, false, false, false, false, false, false, false, true, true, false, false, false, false, false
        };

        for (Integer i = 0; i < slots.size(); i++) {
            System.assertEquals(expectedOnsite[i], (Integer) slots[i].DVC_Total_Onsite_Capacity__c,
                'Row ' + i + ' onsite capacity mismatch');
            System.assertEquals(expectedLunch[i], slots[i].DVC_Is_Lunch_Block__c,
                'Row ' + i + ' lunch flag mismatch');
            String expectedStatus = expectedOnsite[i] > 0
                ? DVC_TourAvailabilityConstants.SLOT_STATUS_OPEN
                : DVC_TourAvailabilityConstants.SLOT_STATUS_CLOSED;
            System.assertEquals(expectedStatus, slots[i].DVC_Slot_Status__c, 'Row ' + i + ' status mismatch');
        }

        Integer openCount = 0;
        for (DVC_Tour_Availability_Slot__c slot : slots) {
            if (slot.DVC_Total_Onsite_Capacity__c > 0) {
                openCount++;
            }
        }
        System.assertEquals(5, openCount, 'Expected exactly 5 Open rows');
    }

    /**
     * "Combo 4" from LLD Section 10.6: Duration = Interval = 60 min. Only 7 full rows are
     * generated because 08:30-16:00 (450 minutes) is not evenly divisible by 60 - the trailing
     * 03:30-04:00 PM block is dropped (LLD Section 20, Item 7). Only the single row that exactly
     * coincides with the Lunch window (12:30-01:30 PM) is Closed; all others are Open.
     */
    @isTest
    static void testCombo4SixtyMinuteIntervalLeftoverBlockAndLunchAlignment() {
        Location loc = DVC_TourAvailabilityTestDataFactory.createResortLocation('Beach Club');
        DVC_TourAvailabilityRequest request = DVC_TourAvailabilityTestDataFactory.buildCombo1Request(loc.Id);
        request.tourDurationMinutes = 60;
        request.slotInterval = '60 Minutes';

        Test.startTest();
        List<DVC_Tour_Availability_Slot__c> slots = DVC_TourSlotGenerationService.buildSlotRecords(loc.Id, request.startDate, request);
        Test.stopTest();

        System.assertEquals(7, slots.size(), 'Expected 7 full 60-minute rows with the trailing 30-minute block dropped');

        Integer openCount = 0;
        Integer lunchCount = 0;
        for (DVC_Tour_Availability_Slot__c slot : slots) {
            if (slot.DVC_Total_Onsite_Capacity__c > 0) {
                openCount++;
            }
            if (slot.DVC_Is_Lunch_Block__c) {
                lunchCount++;
            }
        }
        System.assertEquals(6, openCount, 'Expected 6 Open rows');
        System.assertEquals(1, lunchCount, 'Expected exactly 1 Lunch row');
    }

    /**
     * "Combo 6" from LLD Section 10.6: Duration = 90, Interval = 60. Demonstrates the
     * compounding effect where Lunch suppresses a would-be open row and the delayed restart
     * results in fewer opens than the no-lunch case.
     */
    @isTest
    static void testCombo6LunchCompoundingEffect() {
        Location loc = DVC_TourAvailabilityTestDataFactory.createResortLocation('Beach Club');
        DVC_TourAvailabilityRequest request = DVC_TourAvailabilityTestDataFactory.buildCombo1Request(loc.Id);
        request.tourDurationMinutes = 90;
        request.slotInterval = '60 Minutes';

        Test.startTest();
        List<DVC_Tour_Availability_Slot__c> slots = DVC_TourSlotGenerationService.buildSlotRecords(loc.Id, request.startDate, request);
        Test.stopTest();

        System.assertEquals(7, slots.size());

        Integer openCount = 0;
        for (DVC_Tour_Availability_Slot__c slot : slots) {
            if (slot.DVC_Total_Onsite_Capacity__c > 0) {
                openCount++;
            }
        }
        System.assertEquals(3, openCount, 'Expected 3 Open rows once Lunch delays the restart (LLD Section 10.6, Combo 6)');
    }

    @isTest
    static void testOnlineCapacityIsCappedAtOnsiteCapacity() {
        Location loc = DVC_TourAvailabilityTestDataFactory.createResortLocation('Beach Club');
        DVC_TourAvailabilityRequest request = DVC_TourAvailabilityTestDataFactory.buildCombo1Request(loc.Id);
        request.onlineTourBookingEnabled = true;
        request.onlineCapacityInput = 99; // deliberately far above onsite capacity (2)

        Test.startTest();
        List<DVC_Tour_Availability_Slot__c> slots = DVC_TourSlotGenerationService.buildSlotRecords(loc.Id, request.startDate, request);
        Test.stopTest();

        for (DVC_Tour_Availability_Slot__c slot : slots) {
            System.assert(slot.DVC_Total_Online_Capacity__c <= slot.DVC_Total_Onsite_Capacity__c,
                'Online capacity must never exceed Onsite capacity for the same row (VR-07)');
            if (slot.DVC_Total_Onsite_Capacity__c == 0) {
                System.assertEquals(0, slot.DVC_Total_Online_Capacity__c, 'Zero-capacity rows must show Online = 0 regardless of input');
            }
        }
    }

    @isTest
    static void testLocationDateKeyIsDeterministicAndUnique() {
        Location loc = DVC_TourAvailabilityTestDataFactory.createResortLocation('Beach Club');
        Date theDate = Date.newInstance(2026, 9, 1);

        String key1 = DVC_TourSlotGenerationService.buildLocationDateKey(loc.Id, theDate, 'Onsite');
        String key2 = DVC_TourSlotGenerationService.buildLocationDateKey(loc.Id, theDate, 'Onsite');
        String key3 = DVC_TourSlotGenerationService.buildLocationDateKey(loc.Id, theDate, 'Event');

        System.assertEquals(key1, key2, 'The same inputs must always produce the same key');
        System.assertNotEquals(key1, key3, 'Different Slot Types must produce different keys (LLD Section 15)');
        System.assert(key1.contains('2026-09-01'), 'Expected a stable, locale-independent ISO date in the key: ' + key1);
    }
}
