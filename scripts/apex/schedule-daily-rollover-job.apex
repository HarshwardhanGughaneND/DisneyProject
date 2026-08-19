/**
 * Schedules DVC_TourAvailabilityDailyRolloverJob (docs/DMS-4909-LLD.md Section 12).
 *
 * This is NOT run automatically by the metadata deploy - Salesforce has no supported metadata
 * type to declaratively schedule Apex on deploy, so this script must be run once per org
 * (production, each sandbox, and each scratch org) immediately after deploying this feature.
 *
 * Run with, e.g.:
 *   sf apex run --file scripts/apex/schedule-daily-rollover-job.apex --target-org <alias>
 *
 * Safe to re-run: it first aborts any existing scheduled job with the same name before
 * re-scheduling, so this script can also be used to reschedule after a CRON_EXPRESSION change.
 */

String jobName = 'DVC Tour Availability Daily Rollover';

for (CronTrigger existing : [
    SELECT Id
    FROM CronTrigger
    WHERE CronJobDetail.Name = :jobName
    WITH SECURITY_ENFORCED
]) {
    System.abortJob(existing.Id);
}

Id scheduledJobId = System.schedule(
    jobName,
    DVC_TourAvailabilityDailyRolloverJob.CRON_EXPRESSION,
    new DVC_TourAvailabilityDailyRolloverJob()
);

System.debug('Scheduled ' + jobName + ' with CronTrigger Id: ' + scheduledJobId);
