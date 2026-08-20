@isTest
private class DVC_TourLocationTreeControllerTest {

    @isTest
    static void testGetTourLocationTreeGroupsResortsByChannel() {
        Location channel = new Location(Name = 'Walt Disney World', LocationType = 'Channel');
        insert channel;

        Location resort1 = new Location(Name = 'Beach Club', LocationType = DVC_TourAvailabilityConstants.LOCATION_TYPE_RESORT, ParentLocationId = channel.Id);
        Location resort2 = new Location(Name = 'Boardwalk Villas', LocationType = DVC_TourAvailabilityConstants.LOCATION_TYPE_RESORT, ParentLocationId = channel.Id);
        insert new List<Location>{ resort1, resort2 };

        Test.startTest();
        List<DVC_TourLocationTreeController.LocationGroup> groups = DVC_TourLocationTreeController.getTourLocationTree();
        Test.stopTest();

        System.assertEquals(1, groups.size(), 'Expected a single channel group');
        System.assertEquals('Walt Disney World', groups[0].channelName);
        System.assertEquals(2, groups[0].resorts.size());
    }

    @isTest
    static void testGetTourLocationTreeReturnsEmptyListWhenNoResorts() {
        Test.startTest();
        List<DVC_TourLocationTreeController.LocationGroup> groups = DVC_TourLocationTreeController.getTourLocationTree();
        Test.stopTest();

        System.assertEquals(0, groups.size());
    }
}
