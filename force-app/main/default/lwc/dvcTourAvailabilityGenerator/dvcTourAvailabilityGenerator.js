import { LightningElement } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import publishSchedule from '@salesforce/apex/DVC_TourAvailabilityPublishController.publishSchedule';
import validatePublishRequest from '@salesforce/apex/DVC_TourAvailabilityPublishController.validatePublishRequest';
import { generatePreviewSlots } from 'c/dvcTourAvailabilityUtils';

/**
 * dvcTourAvailabilityGenerator
 *
 * Main container LWC (docs/DMS-4909-LLD.md Section 4.1). Owns shared state across the three
 * child components (Location Tree, Config Form, Schedule Preview Grid) and the two top-level
 * actions:
 *   - Generate & Preview Schedule: 100% client-side, no Apex call, no records created (Q0).
 *   - Publish: calls Apex to persist the schedule via DVC_TourSlotGenerationBatch.
 */
export default class DvcTourAvailabilityGenerator extends LightningElement {
    selectedLocationIds = [];
    currentConfig = {};
    previewSlots = [];
    hasGeneratedPreview = false;
    isPublishing = false;

    handleLocationSelectionChange(event) {
        this.selectedLocationIds = event.detail.selectedLocationIds;
    }

    handleConfigChange(event) {
        this.currentConfig = event.detail;
    }

    handleGenerateClick() {
        const configForm = this.template.querySelector('c-dvc-tour-availability-config-form');

        if (this.selectedLocationIds.length === 0) {
            this.showToast('Error', 'Select at least one Tour Location to continue.', 'error');
            return;
        }
        if (configForm && !configForm.reportValidity()) {
            return;
        }

        // Client-side only - no Apex call, no records created (LLD Section 19, Q0).
        this.previewSlots = generatePreviewSlots(this.currentConfig);
        this.hasGeneratedPreview = true;

        if (this.previewSlots.length === 0) {
            this.showToast('Warning', 'No slots were generated for the current configuration. Check your operating hours, duration, and interval.', 'warning');
        }
    }

    handleOnlineCapacityChange(event) {
        const { key, onlineCapacity } = event.detail;
        this.previewSlots = this.previewSlots.map((slot) =>
            slot.key === key
                ? { ...slot, onlineCapacity: Math.max(0, Math.min(onlineCapacity, slot.onsiteCapacity)) }
                : slot
        );
    }

    async handlePublishClick() {
        const request = this.buildPublishRequest();

        this.isPublishing = true;
        try {
            const errors = await validatePublishRequest(request);
            if (errors && errors.length > 0) {
                this.showToast('Error', errors.join(' '), 'error');
                return;
            }

            await publishSchedule(request);
            this.showToast(
                'Success',
                'Your schedule has been submitted for publishing. This runs asynchronously and may take a few minutes for large date ranges.',
                'success'
            );
        } catch (error) {
            const message = (error && error.body && error.body.message) || 'Something went wrong while publishing the schedule.';
            this.showToast('Error', message, 'error');
        } finally {
            this.isPublishing = false;
        }
    }

    buildPublishRequest() {
        return {
            locationIds: this.selectedLocationIds,
            startDate: this.currentConfig.startDate,
            endDate: this.currentConfig.endDate,
            operatingStartTime: this.currentConfig.operatingStartTime,
            operatingEndTime: this.currentConfig.operatingEndTime,
            tourDurationMinutes: this.currentConfig.tourDurationMinutes,
            slotInterval: this.currentConfig.slotInterval,
            lunchBlockNeeded: this.currentConfig.lunchBlockNeeded,
            lunchStartTime: this.currentConfig.lunchStartTime,
            lunchEndTime: this.currentConfig.lunchEndTime,
            onlineTourBookingEnabled: this.currentConfig.onlineTourBookingEnabled,
            onlineCapacityInput: this.currentConfig.onlineCapacityInput,
            guideShifts: this.currentConfig.guideShifts,
            slotType: 'Onsite'
        };
    }

    showToast(title, message, variant) {
        this.dispatchEvent(new ShowToastEvent({ title, message, variant }));
    }

    get isGenerateDisabled() {
        return this.selectedLocationIds.length === 0;
    }

    get isPublishDisabled() {
        return !this.hasGeneratedPreview || this.isPublishing;
    }

    get onlineEnabled() {
        return Boolean(this.currentConfig.onlineTourBookingEnabled);
    }
}
