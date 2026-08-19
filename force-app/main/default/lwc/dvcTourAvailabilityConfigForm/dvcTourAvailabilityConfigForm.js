import { LightningElement, api } from 'lwc';

let shiftKeySequence = 0;
function nextShiftKey() {
    shiftKeySequence += 1;
    return `shift-${shiftKeySequence}`;
}

const DEFAULT_TOUR_DURATION_MINUTES = 60;
const DEFAULT_SLOT_INTERVAL = '30 Minutes';
const DEFAULT_NUMBER_OF_GUIDES = 2; // confirmed default per LLD Decision Log Q8
const MAX_START_DATE_DAYS_IN_FUTURE = 90; // BR-1 / VR-03

/**
 * dvcTourAvailabilityConfigForm
 *
 * Child LWC - Config Form (docs/DMS-4909-LLD.md Section 4.1 / 8.1). Captures Start/End Date,
 * Opening/Closing Time, a repeatable list of Guide Shifts, Lunch Block, Tour Duration, Tour
 * Slot Increment, and Online Tour Booking, and emits `configchange` with the full config
 * object on every field change (including once on initial render, so the container always has
 * the form's defaults even if the user never touches a field). Exposes `getConfig()` and
 * `reportValidity()` (VR-01-VR-09, LLD Section 9) for the container.
 */
export default class DvcTourAvailabilityConfigForm extends LightningElement {
    startDate;
    endDate;
    operatingStartTime;
    operatingEndTime;
    guideShifts = this.renumberShifts([this.createShift()]);
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

    connectedCallback() {
        // Emit the form's defaults immediately, so the container's currentConfig is never left
        // empty for a user who accepts every default and clicks Generate without touching a
        // single field.
        this.notifyChange();
    }

    createShift() {
        return {
            key: nextShiftKey(),
            shiftStartTime: this.operatingStartTime || null,
            shiftEndTime: this.operatingEndTime || null,
            numberOfGuides: DEFAULT_NUMBER_OF_GUIDES
        };
    }

    /**
     * Recomputes per-row display labels ("Shift 1 Start Time", "Shift 2 Start Time", ...) so
     * screen-reader users can distinguish rows when there are multiple shifts (a11y gap fix).
     */
    renumberShifts(shifts) {
        return shifts.map((shift, index) => ({
            ...shift,
            displayNumber: index + 1,
            shiftStartLabel: `Shift ${index + 1} Start Time`,
            shiftEndLabel: `Shift ${index + 1} End Time`,
            guidesLabel: `Shift ${index + 1} Guides`
        }));
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
        // Default/unedited shift rows (LLD Section 8.1: "matching the Shift Time to
        // Opening-Closing") inherit the new Opening Time - but only rows the user hasn't
        // already set explicitly, so we never clobber a manual edit.
        this.guideShifts = this.renumberShifts(
            this.guideShifts.map((shift) =>
                shift.shiftStartTime ? shift : { ...shift, shiftStartTime: this.operatingStartTime }
            )
        );
        this.notifyChange();
    }

    handleClosingTimeChange(event) {
        this.operatingEndTime = event.target.value;
        this.guideShifts = this.renumberShifts(
            this.guideShifts.map((shift) =>
                shift.shiftEndTime ? shift : { ...shift, shiftEndTime: this.operatingEndTime }
            )
        );
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
        this.guideShifts = this.renumberShifts(
            this.guideShifts.map((shift) => (shift.key === shiftKey ? { ...shift, [field]: value } : shift))
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
        this.guideShifts = this.renumberShifts([...this.guideShifts, templateShift]);
        this.notifyChange();
    }

    handleRemoveShift(event) {
        if (this.guideShifts.length <= 1) {
            return; // at least one shift is required (VR-05)
        }
        const shiftKey = event.target.dataset.key;
        this.guideShifts = this.renumberShifts(this.guideShifts.filter((shift) => shift.key !== shiftKey));
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
     * Clears any custom validity messages set by a prior reportValidity() call, so stale
     * errors don't linger on fields the user has since corrected.
     */
    clearCustomValidity() {
        this.template.querySelectorAll('lightning-input, lightning-combobox').forEach((input) => {
            input.setCustomValidity('');
        });
    }

    getFieldInput(fieldName) {
        return this.template.querySelector(`[data-field="${fieldName}"]`);
    }

    getShiftInput(shiftKey, fieldName) {
        return this.template.querySelector(`[data-key="${shiftKey}"][data-field="${fieldName}"]`);
    }

    /**
     * Implements the client-side portion of VR-01-VR-09 (LLD Section 9) with the exact
     * user-facing messages specified there, using setCustomValidity so the same
     * lightning-input components used for native (required/min) validation also surface these
     * business-rule violations. This is a UX convenience only - every rule is re-validated in
     * Apex before Publish, since Apex must never trust client-only validation.
     */
    @api
    reportValidity() {
        this.clearCustomValidity();
        let allValid = true;

        const startDateInput = this.getFieldInput('startDate');
        const endDateInput = this.getFieldInput('endDate');
        const openingInput = this.getFieldInput('operatingStartTime');
        const closingInput = this.getFieldInput('operatingEndTime');

        // VR-02: Start Date <= End Date
        if (this.startDate && this.endDate && this.startDate > this.endDate) {
            endDateInput.setCustomValidity('End Date must be on or after Start Date.');
            allValid = false;
        }

        // VR-03: Start Date <= TODAY + 90 days (BR-1)
        if (this.startDate) {
            const maxStartDate = new Date();
            maxStartDate.setDate(maxStartDate.getDate() + MAX_START_DATE_DAYS_IN_FUTURE);
            const maxStartDateStr = maxStartDate.toISOString().slice(0, 10);
            if (this.startDate > maxStartDateStr) {
                startDateInput.setCustomValidity('Start Date cannot be more than 90 days in the future.');
                allValid = false;
            }
        }

        // VR-04: Opening Time < Closing Time
        if (this.operatingStartTime && this.operatingEndTime && this.operatingStartTime >= this.operatingEndTime) {
            closingInput.setCustomValidity('Closing Time must be later than Opening Time.');
            allValid = false;
        }

        // VR-05: each Guide Shift - Shift End > Shift Start; >= 1 guide
        this.guideShifts.forEach((shift) => {
            const shiftEndInput = this.getShiftInput(shift.key, 'shiftEnd');
            const guidesInput = this.getShiftInput(shift.key, 'guides');
            if (shift.shiftStartTime && shift.shiftEndTime && shift.shiftStartTime >= shift.shiftEndTime) {
                shiftEndInput.setCustomValidity('Enter a valid shift time range and guide count.');
                allValid = false;
            }
            if (shift.numberOfGuides == null || Number(shift.numberOfGuides) < 1) {
                guidesInput.setCustomValidity('Enter a valid shift time range and guide count.');
                allValid = false;
            }
        });

        // VR-06: Lunch Block, when enabled, must be populated, End > Start, and within
        // [Opening, Closing]
        if (this.lunchBlockNeeded) {
            const lunchStartInput = this.getFieldInput('lunchStartTime');
            const lunchEndInput = this.getFieldInput('lunchEndTime');
            const lunchMessage = 'Enter a valid Lunch Start and Lunch End within the operating hours.';

            const lunchWithinHours =
                this.operatingStartTime && this.operatingEndTime && this.lunchStartTime && this.lunchEndTime
                    ? this.lunchStartTime >= this.operatingStartTime && this.lunchEndTime <= this.operatingEndTime
                    : true;

            if (
                !this.lunchStartTime ||
                !this.lunchEndTime ||
                this.lunchEndTime <= this.lunchStartTime ||
                !lunchWithinHours
            ) {
                lunchEndInput.setCustomValidity(lunchMessage);
                allValid = false;
            }
        }

        // VR-08: Tour Duration > 0
        const durationInput = this.getFieldInput('tourDurationMinutes');
        if (this.tourDurationMinutes == null || Number(this.tourDurationMinutes) <= 0) {
            durationInput.setCustomValidity('Tour Duration must be greater than zero.');
            allValid = false;
        }

        // VR-09: capacities are non-negative (Online Capacity input; per-slot Onsite/Online
        // capacity itself is guide-derived/clamped downstream in the preview grid)
        if (this.onlineTourBookingEnabled && this.onlineCapacityInput != null && this.onlineCapacityInput !== '') {
            const onlineCapacityInputEl = this.getFieldInput('onlineCapacityInput');
            if (Number(this.onlineCapacityInput) < 0) {
                onlineCapacityInputEl.setCustomValidity('Capacity values cannot be negative.');
                allValid = false;
            }
        }

        // Note on VR-07 (Online Capacity <= guide-derived Onsite Capacity): the guide-derived
        // Onsite capacity only exists per-slot, after generation - it cannot be evaluated at
        // the config-form level before Generate runs. It is enforced per-row once the preview
        // is generated (dvcTourSchedulePreviewGrid clamps on edit) and again server-side before
        // Publish (DVC_TourAvailabilityValidationService).

        // Finally, run native HTML5 constraint validation (required/min/type) across every
        // input - this also displays the custom messages set above via reportValidity()'s
        // built-in bubble UI.
        const inputs = this.template.querySelectorAll('lightning-input, lightning-combobox');
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
