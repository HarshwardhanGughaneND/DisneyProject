/**
 * TourBookingController
 * Central Apex controller for the Tour Booking LWC wizard.
 * Handles guest search, household retrieval, availability lookup,
 * tour location retrieval, and record creation.
 */
public with sharing class TourBookingController {

    // ─────────────────────────────────────────────────────────────
    // GUEST SEARCH
    // ─────────────────────────────────────────────────────────────

    /**
     * Searches Person Accounts by name, email, phone, or address.
     * Uses SOSL for full-text relevance search; falls back to SOQL
     * for exact field matches to ensure broad coverage.
     */
    @AuraEnabled(cacheable=true)
    public static List<GuestResult> searchGuests(String searchTerm) {
        if (String.isBlank(searchTerm) || searchTerm.trim().length() < 2) {
            return new List<GuestResult>();
        }
        String term = String.escapeSingleQuotes(searchTerm.trim());
        String wildcard = '%' + term + '%';

        // SOSL search across multiple fields
        Set<Id> soslIds = new Set<Id>();
        String soslQuery = 'FIND :term IN ALL FIELDS RETURNING Account(Id WHERE IsPersonAccount = true) LIMIT 50';
        List<List<SObject>> soslResults = Search.query(soslQuery);
        if (!soslResults.isEmpty()) {
            for (SObject so : soslResults[0]) {
                soslIds.add(so.Id);
            }
        }

        // SOQL fallback for field-level wildcard matching
        List<Account> accounts = [
            SELECT Id, Name, PersonEmail, Phone, BillingStreet, BillingCity,
                   BillingState, BillingPostalCode, BillingCountry,
                   PersonMobilePhone, RecordType.Name
            FROM Account
            WHERE IsPersonAccount = true
              AND (
                    Name LIKE :wildcard
                 OR PersonEmail LIKE :wildcard
                 OR Phone LIKE :wildcard
                 OR PersonMobilePhone LIKE :wildcard
                 OR BillingStreet LIKE :wildcard
                 OR BillingCity LIKE :wildcard
                 OR BillingPostalCode LIKE :wildcard
              )
            LIMIT 50
        ];

        // Merge SOSL results
        Map<Id, Account> accountMap = new Map<Id, Account>();
        for (Account a : accounts) {
            accountMap.put(a.Id, a);
        }
        if (!soslIds.isEmpty()) {
            for (Account a : [
                SELECT Id, Name, PersonEmail, Phone, BillingStreet, BillingCity,
                       BillingState, BillingPostalCode, BillingCountry,
                       PersonMobilePhone, RecordType.Name
                FROM Account
                WHERE Id IN :soslIds AND IsPersonAccount = true
                LIMIT 50
            ]) {
                accountMap.put(a.Id, a);
            }
        }

        List<GuestResult> results = new List<GuestResult>();
        for (Account a : accountMap.values()) {
            results.add(new GuestResult(a));
        }
        return results;
    }

    /**
     * Returns members of the same household (same BillingStreet + BillingCity)
     * as the selected guest, grouped by address.
     */
    @AuraEnabled(cacheable=true)
    public static List<HouseholdGroup> getHouseholdMembers(Id guestId) {
        Account guest = [
            SELECT Id, Name, BillingStreet, BillingCity, BillingState, BillingPostalCode
            FROM Account
            WHERE Id = :guestId
            LIMIT 1
        ];

        if (String.isBlank(guest.BillingStreet)) {
            return new List<HouseholdGroup>();
        }

        List<Account> members = [
            SELECT Id, Name, PersonEmail, Phone, BillingStreet, BillingCity,
                   BillingState, BillingPostalCode
            FROM Account
            WHERE IsPersonAccount = true
              AND BillingStreet = :guest.BillingStreet
              AND BillingCity = :guest.BillingCity
              AND Id != :guestId
            LIMIT 50
        ];

        // Group into a single household
        HouseholdGroup group = new HouseholdGroup();
        group.householdName = deriveHouseholdName(guest, members);
        group.members = new List<GuestResult>();
        for (Account m : members) {
            group.members.add(new GuestResult(m));
        }

        return new List<HouseholdGroup>{ group };
    }

    // ─────────────────────────────────────────────────────────────
    // TOUR LOCATIONS
    // ─────────────────────────────────────────────────────────────

    @AuraEnabled(cacheable=true)
    public static List<TourLocationResult> getTourLocations(String area) {
        String query = 'SELECT Id, Name, Area__c, Description__c FROM Tour_Location__c';
        if (String.isNotBlank(area)) {
            query += ' WHERE Area__c = \'' + String.escapeSingleQuotes(area) + '\'';
        }
        query += ' ORDER BY Name LIMIT 200';

        List<TourLocationResult> results = new List<TourLocationResult>();
        for (Tour_Location__c loc : Database.query(query)) {
            TourLocationResult r = new TourLocationResult();
            r.id = loc.Id;
            r.name = loc.Name;
            r.area = loc.Area__c;
            r.description = loc.Description__c;
            results.add(r);
        }
        return results;
    }

    // ─────────────────────────────────────────────────────────────
    // TOUR AVAILABILITY
    // ─────────────────────────────────────────────────────────────

    /**
     * Returns availability slots for a given date and optional area/location filter.
     */
    @AuraEnabled(cacheable=true)
    public static List<AvailabilityResult> getTourAvailability(
        String tourDate,
        String area,
        String locationId
    ) {
        Date selectedDate;
        try {
            selectedDate = Date.valueOf(tourDate);
        } catch (Exception e) {
            selectedDate = Date.today();
        }

        String soql = 'SELECT Id, Name, Tour_Date__c, Start_Time__c, End_Time__c, ' +
                      'Total_Capacity__c, Booked_Count__c, Tour_Location__c, ' +
                      'Tour_Location__r.Name, Tour_Location__r.Area__c, Status__c ' +
                      'FROM Tour_Availability__c ' +
                      'WHERE Tour_Date__c = :selectedDate';

        if (String.isNotBlank(locationId)) {
            soql += ' AND Tour_Location__c = \'' + String.escapeSingleQuotes(locationId) + '\'';
        } else if (String.isNotBlank(area)) {
            soql += ' AND Tour_Location__r.Area__c = \'' + String.escapeSingleQuotes(area) + '\'';
        }
        soql += ' ORDER BY Start_Time__c LIMIT 200';

        List<AvailabilityResult> results = new List<AvailabilityResult>();
        for (Tour_Availability__c avail : Database.query(soql)) {
            AvailabilityResult r = new AvailabilityResult();
            r.id = avail.Id;
            r.name = avail.Name;
            r.tourDate = String.valueOf(avail.Tour_Date__c);
            r.startTime = avail.Start_Time__c;
            r.endTime = avail.End_Time__c;
            r.totalCapacity = avail.Total_Capacity__c != null ? Integer.valueOf(avail.Total_Capacity__c) : 0;
            r.bookedCount = avail.Booked_Count__c != null ? Integer.valueOf(avail.Booked_Count__c) : 0;
            r.availableSlots = r.totalCapacity - r.bookedCount;
            r.locationId = avail.Tour_Location__c;
            r.locationName = avail.Tour_Location__r != null ? avail.Tour_Location__r.Name : '';
            r.area = avail.Tour_Location__r != null ? avail.Tour_Location__r.Area__c : '';
            r.status = avail.Status__c;
            r.isAvailable = r.availableSlots > 0 && avail.Status__c != 'Closed';
            results.add(r);
        }
        return results;
    }

    /**
     * Returns detailed slots for a specific availability record (used in modal).
     */
    @AuraEnabled(cacheable=true)
    public static List<SlotResult> getAvailabilitySlots(Id availabilityId) {
        List<SlotResult> results = new List<SlotResult>();
        for (Tour_Availability_Slot__c slot : [
            SELECT Id, Name, Slot_Time__c, Available__c, Tour_Location__c,
                   Tour_Location__r.Name, Tour_Location__r.Area__c,
                   Tour_Availability__c
            FROM Tour_Availability_Slot__c
            WHERE Tour_Availability__c = :availabilityId
            ORDER BY Slot_Time__c
            LIMIT 200
        ]) {
            SlotResult r = new SlotResult();
            r.id = slot.Id;
            r.name = slot.Name;
            r.slotTime = slot.Slot_Time__c;
            r.available = slot.Available__c;
            r.locationId = slot.Tour_Location__c;
            r.locationName = slot.Tour_Location__r != null ? slot.Tour_Location__r.Name : '';
            r.area = slot.Tour_Location__r != null ? slot.Tour_Location__r.Area__c : '';
            results.add(r);
        }
        return results;
    }

    /**
     * Returns all available tour locations for a given availability record (for the modal).
     */
    @AuraEnabled(cacheable=true)
    public static List<TourLocationResult> getAvailableLocationsForSlot(
        String tourDate,
        String startTime,
        String area
    ) {
        Date selectedDate;
        try {
            selectedDate = Date.valueOf(tourDate);
        } catch (Exception e) {
            selectedDate = Date.today();
        }

        String soql = 'SELECT Id, Tour_Location__c, Tour_Location__r.Name, ' +
                      'Tour_Location__r.Area__c, Tour_Location__r.Description__c, ' +
                      'Total_Capacity__c, Booked_Count__c ' +
                      'FROM Tour_Availability__c ' +
                      'WHERE Tour_Date__c = :selectedDate ' +
                      'AND Start_Time__c = \'' + String.escapeSingleQuotes(startTime) + '\'' +
                      ' AND (Total_Capacity__c > Booked_Count__c) AND Status__c != \'Closed\'';

        if (String.isNotBlank(area)) {
            soql += ' AND Tour_Location__r.Area__c = \'' + String.escapeSingleQuotes(area) + '\'';
        }
        soql += ' ORDER BY Tour_Location__r.Name LIMIT 50';

        List<TourLocationResult> results = new List<TourLocationResult>();
        for (Tour_Availability__c avail : Database.query(soql)) {
            if (avail.Tour_Location__c == null) continue;
            TourLocationResult r = new TourLocationResult();
            r.id = avail.Tour_Location__c;
            r.name = avail.Tour_Location__r != null ? avail.Tour_Location__r.Name : '';
            r.area = avail.Tour_Location__r != null ? avail.Tour_Location__r.Area__c : '';
            r.description = avail.Tour_Location__r != null ? avail.Tour_Location__r.Description__c : '';
            r.availableSlots = avail.Total_Capacity__c != null && avail.Booked_Count__c != null
                ? Integer.valueOf(avail.Total_Capacity__c) - Integer.valueOf(avail.Booked_Count__c)
                : 0;
            results.add(r);
        }
        return results;
    }

    // ─────────────────────────────────────────────────────────────
    // RECORD CREATION
    // ─────────────────────────────────────────────────────────────

    /**
     * Creates the Tour__c booking record plus one Tour_Guest__c per party member.
     * Returns the new Tour Id.
     */
    @AuraEnabled
    public static String confirmTour(TourBookingRequest request) {
        Savepoint sp = Database.setSavepoint();
        try {
            Tour__c tour = new Tour__c();
            tour.Primary_Guest__c = request.primaryGuestId;
            tour.Tour_Location__c = request.locationId;
            tour.Tour_Date__c = Date.valueOf(request.tourDate);
            tour.Tour_Time__c = request.tourTime;
            tour.Area__c = request.area;
            tour.Status__c = 'Confirmed';
            insert tour;

            List<Tour_Guest__c> guests = new List<Tour_Guest__c>();
            for (String guestId : request.guestIds) {
                Tour_Guest__c tg = new Tour_Guest__c();
                tg.Tour__c = tour.Id;
                tg.Guest__c = guestId;
                tg.Is_Primary__c = (guestId == request.primaryGuestId);
                guests.add(tg);
            }
            if (!guests.isEmpty()) {
                insert guests;
            }

            // Update booked count on availability
            if (String.isNotBlank(request.availabilityId)) {
                Tour_Availability__c avail = [
                    SELECT Id, Booked_Count__c FROM Tour_Availability__c
                    WHERE Id = :request.availabilityId LIMIT 1
                ];
                avail.Booked_Count__c = (avail.Booked_Count__c != null ? avail.Booked_Count__c : 0)
                                        + request.guestIds.size();
                update avail;
            }

            return tour.Id;
        } catch (Exception e) {
            Database.rollback(sp);
            throw new AuraHandledException('Error creating tour booking: ' + e.getMessage());
        }
    }

    // ─────────────────────────────────────────────────────────────
    // HELPER METHODS
    // ─────────────────────────────────────────────────────────────

    private static String deriveHouseholdName(Account primary, List<Account> members) {
        // Extract last name from primary guest
        String lastName = primary.Name != null && primary.Name.contains(' ')
            ? primary.Name.substringAfterLast(' ').toUpperCase()
            : primary.Name != null ? primary.Name.toUpperCase() : 'HOUSEHOLD';
        return lastName + ' HOUSEHOLD';
    }

    // ─────────────────────────────────────────────────────────────
    // INNER CLASSES (Data Transfer Objects)
    // ─────────────────────────────────────────────────────────────

    public class GuestResult {
        @AuraEnabled public String id;
        @AuraEnabled public String name;
        @AuraEnabled public String email;
        @AuraEnabled public String phone;
        @AuraEnabled public String address;
        @AuraEnabled public String street;
        @AuraEnabled public String city;
        @AuraEnabled public String state;
        @AuraEnabled public String postalCode;
        @AuraEnabled public String country;

        public GuestResult(Account a) {
            this.id = a.Id;
            this.name = a.Name;
            this.email = a.PersonEmail;
            this.phone = String.isNotBlank(a.Phone) ? a.Phone : a.PersonMobilePhone;
            this.street = a.BillingStreet;
            this.city = a.BillingCity;
            this.state = a.BillingState;
            this.postalCode = a.BillingPostalCode;
            this.country = a.BillingCountry;
            List<String> parts = new List<String>();
            if (String.isNotBlank(a.BillingStreet)) parts.add(a.BillingStreet);
            if (String.isNotBlank(a.BillingCity)) parts.add(a.BillingCity);
            if (String.isNotBlank(a.BillingState)) parts.add(a.BillingState);
            if (String.isNotBlank(a.BillingPostalCode)) parts.add(a.BillingPostalCode);
            this.address = String.join(parts, ', ');
        }
    }

    public class HouseholdGroup {
        @AuraEnabled public String householdName;
        @AuraEnabled public List<GuestResult> members;
    }

    public class TourLocationResult {
        @AuraEnabled public String id;
        @AuraEnabled public String name;
        @AuraEnabled public String area;
        @AuraEnabled public String description;
        @AuraEnabled public Integer availableSlots;
    }

    public class AvailabilityResult {
        @AuraEnabled public String id;
        @AuraEnabled public String name;
        @AuraEnabled public String tourDate;
        @AuraEnabled public String startTime;
        @AuraEnabled public String endTime;
        @AuraEnabled public Integer totalCapacity;
        @AuraEnabled public Integer bookedCount;
        @AuraEnabled public Integer availableSlots;
        @AuraEnabled public String locationId;
        @AuraEnabled public String locationName;
        @AuraEnabled public String area;
        @AuraEnabled public String status;
        @AuraEnabled public Boolean isAvailable;
    }

    public class SlotResult {
        @AuraEnabled public String id;
        @AuraEnabled public String name;
        @AuraEnabled public String slotTime;
        @AuraEnabled public Boolean available;
        @AuraEnabled public String locationId;
        @AuraEnabled public String locationName;
        @AuraEnabled public String area;
    }

    public class TourBookingRequest {
        @AuraEnabled public String primaryGuestId;
        @AuraEnabled public String locationId;
        @AuraEnabled public String tourDate;
        @AuraEnabled public String tourTime;
        @AuraEnabled public String area;
        @AuraEnabled public String availabilityId;
        @AuraEnabled public List<String> guestIds;
    }
}
