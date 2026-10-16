(function () {
    'use strict';
    if (parent === window) { return; }
    var host;
    try { host = parent.trashLandscapeHost; } catch (error) { return; }
    if (!host) { return; }
    window.__trashHost = host;
    function gesture(event) {
        var active = document.activeElement;
        if (event.isTrusted && !/INPUT|TEXTAREA/.test(event.target.tagName) && !event.target.isContentEditable && !(active && /INPUT|TEXTAREA/.test(active.tagName))) { host.auto(); }
    }
    addEventListener('pointerup',gesture,{capture:true,passive:true});
    addEventListener('touchend',gesture,{capture:true,passive:true});
    var replace = history.replaceState.bind(history);
    history.replaceState = function () { var result = replace.apply(history,arguments); host.syncURL(location.search,location.hash); return result; };
    function ready() {
        var observer = new MutationObserver(function () {
            if (!document.getElementById('boot')) { observer.disconnect(); host.ready(); }
        });
        observer.observe(document.body,{childList:true});
        if (!document.getElementById('boot')) { observer.disconnect(); host.ready(); }
        document.addEventListener('focusin',host.fit);
        document.addEventListener('focusout',function () { setTimeout(host.fit,150); });
    }
    if (document.readyState === 'loading') { document.addEventListener('DOMContentLoaded',ready,{once:true}); } else { ready(); }
}());
