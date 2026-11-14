import type { HitokotoQuote } from "@/types/hitokotoConfig";

// 每日一言的浏览器端取数与轮换逻辑
// 由 components/common/HitokotoQuote.astro 的客户端脚本调用，因此这里不能引用任何
// 只能跑在服务端的模块（astro:content、fs 等）。

export interface HitokotoRuntimeConfig {
	apis: string[];
	timeout: number;
	rotateMinHours: number;
	rotateMaxHours: number;
	fallbacks: HitokotoQuote[];
}

interface HitokotoCacheEntry {
	quote: HitokotoQuote;
	// 写入时间戳（毫秒）
	at: number;
	// 该条句子的到期时间戳（毫秒），到期后自动换下一句
	expiresAt: number;
}

// 缓存键带版本号，方便以后调整结构时自然失效
const CACHE_KEY = "hitokoto:quote:v1";
const DAY_MS = 24 * 60 * 60 * 1000;
const HOUR_MS = 60 * 60 * 1000;
const MIN_TTL_MS = 60 * 1000;

// 按日期轮换兜底句子：同一天内 SSR 与客户端结果一致，避免内容跳动
export function getDailyFallback(
	config: HitokotoRuntimeConfig,
	now: number = Date.now(),
): HitokotoQuote | null {
	if (config.fallbacks.length === 0) return null;
	const dayIndex = Math.floor(now / DAY_MS);
	const index =
		((dayIndex % config.fallbacks.length) + config.fallbacks.length) %
		config.fallbacks.length;
	return config.fallbacks[index];
}

// 出处文本，形如：—— 晏几道《临江仙·梦后楼台高锁》
export function getQuoteSourceLabel(quote: HitokotoQuote): string {
	const author = quote.fromWho?.trim();
	const from = quote.from?.trim();
	if (!author && !from) return "";
	if (author && from && author !== from) return `—— ${author}《${from}》`;
	return `—— ${author || from}`;
}

// 每轮在 [rotateMinHours, rotateMaxHours] 之间取一个随机时长，
// 避免「整点准时换」的机械感，也避免多个访客同时打接口
export function randomRotateTtlMs(config: HitokotoRuntimeConfig): number {
	const lower = Math.max(
		0,
		Math.min(config.rotateMinHours, config.rotateMaxHours),
	);
	const upper = Math.max(config.rotateMinHours, config.rotateMaxHours);
	const hours = lower + Math.random() * (upper - lower);
	return Math.max(MIN_TTL_MS, Math.round(hours * HOUR_MS));
}

function getStorage(): Storage | null {
	try {
		if (typeof window === "undefined" || !window.localStorage) return null;
		return window.localStorage;
	} catch {
		// 隐私模式下访问 localStorage 会抛异常
		return null;
	}
}

function readEntry(): HitokotoCacheEntry | null {
	const storage = getStorage();
	if (!storage) return null;
	try {
		const raw = storage.getItem(CACHE_KEY);
		if (!raw) return null;
		const entry = JSON.parse(raw) as HitokotoCacheEntry;
		if (!entry?.quote?.text || !entry.expiresAt) return null;
		return entry;
	} catch {
		return null;
	}
}

function writeEntry(quote: HitokotoQuote, ttlMs: number): void {
	const storage = getStorage();
	if (!storage) return;
	try {
		const now = Date.now();
		const entry: HitokotoCacheEntry = {
			quote,
			at: now,
			expiresAt: now + ttlMs,
		};
		storage.setItem(CACHE_KEY, JSON.stringify(entry));
	} catch {
		// 存储配额满或被禁用，忽略即可，不影响展示
	}
}

// 当前这条句子还剩多久到期（毫秒）；0 表示没有缓存或已过期
export function getCacheRemainingMs(): number {
	const entry = readEntry();
	if (!entry) return 0;
	return Math.max(0, entry.expiresAt - Date.now());
}

// 读取当前未过期的缓存句子（Swup 换页后把同一句补到新 DOM 上）
export function readCachedQuote(): HitokotoQuote | null {
	const entry = readEntry();
	if (!entry) return null;
	return entry.expiresAt > Date.now() ? entry.quote : null;
}

async function requestOnce(
	url: string,
	timeout: number,
): Promise<HitokotoQuote | null> {
	if (typeof fetch !== "function") return null;
	// 一言的 CDN 会按完整 URL 缓存，短时间内重复请求同一 URL 会拿到同一句；
	// 加一个随机参数让每次轮换都真正换（接口会忽略未知参数）
	let requestUrl = url;
	try {
		const parsed = new URL(url);
		parsed.searchParams.set("_r", String(Date.now()));
		requestUrl = parsed.toString();
	} catch {
		requestUrl = url;
	}
	const controller = new AbortController();
	const timer = setTimeout(() => controller.abort(), timeout);
	try {
		const response = await fetch(requestUrl, {
			signal: controller.signal,
			cache: "no-store",
			credentials: "omit",
			referrerPolicy: "no-referrer",
		});
		if (!response.ok) return null;
		const data: unknown = await response.json();
		if (!data || typeof data !== "object") return null;
		const record = data as Record<string, unknown>;
		const text =
			typeof record.hitokoto === "string" ? record.hitokoto.trim() : "";
		if (!text) return null;
		return {
			text,
			from: typeof record.from === "string" ? record.from.trim() : undefined,
			fromWho:
				typeof record.from_who === "string"
					? record.from_who.trim()
					: undefined,
		};
	} catch {
		// 超时、断网、CORS 失败都走下一个接口或兜底
		return null;
	} finally {
		clearTimeout(timer);
	}
}

// 取一条句子：缓存未过期就直接用，否则依次请求接口；全部失败时回退到本地兜底。
// force 为 true 时跳过缓存（自动轮换到点）。
// 兜底句子不写缓存：避免一次网络故障把「本地句子」钉住几个小时。
export async function loadQuote(
	config: HitokotoRuntimeConfig,
	options: { force?: boolean } = {},
): Promise<HitokotoQuote | null> {
	if (!options.force) {
		const entry = readEntry();
		if (entry && entry.expiresAt > Date.now()) return entry.quote;
	}

	for (const api of config.apis) {
		const quote = await requestOnce(api, config.timeout);
		if (quote) {
			writeEntry(quote, randomRotateTtlMs(config));
			return quote;
		}
	}

	return getDailyFallback(config);
}
