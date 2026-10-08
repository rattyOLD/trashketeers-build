// Ограничение плотности пикселей холста (подключается в <head> ДО index.js).
// Godot в вебе рисует в разрешении экрана × devicePixelRatio: на телефоне с DPR 3 это
// ~3 млн пикселей на кадр — видеочип греется, WebView начинает лагать и со временем падает.
// Подменяем window.devicePixelRatio геттером с потолком window.__trash_dpr_cap: движок читает
// его каждый кадр (GodotDisplayScreen.updateSize), так что игра может менять потолок на лету
// из настроек графики (Platform.set_render_cap). Ввод пересчитывается движком по реальному
// размеру холста, поэтому касания остаются точными.
(function () {
	'use strict';
	try {
		var descriptor = Object.getOwnPropertyDescriptor(window, 'devicePixelRatio')
			|| Object.getOwnPropertyDescriptor(Window.prototype, 'devicePixelRatio');
		var initial = window.devicePixelRatio || 1;
		var real = descriptor && descriptor.get
			? function () { return descriptor.get.call(window) || initial; }
			: function () { return initial; };
		var touch = ('ontouchstart' in window) || (navigator.maxTouchPoints || 0) > 0;
		window.__trash_real_dpr = real;
		window.__trash_is_touch = touch;
		if (typeof window.__trash_dpr_cap !== 'number') {
			window.__trash_dpr_cap = touch ? 1.5 : 2;
		}
		Object.defineProperty(window, 'devicePixelRatio', {
			configurable: true,
			get: function () {
				var r = real();
				var cap = window.__trash_dpr_cap || r;
				return Math.max(0.6, Math.min(r, cap));
			}
		});
	} catch (e) {
		// Браузер не дал переопределить свойство — рисуем в родном разрешении.
	}
})();

// Потеря WebGL-контекста (iOS/Android выгружают видеопамять под нагрузкой): игра встаёт намертво.
// Перезагружаем страницу, но не чаще раза в 20 секунд, чтобы не уйти в цикл.
(function () {
	'use strict';
	window.addEventListener('webglcontextlost', function (event) {
		try {
			event.preventDefault();
			if (window.trkReport) {
				window.trkReport('webgl_context_lost', window.localStorage.getItem('__trash_ctx') || '');
			}
			var last = Number(sessionStorage.getItem('__trash_ctx_reload') || 0);
			if (Date.now() - last < 20000) {
				return;
			}
			sessionStorage.setItem('__trash_ctx_reload', String(Date.now()));
		} catch (e) {
			// sessionStorage может быть закрыт — перезагрузка всё равно нужна.
		}
		setTimeout(function () { location.reload(); }, 400);
	}, true);
})();

// Видимая область окна. Safari на iOS 26 в альбомной ориентации отдаёт в innerHeight всю высоту экрана,
// хотя сверху её занимает панель браузера: холст Godot (он берёт innerWidth × innerHeight) и экран загрузки
// уезжали низом за край. Берём высоту и сдвиг из visualViewport, если она заметно меньше.
// Пока печатают в поле ввода — как раньше (клавиатуру обрабатывает код в странице).
(function () {
	'use strict';
	window.__trashViewport = function () {
		var w = window.innerWidth;
		var h = window.innerHeight;
		var top = 0;
		var vv = window.visualViewport;
		var el = document.activeElement;
		var typing = !!el && (el.tagName === 'INPUT' || el.tagName === 'TEXTAREA');
		if (vv && !typing && Math.abs(vv.scale - 1) < 0.01 && vv.height > 120 && vv.height < h - 2) {
			h = Math.round(vv.height);
			top = Math.max(0, Math.round(vv.offsetTop));
		}
		return [w, h, top];
	};
	var fitBoot = function () {
		var boot = document.getElementById('boot');
		if (!boot) { return; }
		var v = window.__trashViewport();
		var full = v[1] >= window.innerHeight - 2 && v[2] === 0;
		boot.style.top = full ? '' : v[2] + 'px';
		boot.style.height = full ? '' : v[1] + 'px';
		boot.style.bottom = full ? '' : 'auto';
	};
	window.addEventListener('resize', fitBoot);
	window.addEventListener('orientationchange', function () { setTimeout(fitBoot, 300); });
	if (window.visualViewport) {
		window.visualViewport.addEventListener('resize', fitBoot);
		window.visualViewport.addEventListener('scroll', fitBoot);
	}
	document.addEventListener('DOMContentLoaded', fitBoot);
	setInterval(fitBoot, 1000);
})();
