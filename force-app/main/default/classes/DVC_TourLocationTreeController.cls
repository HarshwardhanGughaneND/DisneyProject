/**
 * DVC_TourLocationTreeController
 *
 * Read-only data provider for the `dvcTourLocationTree` child LWC (docs/DMS-4909-LLD.md
 * Section 7.1 / 8.1). Returns Resort-type Location records grouped by their parent Channel
 * Location (e.g., Walt Disney World, Disneyland, Aulani).
 *
 * ASSUMPTION pending verification against the actual org schema: the standard Location
 * object's self-lookup field `ParentLocationId` has relationship name `ParentLocation`. If the
 * org uses a different relationship name, update the SOQL below accordingly.
 */
public with sharing class DVC_TourLocationTreeController {

    @AuraEnabled(cacheable=true)
    public static List<LocationGroup> getTourLocationTree() {
        Map<Id, LocationGroup> groupsByChannelId = new Map<Id, LocationGroup>();

        for (Location loc : [
            SELECT Id, Name, ParentLocationId, ParentLocation.Name
            FROM Location
            WHERE LocationType = :DVC_TourAvailabilityConstants.LOCATION_TYPE_RESORT
            WITH SECURITY_ENFORCED
            ORDER BY ParentLocation.Name NULLS LAST, Name ASC
        ]) {
            Id channelId = loc.ParentLocationId;
            String channelName = (loc.ParentLocation != null && loc.ParentLocation.Name != null)
                ? loc.ParentLocation.Name
                : 'Other';

            if (!groupsByChannelId.containsKey(channelId)) {
                LocationGroup group = new LocationGroup();
                group.channelId = channelId;
                group.channelName = channelName;
                group.resorts = new List<LocationOption>();
                groupsByChannelId.put(channelId, group);
            }

            LocationOption option = new LocationOption();
            option.locationId = loc.Id;
            option.label = loc.Name;
            groupsByChannelId.get(channelId).resorts.add(option);
        }

        return groupsByChannelId.values();
    }

    public class LocationGroup {
        @AuraEnabled public Id channelId;
        @AuraEnabled public String channelName;
        @AuraEnabled public List<LocationOption> resorts;
    }

    public class LocationOption {
        @AuraEnabled public Id locationId;
        @AuraEnabled public String label;
    }
}
