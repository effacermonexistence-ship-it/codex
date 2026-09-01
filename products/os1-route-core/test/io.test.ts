import { describe, expect, it } from "vitest";
import { readBoundedJson } from "../src/io";

describe("bounded JSON ingress", () => {
  it("rejects chunked bodies that exceed the limit without Content-Length", async () => {
    const stream = new ReadableStream<Uint8Array>({
      start(controller) {
        controller.enqueue(new TextEncoder().encode('{"task":"'));
        controller.enqueue(new TextEncoder().encode("x".repeat(128)));
        controller.enqueue(new TextEncoder().encode('"}'));
        controller.close();
      },
    });
    const request = new Request("https://route.invalid/v1/executions", {
      method: "POST",
      body: stream,
      duplex: "half",
    } as RequestInit & { duplex: "half" });
    await expect(readBoundedJson(request, 64)).rejects.toThrow();
  });
});
