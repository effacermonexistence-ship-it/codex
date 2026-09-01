export type ClientArtifactFinding = {
  kind: "symlink" | "forbidden_path" | "forbidden_content" | "high_entropy";
  file: string;
  offset?: number;
  fingerprint?: string;
};

export function loadPolicy(path?: string): Promise<unknown>;
export function scanClientArtifacts(
  targets: string[],
  policy?: unknown,
): Promise<{ filesScanned: number; findings: ClientArtifactFinding[] }>;
