import type { PublicResponse, Ticket } from "./contracts";
import { parsePublicResponse } from "./contracts";
import { reject } from "./errors";

const ERROR_PADDING = "0".repeat(160);

function parseDenylist(serialized: string): string[] {
  let value: unknown;
  try {
    value = JSON.parse(serialized);
  } catch {
    reject();
  }
  if (
    !Array.isArray(value) ||
    value.length > 128 ||
    value.some(
      (entry) =>
        typeof entry !== "string" || entry.length < 12 || entry.length > 256,
    )
  ) {
    reject();
  }
  return value;
}

export function assertTicketDeliveryHygiene(
  ticket: Ticket,
  denylistJson: string,
): void {
  const semanticDelivery = [
    ticket.provider,
    ticket.action,
    ticket.permission_profile,
  ].join("\n");
  for (const protectedFragment of parseDenylist(denylistJson)) {
    if (semanticDelivery.includes(protectedFragment)) reject();
  }
}

export function publicJson(value: PublicResponse): Response {
  const validated = parsePublicResponse(value);
  return new Response(JSON.stringify(validated), {
    status: 200,
    headers: {
      "cache-control": "no-store",
      "content-type": "application/json; charset=utf-8",
      "x-content-type-options": "nosniff",
    },
  });
}

export function opaqueError(): Response {
  return new Response(
    JSON.stringify({ error: "request_rejected", pad: ERROR_PADDING }),
    {
      status: 400,
      headers: {
        "cache-control": "no-store",
        "content-type": "application/json; charset=utf-8",
        "x-content-type-options": "nosniff",
      },
    },
  );
}
