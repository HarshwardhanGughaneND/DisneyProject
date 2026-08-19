/**
 * DVC_LoggerService
 *
 * Thin adapter around the org's Nebula Logger package (docs/DMS-4909-LLD.md Section 18,
 * "Exception Handling & Logging"). All DMS-4909 Apex classes should log through this class
 * rather than calling Nebula Logger's `Logger` class directly, so that:
 *   1. A logging failure can never break the calling transaction (defensive try/catch here).
 *   2. If Nebula Logger's public API changes, or the org standardizes on a different logging
 *      framework, only this one class needs to change.
 *
 * PREREQUISITE: this class assumes the Nebula Logger unmanaged/unlocked package
 * (https://github.com/jongpie/NebulaLogger) is already installed in the target org, exposing
 * the `Logger` class used below. If it is not yet installed, install it before deploying this
 * feature, or temporarily stub out the calls in `logException`/`logSummary`.
 *
 * No PII/PHI/PCI is logged by this feature; only class/method names, record Ids, and
 * schedule-configuration values are captured (see LLD Section 18).
 */
public without sharing class DVC_LoggerService {

    /**
     * Logs an unexpected exception with full context. Never throws - a logging failure must
     * never mask or replace the original exception/behavior of the calling transaction.
     */
    public static void logException(String originClass, String originMethod, Exception ex) {
        try {
            Logger.error(originClass + '.' + originMethod + ': ' + ex.getMessage())
                .setExceptionDetails(ex);
            Logger.saveLog();
        } catch (Exception loggerFailure) {
            // Nebula Logger unavailable/misconfigured - fall back to debug logs rather than
            // letting a logging problem surface as a user-facing error.
            System.debug(LoggingLevel.ERROR, originClass + '.' + originMethod + ' - exception: ' + ex);
            System.debug(LoggingLevel.ERROR, originClass + '.' + originMethod + ' - logger failure: ' + loggerFailure);
        }
    }

    /**
     * Logs a non-exception, informational summary (e.g., batch/scheduled job completion counts).
     */
    public static void logSummary(String originClass, String originMethod, String message) {
        try {
            Logger.info(originClass + '.' + originMethod + ': ' + message);
            Logger.saveLog();
        } catch (Exception loggerFailure) {
            System.debug(LoggingLevel.INFO, originClass + '.' + originMethod + ': ' + message);
        }
    }

    private DVC_LoggerService() {
        // Static-only utility class.
    }
}
