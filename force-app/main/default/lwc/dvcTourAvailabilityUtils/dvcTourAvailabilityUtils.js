/**
 * dvcTourAvailabilityUtils
 *
 * Client-side mirror of DVC_TourSlotGenerationService.buildSlotRecords (Apex). "Generate &
 * Preview Schedule" never calls Apex (docs/DMS-4909-LLD.md Section 19, Q0), so this module
 * re-implements the exact same fixed-Slot-Interval-width algorithm (LLD Section 10.1) so the
 * preview shown to the admin matches what Publish will actually persist.
 *
 * IMPORTANT: any change to this algorithm must be mirrored in
 * force-app/main/default/classes/DVC_TourSlotGenerationService.cls and vice versa.
 */

export const SLOT_INTERVAL_MINUTES = {
    '15 Minutes': 15,
    '30 Minutes': 30,
    '60 Minutes': 60
};

export const SLOT_STATUS_OPEN = 'Open';
export const SLOT_STATUS_CLOSED = 'Closed';

/**
 * Accepts 'HH:mm' or 'HH:mm:ss[.SSS]' (the formats emitted by lightning-input type="time"
 * depending on locale) and returns minutes since midnight, or null if not parseable.
 */
function timeStringToMinutes(timeString) {
    if (!timeString) {
        return null;
    }
    const parts = timeString.split(':');
    if (parts.length < 2) {
        return null;
    }
    const hours = parseInt(parts[0], 10);
    const minutes = parseInt(parts[1], 10);
    if (Number.isNaN(hours) || Number.isNaN(minutes)) {
        return null;
    }
    return hours * 60 + minutes;
}

function minutesToTimeLabel(totalMinutes) {
    const clamped = ((totalMinutes % 1440) + 1440) % 1440;
    const hours24 = Math.floor(clamped / 60);
    const minutes = clamped % 60;
    const period = hours24 >= 12 ? 'PM' : 'AM';
    let hours12 = hours24 % 12;
    if (hours12 === 0) {
        hours12 = 12;
    }
    return `${hours12}:${String(minutes).padStart(2, '0')} ${period}`;
}

/**
 * @param {Object} config
 * @param {string} config.operatingStartTime
 * @param {string} config.operatingEndTime
 * @param {number} config.tourDurationMinutes
 * @param {string} config.slotInterval - one of the SLOT_INTERVAL_MINUTES keys
 * @param {boolean} config.lunchBlockNeeded
 * @param {string} [config.lunchStartTime]
 * @param {string} [config.lunchEndTime]
 * @param {boolean} config.onlineTourBookingEnabled
 * @param {number|null} config.onlineCapacityInput
 * @param {Array<{shiftStartTime:string, shiftEndTime:string, numberOfGuides:number}>} config.guideShifts
 * @returns {Array} one row per fixed Slot-Interval-width block
 */
export function generatePreviewSlots(config) {
    const slotIntervalMinutes = SLOT_INTERVAL_MINUTES[config.slotInterval];
    const tourDurationMinutes = Number(config.tourDurationMinutes);

    if (!slotIntervalMinutes || !tourDurationMinutes || !config.operatingStartTime || !config.operatingEndTime) {
        return [];
    }

    const operatingStartMinutes = timeStringToMinutes(config.operatingStartTime);
    const operatingEndMinutes = timeStringToMinutes(config.operatingEndTime);
    if (operatingStartMinutes === null || operatingEndMinutes === null || operatingStartMinutes >= operatingEndMinutes) {
        return [];
    }

    const lunchNeeded = Boolean(config.lunchBlockNeeded) && Boolean(config.lunchStartTime) && Boolean(config.lunchEndTime);
    const lunchStartMinutes = lunchNeeded ? timeStringToMinutes(config.lunchStartTime) : null;
    const lunchEndMinutes = lunchNeeded ? timeStringToMinutes(config.lunchEndTime) : null;

    const guideShifts = (config.guideShifts || []).map((shift) => ({
        startMinutes: timeStringToMinutes(shift.shiftStartTime),
        endMinutes: timeStringToMinutes(shift.shiftEndTime),
        numberOfGuides: Number(shift.numberOfGuides) || 0
    }));

    let nextAvailableMinutes = operatingStartMinutes;
    let rowStartMinutes = operatingStartMinutes;
    const rows = [];

    // ASSUMPTION pending business confirmation (LLD Section 20, Item 7): a trailing partial
    // block (when the operating window isn't evenly divisible by Slot Interval) is dropped.
    while (rowStartMinutes + slotIntervalMinutes <= operatingEndMinutes) {
        const rowEndMinutes = rowStartMinutes + slotIntervalMinutes;

        const guideCapacity = guideShifts.reduce((total, shift) => {
            if (
                shift.startMinutes !== null &&
                shift.endMinutes !== null &&
                shift.startMinutes <= rowStartMinutes &&
                rowStartMinutes < shift.endMinutes
            ) {
                return total + shift.numberOfGuides;
            }
            return total;
        }, 0);

        // Lunch check uses THIS ROW's own width, not the full Tour Duration span (LLD Section 10.1/10.3).
        const isLunchRow = lunchNeeded && rowStartMinutes < lunchEndMinutes && rowEndMinutes > lunchStartMinutes;

        let onsiteCapacity;
        if (guideCapacity === 0 || isLunchRow) {
            onsiteCapacity = 0;
            // nextAvailableMinutes is deliberately NOT advanced for a lunch/zero-guide row.
        } else if (rowStartMinutes >= nextAvailableMinutes) {
            onsiteCapacity = guideCapacity;
            nextAvailableMinutes = rowStartMinutes + tourDurationMinutes;
        } else {
            onsiteCapacity = 0;
        }

        let onlineCapacity = 0;
        if (config.onlineTourBookingEnabled && onsiteCapacity > 0 && config.onlineCapacityInput != null) {
            onlineCapacity = Math.min(Number(config.onlineCapacityInput), onsiteCapacity);
        }

        rows.push({
            key: `slot-${rowStartMinutes}`,
            startMinutes: rowStartMinutes,
            endMinutes: rowEndMinutes,
            startLabel: minutesToTimeLabel(rowStartMinutes),
            endLabel: minutesToTimeLabel(rowEndMinutes),
            onsiteCapacity,
            onlineCapacity,
            isLunchBlock: isLunchRow,
            status: onsiteCapacity > 0 ? SLOT_STATUS_OPEN : SLOT_STATUS_CLOSED
        });

        rowStartMinutes += slotIntervalMinutes;
    }

    return rows;
}
