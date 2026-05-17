import * as http from "http";

export interface ImeStatus {
  ok: boolean;
  currentInputSourceId?: string;
  previousInputSourceId?: string;
  englishInputSourceId?: string;
  mode?: string;
  error?: string;
}

export class KovimClient {
  constructor(private endpoint: string) {}

  private post(path: string): Promise<ImeStatus> {
    return new Promise((resolve) => {
      const url = new URL(this.endpoint + path);
      const options: http.RequestOptions = {
        hostname: url.hostname,
        port: url.port,
        path: url.pathname,
        method: "POST",
        headers: { "Content-Length": 0 },
        timeout: 300,
      };

      const req = http.request(options, (res) => {
        const chunks: Buffer[] = [];
        res.on("data", (chunk: Buffer) => chunks.push(chunk));
        res.on("end", () => {
          try {
            resolve(JSON.parse(Buffer.concat(chunks).toString()) as ImeStatus);
          } catch {
            resolve({ ok: false, error: "Invalid JSON response" });
          }
        });
      });

      req.on("error", (err) => {
        resolve({ ok: false, error: err.message });
      });

      req.on("timeout", () => {
        req.destroy();
        resolve({ ok: false, error: "Request timed out" });
      });

      req.end();
    });
  }

  private get(path: string): Promise<ImeStatus> {
    return new Promise((resolve) => {
      const url = new URL(this.endpoint + path);
      const options: http.RequestOptions = {
        hostname: url.hostname,
        port: url.port,
        path: url.pathname,
        method: "GET",
        timeout: 300,
      };

      const req = http.request(options, (res) => {
        const chunks: Buffer[] = [];
        res.on("data", (chunk: Buffer) => chunks.push(chunk));
        res.on("end", () => {
          try {
            resolve(JSON.parse(Buffer.concat(chunks).toString()) as ImeStatus);
          } catch {
            resolve({ ok: false, error: "Invalid JSON response" });
          }
        });
      });

      req.on("error", (err) => {
        resolve({ ok: false, error: err.message });
      });

      req.on("timeout", () => {
        req.destroy();
        resolve({ ok: false, error: "Request timed out" });
      });

      req.end();
    });
  }

  async modeNormal(): Promise<ImeStatus> {
    return this.post("/mode/normal");
  }

  async modeInsert(): Promise<ImeStatus> {
    return this.post("/mode/insert");
  }

  async current(): Promise<ImeStatus> {
    return this.get("/ime/current");
  }

  async health(): Promise<ImeStatus> {
    return this.get("/health");
  }
}
