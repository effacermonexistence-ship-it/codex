export class RequestRejected extends Error {
  constructor() {
    super("request rejected");
    this.name = "RequestRejected";
  }
}

export function reject(): never {
  throw new RequestRejected();
}
