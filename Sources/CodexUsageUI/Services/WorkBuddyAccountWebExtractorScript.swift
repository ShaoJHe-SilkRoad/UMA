import Foundation

enum WorkBuddyAccountWebExtractorScript {
    static let source = #"""
    (() => {
      "use strict";
      const fail = (reason) => ({ extractorVersion: 1, failure: reason, rows: [] });
      if (location.origin !== "https://www.workbuddy.cn" ||
          location.pathname !== "/profile/plans-usage" ||
          location.search !== "" ||
          location.hash !== "") {
        return fail("unexpectedPage");
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

      const canonical = (raw) => {
        const normalized = String(raw || "")
          .replace(/[\s,\uFF0C]/g, "")
          .replace(/credits?|积分/ig, "");
        if (!/^(?:0|[1-9]\d*)(?:\.\d+)?$/.test(normalized)) return null;
        const pieces = normalized.split(".");
        if (pieces.length === 2) {
          pieces[1] = pieces[1].replace(/0+$/, "");
          if (!pieces[1]) return pieces[0];
        }
        return pieces.join(".");
      };
      const numberToken = /(?:[1-9]\d{0,2}(?:[,\uFF0C]\d{3})+|(?:0|[1-9]\d*))(?:\.\d+)?/g;
      const rows = [];
      for (const row of root.querySelectorAll(".plans-usage__quota-row")) {
        const remainingNode = row.querySelector(".plans-usage__quota-remain");
        const remainingMatches = (remainingNode?.textContent || "").match(numberToken) || [];
        if (remainingMatches.length !== 1) return fail("ambiguousCredits");
        const remaining = canonical(remainingMatches[0]);
        if (remaining === null) return fail("malformedCredits");

        const boundedText = Array.from(row.children)
          .filter((node) => !node.classList.contains("plans-usage__quota-remain"))
          .map((node) => node.textContent || "")
          .join(" ");
        const pair = boundedText.match(
          /((?:[1-9]\d{0,2}(?:[,\uFF0C]\d{3})+|(?:0|[1-9]\d*))(?:\.\d+)?)\s*\/\s*((?:[1-9]\d{0,2}(?:[,\uFF0C]\d{3})+|(?:0|[1-9]\d*))(?:\.\d+)?)/
        );
        const used = pair ? canonical(pair[1]) : null;
        const total = pair ? canonical(pair[2]) : null;
        if ((pair && (used === null || total === null)) || rows.length >= 8) {
          return fail("malformedCredits");
        }
        rows.push({ remaining, used, total });
      }
      if (rows.length === 0) return fail("malformedCredits");
      return { extractorVersion: 1, rows };
    })();
    """#
}
