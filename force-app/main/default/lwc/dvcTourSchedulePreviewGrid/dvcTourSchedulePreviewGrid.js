import { LightningElement, api } from 'lwc';

/**
 * dvcTourSchedulePreviewGrid
 *
 * Child LWC - Schedule Preview Grid (docs/DMS-4909-LLD.md Section 4.1 / 8.2). Renders the
 * generated preview: a single "Tour Slots" column when Online Tour Booking is disabled, or
 * separate Onsite (read-only) / Online (editable) columns when it is enabled (UAC8/UAC9).
 * Emits `onlinecapacitychange` when the admin edits a row's Online value.
 */
export default class DvcTourSchedulePreviewGrid extends LightningElement {
    // NOTE: cannot be named "onlineEnabled" (or anything starting with "on") - LWC reserves
    // that prefix for event handlers on public/@api properties (build error LWC1108).
    @api isOnlineBookingEnabled = false;

    _slots = [];

    @api
    get slots() {
        return this._slots;
    }
    set slots(value) {
        this._slots = value || [];
    }

    handleOnlineCapacityChange(event) {
        const rowKey = event.target.dataset.key;
        const parsedValue = Number(event.target.value);
        // Guard against NaN (e.g. an invalid/partial numeric entry) so it never propagates
        // through to the container's clamp logic and renders as a blank/NaN input.
        const newValue = Number.isNaN(parsedValue) ? 0 : parsedValue;
        this.dispatchEvent(
            new CustomEvent('onlinecapacitychange', {
                detail: { key: rowKey, onlineCapacity: newValue }
            })
        );
    }

    get hasSlots() {
        return this._slots.length > 0;
    }

    get rowsForDisplay() {
        return this._slots.map((slot) => ({
            ...slot,
            rowClass: `slds-border_left dvc-slot-row ${slot.onsiteCapacity > 0 ? 'dvc-slot-open' : 'dvc-slot-closed'}`,
            // Per-row accessible labels (rather than the shared "Onsite"/"Online"/"Tour Slots"
            // column label alone) so screen-reader users can distinguish which time each input
            // belongs to.
            onsiteAriaLabel: `Onsite capacity at ${slot.startLabel}`,
            onlineAriaLabel: `Online capacity at ${slot.startLabel}`,
            tourSlotsAriaLabel: `Tour slots at ${slot.startLabel}`
        }));
    }
}
