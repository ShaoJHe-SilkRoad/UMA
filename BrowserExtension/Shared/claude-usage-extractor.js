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
    schemaVersion: 2,
    sourceLayoutVersion: 1,
    origin: "https://claude.ai",
    path: "/new",
    hash: "#settings/usage",
    href: "https://claude.ai/new#settings/usage",
    maximumLabelElementCount: 4096,
    maximumCandidateCount: 64,
  });

  const FAILURE_REASONS = Object.freeze({
    routeNotReady: "ROUTE_NOT_READY",
    providerStructureUnsupported: "PROVIDER_STRUCTURE_UNSUPPORTED",
    providerSessionUnavailable: "PROVIDER_SESSION_UNAVAILABLE",
    targetDataNotReady: "TARGET_DATA_NOT_READY",
    extractionValidationFailed: "EXTRACTION_VALIDATION_FAILED",
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
    weeklyAllModels: [/^all models$/i, /^weekly limit(?:s)?$/i, /^7[- ]day limit$/i, /^this week$/i],
  });

  // Labels that mark a different quota row. They are never read as quota; they
  // only bound a row so a neighbouring row's percentage cannot be claimed.
  const BOUNDARY_PATTERNS = Object.freeze({
    modelSpecific: [/^(?:sonnet|opus|haiku)(?: only)?$/i],
    extraUsage: [/^extra usage$/i],
  });

  const MAXIMUM_ROW_DEPTH = 8;

  function exactUsageURL(locationLike) {
    if (!locationLike || locationLike.protocol !== "https:" || locationLike.origin !== CONTRACT.origin) {
      return false;
    }
    return locationLike.pathname === CONTRACT.path &&
      !locationLike.search &&
      locationLike.hash === CONTRACT.hash;
  }

  function usageRouteState(locationLike) {
    if (exactUsageURL(locationLike)) return "exact";
    if (locationLike?.protocol === "https:"
        && locationLike.origin === CONTRACT.origin
        && locationLike.pathname === CONTRACT.path
        && !locationLike.search) return "providerRoutePending";
    return "rejected";
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

  // Claude renders "This week" as the text of a toggle button that also holds
  // an icon-font glyph in an aria-hidden span. Such a control counts as a
  // label only when every child element is hidden from assistive technology,
  // and only its own text nodes are read, so neither the glyph nor a
  // container of visible text ever becomes part of a label.
  function iconLabelText(element) {
    for (const child of Array.from(element.children || [])) {
      if (child.getAttribute("aria-hidden") !== "true") return null;
    }
    let own = "";
    for (const node of Array.from(element.childNodes || [])) {
      if (node.nodeType === 3) own += node.nodeValue;
    }
    const value = own.replace(/\s+/g, " ").trim();
    return value && value.length <= 80 ? value : null;
  }

  function labelText(element) {
    if (!element) return null;
    return element.childElementCount > 0 ? iconLabelText(element) : boundedOwnText(element, 80);
  }

  function labelKind(element) {
    const text = labelText(element);
    if (!text) return null;
    for (const [kind, patterns] of Object.entries(HEADING_PATTERNS)) {
      if (patterns.some((pattern) => pattern.test(text))) return kind;
    }
    for (const [kind, patterns] of Object.entries(BOUNDARY_PATTERNS)) {
      if (patterns.some((pattern) => pattern.test(text))) return kind;
    }
    return null;
  }

  function labelKindsWithin(scope) {
    const kinds = [];
    const leaves = Array.from(scope.querySelectorAll('h1, h2, h3, h4, h5, h6, [role="heading"], div, p, span, button'))
      .slice(0, CONTRACT.maximumLabelElementCount);
    for (const leaf of leaves) {
      const kind = labelKind(leaf);
      if (kind) kinds.push(kind);
    }
    return kinds;
  }

  // The usage page may put several quota rows inside one section. Walk up from
  // the label and keep the widest ancestor that still holds exactly one
  // percentage and no other quota label. Two percentages, or a second label,
  // before any single-value ancestor means the row cannot be isolated: fail
  // closed rather than pick one.
  function rowForLabel(label, kind) {
    const card = cardForHeading(label);
    if (card && percentageValues(card).length === 1
        && labelKindsWithin(card).every((other) => other === kind)) {
      return card;
    }
    let row = null;
    let node = label.parentElement;
    for (let depth = 0; node && depth < MAXIMUM_ROW_DEPTH; depth += 1) {
      if (labelKindsWithin(node).length > 1) break;
      const values = percentageValues(node);
      if (values.length > 1) break;
      if (values.length === 1) row = node;
      node = node.parentElement;
    }
    return row;
  }

  function matchingLabelCards(documentLike, patterns, kind) {
    const labels = documentLike.querySelectorAll(
      'h1, h2, h3, h4, h5, h6, [role="heading"], div, p, span, button'
    );
    const cards = [];
    // The settings SPA contains many structural div/span nodes before its
    // Usage cards. Keep the search bounded without truncating it to the first
    // few page nodes, which can exclude every allowlisted Usage landmark.
    const upperBound = Math.min(labels.length, CONTRACT.maximumLabelElementCount);
    for (let index = 0; index < upperBound; index += 1) {
      const label = labels[index];
      // Claude renders "Current session" as a leaf label and "This week" as a
      // toggle's own text, not as semantic headings. Match only exact
      // allowlisted text; no unrelated page copy is retained or allowed
      // across the boundary.
      const text = label.childElementCount > 0 ? iconLabelText(label) : boundedOwnText(label, 80);
      if (!text || !patterns.some((pattern) => pattern.test(text))) continue;
      // A label whose row cannot be isolated, such as a section heading above
      // several rows, has no percentage of its own and is not a candidate.
      const card = rowForLabel(label, kind);
      if (card && !cards.includes(card)) cards.push(card);
      if (cards.length > 1) return cards;
    }
    return cards;
  }

  function uniqueCard(documentLike, kind) {
    const explicit = matchingExplicitCards(documentLike, CARD_SELECTORS[kind]);
    if (explicit.length === 1) return explicit[0];
    if (explicit.length > 1) return null;
    const labelled = matchingLabelCards(documentLike, HEADING_PATTERNS[kind], kind);
    return labelled.length === 1 ? labelled[0] : null;
  }

  function finitePercentage(raw) {
    if (typeof raw === "number") {
      return Number.isFinite(raw) && raw >= 0 && raw <= 100 ? raw : null;
    }
    if (typeof raw !== "string" || raw.length > 16) return null;
    // "8%" and "8% used" are the used share. Anything else, including
    // "8% left", is not read, so a remaining share is never taken as used.
    const match = raw.trim().match(/^(100(?:\.0+)?|\d{1,2}(?:\.\d+)?)\s*(?:%(?:\s+used)?)?$/i);
    if (!match) return null;
    const parsed = Number(match[1]);
    return Number.isFinite(parsed) && parsed >= 0 && parsed <= 100 ? parsed : null;
  }

  function readPercentage(card) {
    const unique = percentageValues(card);
    return unique.length === 1 ? unique[0] : null;
  }

  function percentageValues(card) {
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
    return Array.from(new Set(values));
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
    if (keys !== "extractorSchemaVersion,fiveHour,modelSpecificWeekly,observedAt,sourceLayoutVersion,weeklyAllModels") return false;
    if (value.extractorSchemaVersion !== CONTRACT.schemaVersion) return false;
    if (value.sourceLayoutVersion !== CONTRACT.sourceLayoutVersion) return false;
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
      sourceLayoutVersion: CONTRACT.sourceLayoutVersion,
    };
    // The SPA may navigate while extraction is in progress. Revalidate both
    // route and login absence after reading the bounded landmarks so a click
    // cannot carry a result from a tab that changed underneath the extractor.
    if (!exactUsageURL(locationLike) || hasLoginForm(documentLike)) return null;
    return validateObservation(observation) ? observation : null;
  }

  function extractResult(documentLike, locationLike, now) {
    // The URL gate must run before the first DOM query. Persistent host access
    // covers /new*, but UMA is allowed to inspect only the exact Usage hash.
    if (!exactUsageURL(locationLike)) {
      return { status: "routeRejected", reasonCode: FAILURE_REASONS.routeNotReady };
    }
    // On the exact route, authentication uncertainty is classified using only
    // narrow form landmarks. No Usage labels or other page content are read.
    if (hasLoginForm(documentLike)) {
      return { status: "signInRequired", reasonCode: FAILURE_REASONS.providerSessionUnavailable };
    }

    const observation = extract(documentLike, locationLike, now);
    if (observation) return { status: "success", observation };

    // The SPA can navigate while extraction is running. Recheck the route and
    // login guard before reporting a content-free failure classification.
    if (!exactUsageURL(locationLike)) {
      return { status: "routeRejected", reasonCode: FAILURE_REASONS.routeNotReady };
    }
    if (hasLoginForm(documentLike)) {
      return { status: "signInRequired", reasonCode: FAILURE_REASONS.providerSessionUnavailable };
    }
    const hasRecognizedCard = Boolean(
      uniqueCard(documentLike, "fiveHour") || uniqueCard(documentLike, "weeklyAllModels")
    );
    return {
      status: "usageUnavailable",
      reasonCode: hasRecognizedCard
        ? FAILURE_REASONS.providerStructureUnsupported
        : FAILURE_REASONS.targetDataNotReady,
    };
  }

  root.UMAClaudeUsageExtractor = Object.freeze({
    CONTRACT,
    FAILURE_REASONS,
    exactUsageURL,
    usageRouteState,
    finitePercentage,
    normalizedTimestamp,
    validateObservation,
    extract,
    extractResult,
  });
})(globalThis);
