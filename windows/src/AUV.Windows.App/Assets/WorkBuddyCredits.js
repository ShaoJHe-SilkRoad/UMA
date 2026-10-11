    (() => {
      "use strict";

      const VERSION = 3;
      const empty = () => ({
        extractorVersion: VERSION,
        discoveredSections: [],
        subscriptionPools: [],
        addOnPools: [],
        benefitGiftPools: [],
        authoritativePageBalances: [],
        sectionSummaries: []
      });
      const fail = (reason, safeDiagnosticCode = null) => ({
        ...empty(),
        failure: reason,
        ...(safeDiagnosticCode ? { safeDiagnosticCode } : {})
      });

      if (location.origin !== "https://www.workbuddy.cn" ||
          location.pathname !== "/profile/plans-usage" ||
          location.search !== "" ||
          location.hash !== "") {
        return fail("unexpectedPage");
      }
      if (document.readyState !== "interactive" &&
          document.readyState !== "complete") {
        return fail("pageNotStabilized");
      }

      const root = document.querySelector(".plans-usage");
      if (!root) return fail("unexpectedPage");
      const title = root.querySelector(
        "h1, h2, .plans-usage__header, .plans-usage__section-title"
      );
      const titleText = title ? (title.textContent || "").trim() : "";
      if (titleText &&
          !titleText.includes("套餐与用量") &&
          !titleText.includes("套餐与积分") &&
          !/plan\s*(and|&)\s*usage/i.test(titleText)) {
        return fail("unexpectedPage");
      }

      const normalizedText = (value) => String(value || "")
        .replace(/\u00a0/g, " ")
        .replace(/\s+/g, " ")
        .trim();
      const pairPattern =
        /((?:[1-9]\d{0,2}(?:[,\uFF0C]\d{3})+|(?:0|[1-9]\d*))(?:\.\d{1,2})?)\s*\/\s*((?:[1-9]\d{0,2}(?:[,\uFF0C]\d{3})+|(?:0|[1-9]\d*))(?:\.\d{1,2})?)/;
      const sectionPatterns = {
        subscription:
          /订阅|基础(?:套餐|资源|额度|积分|权益|包)|套餐(?:额度|资源|积分)|subscription|plan\s*credits|included\s*credits/i,
        addOn: /购买积分|加量包|add[\s-]*on/i,
        benefitGift: /平台奖励积分|权益赠送包|权益包|赠送包|benefit|gift/i
      };
      const matchingSectionKeys = (text) => Object.entries(sectionPatterns)
        .filter(([, pattern]) => pattern.test(text))
        .map(([key]) => key);
      const semanticNodeText = (node) => normalizedText([
        node.textContent,
        node.getAttribute && node.getAttribute("aria-label"),
        node.getAttribute && node.getAttribute("data-section"),
        node.getAttribute && node.getAttribute("data-section-title")
      ].filter(Boolean).join(" "));
      const sectionKeyForText = (text) => {
        const matches = matchingSectionKeys(text);
        return matches.length === 1 ? matches[0] : null;
      };
      const titleSelector =
        "h1, h2, h3, h4, h5, h6, [role='heading'], [aria-level], " +
        "[data-section], [data-section-title], " +
        ".plans-usage__section-title, .section-title, .card-title";
      const quotaRowSelectors = [
        ".plans-usage__quota-row",
        ".plans-usage__resource-row",
        ".plans-usage__package-row",
        ".plans-usage__benefit-row",
        ".quota-row",
        ".quota-item",
        ".resource-row",
        ".resource-item",
        ".package-row",
        ".package-item",
        "[data-quota-id]",
        "[data-resource-id]",
        "[data-package-id]",
        "[data-benefit-id]",
        "[data-used-credits][data-total-credits]",
        "[role='row']",
        "[role='listitem']",
        "li",
        "tr"
      ];
      const quotaRowSelector = quotaRowSelectors.join(", ");
      const quotaRowCandidates = (container) =>
        Array.from(container.querySelectorAll(quotaRowSelector));
      const pairCount = (text) => (
        normalizedText(text).match(new RegExp(pairPattern.source, "g")) || []
      ).length;
      const owningCreditRow = (node, section) => {
        let best = node;
        let candidate = node.parentElement;
        for (let depth = 0;
             candidate && depth < 12;
             depth += 1) {
          if (candidate === section) break;
          if (pairCount(candidate.textContent) !== 1) break;
          best = candidate;
          candidate = candidate.parentElement;
        }
        return best;
      };
      const visibleCreditRows = (container) => {
        const rows = [];
        for (const selector of quotaRowSelectors) {
          const candidates = Array.from(
            container.querySelectorAll(selector)
          ).filter((node) =>
            node.getClientRects().length > 0 &&
            pairCount(node.textContent) === 1
          );
          const outerRows = candidates.filter((node) =>
            !candidates.some((other) =>
              other !== node && other.contains(node)
            )
          ).map((node) => owningCreditRow(node, container));
          for (const row of outerRows) {
            if (!rows.includes(row)) rows.push(row);
          }
        }
        return rows;
      };
      const titleNodes = Array.from(root.querySelectorAll(titleSelector));
      const sectionKey = (node) => {
        return sectionKeyForText(semanticNodeText(node));
      };
      const titles = {};
      for (const node of titleNodes) {
        const key = sectionKey(node);
        if (!key) continue;
        if (titles[key]) {
          const existing = titles[key];
          const duplicateIsHidden =
            existing.getClientRects().length === 0 ||
            node.getClientRects().length === 0;
          if (duplicateIsHidden) {
            if (existing.getClientRects().length === 0) titles[key] = node;
            continue;
          }
          return fail("ambiguousCredits");
        }
        titles[key] = node;
      }

      const rowDerivedSections = {};
      const deriveSectionFromRow = (row) => {
        let candidate = row.parentElement;
        let best = null;
        for (let depth = 0; candidate && candidate !== root && depth < 6; depth += 1) {
          const key = sectionKeyForText(normalizedText(candidate.textContent));
          if (key) {
            best = { key, container: candidate };
          } else if (matchingSectionKeys(
            normalizedText(candidate.textContent)
          ).length > 1) {
            break;
          }
          candidate = candidate.parentElement;
        }
        return best;
      };
      for (const row of quotaRowCandidates(root).filter(
        (node) => node.getClientRects().length > 0
      )) {
        const derived = deriveSectionFromRow(row);
        if (!derived) continue;
        const existing = rowDerivedSections[derived.key];
        if (existing &&
            existing !== derived.container &&
            !existing.contains(derived.container) &&
            !derived.container.contains(existing)) {
          return fail("ambiguousCredits");
        }
        if (!existing || derived.container.contains(existing)) {
          rowDerivedSections[derived.key] = derived.container;
        }
      }

      const missingTitleKeys = Object.keys(sectionPatterns).filter(
        (key) => !titles[key] && !rowDerivedSections[key]
      );
      const safeDiagnosticCode = () => {
        const bit = (value) => value ? "1" : "0";
        return "T" +
          bit(Boolean(titles.subscription)) +
          bit(Boolean(titles.addOn)) +
          bit(Boolean(titles.benefitGift)) +
          "-D" +
          bit(Boolean(rowDerivedSections.subscription)) +
          bit(Boolean(rowDerivedSections.addOn)) +
          bit(Boolean(rowDerivedSections.benefitGift)) +
          "-Q" +
          bit(quotaRowCandidates(root).length > 0);
      };
      if (missingTitleKeys.length > 0) {
        return fail("incompletePoolSections", safeDiagnosticCode());
      }
      delete globalThis.__umaWorkBuddySectionDiscoveryStepV3;

      const sectionContainer = (heading) => {
        let candidate = heading.parentElement;
        let best = candidate;
        for (let depth = 0; candidate && candidate !== root && depth < 6; depth += 1) {
          const recognizedHeadings = Array.from(
            candidate.querySelectorAll(titleSelector)
          ).filter((node) =>
            sectionKey(node) !== null && node.getClientRects().length > 0
          );
          if (recognizedHeadings.length === 1) best = candidate;
          if (recognizedHeadings.length > 1) break;
          candidate = candidate.parentElement;
        }
        return best;
      };
      const sections = {
        subscription: titles.subscription
          ? sectionContainer(titles.subscription)
          : rowDerivedSections.subscription,
        addOn: titles.addOn
          ? sectionContainer(titles.addOn)
          : rowDerivedSections.addOn,
        benefitGift: titles.benefitGift
          ? sectionContainer(titles.benefitGift)
          : rowDerivedSections.benefitGift
      };
      if (!sections.subscription || !sections.addOn || !sections.benefitGift ||
          new Set(Object.values(sections)).size !== 3) {
        return fail("incompletePoolSections", safeDiagnosticCode());
      }

      const expandAndCount = (key) => {
        const section = sections[key];
        return {
          expanded: false,
          count: visibleCreditRows(section).length
        };
      };

      const subscriptionState = expandAndCount("subscription");
      const addOnState = expandAndCount("addOn");
      const benefitGiftState = expandAndCount("benefitGift");
      const states = [subscriptionState, addOnState, benefitGiftState];
      const stateFailure = states.find((state) => state.failure);
      if (stateFailure) return fail(stateFailure.failure);
      if (states.some((state) => state.expanded)) {
        return fail("pageNotStabilized");
      }
      const signature = states.map((state) => state.count).join("|");
      const prior = globalThis.__umaWorkBuddyPoolStabilityV2;
      if (!prior || prior.signature !== signature) {
        globalThis.__umaWorkBuddyPoolStabilityV2 = {
          signature,
          stableObservations: 1
        };
        return fail("pageNotStabilized");
      }
      prior.stableObservations += 1;
      if (prior.stableObservations < 2) return fail("pageNotStabilized");

      const canonical = (raw) => {
        const normalized = String(raw || "")
          .replace(/[\s,\uFF0C\u00a0]/g, "")
          .replace(/credits?|积分/ig, "");
        if (!/^(?:0|[1-9]\d*)(?:\.\d{1,2})?$/.test(normalized)) return null;
        const pieces = normalized.split(".");
        if (pieces.length === 2) {
          pieces[1] = pieces[1].replace(/0+$/, "");
          if (!pieces[1]) return pieces[0];
        }
        return pieces.join(".");
      };
      const numberToken =
        /(?:[1-9]\d{0,2}(?:[,\uFF0C]\d{3})+|(?:0|[1-9]\d*))(?:\.\d{1,2})?/g;
      const explicitEmptyPattern =
        /暂无(?:可用)?|无(?:可用)?(?:额度|积分|资源|套餐|权益|加量包)|none|no\s+(?:available\s+)?(?:credits?|packages?|resources?)/i;
      const sectionIsExplicitlyEmpty = (key) =>
        explicitEmptyPattern.test(normalizedText(sections[key].textContent));

      const hash = (raw) => {
        let value = 2166136261;
        for (let index = 0; index < raw.length; index += 1) {
          value ^= raw.charCodeAt(index);
          value = Math.imul(value, 16777619);
        }
        return `pool-${(value >>> 0).toString(16).padStart(8, "0")}`;
      };
      const stablePageID = (row) => {
        let candidate = row;
        for (let depth = 0; candidate && depth < 5; depth += 1) {
          const raw = [
            candidate.getAttribute("data-id"),
            candidate.getAttribute("data-package-id"),
            candidate.getAttribute("data-resource-id"),
            candidate.getAttribute("data-quota-id"),
            candidate.getAttribute("data-benefit-id")
          ].find((value) => value && value.length <= 128);
          if (raw) return hash(raw);
          candidate = candidate.parentElement;
        }
        const semanticRow = normalizedText(row.textContent);
        return semanticRow.length > 0 && semanticRow.length <= 1_024
          ? hash(semanticRow)
          : null;
      };
      const normalizedDate = (raw, endOfDay) => {
        const match = normalizedText(raw).match(
          /(\d{4})[年\-\/.](\d{1,2})[月\-\/.](\d{1,2})(?:日)?(?:\s+(\d{1,2}):(\d{2})(?::(\d{2}))?)?/
        );
        if (!match) return null;
        const year = match[1];
        const month = match[2].padStart(2, "0");
        const day = match[3].padStart(2, "0");
        const clock = match[4]
          ? [
              match[4].padStart(2, "0"),
              match[5],
              match[6] || "00"
            ].join(":")
          : (endOfDay ? "23:59:59" : "00:00:00");
        const epoch = Date.parse(`${year}-${month}-${day}T${clock}+08:00`);
        return Number.isSafeInteger(epoch) ? epoch : null;
      };
      const dates = (text) => {
        const dateTimeToken =
          "((?:\\d{4})[年\\-\\/.](?:\\d{1,2})[月\\-\\/.](?:\\d{1,2})(?:日)?" +
          "(?:\\s+\\d{1,2}:\\d{2}(?::\\d{2})?)?)";
        const effective = text.match(
          new RegExp(
            "(?:生效(?:时间|日期)?|effective(?:\\s+from)?|starts?)" +
              "\\s*[:：]?\\s*" + dateTimeToken,
            "i"
          )
        );
        const expiry = text.match(
          new RegExp(
            "(?:到期(?:时间|日期)?|有效期至|expires?|expiry)" +
              "\\s*[:：]?\\s*" + dateTimeToken,
            "i"
          )
        );
        return {
          effectiveAtMilliseconds: effective
            ? normalizedDate(effective[1], false)
            : null,
          expiresAtMilliseconds: expiry
            ? normalizedDate(expiry[1], true)
            : null
        };
      };
      const status = (text, used, total) => {
        const matches = [];
        if (/已过期|expired/i.test(text)) matches.push("expired");
        if (/未生效|待生效|not\s+yet\s+effective|future/i.test(text)) {
          matches.push("future");
        }
        if (/不可用|不可使用|无法使用|已失效|invalid|unavailable/i.test(text)) {
          matches.push("unavailable");
        }
        if (/历史|historical/i.test(text)) matches.push("historical");
        if (/使用中|active|in\s+use/i.test(text)) matches.push("active");
        if (/(?:^|[^不])可用|available/i.test(text)) matches.push("available");
        const unique = Array.from(new Set(matches));
        if (unique.length > 1) {
          const positive = unique.filter((value) =>
            value === "active" || value === "available"
          );
          const negative = unique.filter((value) =>
            value !== "active" && value !== "available"
          );
          if (positive.length > 0 && negative.length > 0) return "ambiguous";
          if (negative.length > 1) return "ambiguous";
          return negative[0] || "active";
        }
        if (unique.length === 1) return unique[0];
        return used === total ? "exhausted" : "available";
      };
      const subscriptionKind = (text) => {
        const base = /基础|base/i.test(text);
        const bonus = /奖励|赠送|bonus/i.test(text);
        if (base === bonus) return null;
        return base ? "subscriptionBase" : "subscriptionBonus";
      };
      const hasDisabledMetadata = (row, section) => {
        let candidate = row;
        for (let depth = 0;
             candidate && section.contains(candidate) && depth < 8;
             depth += 1) {
          const metadata = [
            candidate.getAttribute("aria-disabled"),
            candidate.getAttribute("data-disabled"),
            candidate.getAttribute("data-status"),
            candidate.getAttribute("data-state"),
            candidate.getAttribute("class")
          ].map(normalizedText).join(" ");
          if (/(?:^|\s)(?:true|disabled|unavailable|invalid|expired)(?:\s|$)/i
                .test(metadata)) {
            return true;
          }
          if (candidate.hasAttribute &&
              candidate.hasAttribute("disabled")) {
            return true;
          }
          candidate = candidate.parentElement;
        }
        return false;
      };
      const extractRows = (key, kindForText, maximumCount) => {
        const output = [];
        const rows = visibleCreditRows(sections[key]);
        const visibleCandidates = quotaRowCandidates(sections[key]).filter(
          (node) => node.getClientRects().length > 0
        );
        if (visibleCandidates.length > 0 &&
            rows.length === 0 &&
            !sectionIsExplicitlyEmpty(key)) {
          return { failure: "malformedCredits" };
        }
        if (rows.length > maximumCount) return { failure: "malformedCredits" };
        for (const row of rows) {
          const text = normalizedText(row.textContent);
          const pair = text.match(pairPattern);
          if (!pair) return { failure: "malformedCredits" };
          const used = canonical(pair[1]);
          const total = canonical(pair[2]);
          if (used === null || total === null) {
            return { failure: "malformedCredits" };
          }
          const remainingNode = row.querySelector(
            ".plans-usage__quota-remain, [data-remaining-credits]"
          );
          const remainingMatches = remainingNode
            ? (normalizedText(remainingNode.textContent).match(numberToken) || [])
            : [];
          if (remainingMatches.length > 1) {
            return { failure: "ambiguousCredits" };
          }
          const displayedRemaining = remainingMatches.length === 1
            ? canonical(remainingMatches[0])
            : null;
          if (remainingMatches.length === 1 && displayedRemaining === null) {
            return { failure: "malformedCredits" };
          }
          const kind = kindForText(text);
          if (!kind) return { failure: "ambiguousCredits" };
          const poolDates = dates(text);
          const disabledByMetadata = hasDisabledMetadata(
            row,
            sections[key]
          );
          output.push({
            stablePageID: stablePageID(row),
            kind,
            used,
            total,
            displayedRemaining,
            effectiveAtMilliseconds: poolDates.effectiveAtMilliseconds,
            expiresAtMilliseconds: poolDates.expiresAtMilliseconds,
            pageStatus: disabledByMetadata
              ? "unavailable"
              : status(text, used, total)
          });
        }
        return { rows: output };
      };

      const subscription = extractRows(
        "subscription",
        subscriptionKind,
        16
      );
      const addOn = extractRows("addOn", () => "addOn", 32);
      const benefitGift = extractRows(
        "benefitGift",
        () => "benefitGift",
        64
      );
      const extractionFailure = [subscription, addOn, benefitGift]
        .find((result) => result.failure);
      if (extractionFailure) return fail(extractionFailure.failure);
      if (subscription.rows.length === 0) {
        return fail("incompletePoolSections");
      }
      if ((addOn.rows.length === 0 && !sectionIsExplicitlyEmpty("addOn")) ||
          (benefitGift.rows.length === 0 &&
            !sectionIsExplicitlyEmpty("benefitGift"))) {
        return fail("incompletePoolSections", safeDiagnosticCode());
      }

      const accountBalancePattern =
        /积分余额|当前可用总积分|可用积分|credits?\s+balance|available\s+credits?/i;
      const accountBalanceSelector =
        "[data-account-balance], [data-credit-balance], .credit-balance, " +
        ".credits-balance, .plans-usage__balance, .balance-item";
      const isAccountBalanceNode = (node) => {
        if (!accountBalancePattern.test(normalizedText(node.textContent))) {
          return false;
        }
        return !Object.values(sections).some((section) => section.contains(node));
      };
      const accountBalanceNodes = Array.from(
        root.querySelectorAll(accountBalanceSelector)
      ).filter(isAccountBalanceNode);
      const authoritativePageBalances = [];
      for (const node of accountBalanceNodes) {
        const matches = normalizedText(node.textContent).match(numberToken) || [];
        if (matches.length !== 1) return fail("ambiguousAccountBalance");
        const value = canonical(matches[0]);
        if (value === null) return fail("malformedCredits");
        authoritativePageBalances.push(value);
      }
      if (new Set(authoritativePageBalances).size !== authoritativePageBalances.length) {
        return fail("ambiguousAccountBalance");
      }
      // Reconcile visible eligible packages against the official section summaries.
      // A truncated list is unavailable; never click purchase, redeem or View All controls.
      const sectionSummaries = [];
      for (const key of ["addOn", "benefitGift"]) {
        const nodes = sections[key].querySelectorAll(".plans-usage__view-all-summary");
        if (nodes.length !== 1) return fail("incompletePoolSections");
        const match = normalizedText(nodes[0].textContent).match(
          /可用\s*(\d+)\s*个\s*[·•・]?\s*剩余\s*((?:[\d,，]+)(?:\.\d{1,2})?)\s*积分/
        );
        const count = match ? Number(match[1]) : NaN;
        const remaining = match ? canonical(match[2]) : null;
        if (!Number.isSafeInteger(count) || count < 0 || remaining === null) return fail("incompletePoolSections");
        sectionSummaries.push({ section: key, count, remaining });
      }
      if (location.origin !== "https://www.workbuddy.cn" ||
          location.pathname !== "/profile/plans-usage" ||
          location.search !== "" ||
          location.hash !== "") {
        return fail("unexpectedPage");
      }
      return {
        extractorVersion: VERSION,
        discoveredSections: ["subscription", "addOn", "benefitGift"],
        subscriptionPools: subscription.rows,
        addOnPools: addOn.rows,
        benefitGiftPools: benefitGift.rows,
        authoritativePageBalances,
        sectionSummaries
      };
    })();
