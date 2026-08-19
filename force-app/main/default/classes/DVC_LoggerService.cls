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
 * PREREQUISITE (hard, compile-time dependency): this class references the Nebula Logger
 * unmanaged/unlocked package's (https://github.com/jongpie/NebulaLogger) `Logger` class
 * directly. That reference is resolved at COMPILE TIME, not runtime - if Nebula Logger is not
 * installed in the target org, this class (and every class in this feature that depends on it)
 * will FAIL TO COMPILE/DEPLOY. It does NOT "silently degrade" to System.debug in that scenario;
 * the try/catch blocks below only guard against a *runtime* failure of an already-compiled
 * Logger call (e.g. a misconfigured logging level or a Nebula Logger internal error), not
 * against the package being absent. Nebula Logger must be installed before deploying this
 * feature - see the dependency declared in sfdx-project.json.
 *
 * No PII/PHI/PCI is logged by this feature; only class/method names, record Ids, and
 * schedule-configuration values are captured (see LLD Section 18).
 */
public with sharing class DVC_LoggerService {

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
            // Guards only against a RUNTIME failure of an already-compiled Logger call (see
            // class-level comment above) - fall back to debug logs rather than letting a
            // logging problem surface as a user-facing error.
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
