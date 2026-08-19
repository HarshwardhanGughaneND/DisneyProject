/**
 * DVC_TourAvailabilityPublishController
 *
 * @AuraEnabled entry point for the `dvcTourAvailabilityGenerator` container LWC's Publish
 * action (docs/DMS-4909-LLD.md Section 11.1). "Generate & Preview Schedule" never calls Apex at
 * all (Section 19, Q0) - only Publish does.
 *
 * SECURITY-REVIEW: `with sharing` is enforced; every field on the incoming request is treated as
 * untrusted client input and re-validated server-side (never trusting the LWC's own validation);
 * CRUD is explicitly checked before any DML is scheduled.
 */
public with sharing class DVC_TourAvailabilityPublishController {

    /**
     * Lets the LWC re-check validity server-side before enabling Publish, without actually
     * publishing anything.
     */
    @AuraEnabled
    public static List<String> validatePublishRequest(DVC_TourAvailabilityRequest request) {
        try {
            return DVC_TourAvailabilityValidationService.validate(request);
        } catch (Exception ex) {
            DVC_LoggerService.logException(DVC_TourAvailabilityPublishController.class.getName(), 'validatePublishRequest', ex);
            throw new AuraHandledException('Unable to validate the schedule right now. Please try again.');
        }
    }

    /**
     * Validates the request, checks object-level create permission, and enqueues
     * DVC_TourSlotGenerationBatch to persist the schedule asynchronously. Returns the
     * AsyncApexJob Id so the LWC can (in future) poll for completion once the exact
     * success/failure UX is finalized with business (LLD Section 20, Item 2).
     */
    @AuraEnabled
    public static Id publishSchedule(DVC_TourAvailabilityRequest request) {
        try {
            List<String> errors = DVC_TourAvailabilityValidationService.validate(request);
            if (!errors.isEmpty()) {
                throw new DVC_TourAvailabilityException(String.join(errors, ' '));
            }

            if (!hasPublishPermission()) {
                throw new DVC_TourAvailabilityException('You do not have permission to publish a Tour Availability schedule.');
            }

            String serializedRequest = JSON.serialize(request);
            return Database.executeBatch(new DVC_TourSlotGenerationBatch(serializedRequest), DVC_TourAvailabilityConstants.BATCH_SCOPE_SIZE);
        } catch (DVC_TourAvailabilityException expected) {
            // Expected, user-actionable validation/permission failure - safe to surface directly.
            throw new AuraHandledException(expected.getMessage());
        } catch (Exception ex) {
            DVC_LoggerService.logException(DVC_TourAvailabilityPublishController.class.getName(), 'publishSchedule', ex);
            throw new AuraHandledException('Something went wrong while publishing the schedule. Please try again or contact your administrator.');
        }
    }

    private static Boolean hasPublishPermission() {
        return Schema.sObjectType.DVC_Tour_Availability__c.isCreateable()
            && Schema.sObjectType.DVC_Tour_Guide_Shift__c.isCreateable()
            && Schema.sObjectType.DVC_Tour_Availability_Slot__c.isCreateable();
    }
}
