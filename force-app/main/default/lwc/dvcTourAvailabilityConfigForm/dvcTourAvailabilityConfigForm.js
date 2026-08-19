import { LightningElement, api } from 'lwc';

let shiftKeySequence = 0;
function nextShiftKey() {
    shiftKeySequence += 1;
    return `shift-${shiftKeySequence}`;
}

const DEFAULT_TOUR_DURATION_MINUTES = 60;
const DEFAULT_SLOT_INTERVAL = '30 Minutes';
const DEFAULT_NUMBER_OF_GUIDES = 2; // confirmed default per LLD Decision Log Q8

/**
 * dvcTourAvailabilityConfigForm
 *
 * Child LWC - Config Form (docs/DMS-4909-LLD.md Section 4.1 / 8.1). Captures Start/End Date,
 * Opening/Closing Time, a repeatable list of Guide Shifts, Lunch Block, Tour Duration, Tour
 * Slot Increment, and Online Tour Booking, and emits `configchange` with the full config
 * object on every field change. Exposes `getConfig()` and `reportValidity()` for the container.
 */
export default class DvcTourAvailabilityConfigForm extends LightningElement {
    startDate;
    endDate;
    operatingStartTime;
    operatingEndTime;
    guideShifts = [this.createShift()];
    lunchBlockNeeded = false;
    lunchStartTime;
    lunchEndTime;
    tourDurationMinutes = DEFAULT_TOUR_DURATION_MINUTES;
    slotInterval = DEFAULT_SLOT_INTERVAL;
    onlineTourBookingEnabled = false;
    onlineCapacityInput;

    slotIntervalOptions = [
        { label: '15 Minutes', value: '15 Minutes' },
        { label: '30 Minutes', value: '30 Minutes' },
        { label: '60 Minutes', value: '60 Minutes' }
    ];

    createShift() {
        return {
            key: nextShiftKey(),
            shiftStartTime: null,
            shiftEndTime: null,
            numberOfGuides: DEFAULT_NUMBER_OF_GUIDES
        };
    }

    handleStartDateChange(event) {
        this.startDate = event.target.value;
        this.notifyChange();
    }

    handleEndDateChange(event) {
        this.endDate = event.target.value;
        this.notifyChange();
    }

    handleOpeningTimeChange(event) {
        this.operatingStartTime = event.target.value;
        this.notifyChange();
    }

    handleClosingTimeChange(event) {
        this.operatingEndTime = event.target.value;
        this.notifyChange();
    }

    handleShiftStartChange(event) {
        this.updateShift(event.target.dataset.key, 'shiftStartTime', event.target.value);
    }

    handleShiftEndChange(event) {
        this.updateShift(event.target.dataset.key, 'shiftEndTime', event.target.value);
    }

    handleShiftGuidesChange(event) {
        this.updateShift(event.target.dataset.key, 'numberOfGuides', Number(event.target.value));
    }

    updateShift(shiftKey, field, value) {
        this.guideShifts = this.guideShifts.map((shift) =>
            shift.key === shiftKey ? { ...shift, [field]: value } : shift
        );
        this.notifyChange();
    }

    handleAddShift() {
        const templateShift = {
            key: nextShiftKey(),
            shiftStartTime: this.operatingStartTime,
            shiftEndTime: this.operatingEndTime,
            numberOfGuides: DEFAULT_NUMBER_OF_GUIDES
        };
        this.guideShifts = [...this.guideShifts, templateShift];
        this.notifyChange();
    }

    handleRemoveShift(event) {
        if (this.guideShifts.length <= 1) {
            return; // at least one shift is required (VR-05)
        }
        const shiftKey = event.target.dataset.key;
        this.guideShifts = this.guideShifts.filter((shift) => shift.key !== shiftKey);
        this.notifyChange();
    }

    handleLunchToggleChange(event) {
        this.lunchBlockNeeded = event.target.checked;
        this.notifyChange();
    }

    handleLunchStartChange(event) {
        this.lunchStartTime = event.target.value;
        this.notifyChange();
    }

    handleLunchEndChange(event) {
        this.lunchEndTime = event.target.value;
        this.notifyChange();
    }

    handleDurationChange(event) {
        this.tourDurationMinutes = event.target.value;
        this.notifyChange();
    }

    handleSlotIntervalChange(event) {
        this.slotInterval = event.detail.value;
        this.notifyChange();
    }

    handleOnlineToggleChange(event) {
        this.onlineTourBookingEnabled = event.target.checked;
        this.notifyChange();
    }

    handleOnlineCapacityChange(event) {
        this.onlineCapacityInput = event.target.value;
        this.notifyChange();
    }

    notifyChange() {
        this.dispatchEvent(new CustomEvent('configchange', { detail: this.buildConfig() }));
    }

    buildConfig() {
        return {
            startDate: this.startDate,
            endDate: this.endDate,
            operatingStartTime: this.operatingStartTime,
            operatingEndTime: this.operatingEndTime,
            guideShifts: this.guideShifts.map(({ shiftStartTime, shiftEndTime, numberOfGuides }) => ({
                shiftStartTime,
                shiftEndTime,
                numberOfGuides
            })),
            lunchBlockNeeded: this.lunchBlockNeeded,
            lunchStartTime: this.lunchBlockNeeded ? this.lunchStartTime : null,
            lunchEndTime: this.lunchBlockNeeded ? this.lunchEndTime : null,
            tourDurationMinutes: this.tourDurationMinutes != null ? Number(this.tourDurationMinutes) : null,
            slotInterval: this.slotInterval,
            onlineTourBookingEnabled: this.onlineTourBookingEnabled,
            onlineCapacityInput:
                this.onlineTourBookingEnabled && this.onlineCapacityInput !== '' && this.onlineCapacityInput != null
                    ? Number(this.onlineCapacityInput)
                    : null
        };
    }

    @api
    getConfig() {
        return this.buildConfig();
    }

    /**
     * Runs native HTML5 validity checks (required/min/type) across every field. Business-rule
     * validation (date ranges, lunch-within-hours, etc.) is re-run server-side regardless -
     * this is a UX convenience only (LLD Section 9).
     */
    @api
    reportValidity() {
        const inputs = this.template.querySelectorAll('lightning-input, lightning-combobox');
        let allValid = true;
        inputs.forEach((input) => {
            if (typeof input.reportValidity === 'function' && !input.reportValidity()) {
                allValid = false;
            }
        });
        return allValid;
    }

    get canRemoveShift() {
        return this.guideShifts.length > 1;
    }

    get disableRemoveShift() {
        return !this.canRemoveShift;
    }

    get showLunchFields() {
        return this.lunchBlockNeeded;
    }

    get showOnlineCapacityField() {
        return this.onlineTourBookingEnabled;
    }
}
