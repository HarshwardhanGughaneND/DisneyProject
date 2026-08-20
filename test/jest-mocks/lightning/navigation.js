/**
 * Custom test-only mock for `lightning/navigation`, overriding the one built into
 * @salesforce/sfdx-lwc-jest. The built-in stub's NavigationMixin.[Navigate]() is defined on a
 * frozen/non-configurable class prototype (LWC's compiler hardens component internals against
 * monkey-patching), which makes it impossible for a test to jest.spyOn() or
 * Object.defineProperty() over it directly. This mock instead routes every [Navigate] call
 * through a plain, always-mockable Jest function, and exposes `getNavigateCalledWith()` (the
 * same helper Salesforce's own lwc-recipes samples use) so tests can assert on navigation
 * without needing to patch anything on the component class itself.
 *
 * Wired in via jest.config.js's moduleNameMapper.
 */
import { createTestWireAdapter } from '@salesforce/wire-service-jest-util';

const Navigate = Symbol('Navigate');
const GenerateUrl = Symbol('GenerateUrl');

const navigateMock = jest.fn();
const generateUrlMock = jest.fn().mockReturnValue(Promise.resolve('https://www.example.com'));

export const CurrentPageReference = createTestWireAdapter(jest.fn());

export const NavigationMixin = (Base) => {
    return class extends Base {
        [Navigate](...args) {
            return navigateMock(...args);
        }
        [GenerateUrl](...args) {
            return generateUrlMock(...args);
        }
    };
};
NavigationMixin.Navigate = Navigate;
NavigationMixin.GenerateUrl = GenerateUrl;

/** Returns { pageReference, replace } from the most recent [NavigationMixin.Navigate] call, or
 * undefined if it was never called. Also resettable via `navigateMock.mockClear()` between tests. */
export function getNavigateCalledWith() {
    if (navigateMock.mock.calls.length === 0) {
        return undefined;
    }
    const [pageReference, replace] = navigateMock.mock.calls[navigateMock.mock.calls.length - 1];
    return { pageReference, replace };
}

export { navigateMock, generateUrlMock };
