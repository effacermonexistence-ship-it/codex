import { mkdtemp, rm, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { afterEach, describe, expect, it } from "vitest";
import { scanClientArtifacts } from "../scripts/client-artifact-scan.mjs";

const temporaryDirectories: string[] = [];

afterEach(async () => {
  await Promise.all(
    temporaryDirectories.splice(0).map((path) => rm(path, { recursive: true })),
  );
});

describe("client release artifact hygiene gate", () => {
  it("passes a minimal client artifact", async () => {
    const directory = await mkdtemp(join(tmpdir(), "os1-clean-"));
    temporaryDirectories.push(directory);
    await writeFile(join(directory, "runtime.txt"), "ticket executor only\n");
    const result = await scanClientArtifacts([directory]);
    expect(result.findings).toEqual([]);
  });

  it("reports fingerprints without printing protected content", async () => {
    const directory = await mkdtemp(join(tmpdir(), "os1-leak-"));
    temporaryDirectories.push(directory);
    await writeFile(
      join(directory, "runtime.txt"),
      "accidental private routing prompt material",
    );
    const result = await scanClientArtifacts([directory]);
    expect(result.findings).toHaveLength(1);
    expect(JSON.stringify(result.findings)).not.toContain("private routing prompt");
  });
});
