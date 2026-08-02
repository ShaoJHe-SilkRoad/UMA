/*
 * UMA Claude Browser Companion extraction core.
 *
 * This file intentionally has no browser API dependency. It may inspect only
 * the exact official personal Usage route and emits a small normalized quota
 * object. Page source, broad page text, URL data, private identity fields, and spending data never
 * leave this function.
 */
(function (root) {
  "use strict";

  const CONTRACT = Object.freeze({
    schemaVersion: 1,
    origin: "https://claude.ai",
    path: "/new",
    hash: "#settings/usage",
    href: "https://claude.ai/new#settings/usage",
    maximumLabelElementCount: 4096,
    maximumCandidateCount: 64,
  });

  const CARD_SELECTORS = Object.freeze({
    fiveHour: [
      '[data-testid="usage-current-session"]',
      '[data-testid="five-hour-limit"]',
      '[data-testid="five-hour-usage"]',
    ],
    weeklyAllModels: [
      '[data-testid="usage-weekly-all-models"]',
      '[data-testid="weekly-all-models"]',
      '[data-testid="weekly-limit"]',
    ],
    sonnet: ['[data-testid="usage-weekly-sonnet"]', '[data-testid="weekly-sonnet-limit"]'],
    opus: ['[data-testid="usage-weekly-opus"]', '[data-testid="weekly-opus-limit"]'],
    haiku: ['[data-testid="usage-weekly-haiku"]', '[data-testid="weekly-haiku-limit"]'],
  });

  const HEADING_PATTERNS = Object.freeze({
    fiveHour: [/^current session$/i, /^5[- ]hour limit$/i, /^five[- ]hour limit$/i],
    weeklyAllModels: [/^all models$/i, /^weekly limit(?:s)?$/i, /^7[- ]day limit$/i],
  });

  function exactUsageURL(locationLike) {
    if (!locationLike || locationLike.protocol !== "https:" || locationLike.origin !== CONTRACT.origin) {
      return false;
    }
    return locationLike.pathname === CONTRACT.path &&
      !locationLike.search &&
      locationLike.hash === CONTRACT.hash;
  }

  function boundedOwnText(element, maximum) {
    if (!element) return null;
    const value = String(element.textContent || "").replace(/\s+/g, " ").trim();
    return value && value.length <= maximum ? value : null;
  }

  function hasLoginForm(documentLike) {
    return Boolean(documentLike.querySelector(
      'input[type="password"], input[autocomplete="current-password"], form[action*="login"], form[action*="signin"]'
    ));
  }

  function matchingExplicitCards(documentLike, selectors) {
    const matches = [];
    for (const selector of selectors) {
      for (const element of documentLike.querySelectorAll(selector)) {
        if (!matches.includes(element)) matches.push(element);
      }
    }
    return matches;
  }

  function cardForHeading(heading) {
    return heading.closest('article, section, [data-testid*="usage"], [data-testid*="limit"], [role="group"]');
  }

  function matchingLabelCards(documentLike, patterns) {
    const labels = documentLike.querySelectorAll(
      'h1, h2, h3, h4, h5, h6, [role="heading"], div, p, span'
    );
    const cards = [];
    // The settings SPA contains many structural div/span nodes before its
    // Usage cards. Keep the search bounded without truncating it to the first
    // few page nodes, which can exclude every allowlisted Usage landmark.
    const upperBound = Math.min(labels.length, CONTRACT.maximumLabelElementCount);
    for (let index = 0; index < upperBound; index += 1) {
      const label = labels[index];
      // Claude currently renders "Current session" as a leaf label rather
      // than a semantic heading. Match only exact allowlisted leaf text; no
      // unrelated page copy is retained or allowed across the boundary.
      if (label.childElementCount > 0) continue;
      const text = boundedOwnText(label, 80);
      if (!text || !patterns.some((pattern) => pattern.test(text))) continue;
      const card = cardForHeading(label);
      if (card && !cards.includes(card)) cards.push(card);
      if (cards.length > 1) return cards;
    }
    return cards;
  }

  function uniqueCard(documentLike, kind) {
    const explicit = matchingExplicitCards(documentLike, CARD_SELECTORS[kind]);
    if (explicit.length === 1) return explicit[0];
    if (explicit.length > 1) return null;
    const labelled = matchingLabelCards(documentLike, HEADING_PATTERNS[kind]);
    return labelled.length === 1 ? labelled[0] : null;
  }

  function finitePercentage(raw) {
    if (typeof raw === "number") {
      return Number.isFinite(raw) && raw >= 0 && raw <= 100 ? raw : null;
    }
    if (typeof raw !== "string" || raw.length > 16) return null;
    const match = raw.trim().match(/^(100(?:\.0+)?|\d{1,2}(?:\.\d+)?)\s*%?$/);
    if (!match) return null;
    const parsed = Number(match[1]);
    return Number.isFinite(parsed) && parsed >= 0 && parsed <= 100 ? parsed : null;
  }

  function readPercentage(card) {
    const values = [];
    const candidates = Array.from(card.querySelectorAll(
      '[aria-valuenow], [data-used-percentage], [data-testid="usage-percentage"], ' +
      '[data-testid="percentage-used"], [data-testid="limit-percentage"], span, strong, p'
    )).slice(0, CONTRACT.maximumCandidateCount);

    for (const candidate of candidates) {
      const aria = candidate.getAttribute("aria-valuenow");
      const data = candidate.getAttribute("data-used-percentage");
      const text = boundedOwnText(candidate, 16);
      for (const raw of [aria, data]) {
        const parsed = finitePercentage(raw);
        if (parsed !== null) values.push(parsed);
      }
      // Visible copy must include the percent sign. This keeps promotional
      // multipliers, Credit counts, dates, and other plain numbers from ever
      // becoming quota merely because they sit inside a Usage card.
      if (text && text.includes("%")) {
        const parsed = finitePercentage(text);
        if (parsed !== null) values.push(parsed);
      }
    }
    const unique = Array.from(new Set(values));
    return unique.length === 1 ? unique[0] : null;
  }

  function normalizedTimestamp(raw) {
    if (typeof raw !== "string" || raw.length > 64) return null;
    const value = raw.trim();
    if (!/^\d{4}-\d{2}-\d{2}T/.test(value)) return null;
    const milliseconds = Date.parse(value);
    return Number.isFinite(milliseconds) ? new Date(milliseconds).toISOString() : null;
  }

  function readReset(card) {
    const values = [];
    const candidates = Array.from(card.querySelectorAll('time[datetime], [data-reset-at]'))
      .slice(0, 8);
    for (const candidate of candidates) {
      for (const raw of [
        candidate.getAttribute("datetime"),
        candidate.getAttribute("data-reset-at"),
      ]) {
        if (!raw) continue;
        const normalized = normalizedTimestamp(raw);
        if (!normalized) return { valid: false, value: null };
        values.push(normalized);
      }
    }
    const unique = Array.from(new Set(values));
    if (unique.length > 1) return { valid: false, value: null };
    return { valid: true, value: unique.length === 1 ? unique[0] : null };
  }

  function quotaWindow(card) {
    if (!card) return null;
    const usedPercentage = readPercentage(card);
    if (usedPercentage === null) return null;
    const reset = readReset(card);
    if (!reset.valid) return null;
    return { usedPercentage, resetAt: reset.value };
  }

  function modelSpecificWindow(documentLike) {
    const candidates = [];
    for (const modelFamily of ["sonnet", "opus", "haiku"]) {
      const cards = matchingExplicitCards(documentLike, CARD_SELECTORS[modelFamily]);
      if (cards.length > 1) return null;
      if (cards.length === 1) {
        const window = quotaWindow(cards[0]);
        if (window) candidates.push({ modelFamily, window });
      }
    }
    return candidates.length === 1 ? candidates[0] : null;
  }

  function validateWindow(windowValue) {
    if (windowValue === null) return true;
    if (!windowValue || Object.getPrototypeOf(windowValue) !== Object.prototype) return false;
    const keys = Object.keys(windowValue).sort().join(",");
    if (keys !== "resetAt,usedPercentage") return false;
    if (finitePercentage(windowValue.usedPercentage) === null) return false;
    return windowValue.resetAt === null || normalizedTimestamp(windowValue.resetAt) !== null;
  }

  function validateObservation(value) {
    if (!value || Object.getPrototypeOf(value) !== Object.prototype) return false;
    const keys = Object.keys(value).sort().join(",");
    if (keys !== "extractorSchemaVersion,fiveHour,modelSpecificWeekly,observedAt,weeklyAllModels") return false;
    if (value.extractorSchemaVersion !== CONTRACT.schemaVersion) return false;
    if (!normalizedTimestamp(value.observedAt)) return false;
    if (!validateWindow(value.fiveHour) || !validateWindow(value.weeklyAllModels)) return false;
    if (value.fiveHour === null && value.weeklyAllModels === null) return false;
    if (value.modelSpecificWeekly === null) return true;
    const model = value.modelSpecificWeekly;
    if (!model || Object.getPrototypeOf(model) !== Object.prototype) return false;
    if (Object.keys(model).sort().join(",") !== "modelFamily,window") return false;
    if (!["sonnet", "opus", "haiku"].includes(model.modelFamily)) return false;
    return validateWindow(model.window) && model.window !== null;
  }

  function extract(documentLike, locationLike, now) {
    if (!exactUsageURL(locationLike) || hasLoginForm(documentLike)) return null;
    const fiveHour = quotaWindow(uniqueCard(documentLike, "fiveHour"));
    const weeklyAllModels = quotaWindow(uniqueCard(documentLike, "weeklyAllModels"));
    if (!fiveHour && !weeklyAllModels) return null;
    const observation = {
      fiveHour,
      weeklyAllModels,
      modelSpecificWeekly: modelSpecificWindow(documentLike),
      observedAt: (now || new Date()).toISOString(),
      extractorSchemaVersion: CONTRACT.schemaVersion,
    };
    // The SPA may navigate while extraction is in progress. Revalidate both
    // route and login absence after reading the bounded landmarks so a click
    // cannot carry a result from a tab that changed underneath the extractor.
    if (!exactUsageURL(locationLike) || hasLoginForm(documentLike)) return null;
    return validateObservation(observation) ? observation : null;
  }

  root.UMAClaudeUsageExtractor = Object.freeze({
    CONTRACT,
    exactUsageURL,
    finitePercentage,
    normalizedTimestamp,
    validateObservation,
    extract,
  });
})(globalThis);
