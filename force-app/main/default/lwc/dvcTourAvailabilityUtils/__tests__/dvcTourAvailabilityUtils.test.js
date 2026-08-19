import { generatePreviewSlots, SLOT_STATUS_OPEN, SLOT_STATUS_CLOSED } from 'c/dvcTourAvailabilityUtils';

/**
 * Mirrors DVC_TourSlotGenerationServiceTest.cls (Apex) exactly, using the same Combo 1/4/6
 * scenarios from docs/DMS-4909-LLD.md Section 10.6, so client and server algorithms are proven
 * to stay in sync - this is the most business-critical client logic in the feature (Generate &
 * Preview never calls Apex, per LLD Section 19 Q0), so it must be covered independently of the
 * Apex tests.
 */
function buildCombo1Config(overrides = {}) {
    return {
        operatingStartTime: '08:30',
        operatingEndTime: '16:00',
        tourDurationMinutes: 90,
        slotInterval: '30 Minutes',
        lunchBlockNeeded: true,
        lunchStartTime: '12:30',
        lunchEndTime: '13:30',
        onlineTourBookingEnabled: false,
        onlineCapacityInput: null,
        guideShifts: [{ shiftStartTime: '08:30', shiftEndTime: '16:00', numberOfGuides: 2 }],
        ...overrides
    };
}

describe('c/dvcTourAvailabilityUtils generatePreviewSlots', () => {
    it('reproduces Combo 1 from the LLD exactly (90 min duration, 30 min interval, with lunch)', () => {
        const rows = generatePreviewSlots(buildCombo1Config());

        expect(rows).toHaveLength(15);

        const expectedOnsite = [2, 0, 0, 2, 0, 0, 2, 0, 0, 0, 2, 0, 0, 2, 0];
        const expectedLunch = [
            false, false, false, false, false, false, false, false, true, true, false, false, false, false, false
        ];

        rows.forEach((row, index) => {
            expect(row.onsiteCapacity).toBe(expectedOnsite[index]);
            expect(row.isLunchBlock).toBe(expectedLunch[index]);
            expect(row.status).toBe(expectedOnsite[index] > 0 ? SLOT_STATUS_OPEN : SLOT_STATUS_CLOSED);
        });

        const openCount = rows.filter((row) => row.onsiteCapacity > 0).length;
        expect(openCount).toBe(5);
    });

    it('reproduces Combo 4 from the LLD (60/60 min - leftover block dropped, one lunch-aligned row)', () => {
        const rows = generatePreviewSlots(
            buildCombo1Config({ tourDurationMinutes: 60, slotInterval: '60 Minutes' })
        );

        // 08:30-16:00 = 450 minutes, not evenly divisible by 60 - the trailing 03:30-04:00 PM
        // block is dropped (LLD Section 20, Item 7).
        expect(rows).toHaveLength(7);

        const openCount = rows.filter((row) => row.onsiteCapacity > 0).length;
        const lunchCount = rows.filter((row) => row.isLunchBlock).length;
        expect(openCount).toBe(6);
        expect(lunchCount).toBe(1);
    });

    it('reproduces Combo 6 from the LLD (90/60 min - lunch compounding effect)', () => {
        const rows = generatePreviewSlots(
            buildCombo1Config({ tourDurationMinutes: 90, slotInterval: '60 Minutes' })
        );

        expect(rows).toHaveLength(7);
        const openCount = rows.filter((row) => row.onsiteCapacity > 0).length;
        expect(openCount).toBe(3);
    });

    it('caps Online capacity at the row Onsite capacity and forces 0 on zero-capacity rows (VR-07)', () => {
        const rows = generatePreviewSlots(
            buildCombo1Config({ onlineTourBookingEnabled: true, onlineCapacityInput: 99 })
        );

        rows.forEach((row) => {
            expect(row.onlineCapacity).toBeLessThanOrEqual(row.onsiteCapacity);
            if (row.onsiteCapacity === 0) {
                expect(row.onlineCapacity).toBe(0);
            }
        });
    });

    it('returns an empty array when required configuration is missing', () => {
        expect(generatePreviewSlots({})).toEqual([]);
        expect(generatePreviewSlots(buildCombo1Config({ slotInterval: null }))).toEqual([]);
        expect(generatePreviewSlots(buildCombo1Config({ tourDurationMinutes: null }))).toEqual([]);
    });

    it('returns an empty array when Opening Time is not before Closing Time (VR-04 mirrored client-side)', () => {
        expect(
            generatePreviewSlots(buildCombo1Config({ operatingStartTime: '16:00', operatingEndTime: '08:30' }))
        ).toEqual([]);
    });

    it('treats a would-be tour start as blocked when it does not align with guide availability, even mid-shift', () => {
        // Two 30-minute rows in a row starting exactly at shift start; with a 90-minute
        // duration only every 3rd row should be Open.
        const rows = generatePreviewSlots(buildCombo1Config({ lunchBlockNeeded: false }));
        expect(rows[0].onsiteCapacity).toBe(2); // 08:30 - shift start, guides free
        expect(rows[1].onsiteCapacity).toBe(0); // 09:00 - guides occupied until 10:00
        expect(rows[2].onsiteCapacity).toBe(0); // 09:30 - guides occupied until 10:00
        expect(rows[3].onsiteCapacity).toBe(2); // 10:00 - guides free again
    });
});
