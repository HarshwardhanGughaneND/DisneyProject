import { createElement } from 'lwc';
import { getNavigateCalledWith, navigateMock } from 'lightning/navigation';
import DvcTourAvailabilityGenerator from 'c/dvcTourAvailabilityGenerator';
import publishSchedule from '@salesforce/apex/DVC_TourAvailabilityPublishController.publishSchedule';
import validatePublishRequest from '@salesforce/apex/DVC_TourAvailabilityPublishController.validatePublishRequest';

jest.mock(
    '@salesforce/apex/DVC_TourAvailabilityPublishController.publishSchedule',
    () => ({ default: jest.fn() }),
    { virtual: true }
);
jest.mock(
    '@salesforce/apex/DVC_TourAvailabilityPublishController.validatePublishRequest',
    () => ({ default: jest.fn() }),
    { virtual: true }
);

/** Flushes both the microtask queue and any pending macrotasks (e.g. chained async/await calls
 * inside event handlers), which is more reliable than chaining a fixed number of
 * Promise.resolve() calls for LWC components with multi-step async handlers. */
function flushPromises() {
    return new Promise((resolve) => setTimeout(resolve, 0));
}

function createComponent() {
    const element = createElement('c-dvc-tour-availability-generator', { is: DvcTourAvailabilityGenerator });
    document.body.appendChild(element);
    return element;
}

function stubConfigForm(element, { valid = true } = {}) {
    const configForm = element.shadowRoot.querySelector('c-dvc-tour-availability-config-form');
    configForm.reportValidity = jest.fn().mockReturnValue(valid);
    return configForm;
}

function selectLocations(element, locationIds) {
    const locationTree = element.shadowRoot.querySelector('c-dvc-tour-location-tree');
    locationTree.dispatchEvent(
        new CustomEvent('locationselectionchange', { detail: { selectedLocationIds: locationIds } })
    );
}

async function generateThenGetPublishButton(element) {
    await flushPromises(); // let the Generate button's disabled state recompute after location selection
    const generateButton = element.shadowRoot.querySelector('[data-id="generate-button"]');
    expect(generateButton.disabled).toBe(false);
    generateButton.click();

    await flushPromises(); // let the Publish button's disabled state recompute after hasGeneratedPreview=true
    const publishButton = element.shadowRoot.querySelector('[data-id="publish-button"]');
    expect(publishButton.disabled).toBe(false);
    return publishButton;
}

afterEach(() => {
    jest.clearAllMocks();
    navigateMock.mockClear();
    while (document.body.firstChild) {
        document.body.removeChild(document.body.firstChild);
    }
});

describe('c-dvc-tour-availability-generator Publish flow (Decision Log Q13)', () => {
    it('navigates to the DVC_Tour_Availability__c List View after a successful Publish', async () => {
        const element = createComponent();

        selectLocations(element, ['a01000000000001AAA']);
        stubConfigForm(element, { valid: true });

        validatePublishRequest.mockResolvedValue([]);
        publishSchedule.mockResolvedValue('707000000000001AAA');

        const publishButton = await generateThenGetPublishButton(element);
        publishButton.click();
        await flushPromises();

        expect(publishSchedule).toHaveBeenCalledTimes(1);
        const { pageReference } = getNavigateCalledWith();
        expect(pageReference).toEqual({
            type: 'standard__objectPage',
            attributes: {
                objectApiName: 'DVC_Tour_Availability__c',
                actionName: 'list'
            }
        });
    });

    it('does not navigate when server-side validation returns errors', async () => {
        const element = createComponent();

        selectLocations(element, ['a01000000000001AAA']);
        stubConfigForm(element, { valid: true });
        validatePublishRequest.mockResolvedValue(['Closing Time must be later than Opening Time.']);

        const publishButton = await generateThenGetPublishButton(element);
        publishButton.click();
        await flushPromises();

        expect(publishSchedule).not.toHaveBeenCalled();
        expect(navigateMock).not.toHaveBeenCalled();
    });

    it('does not navigate when Publish throws (e.g. permission or unexpected server error)', async () => {
        const element = createComponent();

        selectLocations(element, ['a01000000000001AAA']);
        stubConfigForm(element, { valid: true });
        validatePublishRequest.mockResolvedValue([]);
        publishSchedule.mockRejectedValue({ body: { message: 'You do not have permission to publish a Tour Availability schedule.' } });

        const publishButton = await generateThenGetPublishButton(element);
        publishButton.click();
        await flushPromises();

        expect(publishSchedule).toHaveBeenCalledTimes(1);
        expect(navigateMock).not.toHaveBeenCalled();
    });

    it('does not call Publish or navigate when the config form fails client-side validation', async () => {
        const element = createComponent();

        selectLocations(element, ['a01000000000001AAA']);
        // Passes validation for the Generate click (so Publish becomes reachable/enabled), then
        // fails validation specifically when Publish itself re-checks reportValidity() - e.g. a
        // field became invalid after the preview was generated.
        const configForm = stubConfigForm(element, { valid: true });

        const publishButton = await generateThenGetPublishButton(element);
        configForm.reportValidity.mockReturnValue(false);
        publishButton.click();
        await flushPromises();

        expect(publishSchedule).not.toHaveBeenCalled();
        expect(navigateMock).not.toHaveBeenCalled();
    });

    it('keeps Publish disabled (and unreachable) until a preview has been generated', () => {
        const element = createComponent();
        const publishButton = element.shadowRoot.querySelector('[data-id="publish-button"]');
        expect(publishButton.disabled).toBe(true);
    });
});
