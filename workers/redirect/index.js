/**
 * 裸域到 www 的强制跳转。
 *
 * 该 Worker 只绑定 taosu.dpdns.org，不处理站点内容；
 * 所有请求按原路径和查询串 301 到 https://www.taosu.dpdns.org。
 */
export default {
	fetch(request) {
		const url = new URL(request.url);
		url.hostname = "www.taosu.dpdns.org";
		return Response.redirect(url.toString(), 301);
	},
};
