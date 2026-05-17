/**
 * Local Jest mock for `lightning/navigation`. The default sfdx-lwc-jest stub
 * exposes the NavigationMixin but does NOT export `getNavigateCalledWith` /
 * `getGenerateUrlCalledWith` — so our tests cannot assert what the Navigate
 * symbol was called with. This shim wires those helpers up.
 *
 * Registered in `jest.config.js` via `moduleNameMapper`.
 */
"use strict";

const Navigate = Symbol("Navigate");
const GenerateUrl = Symbol("GenerateUrl");

let lastNavigateConfig;
let lastGenerateUrlConfig;

const NavigationMixin = (Base) => {
  return class extends Base {
    [Navigate](config) {
      lastNavigateConfig = config;
    }
    [GenerateUrl](config) {
      lastGenerateUrlConfig = config;
      return Promise.resolve("https://www.example.com");
    }
  };
};
NavigationMixin.Navigate = Navigate;
NavigationMixin.GenerateUrl = GenerateUrl;

function getNavigateCalledWith() {
  return lastNavigateConfig;
}

function getGenerateUrlCalledWith() {
  return lastGenerateUrlConfig;
}

// Reset hook for `afterEach`.
function __resetNavigationMockState() {
  lastNavigateConfig = undefined;
  lastGenerateUrlConfig = undefined;
}

// `lightning/navigation` is consumed via named imports throughout the codebase;
// CurrentPageReference is a wire adapter — kept minimal here.
const CurrentPageReference = jest.fn();

module.exports = {
  NavigationMixin,
  CurrentPageReference,
  getNavigateCalledWith,
  getGenerateUrlCalledWith,
  __resetNavigationMockState,
  __esModule: true
};
