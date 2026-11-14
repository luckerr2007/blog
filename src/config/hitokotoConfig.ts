import type { HitokotoConfig } from "@/types/hitokotoConfig";

// 每日一言配置
// 数据来自「一言」开放接口（https://hitokoto.cn），纯前端请求，不经过本站后端。
// 接口全部失败时回退到下方 fallbacks，按日期轮换，因此构建与访问都不依赖外网。
export const hitokotoConfig: HitokotoConfig = {
	// 总开关
	enable: true,

	// 侧边栏组件标题
	title: "每日一言",

	// 是否在首页顶部展示
	showOnHome: true,

	// 接口地址，按顺序尝试
	// c= 分类：i 诗词 / k 哲学；默认不取 d 文学与 h 影视——前者混有网络小说台词，后者会返回英文台词
	// 想放宽时自行加 &c=d / &c=h；min_length、max_length 限制长度，避免长句把卡片撑破
	apis: [
		"https://v1.hitokoto.cn/?encode=json&charset=utf-8&c=i&c=k&min_length=6&max_length=42",
		"https://international.v1.hitokoto.cn/?encode=json&charset=utf-8&c=i&c=k&min_length=6&max_length=42",
	],

	// 单次请求超时（毫秒）
	timeout: 8000,

	// 自动轮换间隔（小时）：每次在 1–6 小时之间取随机值，避免整点刷新的机械感。
	// 页面一直开着时由定时器自动换；重新打开页面时沿用未过期的缓存。
	rotateMinHours: 1,
	rotateMaxHours: 6,

	// 接口不可用时的兜底句子（按日期轮换）
	fallbacks: [
		{
			text: "怕什么真理无穷，进一寸有一寸的欢喜。",
			fromWho: "胡适",
		},
		{
			text: "路虽远行则将至，事虽难做则必成。",
			from: "荀子·修身",
		},
		{
			text: "纸上得来终觉浅，绝知此事要躬行。",
			fromWho: "陆游",
			from: "冬夜读书示子聿",
		},
		{
			text: "不要把时间浪费在重复造轮子上，但一定要亲手装过一次轮子。",
			fromWho: "桃苏",
		},
		{
			text: "慢慢来，比较快。",
			fromWho: "桃苏",
		},
		{
			text: "学而不思则罔，思而不学则殆。",
			from: "论语·为政",
		},
	],
};
