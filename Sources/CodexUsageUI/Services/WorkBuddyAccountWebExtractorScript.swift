import Foundation

enum WorkBuddyAccountWebExtractorScript {
    static let source = #"""
    (() => {
      "use strict";

      const VERSION = 2;
      const empty = () => ({
        extractorVersion: VERSION,
        discoveredSections: [],
        subscriptionPools: [],
        addOnPools: [],
        benefitGiftPools: [],
        authoritativePageBalances: []
      });
      const fail = (reason) => ({ ...empty(), failure: reason });

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
          !/plan\s*(and|&)\s*usage/i.test(titleText)) {
        return fail("unexpectedPage");
      }

      const normalizedText = (value) => String(value || "")
        .replace(/\u00a0/g, " ")
        .replace(/\s+/g, " ")
        .trim();
      const sectionPatterns = {
        subscription: /订阅套餐|订阅资源|基础套餐|subscription|plan\s*credits/i,
        addOn: /加量包|add[\s-]*on/i,
        benefitGift: /权益赠送包|权益包|赠送包|benefit|gift/i
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
      for (const row of Array.from(
        root.querySelectorAll(".plans-usage__quota-row")
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
      if (missingTitleKeys.length > 0) {
        const discoveryTargets = [
          root.firstElementChild,
          root.lastElementChild,
          ...Array.from(
            root.querySelectorAll(".plans-usage__quota-row")
          ).slice(-1)
        ].filter(Boolean);
        const priorStep = Number.isSafeInteger(
          globalThis.__umaWorkBuddySectionDiscoveryStepV3
        )
          ? globalThis.__umaWorkBuddySectionDiscoveryStepV3
          : 0;
        const maximumDiscoverySteps = Math.max(2, discoveryTargets.length * 2);
        if (priorStep < maximumDiscoverySteps) {
          const target = discoveryTargets[
            priorStep % Math.max(1, discoveryTargets.length)
          ] || root;
          target.scrollIntoView({
            block: priorStep % 2 === 0 ? "end" : "start",
            inline: "nearest"
          });
          globalThis.__umaWorkBuddySectionDiscoveryStepV3 = priorStep + 1;
          return fail("pageNotStabilized");
        }
        return fail("incompletePoolSections");
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
        return fail("incompletePoolSections");
      }

      const expandAndCount = (key) => {
        const section = sections[key];
        section.scrollIntoView({ block: "center", inline: "nearest" });
        const controls = Array.from(section.querySelectorAll("button, [role='button']"));
        const viewAll = controls.filter((control) => {
          const label = normalizedText(control.textContent);
          return label === "查看全部" || /^view\s+all$/i.test(label);
        });
        if (viewAll.length > 1) return { failure: "ambiguousCredits" };
        if (viewAll.length === 1 &&
            viewAll[0].getAttribute("data-uma-expanded") !== "true") {
          viewAll[0].setAttribute("data-uma-expanded", "true");
          viewAll[0].click();
          return { expanded: true, count: -1 };
        }
        return {
          expanded: false,
          count: section.querySelectorAll(".plans-usage__quota-row").length
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
      const pairPattern =
        /((?:[1-9]\d{0,2}(?:[,\uFF0C]\d{3})+|(?:0|[1-9]\d*))(?:\.\d{1,2})?)\s*\/\s*((?:[1-9]\d{0,2}(?:[,\uFF0C]\d{3})+|(?:0|[1-9]\d*))(?:\.\d{1,2})?)/;

      const hash = (raw) => {
        let value = 2166136261;
        for (let index = 0; index < raw.length; index += 1) {
          value ^= raw.charCodeAt(index);
          value = Math.imul(value, 16777619);
        }
        return `pool-${(value >>> 0).toString(16).padStart(8, "0")}`;
      };
      const stablePageID = (row) => {
        const raw = [
          row.getAttribute("data-id"),
          row.getAttribute("data-package-id"),
          row.getAttribute("data-resource-id"),
          row.getAttribute("data-quota-id"),
          row.getAttribute("data-benefit-id")
        ].find((value) => value && value.length <= 128);
        return raw ? hash(raw) : null;
      };
      const normalizedDate = (raw, endOfDay) => {
        const match = normalizedText(raw).match(
          /(\d{4})[年\-\/.](\d{1,2})[月\-\/.](\d{1,2})/
        );
        if (!match) return null;
        const year = match[1];
        const month = match[2].padStart(2, "0");
        const day = match[3].padStart(2, "0");
        const clock = endOfDay ? "23:59:59" : "00:00:00";
        const epoch = Date.parse(`${year}-${month}-${day}T${clock}+08:00`);
        return Number.isSafeInteger(epoch) ? epoch : null;
      };
      const dates = (text) => {
        const effective = text.match(
          /(?:生效(?:时间|日期)?|effective(?:\s+from)?|starts?)\s*[:：]?\s*([^\s,，;；]+)/i
        );
        const expiry = text.match(
          /(?:到期(?:时间|日期)?|有效期至|expires?|expiry)\s*[:：]?\s*([^\s,，;；]+)/i
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
        if (/不可用|已失效|invalid|unavailable/i.test(text)) {
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
      const extractRows = (key, kindForText, maximumCount) => {
        const output = [];
        const rows = Array.from(
          sections[key].querySelectorAll(".plans-usage__quota-row")
        );
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
          output.push({
            stablePageID: stablePageID(row),
            kind,
            used,
            total,
            displayedRemaining,
            effectiveAtMilliseconds: poolDates.effectiveAtMilliseconds,
            expiresAtMilliseconds: poolDates.expiresAtMilliseconds,
            pageStatus: status(text, used, total)
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

      const accountBalancePattern =
        /积分余额|当前可用总积分|可用积分|credits?\s+balance|available\s+credits?/i;
      const accountBalanceNodes = Array.from(root.querySelectorAll(
        "[data-account-balance], [data-credit-balance], .credit-balance, " +
        ".credits-balance, .plans-usage__balance, .balance-item"
      )).filter((node) => {
        if (!accountBalancePattern.test(normalizedText(node.textContent))) {
          return false;
        }
        return !Object.values(sections).some((section) => section.contains(node));
      });
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
        authoritativePageBalances
      };
    })();
    """#
}
