import { LightningElement, track } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';

export default class TourBookingWizard extends LightningElement {
    @track currentStep = 1;
    @track selectedGuest = null;
    @track selectedTimeSlot = null;
    @track selectedLocation = null;
    @track showLocationModal = false;

    get steps() {
        return [
            {
                id: 1,
                number: 1,
                label: 'Guest Search',
                completed: this.currentStep > 1,
                isLast: false,
                cssClass: this.getStepClass(1)
            },
            {
                id: 2,
                number: 2,
                label: 'Availability',
                completed: this.currentStep > 2,
                isLast: false,
                cssClass: this.getStepClass(2)
            },
            {
                id: 3,
                number: 3,
                label: 'Tour Location',
                completed: this.currentStep > 3,
                isLast: false,
                cssClass: this.getStepClass(3)
            },
            {
                id: 4,
                number: 4,
                label: 'Confirm Party',
                completed: this.currentStep > 4,
                isLast: true,
                cssClass: this.getStepClass(4)
            }
        ];
    }

    getStepClass(stepNumber) {
        let base = 'wizard-step slds-col';
        if (stepNumber === this.currentStep) return base + ' step-active';
        if (stepNumber < this.currentStep) return base + ' step-completed';
        return base + ' step-pending';
    }

    get isStep1() { return this.currentStep === 1; }
    get isStep2() { return this.currentStep === 2; }
    get isStep4() { return this.currentStep === 4; }

    handleGuestSelected(event) {
        this.selectedGuest = event.detail;
        this.currentStep = 2;
    }

    handleTimeSlotSelected(event) {
        this.selectedTimeSlot = event.detail;
        this.showLocationModal = true;
    }

    handleLocationSelected(event) {
        this.selectedLocation = event.detail;
        this.showLocationModal = false;
        this.currentStep = 4;
    }

    handleModalCancel() {
        this.showLocationModal = false;
    }

    handleBack() {
        if (this.currentStep > 1) {
            this.currentStep -= 1;
            this.showLocationModal = false;
        }
    }

    handleTourConfirmed(event) {
        const tourId = event.detail;
        this.dispatchEvent(
            new ShowToastEvent({
                title: 'Tour Booked!',
                message: 'Tour booking confirmed successfully. Tour ID: ' + tourId,
                variant: 'success'
            })
        );
        // Reset wizard
        this.currentStep = 1;
        this.selectedGuest = null;
        this.selectedTimeSlot = null;
        this.selectedLocation = null;
        this.showLocationModal = false;
    }
}
