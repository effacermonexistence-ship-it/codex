import { describe, expect, it } from "vitest";
import { PRIVATE_CORE_PROTOCOL_VERSION } from "../src/gateway";

describe("private route-core protocol", () => {
  it("uses the source-locked RCC v3 contract for start and result decisions", () => {
    expect(PRIVATE_CORE_PROTOCOL_VERSION).toBe(3);
  });
});
