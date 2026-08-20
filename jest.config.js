const { jestConfig } = require('@salesforce/sfdx-lwc-jest/config');

module.exports = {
    ...jestConfig,
    modulePathIgnorePatterns: ['<rootDir>/.localdevserver'],
    moduleNameMapper: {
        // Override the built-in lightning/navigation stub with our own - see the file for why.
        '^lightning/navigation$': '<rootDir>/test/jest-mocks/lightning/navigation'
    }
};
