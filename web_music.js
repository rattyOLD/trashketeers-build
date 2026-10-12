/* One streamed music element, routed through the existing Godot context.
 * Long tracks never become decoded, permanently retained PCM samples. */
(function () {
  'use strict';
  var ids = ['menu', 'battle', 'raid', 'knife', 'win', 'boss'];
  var version = document.currentScript ? new URL(document.currentScript.src).search : '';
  var audio = new Audio();
  audio.loop = true;
  audio.preload = 'none';
  var gain = null, context = null, source = null;
  var desired = '', hidden = document.hidden, volume = 0, generation = 0;
  var bridge = window.trashMusic = {
    ready: !!audio.canPlayType('audio/mp4; codecs="mp4a.40.2"'),
    failed: false,
    failureReason: '',
    element: audio,
    play: function (id, value) {
      if (ids.indexOf(id) < 0 || bridge.failed) return;
      if (desired !== id) {
        desired = id;
        generation++;
        audio.src = 'music/' + id + '.m4a' + version;
      }
      bridge.setVolume(value);
      start();
    },
    setVolume: function (value) {
      volume = Math.max(0, Math.min(1, Number(value) || 0));
      if (gain && context.state !== 'closed') {
        gain.gain.cancelScheduledValues(context.currentTime);
        gain.gain.setTargetAtTime(hidden ? 0 : volume, context.currentTime, 0.08);
      }
    },
    stop: function () {
      generation++;
      desired = '';
      audio.pause();
      audio.removeAttribute('src');
      audio.load();
    },
    background: function (value) {
      hidden = !!value;
      if (hidden) audio.pause();
      else start();
      bridge.setVolume(volume);
    }
  };
  function start() {
    if (!desired || hidden || bridge.failed) return;
    if (!source) {
      var contexts = window.__godotAudioContexts || [];
      context = contexts.find(function (item) { return item.state !== 'closed'; });
      if (!context) return;
      try {
        source = context.createMediaElementSource(audio);
        gain = context.createGain();
        gain.gain.value = 0;
        source.connect(gain);
        gain.connect(context.destination);
        bridge.setVolume(volume);
      } catch (error) { bridge.failed = true; bridge.failureReason = String(error); return; }
    }
    if (context.state === 'suspended') context.resume().catch(function () {});
    if (!audio.paused) return;
    var request = generation;
    audio.play().catch(function (error) {
      if (request !== generation || error.name === 'AbortError' || error.name === 'NotAllowedError') return;
      bridge.failed = true;
      bridge.failureReason = error.name + ': ' + error.message;
    });
  }
  audio.addEventListener('error', function () {
    if (desired) {
      bridge.failed = true;
      bridge.failureReason = audio.error ? audio.error.code + ': ' + audio.error.message : 'media error';
    }
  });
  ['pointerup', 'touchend', 'keydown'].forEach(function (event) {
    window.addEventListener(event, start, { capture: true, passive: true });
  });
  document.addEventListener('visibilitychange', function () { bridge.background(document.hidden); });
}());
