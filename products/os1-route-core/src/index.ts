import { opaqueError } from "./egress";
import { RequestRejected } from "./errors";
import { ExecutionState } from "./execution-state";
import {
  registerDevice,
  startExecution,
  submitResult,
  uploadArtifact,
} from "./gateway";
import { releaseRequest } from "./releases";

export { ExecutionState };

async function handleRequest(request: Request, env: Env): Promise<Response> {
  const requestId = crypto.randomUUID();
  try {
    const url = new URL(request.url);
    if (request.method === "GET" && (
      url.pathname === "/install.sh" ||
      url.pathname === "/v1/releases/latest" ||
      url.pathname === "/v1/releases/download"
    )) {
      return await releaseRequest(url, env);
    }
    if (request.method !== "POST") throw new RequestRejected();
    if (url.pathname === "/v1/devices/register") {
      return await registerDevice(request, env);
    }
    if (url.pathname === "/v1/executions") return await startExecution(request, env);
    if (url.pathname === "/v1/artifacts") return await uploadArtifact(request, env);
    if (url.pathname === "/v1/results") return await submitResult(request, env);
    throw new RequestRejected();
  } catch (error) {
    console.error(
      JSON.stringify({
        event: error instanceof RequestRejected ? "request_rejected" : "internal_rejected",
        request_id: requestId,
      }),
    );
    return opaqueError();
  }
}

export default {
  fetch(request: Request, env: Env): Promise<Response> {
    return handleRequest(request, env);
  },
} satisfies ExportedHandler<Env>;
