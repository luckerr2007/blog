---
title: 复现不是重放：签名接口评估的实验台与代码
published: 2026-11-19
updated: 2026-11-19
description: 把一次授权协议评估做成可回归的实验：从样本取证、最小协议模型、手写 protobuf、签名与信封，到本地 mock 网关、权限边界测试、证据脱敏和复测。代码全部指向本地实验环境，目标、接口、密钥与数据均已替换为示例。
tags: [复现, 协议分析, 安全工程, TypeScript]
category: 折腾
---

> 本文代码只用于本地 mock 实验，不指向任何真实服务；示例包名、密钥、token、用户数据均为虚构。复现真实系统前必须取得书面授权，并遵守只读、最小影响和负责任披露的边界。

前两篇分别写了[请求的四层门禁](/posts/misc/2026-11-17-protocol-web-client/)和[一次授权渗透的信任边界](/posts/misc/2026-11-19-pentest-retrospective/)。这一篇补上中间缺的那块：**怎么把一次评估变成可重复的实验。**

一句话版本：**复现的产物不是一份“能打通的脚本”，而是一套可解释、可回归、可交接的实验。**

## 一、复现和重放的区别

很多人把“复现”理解成“把抓到的包再发一次”。这最多叫重放。

| 重放 | 复现 |
| --- | --- |
| 抓到请求再发一次 | 重建最小模型，逐层验证 |
| 依赖线上环境 | 本地 mock + 固定 fixture |
| 成功一次就结束 | 有测试、有证据、有复测 |
| 结果难交接 | 目录、命令、期望结果都写清楚 |

复现至少要有三个产出：

1. **协议模型**：每一层输入什么、输出什么、失败时是什么错误；
2. **测试客户端**：能单独替换每一层，能回放，能断言；
3. **回归与证据**：把发现写成测试，把测试结果写成脱敏报告。

下面用一个本地实验台把这些串起来。真实样本用的是非对称签名、分组加密和 protobuf；为了让实验台可以离线运行，示例改用 HMAC、AES-GCM 和 JSON。**能迁移的是方法，不是密钥和算法参数。**

## 二、实验台目录

```text
lab/
├── fixtures/
│   ├── device.json
│   └── users.json
├── src/
│   ├── protobuf.ts
│   ├── envelope.ts
│   ├── sign.ts
│   ├── client.ts
│   ├── mock-server.ts
│   └── report.ts
├── tests/
│   ├── protocol.test.ts
│   └── authz.test.ts
├── package.json
└── tsconfig.json
```

依赖只需要 Node 20+、TypeScript、tsx 和 Vitest。实验台不访问外网，mock server 只监听 `127.0.0.1`。

```bash
pnpm add -D typescript tsx vitest @types/node

# 终端 A：启动本地 mock 网关
pnpm tsx src/mock-server.ts

# 终端 B：跑协议与权限测试
pnpm vitest run
```

## 三、从样本取证开始

第一步是把公开客户端拆开，而不是直接打接口。常用的命令很朴素：

```bash
unzip -o sample.apk -d build/apk
jadx -d build/jadx --no-res sample.apk
apktool d -f sample.apk -o build/apktool
```

拆完之后，需要记录的不是“所有代码”，而是会影响协议建模的东西：

- 包名、版本号、证书摘要；
- 字符串表、反射注入点、运行时拼接的常量；
- proto 定义和字段编号；
- Retrofit / OkHttp 注解里的接口清单；
- 错误码和参数校验顺序；
- 客户端在什么条件下会换线路、换密钥、换设备码。

这些信息最后落成一个 fixture。fixture 里只放**虚构值**：

```json
{
  "packageName": "com.example.lab",
  "versionCode": 1,
  "certificateSha256": "demo-cert-sha256",
  "notes": "all values are synthetic"
}
```

一个很实用的原则：**凡是不能公开的值，都不要进 git。** 真实密钥、token、账户备份放在加密归档里；仓库里只保留 `*.example` 和测试向量。`git status` 应该永远看不到私钥。

## 四、定义最小协议模型

不要一上来就复刻整个 App。先定义“一个请求”需要哪些字段：

```ts
export interface DeviceProfile {
  certificateSha256: string;
  packageName: string;
  versionCode: number;
}

export interface PublicParams {
  platform: "android";
  osVersion: string;
  appVersion: string;
  packageName: string;
  versionCode: number;
  timestamp: number;
  nonce: string;
  signature: string;
}

export interface ApiResult<T> {
  code: number;
  msg: string;
  data: T;
}
```

把这个模型和真实协议对齐，用一张表记录“哪一层负责什么”：

| 层 | 输入 | 输出 | 失败表现 |
| --- | --- | --- | --- |
| 设备身份 | 证书摘要、包名、版本 | 设备码 | 设备码不匹配 |
| 公共参数 | 平台、版本、时间戳、随机串 | 请求头 | 字段缺失、类型错 |
| 签名 | 规范字符串、私钥 | 签名值 | 验签失败、过期 |
| 信封 | 业务参数、会话密钥 | 二进制密文 | 解密失败、长度错 |

这张表就是后面写测试的骨架。每一行至少要有：一个正常用例、一个缺字段用例、一个类型错误用例。

## 五、手写 protobuf：只写需要的部分

如果协议只用到几个 message，不必引入完整运行时。手写一个最小编解码器，反而更容易在测试里定位问题。

```ts
export function concat(...parts: Uint8Array[]): Uint8Array {
  const total = parts.reduce((sum, part) => sum + part.length, 0);
  const out = new Uint8Array(total);
  let offset = 0;
  for (const part of parts) {
    out.set(part, offset);
    offset += part.length;
  }
  return out;
}

export function encodeVarint(input: number): Uint8Array {
  let value = Math.floor(input);
  if (!Number.isSafeInteger(value) || value < 0) {
    throw new RangeError("varint expects a non-negative safe integer");
  }
  const bytes: number[] = [];
  while (value > 0x7f) {
    bytes.push((value % 128) | 0x80);
    value = Math.floor(value / 128);
  }
  bytes.push(value);
  return Uint8Array.from(bytes);
}

export function decodeVarint(
  bytes: Uint8Array,
  offset = 0,
): { value: number; offset: number } {
  let value = 0;
  let shift = 0;
  let cursor = offset;
  while (cursor < bytes.length) {
    const byte = bytes[cursor++];
    value += (byte & 0x7f) * 2 ** shift;
    if ((byte & 0x80) === 0) return { value, offset: cursor };
    shift += 7;
    if (shift > 49) throw new RangeError("varint is too long");
  }
  throw new RangeError("unexpected end of varint");
}

export function writeTag(field: number, wireType: number): Uint8Array {
  return encodeVarint(field * 8 + wireType);
}

export function writeBytes(field: number, value: Uint8Array): Uint8Array {
  return concat(writeTag(field, 2), encodeVarint(value.length), value);
}

export function writeString(field: number, value: string): Uint8Array {
  return writeBytes(field, Buffer.from(value, "utf8"));
}

export function writeVarintField(field: number, value: number): Uint8Array {
  return concat(writeTag(field, 0), encodeVarint(value));
}

export type ProtoField =
  | { field: number; wireType: 0; value: number }
  | { field: number; wireType: 2; value: Uint8Array };

export function readFields(bytes: Uint8Array): ProtoField[] {
  const fields: ProtoField[] = [];
  let offset = 0;
  while (offset < bytes.length) {
    const tag = decodeVarint(bytes, offset);
    offset = tag.offset;
    const field = Math.floor(tag.value / 8);
    const wireType = tag.value % 8;
    if (wireType === 0) {
      const item = decodeVarint(bytes, offset);
      fields.push({ field, wireType, value: item.value });
      offset = item.offset;
    } else if (wireType === 2) {
      const length = decodeVarint(bytes, offset);
      offset = length.offset;
      const end = offset + length.value;
      if (end > bytes.length) throw new RangeError("truncated field");
      fields.push({ field, wireType, value: bytes.subarray(offset, end) });
      offset = end;
    } else {
      throw new RangeError(`unsupported wire type: ${wireType}`);
    }
  }
  return fields;
}
```

这里有两个容易踩的坑。

**第一，别用 32 位位移处理 13 位毫秒时间戳。** JavaScript 的 `>>` 和 `&` 会把数字截成 32 位有符号整数。上面的代码用 `% 128` 和 `Math.floor`，就是为了避开这个问题。一个回归测试就能把它钉死：

```ts
import { describe, expect, it } from "vitest";
import { decodeVarint, encodeVarint } from "../src/protobuf";

describe("varint", () => {
  it("round-trips a 13-digit millisecond timestamp", () => {
    const value = 1_795_083_000_000;
    const encoded = encodeVarint(value);
    expect(decodeVarint(encoded)).toEqual({ value, offset: encoded.length });
  });

  it("does not use 32-bit shifts", () => {
    const value = 1_795_083_000_000;
    expect(value >> 7).not.toBe(Math.floor(value / 128));
  });
});
```

**第二，字段编号和 wire type 是协议的一部分。** 少一个字段、字段顺序变化、空串和缺省值处理不同，都会让服务端在进入业务逻辑之前就拒绝。测试里不要只断言“能解码”，还要断言每个字段的编号、类型和值。

## 六、设备指纹与密钥派生

设备身份通常不是随机 UUID，而是从稳定信息派生。示例用一个 HMAC 简化：

```ts
import { createHmac } from "node:crypto";

export interface DeviceProfile {
  certificateSha256: string;
  packageName: string;
  versionCode: number;
}

export function deriveDeviceId(profile: DeviceProfile, secret: Buffer): string {
  const material = [
    profile.certificateSha256,
    profile.packageName,
    profile.versionCode,
  ].join("|");
  return createHmac("sha256", secret).update(material).digest("base64url").slice(0, 32);
}
```

真实样本可能用 AES-ECB、双层 Base64、截断和大小写变换。无论算法怎么变，测试策略是一样的：**准备一组已知输入和期望输出，把它当成黑盒锁住。** 只要派生结果变了，测试就会提醒你“设备身份这一层变了”。

还要记住：派生逻辑在客户端，输入也在客户端。它能区分“像不像官方客户端”，不能证明“现在操作的是真人”。

## 七、签名与信封

签名解决的是完整性和来源问题。示例用 HMAC，真实样本可能是 RSA 或 ECDSA；结构不变：

```ts
import { createHmac, timingSafeEqual } from "node:crypto";

export interface CanonicalInput {
  timestamp: number;
  nonce: string;
  bodyHash: string;
}

export function canonicalString(input: CanonicalInput): string {
  return [input.timestamp, input.nonce, input.bodyHash].join("\n");
}

export function sign(secret: Buffer, canonical: string): string {
  return createHmac("sha256", secret).update(canonical).digest("base64url");
}

export function verify(
  secret: Buffer,
  canonical: string,
  signature: string,
): boolean {
  const expected = Buffer.from(sign(secret, canonical));
  const actual = Buffer.from(signature);
  return expected.length === actual.length && timingSafeEqual(expected, actual);
}
```

签名的难点通常不在算法，而在“规范字符串”：

- 字段顺序是否固定；
- 时间戳是秒还是毫秒；
- 空值参与不参与拼接；
- body 的哈希是对原始字节还是对编码后的字符串；
- 换行、空格、大小写是否一致；
- Base64 还是 Base64URL。

这些细节任何一处不一致，服务端都只会回一个模糊的“签名错误”。所以测试里要单独覆盖 canonical string，而不是只测最终签名。

信封示例用 AES-256-GCM，把 IV、认证标签和密文拼在一起：

```ts
import { createCipheriv, createDecipheriv, randomBytes } from "node:crypto";

const ALGORITHM = "aes-256-gcm";
const AAD = Buffer.from("lab-envelope-v1");

export function seal(plaintext: Buffer, key: Buffer): Buffer {
  if (key.length !== 32) throw new Error("AES-256 needs a 32-byte key");
  const iv = randomBytes(12);
  const cipher = createCipheriv(ALGORITHM, key, iv);
  cipher.setAAD(AAD);
  const ciphertext = Buffer.concat([cipher.update(plaintext), cipher.final()]);
  return Buffer.concat([iv, cipher.getAuthTag(), ciphertext]);
}

export function open(sealed: Buffer, key: Buffer): Buffer {
  if (key.length !== 32) throw new Error("AES-256 needs a 32-byte key");
  if (sealed.length < 12 + 16) throw new Error("sealed payload is too short");
  const iv = sealed.subarray(0, 12);
  const tag = sealed.subarray(12, 28);
  const ciphertext = sealed.subarray(28);
  const decipher = createDecipheriv(ALGORITHM, key, iv);
  decipher.setAAD(AAD);
  decipher.setAuthTag(tag);
  return Buffer.concat([decipher.update(ciphertext), decipher.final()]);
}
```

真实样本如果用的是 ECB，最大的问题不是“能不能解”，而是同样的明文块会产生同样的密文块。复现时可以把这一点写成测试：构造两个相同前缀的请求，观察密文是否出现重复块。测试的目的不是教人攻击，而是证明“这个设计没有完整性保护”。

## 八、客户端：把签名和信封串起来

```ts
import { createHash, randomBytes } from "node:crypto";
import { seal } from "./envelope";
import { canonicalString, sign } from "./sign";
import type { ApiResult } from "./types";

export interface ClientOptions {
  baseUrl: string;
  deviceSecret: Buffer;
  envelopeKey: Buffer;
  packageName: string;
  versionCode: number;
  now?: () => number;
  nonce?: string;
  headers?: Record<string, string>;
}

export async function request<T>(
  options: ClientOptions,
  path: string,
  payload: unknown,
): Promise<ApiResult<T>> {
  const timestamp = (options.now ?? Date.now)();
  const nonce = options.nonce ?? randomBytes(16).toString("base64url");
  const sealed = seal(Buffer.from(JSON.stringify(payload), "utf8"), options.envelopeKey);
  const body = JSON.stringify({ sealed: sealed.toString("base64url") });
  const bodyHash = createHash("sha256").update(body).digest("base64url");
  const signature = sign(
    options.deviceSecret,
    canonicalString({ timestamp, nonce, bodyHash }),
  );

  const response = await fetch(new URL(path, options.baseUrl), {
    method: "POST",
    headers: {
      "content-type": "application/json",
      "x-package": options.packageName,
      "x-version": String(options.versionCode),
      "x-timestamp": String(timestamp),
      "x-nonce": nonce,
      "x-signature": signature,
      ...options.headers,
    },
    body,
  });

  const text = await response.text();
  if (!response.ok) {
    throw new Error(`HTTP ${response.status}: ${text.slice(0, 200)}`);
  }
  return JSON.parse(text) as ApiResult<T>;
}
```

注意几个设计点：

- `now` 和 `nonce` 可注入，测试才能稳定复现“过期”和“重放”；
- 签名绑定 body 哈希，而不是只绑定路径；
- 错误信息只截前 200 字符，避免把整段响应写进日志；
- 客户端不保存长期密钥，示例里的 key 只用于本地实验。

## 九、本地 mock 网关

下面这个服务是**故意有漏洞的**，只用来验证测试能不能发现问题。不要把它部署到任何真实环境。

```ts
import { createServer, type IncomingMessage, type ServerResponse } from "node:http";
import { createHash } from "node:crypto";
import { open } from "./envelope";
import { canonicalString, verify } from "./sign";

const DEVICE_SECRET = Buffer.from("lab-device-secret");
const ENVELOPE_KEY = Buffer.alloc(32, 0x42);
const ADMIN_TOKEN = "demo-admin-token";

const USERS = Array.from({ length: 250 }, (_, index) => ({
  id: index + 1,
  username: index === 0 ? "admin" : `user-${index + 1}`,
  token: `demo-token-${index + 1}`,
  passwordHash: `demo-hash-${index + 1}`,
  salt: `demo-salt-${index + 1}`,
}));

const seenNonces = new Map<string, number>();

function consumeNonce(nonce: string): boolean {
  const now = Date.now();
  for (const [key, expiresAt] of seenNonces) {
    if (expiresAt <= now) seenNonces.delete(key);
  }
  if (seenNonces.has(nonce)) return false;
  seenNonces.set(nonce, now + 5 * 60_000);
  return true;
}

async function readBody(request: IncomingMessage): Promise<Buffer> {
  const chunks: Buffer[] = [];
  for await (const chunk of request) chunks.push(Buffer.from(chunk));
  return Buffer.concat(chunks);
}

function send(response: ServerResponse, status: number, body: unknown): void {
  response.writeHead(status, { "content-type": "application/json" });
  response.end(JSON.stringify(body));
}

const server = createServer(async (request, response) => {
  const url = new URL(request.url ?? "/", "http://127.0.0.1");

  if (request.method === "GET" && url.pathname === "/api/config") {
    return send(response, 200, {
      code: 200,
      data: { signingSecret: "demo-signing-secret", adminToken: ADMIN_TOKEN },
    });
  }

  if (request.method === "GET" && url.pathname === "/api/openapi.json") {
    return send(response, 200, {
      openapi: "3.0.1",
      paths: { "/api/admin/users": { get: {} }, "/api/config": { get: {} } },
    });
  }

  if (request.method !== "POST") {
    return send(response, 405, { code: 405, msg: "method not allowed" });
  }

  try {
    const raw = await readBody(request);
    const timestamp = Number(request.headers["x-timestamp"] ?? 0);
    const nonce = String(request.headers["x-nonce"] ?? "");
    const signature = String(request.headers["x-signature"] ?? "");
    const packageName = String(request.headers["x-package"] ?? "");
    const versionCode = Number(request.headers["x-version"] ?? 0);

    if (!timestamp || Math.abs(Date.now() - timestamp) > 5 * 60_000) {
      return send(response, 401, { code: 401, msg: "stale timestamp" });
    }
    if (!nonce || !signature) {
      return send(response, 401, { code: 401, msg: "missing signature" });
    }
    if (packageName !== "com.example.lab" || versionCode !== 1) {
      return send(response, 401, { code: 401, msg: "unknown client" });
    }

    const bodyHash = createHash("sha256").update(raw).digest("base64url");
    if (!verify(DEVICE_SECRET, canonicalString({ timestamp, nonce, bodyHash }), signature)) {
      return send(response, 401, { code: 401, msg: "bad signature" });
    }
    if (!consumeNonce(nonce)) {
      return send(response, 401, { code: 401, msg: "replayed nonce" });
    }

    const body = JSON.parse(raw.toString("utf8")) as { sealed?: string };
    if (!body.sealed) {
      return send(response, 400, { code: 400, msg: "missing sealed body" });
    }
    const payload = JSON.parse(
      open(Buffer.from(body.sealed, "base64url"), ENVELOPE_KEY).toString("utf8"),
    ) as { userId?: number };

    if (url.pathname === "/api/user/profile") {
      const user = USERS.find((item) => item.id === payload.userId);
      return send(response, 200, { code: 200, msg: "ok", data: user ?? null });
    }

    if (url.pathname === "/api/admin/users") {
      if (request.headers["x-admin-token"] !== ADMIN_TOKEN) {
        return send(response, 401, { code: 401, msg: "unauthorized" });
      }
      const limit = Number(url.searchParams.get("limit") ?? 200);
      return send(response, 200, {
        code: 200,
        msg: "ok",
        data: USERS.slice(0, Math.max(limit, 200)),
      });
    }

    return send(response, 404, { code: 404, msg: "not found" });
  } catch {
    return send(response, 400, { code: 400, msg: "bad request" });
  }
});

server.listen(8787, "127.0.0.1");
```

这个 mock 里故意留了四个问题：

1. `/api/user/profile` 只看 `userId`，不检查调用者是谁；
2. `/api/admin/users` 的 `limit` 被 `Math.max(limit, 200)` 兜底，写 2 也返回 200 条；
3. `/api/config` 匿名返回签名密钥和管理员 token；
4. `/api/openapi.json` 匿名返回接口地图，里面包含后台路径。

## 十、把发现写成测试

测试分三类：协议不变量、已知漏洞、暴露面。

```ts
import { describe, expect, it } from "vitest";
import { randomUUID } from "node:crypto";
import { request } from "../src/client";

const options = {
  baseUrl: "http://127.0.0.1:8787",
  deviceSecret: Buffer.from("lab-device-secret"),
  envelopeKey: Buffer.alloc(32, 0x42),
  packageName: "com.example.lab",
  versionCode: 1,
};

describe("gateway invariants", () => {
  it("accepts a fresh signed request", async () => {
    const result = await request<{ id: number; username: string }>(
      options,
      "/api/user/profile",
      { userId: 2 },
    );
    expect(result.code).toBe(200);
    expect(result.data).toMatchObject({ id: 2, username: "user-2" });
  });

  it("rejects a stale timestamp", async () => {
    await expect(
      request(
        { ...options, now: () => Date.now() - 10 * 60_000 },
        "/api/user/profile",
        { userId: 2 },
      ),
    ).rejects.toThrow(/401/);
  });

  it("rejects a replayed nonce", async () => {
    const nonce = randomUUID();
    await request({ ...options, nonce }, "/api/user/profile", { userId: 2 });
    await expect(
      request({ ...options, nonce }, "/api/user/profile", { userId: 2 }),
    ).rejects.toThrow(/401/);
  });
});

describe("known findings", () => {
  it.fails("IDOR: user 2 must not read user 1's credentials", async () => {
    const result = await request<{ token?: string }>(
      options,
      "/api/user/profile",
      { userId: 1 },
    );
    expect(result.data).not.toHaveProperty("token");
  });

  it.fails("pagination: limit=2 must return at most 2 records", async () => {
    const result = await request<unknown[]>(
      { ...options, headers: { "x-admin-token": "demo-admin-token" } },
      "/api/admin/users?limit=2",
      {},
    );
    expect(result.data.length).toBeLessThanOrEqual(2);
  });
});

describe("exposure checks", () => {
  it("documents anonymous config exposure", async () => {
    const response = await fetch(`${options.baseUrl}/api/config`);
    expect(response.status).toBe(200);
    const body = (await response.json()) as {
      data?: { signingSecret?: string };
    };
    expect(body.data?.signingSecret).toBeDefined();
  });

  it("documents anonymous OpenAPI exposure", async () => {
    const response = await fetch(`${options.baseUrl}/api/openapi.json`);
    expect(response.status).toBe(200);
  });
});
```

这里最关键的是 `it.fails`。它的含义不是“这个测试应该失败”，而是“这个测试现在预期会失败”：

- 修复前，IDOR 能读到 token，`expect(...).not.toHaveProperty("token")` 失败，整个用例通过；
- 修复后，IDOR 被拦住，断言通过，`it.fails` 反而失败，提醒你把 `it.fails` 改成普通 `it`。

这样，**漏洞本身也变成了回归测试**。修复不是靠记忆，而是靠测试状态翻转。

## 十一、证据与脱敏

测试跑通之后，下一步不是截图发群，而是把结果写成可交接的证据。

```ts
export type Severity = "critical" | "high" | "medium" | "low" | "info";
export type FindingStatus = "confirmed" | "unverified" | "fixed";

export interface Finding {
  id: string;
  title: string;
  severity: Severity;
  status: FindingStatus;
  precondition: string;
  request: string;
  response: string;
  impact: string;
  remediation: string;
}

export function redact(input: string): string {
  return input
    .replace(
      /("?(?:authorization|token|cookie|password|salt)"?\s*[:=]\s*)(?:"[^"]*"|[^\s,;]+)/gi,
      "$1[REDACTED]",
    )
    .replace(/[A-Za-z0-9+/=_-]{40,}/g, "[REDACTED]");
}

export function toMarkdown(findings: Finding[]): string {
  return findings
    .map((finding) =>
      [
        `## ${finding.id} ${finding.title}`,
        `- 等级：${finding.severity}`,
        `- 状态：${finding.status}`,
        `- 前提：${finding.precondition}`,
        "",
        "```http",
        redact(finding.request),
        "```",
        "",
        "```http",
        redact(finding.response),
        "```",
        "",
        `影响：${finding.impact}`,
        "",
        `修复：${finding.remediation}`,
      ].join("\n"),
    )
    .join("\n\n");
}
```

脱敏不是“把 token 换成星号”这么简单。至少要做四层：

1. **传输层**：只保留方法、路径、状态码和必要的头，Cookie、Authorization、代理头全部删掉；
2. **字段层**：token、口令散列、盐、邮箱、手机号、IP 做替换或哈希；
3. **样本层**：只保留能证明问题的最小记录，不下载全量数据；
4. **发布层**：公开文章再脱敏一次，去掉目标、接口、密钥和可复现步骤。

证据文件也要分级：原始字节放加密归档，报告正文只放脱敏后的片段，公开复盘只讲模式和教训。

## 十二、复测与回归

修复之后，测试应该发生“状态翻转”。可以维护一张很简单的矩阵：

| 测试 | 修复前 | 修复后 |
| --- | --- | --- |
| 签名缺失 | 401 | 401 |
| 时间戳过期 | 401 | 401 |
| nonce 重放 | 401 | 401 |
| IDOR | `it.fails` 通过 | 普通测试通过 |
| `limit=2` | 返回 200 条 | 返回 2 条 |
| 匿名配置 | 200 + 密钥 | 401 / 403 |
| 匿名 OpenAPI | 200 | 404 / 401 |

复测时不要只看代码 diff。要用同一套请求重新打一遍，确认状态码、响应字段和业务行为都变了。对于“删除调试接口”这种修复，还要确认生产构建里真的没有路由，而不是只在前端隐藏了入口。

CI 里只需要一条命令：

```bash
pnpm test
```

实验台不访问外网，mock server 只绑定回环地址，所以这条命令可以在任何机器上重复执行。

## 十三、迁移到真实协议

示例用的是 HMAC + AES-GCM，真实样本可能是 RSA/ECDSA + 分组加密 + protobuf。要迁移，不要把算法写死在客户端里，抽一层 `CryptoSuite`：

```ts
export interface CryptoSuite {
  sign(canonical: string): string;
  verify(canonical: string, signature: string): boolean;
  seal(plaintext: Buffer): Buffer;
  open(sealed: Buffer): Buffer;
}
```

然后把差异记在表里：

| 层 | 本文 demo | 真实样本（抽象） |
| --- | --- | --- |
| 设备身份 | HMAC 派生 | 证书摘要 + 包名 + 版本派生 |
| 签名 | HMAC-SHA256 | 非对称签名 + 对称校验片段 |
| 信封 | AES-256-GCM | 分组加密 + protobuf 字段拆分 |
| 响应 | JSON 信封 | protobuf 信封，data 可能是明文 / 密文 / 空 |
| 目标 | 本地 mock | 授权测试环境 |

能迁移的是：规范字符串、时间窗、nonce、body 绑定、错误分类、测试结构、证据格式。

不能迁移的是：真实密钥、真实接口、真实用户数据。**示例密钥不是秘密，也永远不要拿示例代码去指真实目标。**

## 十四、常见坑

最后列一份“复现时最容易浪费时间的清单”：

| 现象 | 常见原因 | 处理 |
| --- | --- | --- |
| 签名总是失败 | 字段顺序 / 换行 / 大小写不一致 | 打印 canonical string，逐字节对比 |
| 时间戳总是过期 | 秒和毫秒混用 | 统一用毫秒，测试里注入 `now` |
| Base64 解不开 | Base64 与 Base64URL 混用 | 明确编码，统一用 URL-safe |
| 解密长度错 | IV / tag / 密文拼接顺序不一致 | 固定格式，写解析测试 |
| AES key 长度错 | 把 hex 字符串当字节 | `Buffer.from(hex, "hex")`，断言 32 字节 |
| RSA 私钥加载失败 | PKCS#1 与 PKCS#8 混淆 | 用 `openssl pkey` 转换并锁定测试 |
| 明文响应被当密文解 | 响应类型不固定 | 先看内容特征，再决定是否解密 |
| 参数被编码两次 | URL 编码与表单编码叠加 | 在客户端和网关各打一条原始日志 |
| 测试数据进了 git | fixture 用了真实值 | `.gitignore` + 提交前扫描 |
| mock 监听了所有网卡 | `listen(port)` 默认绑定 | 显式写 `127.0.0.1` |

这些坑看起来琐碎，但它们决定了复现是“一次成功”还是“可以重复成功”。

## 十五、结语

复现的终点不是“我也能打通”，而是“换一个人、换一台机器，也能得到同样的结论”。

一套好的复现至少包含：

- 一个最小协议模型；
- 一个可替换、可回放的测试客户端；
- 一组会随修复翻转的测试；
- 一份脱敏、可交接的证据；
- 一条清晰的授权和停止边界。

做到这些，渗透测试才不只是“当时很刺激”，而是留下了可以维护的知识。

**复现不是重放，而是把一次性的发现，变成可验证的工程。**
