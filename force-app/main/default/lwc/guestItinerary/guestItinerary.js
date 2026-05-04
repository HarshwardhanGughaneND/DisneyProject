import { LightningElement, api, track } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import getTourLocations from '@salesforce/apex/TourBookingController.getTourLocations';
import getTourAvailability from '@salesforce/apex/TourBookingController.getTourAvailability';

const AREAS = [
    { label: 'MK Area', value: 'MK Area' },
    { label: 'EP Area', value: 'EP Area' },
    { label: 'DHS Area', value: 'DHS Area' },
    { label: 'DAK Area', value: 'DAK Area' },
    { label: 'DS Area', value: 'DS Area' }
];

export default class GuestItinerary extends LightningElement {
    @api selectedGuest = null;

    @track selectedArea = 'MK Area';
    @track selectedLocationId = '';
    @track selectedDate = '';
    @track isLoading = false;
    @track availabilitySlots = [];
    @track locationOptions = [{ label: 'All Locations', value: '' }];

    connectedCallback() {
        const today = new Date();
        this.selectedDate = this.formatDateValue(today);
        this.loadLocations();
        this.loadAvailability();
    }

    get guestName() {
        return this.selectedGuest ? this.selectedGuest.name : '';
    }

    get guestEmail() {
        return this.selectedGuest ? this.selectedGuest.email : '';
    }

    get guestPhone() {
        return this.selectedGuest ? this.selectedGuest.phone : '';
    }

    get guestAddress() {
        return this.selectedGuest ? this.selectedGuest.address : '';
    }

    get areaTabs() {
        return AREAS.map(a => ({
            ...a,
            cssClass: 'area-tab-btn' + (a.value === this.selectedArea ? ' tab-active' : '')
        }));
    }

    get hasSlots() {
        return this.availabilitySlots && this.availabilitySlots.length > 0;
    }

    formatDateValue(date) {
        const y = date.getFullYear();
        const m = String(date.getMonth() + 1).padStart(2, '0');
        const d = String(date.getDate()).padStart(2, '0');
        return `${y}-${m}-${d}`;
    }

    loadLocations() {
        getTourLocations({ area: this.selectedArea })
            .then(locs => {
                const opts = [{ label: 'All Locations', value: '' }];
                locs.forEach(loc => opts.push({ label: loc.name, value: loc.id }));
                this.locationOptions = opts;
            })
            .catch(() => {
                // silently continue – non-critical
            });
    }

    loadAvailability() {
        this.isLoading = true;
        getTourAvailability({
            tourDate: this.selectedDate,
            area: this.selectedArea,
            locationId: this.selectedLocationId || null
        })
            .then(results => {
                this.availabilitySlots = results.map(slot => this.enrichSlot(slot));
                this.isLoading = false;
            })
            .catch(error => {
                this.isLoading = false;
                this.dispatchEvent(
                    new ShowToastEvent({
                        title: 'Error Loading Availability',
                        message: this.extractErrorMessage(error),
                        variant: 'error'
                    })
                );
            });
    }

    enrichSlot(slot) {
        const available = slot.isAvailable;
        const slotsText = available
            ? `Tours Available (${slot.availableSlots} slot${slot.availableSlots !== 1 ? 's' : ''})`
            : 'No Tours Available';

        return {
            ...slot,
            availabilityLabel: slotsText,
            badgeClass: available ? 'availability-badge badge-available' : 'availability-badge badge-unavailable',
            dotClass: available ? 'availability-dot dot-green' : 'availability-dot dot-red',
            rowClass: available ? 'timeline-row timeline-row_available' : 'timeline-row timeline-row_unavailable'
        };
    }

    handleAreaTabClick(event) {
        this.selectedArea = event.currentTarget.dataset.value;
        this.selectedLocationId = '';
        this.loadLocations();
        this.loadAvailability();
    }

    handleLocationChange(event) {
        this.selectedLocationId = event.detail.value;
        this.loadAvailability();
    }

    handleDateChange(event) {
        this.selectedDate = event.detail.value;
        this.loadAvailability();
    }

    handlePrevDay() {
        const d = new Date(this.selectedDate + 'T00:00:00');
        d.setDate(d.getDate() - 1);
        this.selectedDate = this.formatDateValue(d);
        this.loadAvailability();
    }

    handleNextDay() {
        const d = new Date(this.selectedDate + 'T00:00:00');
        d.setDate(d.getDate() + 1);
        this.selectedDate = this.formatDateValue(d);
        this.loadAvailability();
    }

    handleSlotClick(event) {
        const slotId = event.currentTarget.dataset.id;
        const slot = this.availabilitySlots.find(s => s.id === slotId);
        if (!slot || !slot.isAvailable) return;

        this.dispatchEvent(
            new CustomEvent('time-slot-selected', {
                detail: {
                    ...slot,
                    tourDate: this.selectedDate,
                    area: this.selectedArea
                },
                bubbles: true,
                composed: true
            })
        );
    }

    handleBack() {
        this.dispatchEvent(new CustomEvent('back', { bubbles: true, composed: true }));
    }

    extractErrorMessage(error) {
        if (error && error.body && error.body.message) return error.body.message;
        if (error && error.message) return error.message;
        return 'An unknown error occurred.';
    }
}
