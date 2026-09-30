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
				return Math.max(1, Math.min(r, cap));
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
