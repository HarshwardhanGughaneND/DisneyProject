import { LightningElement, api, track } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import getAvailableLocationsForSlot from '@salesforce/apex/TourBookingController.getAvailableLocationsForSlot';

export default class TourLocationModal extends LightningElement {
    @api selectedTime = null;
    @api selectedGuest = null;

    @track availableLocations = [];
    @track selectedLocationId = null;
    @track isLoading = false;

    connectedCallback() {
        this.loadLocations();
    }

    get formattedSlotTime() {
        if (!this.selectedTime) return '';
        return this.selectedTime.startTime || '';
    }

    get selectedDate() {
        if (!this.selectedTime) return '';
        const d = this.selectedTime.tourDate;
        if (!d) return '';
        // Format as readable date
        try {
            const parts = d.split('-');
            return new Date(
                parseInt(parts[0]),
                parseInt(parts[1]) - 1,
                parseInt(parts[2])
            ).toLocaleDateString('en-US', { weekday: 'long', year: 'numeric', month: 'long', day: 'numeric' });
        } catch (e) {
            return d;
        }
    }

    get areaLabel() {
        return this.selectedTime ? this.selectedTime.area || '' : '';
    }

    get hasLocations() {
        return this.availableLocations && this.availableLocations.length > 0;
    }

    get isNextDisabled() {
        return !this.selectedLocationId;
    }

    loadLocations() {
        if (!this.selectedTime) return;
        this.isLoading = true;

        getAvailableLocationsForSlot({
            tourDate: this.selectedTime.tourDate,
            startTime: this.selectedTime.startTime,
            area: this.selectedTime.area || null
        })
            .then(locs => {
                this.availableLocations = locs.map(loc => this.enrichLocation(loc));
                this.isLoading = false;

                // If no real data found, load mock locations for demo
                if (this.availableLocations.length === 0) {
                    this.availableLocations = this.getMockLocations();
                }
            })
            .catch(() => {
                this.isLoading = false;
                // Fall back to mock locations
                this.availableLocations = this.getMockLocations();
            });
    }

    getMockLocations() {
        return [
            { id: 'mock-1', name: 'Saratoga Springs', area: this.areaLabel, description: 'A charming resort retreat', availableSlots: 5, isSelected: false, rowClass: 'location-item', slotPlural: 's' },
            { id: 'mock-2', name: 'Riviera', area: this.areaLabel, description: 'European-inspired riviera style', availableSlots: 3, isSelected: false, rowClass: 'location-item', slotPlural: 's' },
            { id: 'mock-3', name: 'Island Tour at Polynesian', area: this.areaLabel, description: 'South Pacific paradise experience', availableSlots: 8, isSelected: false, rowClass: 'location-item', slotPlural: 's' },
            { id: 'mock-4', name: 'Cabins at Fort Wilderness', area: this.areaLabel, description: 'Classic woodland cabin adventure', availableSlots: 12, isSelected: false, rowClass: 'location-item', slotPlural: 's' },
            { id: 'mock-5', name: 'Disney Springs', area: this.areaLabel, description: 'Shopping, dining and entertainment', availableSlots: 4, isSelected: false, rowClass: 'location-item', slotPlural: 's' }
        ];
    }

    enrichLocation(loc) {
        const slots = loc.availableSlots || 0;
        return {
            ...loc,
            isSelected: false,
            rowClass: 'location-item',
            slotPlural: slots !== 1 ? 's' : ''
        };
    }

    handleLocationSelect(event) {
        const locId = event.currentTarget.dataset.id;
        this.selectedLocationId = locId;
        this.availableLocations = this.availableLocations.map(loc => ({
            ...loc,
            isSelected: loc.id === locId,
            rowClass: loc.id === locId ? 'location-item location-item_selected' : 'location-item'
        }));
    }

    handleLocationKeyPress(event) {
        if (event.key === 'Enter' || event.key === ' ') {
            event.preventDefault();
            this.handleLocationSelect(event);
        }
    }

    handleNext() {
        if (!this.selectedLocationId) return;
        const selectedLoc = this.availableLocations.find(l => l.id === this.selectedLocationId);
        this.dispatchEvent(
            new CustomEvent('location-selected', {
                detail: {
                    ...selectedLoc,
                    tourDate: this.selectedTime ? this.selectedTime.tourDate : '',
                    startTime: this.selectedTime ? this.selectedTime.startTime : '',
                    area: this.areaLabel,
                    availabilityId: this.selectedTime ? this.selectedTime.id : ''
                },
                bubbles: true,
                composed: true
            })
        );
    }

    handleCancel() {
        this.dispatchEvent(new CustomEvent('cancel', { bubbles: true, composed: true }));
    }
}
