const { jestConfig } = require("@salesforce/sfdx-lwc-jest/config");

module.exports = {
  ...jestConfig,
  moduleNameMapper: {
    ...(jestConfig.moduleNameMapper || {}),
    "^lightning/modal$":
      "<rootDir>/force-app/test/jest-mocks/lightning/modal.js",
    "^lightning/navigation$":
      "<rootDir>/force-app/test/jest-mocks/lightning/navigation.js"
  },
  modulePathIgnorePatterns: ["<rootDir>/.localdevserver"],
  collectCoverageFrom: [
    "force-app/main/default/lwc/**/*.js",
    "!force-app/main/default/lwc/**/__tests__/**",
    "!force-app/main/default/lwc/**/*.test.js"
  ]
};
