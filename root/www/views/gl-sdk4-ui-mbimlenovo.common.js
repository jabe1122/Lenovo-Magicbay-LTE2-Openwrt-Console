var api = "/cgi-bin/mbim-lenovo-api";

function kv(text) {
	var out = {};
	(text || "").split(/\r?\n/).forEach(function(line) {
		var i = line.indexOf("=");
		if (i > 0) out[line.slice(0, i)] = line.slice(i + 1);
	});
	return out;
}

function bytes(n) {
	n = parseInt(n || "0", 10);
	if (n >= 1073741824) return (n / 1073741824).toFixed(2) + " GB";
	if (n >= 1048576) return (n / 1048576).toFixed(1) + " MB";
	if (n >= 1024) return (n / 1024).toFixed(1) + " KB";
	return n + " B";
}

function hist(value) {
	var samples = [];
	(value || "").split(";").forEach(function(item) {
		var p = item.split(",");
		var s;
		if (p.length !== 3) return;
		s = { t: +p[0], rx: +p[1], tx: +p[2] };
		if (!isNaN(s.t) && !isNaN(s.rx) && !isNaN(s.tx)) samples.push(s);
	});
	return samples;
}

function timeText(t) {
	return new Date(t * 1000).toLocaleTimeString();
}

function pad2(n) {
	return n < 10 ? "0" + n : String(n);
}

function hourText(t) {
	var d = new Date(t * 1000);
	return (d.getMonth() + 1) + "/" + d.getDate() + " " + pad2(d.getHours()) + ":00";
}

function hourRangeText(t) {
	var next = t + 3600;
	var a = new Date(t * 1000);
	var b = new Date(next * 1000);
	if (a.getDate() === b.getDate() && a.getMonth() === b.getMonth())
		return hourText(t) + "-" + pad2(b.getHours()) + ":00";
	return hourText(t) + "-" + hourText(next);
}

function hourlyBars(samples) {
	var map = {};
	var first = null;
	var last = null;
	var bars = [];
	var i;

	for (i = 1; i < samples.length; i++) {
		var hour = Math.floor(samples[i].t / 3600) * 3600;
		var rx = Math.max(0, samples[i].rx - samples[i - 1].rx);
		var tx = Math.max(0, samples[i].tx - samples[i - 1].tx);

		if (first === null) first = hour;
		last = hour;
		if (!map[hour]) map[hour] = { t: hour, rx: 0, tx: 0 };
		map[hour].rx += rx;
		map[hour].tx += tx;
	}

	if (first === null) return bars;

	for (i = first; i <= last; i += 3600)
		bars.push(map[i] || { t: i, rx: 0, tx: 0 });

	return bars;
}

var tpl = [
	"<style>",
	".mbim-console{color:#172033;font-size:15px}.mbim-console *{box-sizing:border-box}.mbim-top{display:flex;align-items:flex-start;justify-content:space-between;gap:14px;margin-bottom:14px}.mbim-title{font-size:24px;font-weight:750;line-height:1.2;margin:0 0 4px}.mbim-sub{color:#667085;font-size:13px}.mbim-actions{display:flex;flex-wrap:wrap;gap:8px;justify-content:flex-end}.mbim-actions button{border:1px solid #d9dee8;background:#fff;color:#172033;border-radius:7px;padding:8px 13px;font-weight:650;cursor:pointer}.mbim-actions button.primary{background:#155eef;border-color:#155eef;color:#fff}.mbim-actions button.danger{color:#b42318}.mbim-actions button:disabled{opacity:.55;cursor:wait}.mbim-banner{border:1px solid #d9dee8;border-radius:8px;background:#fff;padding:10px 12px;margin-bottom:12px;display:flex;align-items:center;justify-content:space-between;gap:10px}.mbim-pill{display:inline-block;border-radius:999px;padding:3px 9px;font-size:12px;font-weight:700;background:#eef2f6;color:#344054}.mbim-pill.ok{background:#dcfae6;color:#087443}.mbim-pill.warn{background:#fffaeb;color:#b54708}.mbim-pill.bad{background:#fef3f2;color:#b42318}.mbim-grid{display:grid;grid-template-columns:repeat(auto-fit,minmax(190px,1fr));gap:10px}.mbim-card{border:1px solid #d9dee8;border-radius:8px;background:#fff;padding:11px 12px;min-height:76px}.mbim-label{color:#667085;font-size:12px;margin-bottom:6px}.mbim-value{font-size:18px;font-weight:750;overflow-wrap:anywhere}.ok{color:#087443}.warn{color:#b54708}.bad{color:#b42318}.mbim-section{margin-top:12px;border:1px solid #d9dee8;border-radius:8px;background:#fff;padding:12px}.mbim-section h2{font-size:15px;margin:0 0 8px}.mbim-chart-box{position:relative;height:260px;padding-left:58px;padding-bottom:34px}.mbim-y-axis{position:absolute;left:0;top:6px;bottom:34px;width:52px;color:#667085;font-size:11px}.mbim-y-axis span{position:absolute;right:6px;transform:translateY(50%);white-space:nowrap}.mbim-y-axis .top{top:0}.mbim-y-axis .mid{top:50%}.mbim-y-axis .bottom{bottom:0}.mbim-y-label{position:absolute;left:0;top:0;color:#667085;font-size:12px}.mbim-plot{position:absolute;left:58px;right:0;top:6px;bottom:34px;border-left:1px solid #d9dee8;border-bottom:1px solid #d9dee8;background:linear-gradient(to bottom,#eef2f6 1px,transparent 1px) 0 0/100% 50%;overflow:hidden}.mbim-bars{height:100%;display:flex;align-items:flex-end;gap:4px;padding:0 6px}.mbim-pair{flex:1 1 8px;min-width:6px;height:100%;display:flex;align-items:flex-end;gap:1px;cursor:crosshair}.mbim-bar{flex:1 1 0;min-height:1px;border-radius:3px 3px 0 0}.mbim-rx{background:#155eef}.mbim-tx{background:#f79009}.mbim-x-axis{position:absolute;left:58px;right:0;bottom:0;height:28px;color:#667085;font-size:11px;display:flex;align-items:flex-start;justify-content:space-between;padding-top:6px}.mbim-axis-title{position:absolute;right:0;bottom:14px;color:#667085;font-size:12px}.mbim-tip{position:absolute;z-index:4;display:none;max-width:240px;background:#172033;color:#fff;border-radius:7px;padding:7px 9px;font-size:12px;line-height:1.5;box-shadow:0 8px 24px rgba(16,24,40,.18);pointer-events:none;white-space:pre-line}.mbim-note{color:#667085;font-size:12px;margin-top:8px}.mbim-dot{display:inline-block;width:10px;height:10px;border-radius:2px;margin-right:4px;vertical-align:-1px}.mbim-console pre{margin:0;white-space:pre-wrap;overflow:auto;overflow-wrap:anywhere;font-family:ui-monospace,SFMono-Regular,Consolas,monospace;font-size:12px;line-height:1.45}.mbim-log{background:#101828;color:#f2f4f7;border-radius:7px;padding:10px;min-height:220px}@media(max-width:680px){.mbim-top{display:block}.mbim-actions{justify-content:flex-start;margin-top:12px}.mbim-actions button{flex:1 1 auto}.mbim-chart-box{height:240px;padding-left:50px}.mbim-plot{left:50px}.mbim-x-axis{left:50px}.mbim-axis-title{display:none}}",
	"</style>",
	"<div class=\"mbim-console\"><div class=\"mbim-top\"><div><div class=\"mbim-title\">Lenovo MagicBay LTE2控制台</div><div class=\"mbim-sub\">ASR1803 MBIM，系统接口 modem_1_1，数据网卡 wwan0</div></div><div class=\"mbim-actions\"><button class=\"primary\" data-action=\"start\">启动</button><button class=\"danger\" data-action=\"stop\">停止</button><button data-action=\"restart\">重启拨号</button><button data-action=\"status\">刷新</button></div></div><div class=\"mbim-banner\"><div id=\"mbim-message\">正在读取状态...</div><span id=\"mbim-pill\" class=\"mbim-pill\">未知</span></div><div class=\"mbim-grid\"><div class=\"mbim-card\"><div class=\"mbim-label\">互联网</div><div id=\"internet\" class=\"mbim-value\">-</div></div><div class=\"mbim-card\"><div class=\"mbim-label\">连接</div><div id=\"running\" class=\"mbim-value\">-</div></div><div class=\"mbim-card\"><div class=\"mbim-label\">OpenWrt接口</div><div id=\"netifd\" class=\"mbim-value\">-</div></div><div class=\"mbim-card\"><div class=\"mbim-label\">模块</div><div id=\"module\" class=\"mbim-value\">-</div></div><div class=\"mbim-card\"><div class=\"mbim-label\">运营商</div><div id=\"provider\" class=\"mbim-value\">-</div></div><div class=\"mbim-card\"><div class=\"mbim-label\">信号 RSSI</div><div id=\"rssi\" class=\"mbim-value\">-</div></div><div class=\"mbim-card\"><div class=\"mbim-label\">IPv4</div><div id=\"ipv4\" class=\"mbim-value\">-</div></div><div class=\"mbim-card\"><div class=\"mbim-label\">IPv6</div><div id=\"ipv6\" class=\"mbim-value\">-</div></div><div class=\"mbim-card\"><div class=\"mbim-label\">网关</div><div id=\"gateway\" class=\"mbim-value\">-</div></div><div class=\"mbim-card\"><div class=\"mbim-label\">DNS</div><div id=\"dns\" class=\"mbim-value\">-</div></div><div class=\"mbim-card\"><div class=\"mbim-label\">流量</div><div id=\"traffic\" class=\"mbim-value\">-</div></div><div class=\"mbim-card\"><div class=\"mbim-label\">开机自启</div><div id=\"enabled\" class=\"mbim-value\">-</div></div><div class=\"mbim-card\"><div class=\"mbim-label\">注册/数据</div><div id=\"packet\" class=\"mbim-value\">-</div></div></div><div class=\"mbim-section\"><h2>流量统计</h2><div class=\"mbim-chart-box\"><div id=\"mbim-y\" class=\"mbim-y-axis\"><span class=\"top\">-</span><span class=\"mid\">-</span><span class=\"bottom\">0 B</span></div><div id=\"mbim-plot\" class=\"mbim-plot\"><div id=\"mbim-bars\" class=\"mbim-bars\"></div><div id=\"mbim-tip\" class=\"mbim-tip\"></div></div><div id=\"mbim-x\" class=\"mbim-x-axis\"></div><div class=\"mbim-axis-title\">时间</div></div><div id=\"mbim-summary\" class=\"mbim-note\">-</div><div class=\"mbim-note\"><span class=\"mbim-dot mbim-rx\"></span>下行流量&nbsp;&nbsp;<span class=\"mbim-dot mbim-tx\"></span>上行流量</div></div><div class=\"mbim-section\"><h2>默认路由</h2><pre id=\"route\">-</pre></div><div class=\"mbim-section\"><h2>最近日志（每行后为注释）</h2><pre id=\"log\" class=\"mbim-log\">-</pre></div></div>"
].join("");

module.exports = {
	name: "mbimlenovo",
	data: function() {
		return { timer: null, busy: false };
	},
	render: function(h) {
		return h("div", { ref: "root" });
	},
	mounted: function() {
		var self = this;
		this.$refs.root.innerHTML = tpl;
		Array.prototype.forEach.call(this.$refs.root.querySelectorAll("button[data-action]"), function(button) {
			button.addEventListener("click", function() {
				self.call(button.getAttribute("data-action"));
			});
		});
		this.call("status");
		this.timer = setInterval(function() {
			if (!self.busy) self.call("status");
		}, 5000);
	},
	beforeDestroy: function() {
		if (this.timer) clearInterval(this.timer);
	},
	destroyed: function() {
		if (this.timer) clearInterval(this.timer);
	},
	methods: {
		el: function(id) {
			return this.$refs.root.querySelector("#" + id);
		},
		set: function(id, value, state) {
			var node = this.el(id);
			if (!node) return;
			node.className = "mbim-value " + (state || "");
			node.textContent = value || "-";
		},
		busySet: function(value) {
			this.busy = value;
			Array.prototype.forEach.call(this.$refs.root.querySelectorAll("button"), function(button) {
				button.disabled = value;
			});
		},
		showTip: function(event, bar) {
			var plot = this.el("mbim-plot");
			var tip = this.el("mbim-tip");
			var rect, left, top;
			if (!plot || !tip) return;
			rect = plot.getBoundingClientRect();
			left = event.clientX - rect.left + 10;
			top = event.clientY - rect.top - 10;
			tip.textContent = hourRangeText(bar.t) + "\n下行流量 " + bytes(bar.rx) + "\n上行流量 " + bytes(bar.tx) + "\n合计 " + bytes(bar.rx + bar.tx);
			tip.style.display = "block";
			tip.style.left = Math.min(left, Math.max(8, rect.width - 210)) + "px";
			tip.style.top = Math.max(8, top) + "px";
		},
		chart: function(value) {
			var samples = hist(value);
			var bars = [];
			var max = 1;
			var totalRx = 0;
			var totalTx = 0;
			var chart = this.el("mbim-bars");
			var y = this.el("mbim-y");
			var x = this.el("mbim-x");
			var sum = this.el("mbim-summary");
			var tip = this.el("mbim-tip");
			var self = this;
			var i;

			if (!chart || !sum || !y || !x) return;
			chart.innerHTML = "";
			x.innerHTML = "";
			if (tip) tip.style.display = "none";

			bars = hourlyBars(samples);
			if (bars.length > 24) bars = bars.slice(-24);

			if (!bars.length) {
				chart.textContent = "等待更多采样...";
				y.innerHTML = "<span class=\"top\">-</span><span class=\"mid\">-</span><span class=\"bottom\">0 B</span>";
				sum.textContent = "页面打开后会自动采样；后台服务也会定期采样。";
				return;
			}

			bars.forEach(function(bar) {
				totalRx += bar.rx;
				totalTx += bar.tx;
				if (bar.rx > max) max = bar.rx;
				if (bar.tx > max) max = bar.tx;
			});

			y.innerHTML = "<span class=\"top\">" + bytes(max) + "</span><span class=\"mid\">" + bytes(Math.round(max / 2)) + "</span><span class=\"bottom\">0 B</span>";
			[0, Math.floor((bars.length - 1) / 2), bars.length - 1].forEach(function(index, pos) {
				var label;
				if (index < 0 || index >= bars.length) return;
				if (pos > 0 && index === 0) return;
				label = document.createElement("span");
				label.textContent = hourText(bars[index].t);
				x.appendChild(label);
			});

			bars.forEach(function(bar) {
				var pair = document.createElement("div");
				var rxNode = document.createElement("div");
				var txNode = document.createElement("div");
				pair.className = "mbim-pair";
				pair.title = hourRangeText(bar.t) + " 下行流量 " + bytes(bar.rx) + " / 上行流量 " + bytes(bar.tx) + " / 合计 " + bytes(bar.rx + bar.tx);
				rxNode.className = "mbim-bar mbim-rx";
				txNode.className = "mbim-bar mbim-tx";
				rxNode.style.height = Math.max(2, Math.round(bar.rx / max * 100)) + "%";
				txNode.style.height = Math.max(2, Math.round(bar.tx / max * 100)) + "%";
				pair.appendChild(rxNode);
				pair.appendChild(txNode);
				pair.addEventListener("mouseenter", function(event) { self.showTip(event, bar); });
				pair.addEventListener("mousemove", function(event) { self.showTip(event, bar); });
				pair.addEventListener("mouseleave", function() { if (tip) tip.style.display = "none"; });
				chart.appendChild(pair);
			});

			sum.textContent = "最近 " + bars.length + " 小时：下行流量 " + bytes(totalRx) + " / 上行流量 " + bytes(totalTx) + "；纵轴上限 " + bytes(max);
		},
		renderStatus: function(s) {
			var online = s.internet === "1";
			var connected = s.running === "1";
			var present = s.dev_present === "1" && s.iface_present === "1";
			var netifdUp = s.netifd_up === "1";
			var direct = s.mode === "direct";
			this.set("internet", online ? "在线" : "离线", online ? "ok" : "bad");
			this.set("running", connected ? "已连接" : "未连接", connected ? "ok" : "warn");
			this.set("netifd", direct ? ((s.iface || "wwan0") + " / 直拨已接管") : ((s.netifd_iface || "-") + " / " + (netifdUp ? "系统已识别" : "系统未识别")), (direct && connected) || netifdUp ? "ok" : "warn");
			this.set("module", present ? "已识别" : "未识别", present ? "ok" : "bad");
			this.set("provider", s.provider || s.registration_state || "-");
			this.set("rssi", s.rssi ? s.rssi + " / 31" : "-");
			this.set("ipv4", s.ipv4 || "-");
			this.set("ipv6", s.ipv6 || "-");
			this.set("gateway", s.gateway || "-");
			this.set("dns", s.dns || "-");
			this.set("traffic", "下行流量 " + bytes(s.rx_bytes) + " / 上行流量 " + bytes(s.tx_bytes));
			this.set("enabled", s.enabled === "1" ? "已开启" : "未开启", s.enabled === "1" ? "ok" : "warn");
			this.set("packet", [s.registration_state, s.packet_state].filter(Boolean).join(" / ") || "-");
			this.el("route").textContent = s.route || "-";
			this.el("log").textContent = (s.log || "").replace(/\\n/g, "\n") || "-";
			this.chart(s.traffic_history || "");
			var pill = this.el("mbim-pill");
			pill.textContent = online ? "ONLINE" : (connected ? "NO INTERNET" : "OFFLINE");
			pill.className = "mbim-pill " + (online ? "ok" : (connected ? "warn" : "bad"));
		},
		call: function(action) {
			var self = this;
			if (this.busy && action !== "status") return;
			this.busySet(action !== "status");
			this.el("mbim-message").textContent = action === "status" ? "正在刷新..." : "已发送 " + action + " 指令，正在读取状态...";
			fetch(api + "?action=" + encodeURIComponent(action), { cache: "no-store" })
				.then(function(res) { return res.text(); })
				.then(function(text) {
					var data = kv(text);
					if (data.error) {
						self.el("mbim-message").textContent = "请求失败：" + data.error;
						return;
					}
					self.renderStatus(data);
					self.el("mbim-message").textContent = "最后刷新：" + new Date().toLocaleTimeString();
				})
				.catch(function(err) {
					self.el("mbim-message").textContent = "无法连接路由器 API：" + err.message;
				})
				.then(function() {
					self.busySet(false);
				});
		}
	}
};
