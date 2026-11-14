<script lang="ts">
/**
 * 侧边栏动态组件 - 从 API 获取数据
 * 支持自定义 API 地址，方便接入第三方后端
 */
import I18nKey from "@i18n/i18nKey";
import { i18n } from "@i18n/translation";
import { onMount } from "svelte";
import { formatDynamicDate } from "@/utils/date-utils";
import { fetchWithDedup } from "@/utils/fetch-dedup";
import { fetchMemos } from "@/utils/memos-adapter";
import { url } from "@/utils/url-utils";

interface DynamicEntry {
	id: string;
	published: number;
	html: string;
	images?: Array<{ alt: string; src: string; title?: string }>;
	searchText?: string;
	pinned?: boolean;
}

interface MemosConfig {
	enable: boolean;
	apiUrl: string;
	parent?: string;
}

interface Props {
	apiUrl: string;
	limit: number;
	memos?: MemosConfig;
}

let { apiUrl, limit, memos }: Props = $props();

let entries: DynamicEntry[] = $state([]);
let totalCount = $state(0);
let loading = $state(true);
let error = $state(false);

onMount(async () => {
	try {
		let data: DynamicEntry[];
		if (memos?.enable) {
			data = await fetchMemos(memos.apiUrl, { parent: memos.parent });
		} else {
			data = await fetchWithDedup(apiUrl);
		}

		totalCount = data.length;
		entries = data.slice(0, limit);
		updateCountBadge();
	} catch {
		error = true;
	} finally {
		loading = false;
	}
});

function updateCountBadge() {
	const badge = document.querySelector("[data-dynamic-count]");
	if (badge && totalCount > 0) {
		badge.textContent = `(${totalCount})`;
	}
}

// 从 HTML 中提取纯文本摘要
function getPlainText(html: string): string {
	const div = document.createElement("div");
	div.innerHTML = html;
	return div.textContent?.trim() || "";
}

// 格式化日期
// 本地 API 使用 formatDynamicDate（带时区转换）
// 第三方 API 和 Memos 使用浏览器本地时区，不做额外转换
function formatDate(timestamp: number): string {
	if (apiUrl.startsWith("http") || memos?.enable) {
		return new Date(timestamp).toLocaleDateString("zh-CN", {
			year: "numeric",
			month: "2-digit",
			day: "2-digit",
			hour: "2-digit",
			minute: "2-digit",
		});
	}
	return formatDynamicDate(new Date(timestamp));
}
</script>

<div class="flex flex-col gap-1.5">
	{#if loading}
		<div class="skeleton-list" aria-hidden="true">
			<div class="skeleton-item">
				<div class="skeleton-line skeleton-line--meta"></div>
				<div class="skeleton-line skeleton-line--body"></div>
				<div class="skeleton-line skeleton-line--short"></div>
			</div>
			<div class="skeleton-item">
				<div class="skeleton-line skeleton-line--meta"></div>
				<div class="skeleton-line skeleton-line--body"></div>
				<div class="skeleton-line skeleton-line--short"></div>
			</div>
		</div>
	{:else if error || entries.length === 0}
		<p class="m-0 p-3 text-center text-sm text-neutral-500">
			{i18n(I18nKey.dynamicEmpty)}
		</p>
	{:else}
		{#each entries as entry (entry.id)}
			{@const text = getPlainText(entry.html)}
			{@const hasImage = (entry.images?.length ?? 0) > 0}
			<a
				href={url(`/dynamic/#dynamic-${entry.id}`)}
				class="group flex min-w-0 min-h-16 items-center gap-3 rounded-lg p-2
					text-neutral-700/75 dark:text-neutral-300/75
					hover:bg-(--btn-plain-bg-hover) hover:text-(--primary)
					active:bg-(--btn-plain-bg-active) transition-colors duration-150"
				aria-label={`${i18n(I18nKey.dynamic)}: ${text}`}
			>
				<div class="min-w-0 flex-1">
					<div class="mb-1 flex items-center gap-1 text-xs leading-4 text-(--primary)">
						<svg class="size-4 shrink-0" fill="currentColor" viewBox="0 0 24 24" aria-hidden="true">
							<path d="M11.99 2C6.47 2 2 6.48 2 12s4.47 10 9.99 10C17.52 22 22 17.52 22 12S17.52 2 11.99 2zM12 20c-4.42 0-8-3.58-8-8s3.58-8 8-8 8 3.58 8 8-3.58 8-8 8zm.5-13H11v6l5.25 3.15.75-1.23-4.5-2.67z"/>
						</svg>
						<time datetime={new Date(entry.published).toISOString()}>
							{formatDate(entry.published)}
						</time>
						{#if hasImage || entry.pinned}
							<span class="ml-auto inline-flex items-center gap-1.5">
								{#if hasImage}
									<svg class="size-3.5 shrink-0 text-neutral-500 dark:text-neutral-400" fill="currentColor" viewBox="0 0 24 24" aria-hidden="true">
										<path d="M21 19V5c0-1.1-.9-2-2-2H5c-1.1 0-2 .9-2 2v14c0 1.1.9 2 2 2h14c1.1 0 2-.9 2-2zM8.5 13.5l2.5 3L14.5 12l4.5 6H5z"/>
									</svg>
								{/if}
								{#if entry.pinned}
									<span class="inline-flex items-center gap-0.5 text-[10px] px-1 py-0.5 rounded bg-(--primary)/10 text-(--primary) font-medium">
										<svg class="size-3" fill="currentColor" viewBox="0 0 24 24"><path d="M16 12V4h1V2H7v2h1v8l-2 2v2h5.2v6h1.6v-6H18v-2z"/></svg>
										{i18n(I18nKey.pinned)}
									</span>
								{/if}
							</span>
						{/if}
					</div>
					<p class="m-0 line-clamp-3 text-sm leading-[1.35rem]">
						{text}
					</p>
				</div>
			</a>
		{/each}
	{/if}
</div>

<style>
	.skeleton-list {
		display: flex;
		flex-direction: column;
		gap: 0.5rem;
		padding: 0.25rem 0;
	}

	.skeleton-item {
		display: flex;
		flex-direction: column;
		gap: 0.45rem;
		padding: 0.5rem;
	}

	.skeleton-line {
		height: 0.6rem;
		border-radius: 4px;
		background: linear-gradient(
			90deg,
			var(--c-inset) 0%,
			color-mix(in srgb, var(--c-fg) 8%, var(--c-inset)) 50%,
			var(--c-inset) 100%
		);
		background-size: 200% 100%;
		animation: skeleton-shimmer 1.4s var(--ease-standard) infinite;
	}

	.skeleton-line--meta {
		width: 38%;
		height: 0.5rem;
	}

	.skeleton-line--body {
		width: 92%;
	}

	.skeleton-line--short {
		width: 64%;
	}

	@keyframes skeleton-shimmer {
		from {
			background-position: 180% 0;
		}
		to {
			background-position: -80% 0;
		}
	}

	@media (prefers-reduced-motion: reduce) {
		.skeleton-line {
			animation: none;
		}
	}
</style>
