/*
 * UMA Gemini Usage extraction core.
 *
 * Like the Claude extractor, this file has no browser API dependency. It reads
 * only the exact official Gemini Usage route, and only inside the region the
 * "Usage limits" heading belongs to: the Gemini sidebar lists conversation
 * titles and the account name, and no text from it, or any other page text,
 * ever leaves this function. What leaves is one of two fixed bucket
 * identifiers, a fixed period, a bounded used percentage, an optional reset
 * timestamp, and an allowlisted plan word.
 *
 * Layout (signed-in page, English, 2026-11-24):
 *   Usage limits [PRO]
 *   Current usage (i) ............ 0% used   [progress bar]   Resets at 6:18 AM
 *   Weekly limit ................. 4% used   Resets Nov 25 at 9:18 PM
 *   Get 5x more usage with AI Ultra / Usage settings / Extra usage  (ignored)
 */
(function (root) {
  "use strict";

  const CONTRACT = Object.freeze({
    provider: "gemini",
    schemaVersion: 1,
    sourceLayoutVersion: 1,
    origin: "https://gemini.google.com",
    path: "/usage",
    href: "https://gemini.google.com/usage",
    maximumLabelElementCount: 4096,
    maximumCandidateCount: 64,
    maximumBuckets: 12,
  });

  const FAILURE_REASONS = Object.freeze({
    routeNotReady: "ROUTE_NOT_READY",
    providerStructureUnsupported: "PROVIDER_STRUCTURE_UNSUPPORTED",
    providerSessionUnavailable: "PROVIDER_SESSION_UNAVAILABLE",
    targetDataNotReady: "TARGET_DATA_NOT_READY",
    extractionValidationFailed: "EXTRACTION_VALIDATION_FAILED",
  });

  const HEADING_PATTERN = /^usage limits$/i;

  // Each row label maps to one fixed bucket and the period the page states
  // for it. "Current usage" names no period on the page, so it is reported
  // as `unknown` and AUV decides how to show it.
  const BUCKETS = Object.freeze({
    current: Object.freeze({ patterns: [/^current usage$/i], period: "unknown" }),
    weekly: Object.freeze({ patterns: [/^weekly limits?$/i], period: "weekly" }),
  });
  const BUCKET_IDS = Object.freeze(Object.keys(BUCKETS));

  // A reset read from text can be no further ahead than its window is long.
  const RESET_HORIZON_MINUTES = Object.freeze({
    fiveHour: 5 * 60 + 10,
    daily: 24 * 60 + 60,
    weekly: 7 * 24 * 60 + 60,
    unknown: 7 * 24 * 60 + 60,
  });

  // The plan is the short badge beside the heading ("PRO"). Only a bare
  // allowlisted word counts, lowercased.
  const PLAN_VALUES = Object.freeze(["free", "plus", "pro", "ultra"]);
  const PLAN_BADGE_PATTERN = /^(free|plus|pro|ultra)$/i;
  const PLAN_BADGE_MAXIMUM_DEPTH = 2;

  const MAXIMUM_ROW_DEPTH = 6;

  function exactUsageURL(locationLike) {
    if (!locationLike || locationLike.protocol !== "https:"
        || locationLike.origin !== CONTRACT.origin) return false;
    return locationLike.pathname === CONTRACT.path
      && !locationLike.search
      && !locationLike.hash;
  }

  function usageRouteState(locationLike) {
    if (exactUsageURL(locationLike)) return "exact";
    if (locationLike?.protocol === "https:"
        && locationLike.origin === CONTRACT.origin
        && locationLike.pathname === CONTRACT.path) return "providerRoutePending";
    return "rejected";
  }

  function boundedOwnText(element, maximum) {
    if (!element) return null;
    const value = String(element.textContent || "").replace(/\s+/g, " ").trim();
    return value && value.length <= maximum ? value : null;
  }

  // An element's own text, without its child elements' text. "Current usage"
  // sits beside an info icon in the same element, so the icon's text, if
  // any, must not become part of the label.
  function ownText(element, maximum) {
    let own = "";
    for (const node of Array.from(element.childNodes || [])) {
      if (node.nodeType === 3) own += node.nodeValue;
    }
    const value = own.replace(/\s+/g, " ").trim();
    return value && value.length <= maximum ? value : null;
  }

  function hasLoginForm(documentLike) {
    return Boolean(documentLike.querySelector(
      'input[type="password"], input[autocomplete="current-password"], '
      + 'form[action*="ServiceLogin"], form[action*="signin"]'
    ));
  }

  const LABEL_SELECTOR = 'h1, h2, h3, h4, h5, h6, [role="heading"], div, p, span, label';

  function bucketForLabel(element) {
    const text = ownText(element, 48);
    if (!text) return null;
    const matches = BUCKET_IDS.filter((id) => BUCKETS[id].patterns.some((pattern) => pattern.test(text)));
    return matches.length === 1 ? matches[0] : null;
  }

  function usageHeading(documentLike) {
    const headings = Array.from(documentLike.querySelectorAll('h1, h2, h3, [role="heading"]'))
      .slice(0, CONTRACT.maximumLabelElementCount)
      .filter((node) => HEADING_PATTERN.test(ownText(node, 40) || ""));
    return headings.length === 1 ? headings[0] : null;
  }

  function labelsWithin(scope) {
    const found = [];
    const candidates = Array.from(scope.querySelectorAll(LABEL_SELECTOR))
      .slice(0, CONTRACT.maximumLabelElementCount);
    for (const candidate of candidates) {
      const bucket = bucketForLabel(candidate);
      if (bucket) found.push(bucket);
    }
    return found;
  }

  // The region read is the smallest ancestor of the "Usage limits" heading
  // that also holds a quota row label. The sidebar is a separate branch, so
  // it is outside that region. If that ancestor is the whole document, the
  // page gives no structure to tell them apart, and a `main` holding the
  // heading must bound the region instead.
  function usageRegion(documentLike) {
    const heading = usageHeading(documentLike);
    if (!heading) return null;
    let node = heading.parentElement;
    while (node && labelsWithin(node).length === 0) node = node.parentElement;
    if (!node) return null;
    if (node === documentLike.body || node === documentLike.documentElement) {
      const mains = Array.from(documentLike.querySelectorAll('main, [role="main"]'))
        .filter((main) => main.contains(heading));
      return mains.length >= 1 ? mains[mains.length - 1] : null;
    }
    return node;
  }

  function finitePercentage(raw) {
    if (typeof raw === "number") {
      return Number.isFinite(raw) && raw >= 0 && raw <= 100 ? raw : null;
    }
    if (typeof raw !== "string" || raw.length > 24) return null;
    // "4% used" is the used share. "96% left" is not read, so a remaining
    // share is never taken as used.
    const match = raw.trim().match(/^(100(?:\.0+)?|\d{1,2}(?:\.\d+)?)\s*(?:%(?:\s+used)?)?$/i);
    if (!match) return null;
    const parsed = Number(match[1]);
    return Number.isFinite(parsed) && parsed >= 0 && parsed <= 100 ? parsed : null;
  }

  function percentageValues(row) {
    const values = [];
    const candidates = Array.from(row.querySelectorAll(
      '[aria-valuenow], [role="progressbar"], span, strong, p, div'
    )).slice(0, CONTRACT.maximumCandidateCount);
    for (const candidate of candidates) {
      const aria = candidate.getAttribute("aria-valuenow");
      if (aria !== null) {
        const minimum = Number(candidate.getAttribute("aria-valuemin") || 0);
        const maximum = Number(candidate.getAttribute("aria-valuemax") || 100);
        const value = Number(aria);
        if (Number.isFinite(value) && Number.isFinite(minimum) && Number.isFinite(maximum)
            && maximum > minimum && value >= minimum && value <= maximum) {
          values.push(Math.round(((value - minimum) / (maximum - minimum)) * 1000) / 10);
        }
      }
      if (candidate.childElementCount > 0) continue;
      const text = boundedOwnText(candidate, 24);
      // Visible copy must include the percent sign, so dates and times in
      // the row never become quota.
      if (text && text.includes("%")) {
        const parsed = finitePercentage(text);
        if (parsed !== null) values.push(parsed);
      }
    }
    return Array.from(new Set(values));
  }

  // The widest ancestor that still holds exactly one value and no other
  // bucket's label is the row. Anything less certain fails closed.
  function rowForLabel(label, bucketID, region) {
    let row = null;
    let node = label.parentElement;
    for (let depth = 0; node && depth < MAXIMUM_ROW_DEPTH; depth += 1) {
      if (!region.contains(node)) break;
      if (labelsWithin(node).some((other) => other !== bucketID)) break;
      const values = percentageValues(node);
      if (values.length > 1) break;
      if (values.length === 1) row = node;
      if (node === region) break;
      node = node.parentElement;
    }
    return row;
  }

  function normalizedTimestamp(raw) {
    if (typeof raw !== "string" || raw.length > 64) return null;
    const value = raw.trim();
    if (!/^\d{4}-\d{2}-\d{2}T/.test(value)) return null;
    const milliseconds = Date.parse(value);
    return Number.isFinite(milliseconds) ? new Date(milliseconds).toISOString() : null;
  }

  // Gemini shows a reset only as text in the viewer's own time zone, in the
  // same shapes as Claude: "Resets at 6:18 AM", "Resets Nov 25 at 9:18 PM".
  // The Claude extractor's reader is shared when it is loaded; without it a
  // reset stays unknown rather than guessed.
  function textResetDate(text, now) {
    const reader = root.UMAClaudeUsageExtractor?.textResetDate;
    return typeof reader === "function" ? reader(text, now) : null;
  }

  function rowReset(row, period, now) {
    const machine = [];
    for (const candidate of Array.from(row.querySelectorAll("time[datetime], [data-reset-at]")).slice(0, 8)) {
      for (const raw of [candidate.getAttribute("datetime"), candidate.getAttribute("data-reset-at")]) {
        if (!raw) continue;
        const normalized = normalizedTimestamp(raw);
        if (!normalized) return { valid: false, value: null };
        machine.push(normalized);
      }
    }
    const values = Array.from(new Set(machine));
    if (values.length === 0) {
      for (const candidate of Array.from(row.querySelectorAll("span, p, div, time"))
        .slice(0, CONTRACT.maximumCandidateCount)) {
        if (candidate.childElementCount > 0) continue;
        const text = boundedOwnText(candidate, 64);
        if (!text || !/^resets\s/i.test(text)) continue;
        const date = textResetDate(text, now);
        if (!date || !Number.isFinite(date.getTime())) continue;
        values.push(date.toISOString());
      }
    }
    const unique = Array.from(new Set(values));
    // Two different resets in one row cannot both be its reset.
    if (unique.length !== 1) return { valid: true, value: null };
    const ahead = (Date.parse(unique[0]) - now.getTime()) / 60000;
    if (ahead < -1 || ahead > RESET_HORIZON_MINUTES[period]) return { valid: true, value: null };
    return { valid: true, value: unique[0] };
  }

  function readBuckets(region, now) {
    const rowsByBucket = new Map();
    const labels = Array.from(region.querySelectorAll(LABEL_SELECTOR))
      .slice(0, CONTRACT.maximumLabelElementCount);
    for (const label of labels) {
      const bucketID = bucketForLabel(label);
      if (!bucketID) continue;
      const row = rowForLabel(label, bucketID, region);
      if (!row) continue;
      const rows = rowsByBucket.get(bucketID) || [];
      if (!rows.includes(row)) rows.push(row);
      rowsByBucket.set(bucketID, rows);
    }
    const buckets = [];
    for (const bucketID of BUCKET_IDS) {
      const rows = rowsByBucket.get(bucketID);
      // Two rows for one bucket cannot be told apart: neither is reported.
      if (!rows || rows.length !== 1) continue;
      const values = percentageValues(rows[0]);
      if (values.length !== 1) continue;
      const period = BUCKETS[bucketID].period;
      const reset = rowReset(rows[0], period, now);
      if (!reset.valid) continue;
      buckets.push({ bucketID, period, usedPercentage: values[0], resetAt: reset.value });
      if (buckets.length >= CONTRACT.maximumBuckets) break;
    }
    return buckets;
  }

  function planBadge(documentLike) {
    const heading = usageHeading(documentLike);
    if (!heading) return null;
    let row = heading.parentElement;
    for (let depth = 0; row && depth < PLAN_BADGE_MAXIMUM_DEPTH; depth += 1) {
      const plans = new Set();
      for (const node of Array.from(row.querySelectorAll("span, div, p, small"))) {
        // The badge may sit inside the heading element or beside it; the
        // heading's own words are never a candidate.
        if (node === heading || node.contains(heading)) continue;
        if (node.childElementCount > 0) continue;
        const match = PLAN_BADGE_PATTERN.exec(boundedOwnText(node, 12) || "");
        if (match) plans.add(match[1].toLowerCase());
      }
      if (plans.size > 1) return null;
      if (plans.size === 1) return Array.from(plans)[0];
      row = row.parentElement;
    }
    return null;
  }

  function validateBucket(bucket) {
    if (!bucket || Object.getPrototypeOf(bucket) !== Object.prototype) return false;
    if (Object.keys(bucket).sort().join(",") !== "bucketID,period,resetAt,usedPercentage") return false;
    if (!BUCKET_IDS.includes(bucket.bucketID)) return false;
    if (!["fiveHour", "daily", "weekly", "unknown"].includes(bucket.period)) return false;
    if (finitePercentage(bucket.usedPercentage) === null) return false;
    return bucket.resetAt === null || normalizedTimestamp(bucket.resetAt) !== null;
  }

  function validateObservation(value) {
    if (!value || Object.getPrototypeOf(value) !== Object.prototype) return false;
    const keys = Object.keys(value).sort().join(",");
    if (keys !== "buckets,extractorSchemaVersion,observedAt,planLabel,sourceLayoutVersion") return false;
    if (value.planLabel !== null && !PLAN_VALUES.includes(value.planLabel)) return false;
    if (value.extractorSchemaVersion !== CONTRACT.schemaVersion) return false;
    if (value.sourceLayoutVersion !== CONTRACT.sourceLayoutVersion) return false;
    if (!normalizedTimestamp(value.observedAt)) return false;
    if (!Array.isArray(value.buckets) || value.buckets.length === 0
        || value.buckets.length > CONTRACT.maximumBuckets) return false;
    if (new Set(value.buckets.map((bucket) => bucket?.bucketID)).size !== value.buckets.length) return false;
    return value.buckets.every(validateBucket);
  }

  function extract(documentLike, locationLike, now) {
    if (!exactUsageURL(locationLike) || hasLoginForm(documentLike)) return null;
    const region = usageRegion(documentLike);
    if (!region) return null;
    const moment = now || new Date();
    const buckets = readBuckets(region, moment);
    if (buckets.length === 0) return null;
    const observation = {
      buckets,
      planLabel: planBadge(documentLike),
      observedAt: moment.toISOString(),
      extractorSchemaVersion: CONTRACT.schemaVersion,
      sourceLayoutVersion: CONTRACT.sourceLayoutVersion,
    };
    // The SPA may navigate while extraction runs.
    if (!exactUsageURL(locationLike) || hasLoginForm(documentLike)) return null;
    return validateObservation(observation) ? observation : null;
  }

  function extractResult(documentLike, locationLike, now) {
    if (!exactUsageURL(locationLike)) {
      return { status: "routeRejected", reasonCode: FAILURE_REASONS.routeNotReady };
    }
    if (hasLoginForm(documentLike)) {
      return { status: "signInRequired", reasonCode: FAILURE_REASONS.providerSessionUnavailable };
    }
    const observation = extract(documentLike, locationLike, now);
    if (observation) return { status: "success", observation };
    if (!exactUsageURL(locationLike)) {
      return { status: "routeRejected", reasonCode: FAILURE_REASONS.routeNotReady };
    }
    if (hasLoginForm(documentLike)) {
      return { status: "signInRequired", reasonCode: FAILURE_REASONS.providerSessionUnavailable };
    }
    const region = usageRegion(documentLike);
    const hasRecognizedLabel = Boolean(region) && labelsWithin(region).length > 0;
    return {
      status: "usageUnavailable",
      reasonCode: hasRecognizedLabel
        ? FAILURE_REASONS.providerStructureUnsupported
        : FAILURE_REASONS.targetDataNotReady,
    };
  }

  // Two equal readings, apart from the extraction time, confirm a result.
  function stableProjection(observation) {
    if (!observation) return null;
    return JSON.stringify({
      buckets: observation.buckets,
      planLabel: observation.planLabel,
      extractorSchemaVersion: observation.extractorSchemaVersion,
      sourceLayoutVersion: observation.sourceLayoutVersion,
    });
  }

  root.UMAGeminiUsageExtractor = Object.freeze({
    CONTRACT,
    FAILURE_REASONS,
    BUCKET_IDS,
    exactUsageURL,
    usageRouteState,
    finitePercentage,
    normalizedTimestamp,
    validateObservation,
    extract,
    extractResult,
    stableProjection,
  });
})(globalThis);
