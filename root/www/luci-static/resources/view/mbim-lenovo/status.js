'use strict';
'require view';
'require fs';
'require poll';
'require ui';

var fields = {};

function parseKV(text) {
	var out = {};

	(text || '').split(/\r?\n/).forEach(function(line) {
		var i = line.indexOf('=');
		if (i > 0)
			out[line.slice(0, i)] = line.slice(i + 1);
	});

	return out;
}

function run(action) {
	return fs.exec_direct('/usr/bin/mbim-lenovo-up.sh', [ action || 'status' ]);
}

function bytes(n) {
	n = parseInt(n || '0', 10);

	if (n >= 1073741824)
		return (n / 1073741824).toFixed(2) + ' GB';
	if (n >= 1048576)
		return (n / 1048576).toFixed(1) + ' MB';
	if (n >= 1024)
		return (n / 1024).toFixed(1) + ' KB';

	return n + ' B';
}

function parseHistory(value) {
	var samples = [];

	(value || '').split(';').forEach(function(item) {
		var p = item.split(',');
		var s;

		if (p.length !== 3)
			return;

		s = {
			t: parseInt(p[0], 10),
			rx: parseInt(p[1], 10),
			tx: parseInt(p[2], 10)
		};

		if (!isNaN(s.t) && !isNaN(s.rx) && !isNaN(s.tx))
			samples.push(s);
	});

	return samples;
}

function pad2(value) {
	return value < 10 ? '0' + value : String(value);
}

function hourText(timestamp) {
	var date = new Date(timestamp * 1000);
	return (date.getMonth() + 1) + '/' + date.getDate() + ' ' + pad2(date.getHours()) + ':00';
}

function hourRangeText(timestamp) {
	var next = timestamp + 3600;
	var from = new Date(timestamp * 1000);
	var to = new Date(next * 1000);

	if (from.getMonth() === to.getMonth() && from.getDate() === to.getDate())
		return hourText(timestamp) + '-' + pad2(to.getHours()) + ':00';

	return hourText(timestamp) + '-' + hourText(next);
}

function hourlyBars(samples) {
	var map = {};
	var bars = [];
	var first = null;
	var last = null;
	var i;

	for (i = 1; i < samples.length; i++) {
		var hour = Math.floor(samples[i].t / 3600) * 3600;
		var rx = Math.max(0, samples[i].rx - samples[i - 1].rx);
		var tx = Math.max(0, samples[i].tx - samples[i - 1].tx);

		if (first === null)
			first = hour;
		last = hour;

		if (!map[hour])
			map[hour] = { t: hour, rx: 0, tx: 0 };

		map[hour].rx += rx;
		map[hour].tx += tx;
	}

	if (first === null)
		return bars;

	for (i = first; i <= last; i += 3600)
		bars.push(map[i] || { t: i, rx: 0, tx: 0 });

	return bars;
}

function renderTrafficChart(history) {
	var samples = parseHistory(history);
	var bars = hourlyBars(samples);
	var max = 1;
	var totalRx = 0;
	var totalTx = 0;
	var start;

	if (bars.length > 24)
		bars = bars.slice(bars.length - 24);

	if (!fields.chart || !fields.trafficSummary)
		return;

	fields.chart.innerHTML = '';

	if (!bars.length) {
		fields.chart.textContent = _('Waiting for more samples...');
		fields.trafficSummary.textContent = _('The page samples while open; the service also records samples in the background.');
		return;
	}

	for (var j = 0; j < bars.length; j++) {
		totalRx += bars[j].rx;
		totalTx += bars[j].tx;
		if (bars[j].rx > max)
			max = bars[j].rx;
		if (bars[j].tx > max)
			max = bars[j].tx;
	}

	start = hourText(bars[0].t);

	bars.forEach(function(bar) {
		var title = hourRangeText(bar.t) + '  下行流量 ' + bytes(bar.rx) +
			' / 上行流量 ' + bytes(bar.tx) + ' / 合计 ' + bytes(bar.rx + bar.tx);
		var rxBar = E('div', {
			'class': 'mbim-bar mbim-bar-rx',
			'style': 'height:' + Math.max(2, Math.round(bar.rx / max * 100)) + '%'
		});
		var txBar = E('div', {
			'class': 'mbim-bar mbim-bar-tx',
			'style': 'height:' + Math.max(2, Math.round(bar.tx / max * 100)) + '%'
		});

		fields.chart.appendChild(E('div', {
			'class': 'mbim-bar-pair',
			'title': title
		}, [ rxBar, txBar ]));
	});

	fields.trafficSummary.textContent = _('Recent') + ' ' + bars.length + ' ' +
		_('hours since') + ' ' + start + ': 下行流量 ' + bytes(totalRx) +
		' / 上行流量 ' + bytes(totalTx);
}

function setValue(id, value, state) {
	if (!fields[id])
		return;

	fields[id].className = 'mbim-value' + (state ? ' ' + state : '');
	fields[id].textContent = value || '-';
}

function renderStatus(s) {
	var online = s.internet === '1';
	var connected = s.running === '1';
	var present = s.dev_present === '1' && s.iface_present === '1';

	setValue('internet', online ? _('Online') : _('Offline'), online ? 'mbim-ok' : 'mbim-bad');
	setValue('running', connected ? _('Connected') : _('Disconnected'), connected ? 'mbim-ok' : 'mbim-warn');
	setValue('module', present ? _('Present') : _('Missing'), present ? 'mbim-ok' : 'mbim-bad');
	setValue('provider', s.provider || s.registration_state || '-');
	setValue('rssi', s.rssi ? (s.rssi + ' / 31') : '-');
	setValue('ipv4', s.ipv4 || '-');
	setValue('ipv6', s.ipv6 || '-');
	setValue('gateway', s.gateway || '-');
	setValue('dns', s.dns || '-');
	setValue('traffic', '下行流量 ' + bytes(s.rx_bytes) + ' / 上行流量 ' + bytes(s.tx_bytes));
	setValue('enabled', s.enabled === '1' ? _('Enabled') : _('Disabled'), s.enabled === '1' ? 'mbim-ok' : 'mbim-warn');
	setValue('packet', [ s.registration_state, s.packet_state ].filter(function(v) { return !!v; }).join(' / ') || '-');

	if (fields.route)
		fields.route.textContent = s.route || '-';
	if (fields.log)
		fields.log.textContent = (s.log || '').replace(/\\n/g, '\n') || '-';
	if (fields.message)
		fields.message.textContent = _('Last refresh') + ': ' + new Date().toLocaleTimeString();

	renderTrafficChart(s.traffic_history || '');
}

function field(id, label) {
	fields[id] = E('div', { 'class': 'mbim-value' }, '-');

	return E('div', { 'class': 'mbim-card' }, [
		E('div', { 'class': 'mbim-label' }, label),
		fields[id]
	]);
}

function refresh() {
	return run('status').then(function(text) {
		renderStatus(parseKV(text));
	}).catch(function(e) {
		if (fields.message)
			fields.message.textContent = _('Status failed') + ': ' + e.message;
	});
}

function action(name) {
	var uiAction = {
		start: 'ui-start',
		stop: 'ui-stop',
		restart: 'ui-restart'
	}[name];

	if (!uiAction)
		return refresh();

	if (fields.message)
		fields.message.textContent = _('Sending command') + ': ' + name;

	return run(uiAction).then(function(text) {
		renderStatus(parseKV(text));
		window.setTimeout(refresh, 3000);
	}).catch(function(e) {
		ui.addNotification(null, E('p', {}, _('Command failed') + ': ' + e.message), 'danger');
	});
}

return view.extend({
	load: function() {
		return run('status').then(parseKV);
	},

	render: function(data) {
		var css = E('style', {}, [
			'.mbim-grid{display:grid;grid-template-columns:repeat(auto-fit,minmax(190px,1fr));gap:10px;margin:12px 0}',
			'.mbim-card{border:1px solid #ddd;border-radius:6px;padding:10px 12px;background:#fff;min-height:72px}',
			'.mbim-label{color:#666;font-size:12px;margin-bottom:4px}',
			'.mbim-value{font-size:18px;font-weight:600;overflow-wrap:anywhere}',
			'.mbim-ok{color:#078a35}.mbim-warn{color:#b36b00}.mbim-bad{color:#b00020}',
			'.mbim-actions{margin:12px 0}.mbim-actions .cbi-button{margin-right:8px;margin-bottom:6px}',
			'.mbim-chart-box{border:1px solid #ddd;border-radius:6px;background:#fff;padding:10px;margin:12px 0}',
			'.mbim-chart{height:190px;display:flex;align-items:flex-end;gap:4px;border-left:1px solid #ddd;border-bottom:1px solid #ddd;padding:8px 6px 0;overflow:hidden}',
			'.mbim-bar-pair{flex:1 1 8px;min-width:5px;height:100%;display:flex;align-items:flex-end;gap:1px}',
			'.mbim-bar{flex:1 1 0;min-height:1px;border-radius:3px 3px 0 0}',
			'.mbim-bar-rx{background:#155eef}.mbim-bar-tx{background:#f79009}',
			'.mbim-chart-note{color:#666;font-size:12px;margin-top:8px}',
			'.mbim-dot{display:inline-block;width:10px;height:10px;border-radius:2px;margin-right:4px;vertical-align:-1px}',
			'.mbim-log{background:#111;color:#eee;min-height:180px;padding:10px;overflow:auto;white-space:pre-wrap}'
		].join(''));

		fields = {};
		fields.message = E('span', {}, _('Loading...'));
		fields.route = E('pre', {}, '-');
		fields.log = E('pre', { 'class': 'mbim-log' }, '-');
		fields.chart = E('div', { 'class': 'mbim-chart' }, '-');
		fields.trafficSummary = E('div', { 'class': 'mbim-chart-note' }, '-');

		var node = E('div', {}, [
			css,
			E('h2', {}, _('Lenovo MagicBay LTE2控制台')),
			E('p', {}, _('Lenovo MagicBay LTE2 / ASR1803 MBIM status and controls.')),
			E('div', { 'class': 'mbim-actions' }, [
				E('button', {
					'class': 'cbi-button cbi-button-apply',
					'click': ui.createHandlerFn(this, function() { return action('start'); })
				}, _('Start')),
				E('button', {
					'class': 'cbi-button cbi-button-reset',
					'click': ui.createHandlerFn(this, function() { return action('stop'); })
				}, _('Stop')),
				E('button', {
					'class': 'cbi-button cbi-button-reload',
					'click': ui.createHandlerFn(this, function() { return action('restart'); })
				}, _('Restart')),
				E('button', {
					'class': 'cbi-button',
					'click': ui.createHandlerFn(this, refresh)
				}, _('Refresh')),
				fields.message
			]),
			E('div', { 'class': 'mbim-grid' }, [
				field('internet', _('Internet')),
				field('running', _('Connection')),
				field('module', _('Module')),
				field('provider', _('Provider')),
				field('rssi', _('Signal RSSI')),
				field('ipv4', 'IPv4'),
				field('ipv6', 'IPv6'),
				field('gateway', _('Gateway')),
				field('dns', 'DNS'),
				field('traffic', _('Traffic')),
				field('enabled', _('Autostart')),
				field('packet', _('Registration / packet'))
			]),
			E('h3', {}, _('Traffic statistics')),
			E('div', { 'class': 'mbim-chart-box' }, [
				fields.chart,
				fields.trafficSummary,
				E('div', { 'class': 'mbim-chart-note' }, [
					E('span', { 'class': 'mbim-dot mbim-bar-rx' }, ''),
					_('下行流量'),
					'  ',
					E('span', { 'class': 'mbim-dot mbim-bar-tx' }, ''),
					_('上行流量')
				])
			]),
			E('h3', {}, _('Default route')),
			fields.route,
			E('h3', {}, _('Recent log with per-line notes')),
			fields.log
		]);

		renderStatus(data || {});
		poll.add(refresh, 5);
		return node;
	},

	handleSaveApply: null,
	handleSave: null,
	handleReset: null
});
