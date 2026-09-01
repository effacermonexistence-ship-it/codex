import { describe, expect, it } from "vitest";
import { parseReleaseManifest } from "../src/releases";

const valid = {
  version: "0.1.0",
  object_key: "os1/releases/0.1.0/OS-1-0.1.0.pkg",
  sha256: "a".repeat(64),
  size: 1234,
  minimum_macos: "13.0",
};

describe("release manifest", () => {
  it("accepts the exact public release schema", () => {
    expect(parseReleaseManifest(valid)).toEqual(valid);
  });

  it("rejects path injection and extra fields", () => {
    expect(() => parseReleaseManifest({ ...valid, object_key: "../secret" })).toThrow();
    expect(() => parseReleaseManifest({ ...valid, rationale: "leak" })).toThrow();
  });
});
