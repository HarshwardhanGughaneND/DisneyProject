# DisneyProject

Salesforce DX project for the DVC MeRLIN Sustainment program.

## DMS-4909: Tour Availability Generator

This repo currently implements [DMS-4909 — Tour Availability Generator: Schedule
Creation](https://disneyexperiences.atlassian.net/browse/DMS-4909), a Lightning app that lets
Business Admin/Operations users configure guide shifts, operating hours, and lunch breaks for
one or more tour locations, preview the resulting bookable time slots client-side, and publish
the schedule to Salesforce.

- **Low-Level Design:** [`docs/DMS-4909-LLD.md`](docs/DMS-4909-LLD.md)
- **Development notes** (implementation details, known gaps, dependencies, testing):
  [`docs/DMS-4909-DEVELOPMENT.md`](docs/DMS-4909-DEVELOPMENT.md)

### Quick start

```bash
# Install Nebula Logger (https://github.com/jongpie/NebulaLogger) in your target org first -
# DVC_LoggerService.cls has a hard compile-time dependency on it.

sf project deploy start --target-org <alias>
sf apex run test --target-org <alias>
sf apex run --file scripts/apex/schedule-daily-rollover-job.apex --target-org <alias>
```

### LWC unit tests

```bash
npm install
npm run test:unit          # single run
npm run test:unit:watch    # watch mode
npm run test:unit:coverage # with coverage report
```

See [`docs/DMS-4909-DEVELOPMENT.md`](docs/DMS-4909-DEVELOPMENT.md) for the full post-deploy
checklist, known open items pending business confirmation, and testing status.
