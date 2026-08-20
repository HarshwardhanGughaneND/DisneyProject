import { LightningElement, wire } from 'lwc';
import getTourLocationTree from '@salesforce/apex/DVC_TourLocationTreeController.getTourLocationTree';

/**
 * dvcTourLocationTree
 *
 * Child LWC - Location Tree (docs/DMS-4909-LLD.md Section 4.1). Renders a multi-select tree of
 * Resort-type Tour Locations grouped by their parent Channel, and emits `locationselectionchange`
 * with the current list of selected Location Ids whenever the selection changes.
 */
export default class DvcTourLocationTree extends LightningElement {
    groups = [];
    hasLoadError = false;
    selectedIds = new Set();

    @wire(getTourLocationTree)
    wiredTree({ data, error }) {
        if (data) {
            this.hasLoadError = false;
            this.groups = data.map((group) => ({
                ...group,
                resorts: group.resorts.map((resort) => ({ ...resort, selected: this.selectedIds.has(resort.locationId) }))
            }));
        } else if (error) {
            this.hasLoadError = true;
            this.groups = [];
        }
    }

    handleCheckboxChange(event) {
        const locationId = event.target.dataset.id;
        const isChecked = event.target.checked;

        if (isChecked) {
            this.selectedIds.add(locationId);
        } else {
            this.selectedIds.delete(locationId);
        }

        this.groups = this.groups.map((group) => ({
            ...group,
            resorts: group.resorts.map((resort) =>
                resort.locationId === locationId ? { ...resort, selected: isChecked } : resort
            )
        }));

        this.dispatchEvent(
            new CustomEvent('locationselectionchange', {
                detail: { selectedLocationIds: Array.from(this.selectedIds) }
            })
        );
    }

    get hasGroups() {
        return this.groups.length > 0;
    }

    get showEmptyState() {
        return !this.hasLoadError && !this.hasGroups;
    }
}
