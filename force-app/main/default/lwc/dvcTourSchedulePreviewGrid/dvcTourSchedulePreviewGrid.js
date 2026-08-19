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
    @api onlineEnabled = false;

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
        const newValue = Number(event.target.value);
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
            rowClass: `slds-border_left dvc-slot-row ${slot.onsiteCapacity > 0 ? 'dvc-slot-open' : 'dvc-slot-closed'}`
        }));
    }
}
