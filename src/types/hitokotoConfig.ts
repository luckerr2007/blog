// 每日一言（Hitokoto / 一言）配置类型定义

// 一条名言
export type HitokotoQuote = {
	// 句子正文
	text: string;
	// 出处（作品名 / 来源）
	from?: string;
	// 作者
	fromWho?: string;
};

export type HitokotoConfig = {
	// 总开关，false 时首页与侧边栏都不渲染
	enable: boolean;
	// 侧边栏组件标题
	title: string;
	// 是否在首页顶部展示
	showOnHome: boolean;
	// 接口地址列表，按顺序尝试，任一成功即停止
	apis: string[];
	// 单次请求超时（毫秒）
	timeout: number;
	// 自动轮换的最短间隔（小时）
	rotateMinHours: number;
	// 自动轮换的最长间隔（小时）
	rotateMaxHours: number;
	// 接口全部失败时使用的本地句子，按日期轮换，保证内容永远可读
	fallbacks: HitokotoQuote[];
};
