/**
 * TourBookingControllerTest
 * Unit tests for TourBookingController.
 */
@IsTest
private class TourBookingControllerTest {

    @TestSetup
    static void setupData() {
        // Create Person Accounts (requires Person Account enabled org)
        RecordType personAccountRT = [
            SELECT Id FROM RecordType
            WHERE SObjectType = 'Account' AND IsPersonType = true
            LIMIT 1
        ];

        Account guest1 = new Account(
            FirstName = 'Mickey',
            LastName = 'Mouse',
            RecordTypeId = personAccountRT.Id,
            PersonEmail = 'mickey@disney.com',
            Phone = '4071234567',
            BillingStreet = '1 Magic Kingdom Way',
            BillingCity = 'Orlando',
            BillingState = 'FL',
            BillingPostalCode = '32830',
            BillingCountry = 'US'
        );
        insert guest1;

        Account guest2 = new Account(
            FirstName = 'Minnie',
            LastName = 'Mouse',
            RecordTypeId = personAccountRT.Id,
            PersonEmail = 'minnie@disney.com',
            Phone = '4079876543',
            BillingStreet = '1 Magic Kingdom Way',
            BillingCity = 'Orlando',
            BillingState = 'FL',
            BillingPostalCode = '32830',
            BillingCountry = 'US'
        );
        insert guest2;

        Tour_Location__c loc = new Tour_Location__c(
            Name = 'Magic Kingdom Tour',
            Area__c = 'MK Area',
            Description__c = 'Main Street Tour'
        );
        insert loc;

        Tour_Availability__c avail = new Tour_Availability__c(
            Tour_Location__c = loc.Id,
            Tour_Date__c = Date.today().addDays(1),
            Start_Time__c = '09:00 AM',
            End_Time__c = '10:00 AM',
            Total_Capacity__c = 10,
            Booked_Count__c = 2,
            Status__c = 'Open'
        );
        insert avail;
    }

    @IsTest
    static void testSearchGuests_byName() {
        Test.startTest();
        List<TourBookingController.GuestResult> results =
            TourBookingController.searchGuests('Mickey');
        Test.stopTest();
        System.assert(!results.isEmpty(), 'Should find Mickey Mouse');
    }

    @IsTest
    static void testSearchGuests_blank() {
        Test.startTest();
        List<TourBookingController.GuestResult> results =
            TourBookingController.searchGuests('');
        Test.stopTest();
        System.assertEquals(0, results.size(), 'Blank search returns empty list');
    }

    @IsTest
    static void testGetHouseholdMembers() {
        Account guest = [SELECT Id FROM Account WHERE FirstName = 'Mickey' LIMIT 1];
        Test.startTest();
        List<TourBookingController.HouseholdGroup> groups =
            TourBookingController.getHouseholdMembers(guest.Id);
        Test.stopTest();
        System.assertEquals(1, groups.size(), 'Should return 1 household group');
        System.assert(groups[0].householdName.contains('MOUSE'), 'Household name should contain MOUSE');
        System.assertEquals(1, groups[0].members.size(), 'Minnie should be in the household');
    }

    @IsTest
    static void testGetTourLocations() {
        Test.startTest();
        List<TourBookingController.TourLocationResult> locs =
            TourBookingController.getTourLocations('MK Area');
        Test.stopTest();
        System.assertEquals(1, locs.size(), 'Should return 1 location for MK Area');
    }

    @IsTest
    static void testGetTourAvailability() {
        String tomorrow = String.valueOf(Date.today().addDays(1));
        Test.startTest();
        List<TourBookingController.AvailabilityResult> results =
            TourBookingController.getTourAvailability(tomorrow, 'MK Area', null);
        Test.stopTest();
        System.assertEquals(1, results.size(), 'Should return 1 availability slot');
        System.assertEquals(8, results[0].availableSlots, 'Should have 8 available slots');
        System.assert(results[0].isAvailable, 'Slot should be available');
    }

    @IsTest
    static void testConfirmTour() {
        Account guest1 = [SELECT Id FROM Account WHERE FirstName = 'Mickey' LIMIT 1];
        Account guest2 = [SELECT Id FROM Account WHERE FirstName = 'Minnie' LIMIT 1];
        Tour_Location__c loc = [SELECT Id FROM Tour_Location__c LIMIT 1];
        Tour_Availability__c avail = [SELECT Id FROM Tour_Availability__c LIMIT 1];

        TourBookingController.TourBookingRequest req = new TourBookingController.TourBookingRequest();
        req.primaryGuestId = guest1.Id;
        req.locationId = loc.Id;
        req.tourDate = String.valueOf(Date.today().addDays(1));
        req.tourTime = '09:00 AM';
        req.area = 'MK Area';
        req.availabilityId = avail.Id;
        req.guestIds = new List<String>{ guest1.Id, guest2.Id };

        Test.startTest();
        String tourId = TourBookingController.confirmTour(req);
        Test.stopTest();

        System.assertNotEquals(null, tourId, 'Tour Id should not be null');
        Tour__c tour = [SELECT Id, Status__c FROM Tour__c WHERE Id = :tourId LIMIT 1];
        System.assertEquals('Confirmed', tour.Status__c);

        List<Tour_Guest__c> tgs = [SELECT Id FROM Tour_Guest__c WHERE Tour__c = :tourId];
        System.assertEquals(2, tgs.size(), 'Should have 2 tour guests');
    }
}
