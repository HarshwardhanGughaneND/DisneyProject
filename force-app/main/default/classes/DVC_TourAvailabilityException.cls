/**
 * DVC_TourAvailabilityException
 *
 * Custom exception for expected, user-facing validation/business-rule failures raised while
 * generating or publishing a Tour Availability schedule (DMS-4909). Kept distinct from
 * unexpected system exceptions so callers can decide whether to surface the message directly
 * to the user (this exception) or a generic message (all other exceptions) - see
 * docs/DMS-4909-LLD.md Section 18 (Security & Compliance Considerations).
 */
public class DVC_TourAvailabilityException extends Exception {
}
