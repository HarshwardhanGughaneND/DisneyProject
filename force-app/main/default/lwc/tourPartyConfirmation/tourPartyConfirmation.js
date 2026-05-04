import { LightningElement, api, track } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import getHouseholdMembers from '@salesforce/apex/TourBookingController.getHouseholdMembers';
import confirmTour from '@salesforce/apex/TourBookingController.confirmTour';

export default class TourPartyConfirmation extends LightningElement {
    @api selectedGuest = null;
    @api selectedLocation = null;
    @api selectedTimeSlot = null;

    @track tourParty = [];
    @track householdGroups = [];
    @track partySearchTerm = '';
    @track isLoadingHousehold = false;
    @track isConfirming = false;

    connectedCallback() {
        // Always start with primary guest in the tour party
        if (this.selectedGuest) {
            this.tourParty = [{
                ...this.selectedGuest,
                isPrimary: true
            }];
            this.loadHouseholdMembers();
        }
    }

    // ─── Computed Properties ──────────────────────────────────

    get selectedLocationName() {
        return this.selectedLocation ? this.selectedLocation.name : '';
    }

    get selectedTime() {
        return this.selectedTimeSlot ? this.selectedTimeSlot.startTime : '';
    }

    get selectedArea() {
        return this.selectedTimeSlot ? this.selectedTimeSlot.area : '';
    }

    get primaryGuestName() {
        return this.selectedGuest ? this.selectedGuest.name : '';
    }

    get formattedDate() {
        if (!this.selectedTimeSlot || !this.selectedTimeSlot.tourDate) return '';
        try {
            const parts = this.selectedTimeSlot.tourDate.split('-');
            return new Date(
                parseInt(parts[0]),
                parseInt(parts[1]) - 1,
                parseInt(parts[2])
            ).toLocaleDateString('en-US', { weekday: 'short', year: 'numeric', month: 'short', day: 'numeric' });
        } catch (e) {
            return this.selectedTimeSlot.tourDate;
        }
    }

    get partyCount() {
        return this.tourParty ? this.tourParty.length : 0;
    }

    get hasTourParty() {
        return this.tourParty && this.tourParty.length > 0;
    }

    get hasHouseholdGroups() {
        return this.householdGroups && this.householdGroups.length > 0;
    }

    get isConfirmDisabled() {
        return this.tourParty.length === 0;
    }

    // ─── Household Logic ─────────────────────────────────────

    loadHouseholdMembers() {
        if (!this.selectedGuest || !this.selectedGuest.id) return;
        this.isLoadingHousehold = true;

        getHouseholdMembers({ guestId: this.selectedGuest.id })
            .then(groups => {
                this.householdGroups = groups.map(group => this.enrichGroup(group));
                this.isLoadingHousehold = false;
            })
            .catch(() => {
                this.isLoadingHousehold = false;
                // Use mock data for demo
                this.householdGroups = this.getMockHouseholds();
            });
    }

    getMockHouseholds() {
        const primaryLastName = this.selectedGuest && this.selectedGuest.name
            ? this.selectedGuest.name.split(' ').pop().toUpperCase()
            : 'GUEST';

        return [
            {
                householdName: primaryLastName + ' HOUSEHOLD',
                members: [
                    { id: 'mock-hh-1', name: 'Sarah ' + this.selectedGuest.name.split(' ').pop(), email: 'sarah@example.com', phone: '4071112222', address: this.selectedGuest.address },
                    { id: 'mock-hh-2', name: 'James ' + this.selectedGuest.name.split(' ').pop(), email: 'james@example.com', phone: '4073334444', address: this.selectedGuest.address }
                ],
                hasFilteredMembers: true,
                filteredMembers: []
            },
            {
                householdName: 'ROW HOUSEHOLD',
                members: [
                    { id: 'mock-hh-3', name: 'Tom Row', email: 'tom@example.com', phone: '4075556666', address: '2 Epcot Center Dr' },
                    { id: 'mock-hh-4', name: 'Lisa Row', email: 'lisa@example.com', phone: '4077778888', address: '2 Epcot Center Dr' }
                ],
                hasFilteredMembers: true,
                filteredMembers: []
            }
        ].map(g => this.enrichGroup(g));
    }

    enrichGroup(group) {
        const partyIds = new Set(this.tourParty.map(m => m.id));
        const term = this.partySearchTerm.toLowerCase();

        const filtered = (group.members || []).filter(m =>
            !term || m.name.toLowerCase().includes(term) ||
            (m.email && m.email.toLowerCase().includes(term))
        ).map(m => ({
            ...m,
            inParty: partyIds.has(m.id)
        }));

        return {
            ...group,
            filteredMembers: filtered,
            hasFilteredMembers: filtered.length > 0
        };
    }

    refreshHouseholdGroups() {
        this.householdGroups = this.householdGroups.map(g => this.enrichGroup(g));
    }

    // ─── Event Handlers ───────────────────────────────────────

    handlePartySearchInput(event) {
        this.partySearchTerm = event.target.value;
        this.refreshHouseholdGroups();
    }

    handleAddMember(event) {
        const memberId = event.currentTarget.dataset.id;

        // Find member across all groups
        let memberToAdd = null;
        for (const group of this.householdGroups) {
            const found = group.members.find(m => m.id === memberId);
            if (found) { memberToAdd = found; break; }
        }

        if (!memberToAdd) return;

        // Avoid duplicates
        if (this.tourParty.some(m => m.id === memberId)) return;

        this.tourParty = [
            ...this.tourParty,
            { ...memberToAdd, isPrimary: false }
        ];
        this.refreshHouseholdGroups();
    }

    handleRemoveMember(event) {
        const memberId = event.currentTarget.dataset.id;
        this.tourParty = this.tourParty.filter(m => m.id !== memberId);
        this.refreshHouseholdGroups();
    }

    handleTapAction() {
        this.dispatchEvent(
            new ShowToastEvent({
                title: 'Tap Guest Media',
                message: 'Please tap the guest\'s media device to identify.',
                variant: 'info'
            })
        );
    }

    handleCameraAction() {
        this.dispatchEvent(
            new ShowToastEvent({
                title: 'Camera Scan',
                message: 'Please scan the guest\'s QR code or barcode.',
                variant: 'info'
            })
        );
    }

    handleBack() {
        this.dispatchEvent(new CustomEvent('back', { bubbles: true, composed: true }));
    }

    handleConfirmTour() {
        if (this.tourParty.length === 0) return;
        this.isConfirming = true;

        const request = {
            primaryGuestId: this.selectedGuest.id,
            locationId: this.selectedLocation ? this.selectedLocation.id : null,
            tourDate: this.selectedTimeSlot ? this.selectedTimeSlot.tourDate : '',
            tourTime: this.selectedTimeSlot ? this.selectedTimeSlot.startTime : '',
            area: this.selectedTimeSlot ? this.selectedTimeSlot.area : '',
            availabilityId: this.selectedTimeSlot ? this.selectedTimeSlot.id : '',
            guestIds: this.tourParty.map(m => m.id)
        };

        confirmTour({ request })
            .then(tourId => {
                this.isConfirming = false;
                this.dispatchEvent(
                    new CustomEvent('tour-confirmed', {
                        detail: tourId,
                        bubbles: true,
                        composed: true
                    })
                );
            })
            .catch(error => {
                this.isConfirming = false;
                this.dispatchEvent(
                    new ShowToastEvent({
                        title: 'Error Confirming Tour',
                        message: this.extractErrorMessage(error),
                        variant: 'error'
                    })
                );
            });
    }

    extractErrorMessage(error) {
        if (error && error.body && error.body.message) return error.body.message;
        if (error && error.message) return error.message;
        return 'An unknown error occurred.';
    }
}
