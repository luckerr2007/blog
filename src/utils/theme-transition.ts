// 主题切换的圆形揭示（View Transition API）
// 参考 Apple / Material 的做法：从触发点扩散，而不是整页硬切。
// 不支持该 API、或用户要求减少动效时，直接切换，不做降级动画。

type ViewTransitionDocument = Document & {
	startViewTransition?: (callback: () => void) => unknown;
};

const REVEAL_FALLBACK_RADIUS = "150vmax";

/**
 * @param apply   真正修改主题的回调（同步生效）
 * @param origin  触发切换的元素，用来计算扩散圆心；缺省用视口中上方
 */
export function runThemeTransition(
	apply: () => void,
	origin?: Element | null,
): void {
	const reduceMotion = window.matchMedia(
		"(prefers-reduced-motion: reduce)",
	).matches;
	const doc = document as ViewTransitionDocument;

	if (reduceMotion || typeof doc.startViewTransition !== "function") {
		apply();
		return;
	}

	const rect = origin?.getBoundingClientRect();
	const x = rect ? rect.left + rect.width / 2 : window.innerWidth / 2;
	const y = rect ? rect.top + rect.height / 2 : 0;
	const radius = rect
		? Math.hypot(
				Math.max(x, window.innerWidth - x),
				Math.max(y, window.innerHeight - y),
			)
		: 0;

	const root = document.documentElement;
	root.style.setProperty("--theme-x", `${x}px`);
	root.style.setProperty("--theme-y", `${y}px`);
	root.style.setProperty(
		"--theme-r",
		radius > 0 ? `${radius}px` : REVEAL_FALLBACK_RADIUS,
	);

	doc.startViewTransition(apply);
}
