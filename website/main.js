// 填充版本信息、语言切换，以及页面上的各个演示：贯穿全页的 3D 手机与其中自绘的界面、弹幕、宣言划线、推荐流过滤与滚动、代码联动、主题色、标签栏、字号。无依赖。
(function () {
  "use strict";
  var root = document.documentElement;
  var reduceMotion = window.matchMedia("(prefers-reduced-motion: reduce)");

  // 与 NeoBili/Core/UI/AppTheme.swift 保持一致
  var THEMES = [
    ["#FB7AB3", "樱花粉", "Sakura Pink"], ["#D94F78", "玫瑰红", "Rose"], ["#C43C51", "宝石红", "Ruby"],
    ["#E66B58", "珊瑚橙", "Coral"], ["#E77D22", "活力橙", "Orange"], ["#BA871B", "琥珀金", "Amber"],
    ["#879535", "橄榄绿", "Olive"], ["#69A441", "青柠绿", "Lime"], ["#429961", "青草绿", "Leaf Green"],
    ["#268260", "森林绿", "Forest"], ["#249B80", "翡翠绿", "Jade"], ["#258E98", "青瓷色", "Celadon"],
    ["#269DBD", "湖水蓝", "Lake Blue"], ["#409DDA", "晴空蓝", "Sky Blue"], ["#3478D5", "经典蓝", "Classic Blue"],
    ["#4966C7", "钴蓝色", "Cobalt"], ["#6860C7", "靛青色", "Indigo"], ["#8A62C9", "紫罗兰", "Violet"],
    ["#A47CCB", "薰衣草", "Lavender"], ["#B561B4", "兰花紫", "Orchid"], ["#AC527F", "莓果色", "Berry"],
    ["#997159", "可可棕", "Cocoa"], ["#657F99", "岩石蓝", "Slate"], ["#7C8087", "石墨灰", "Graphite"]
  ];
  var TITLES = { zh: "NeoBili — B 站，就该这么刷", en: "NeoBili — Bilibili. Beautifully native." };

  function store(key, value) { try { localStorage.setItem(key, value); } catch (e) {} }
  function lang() { return root.dataset.lang === "en" ? "en" : "zh"; }
  function $(sel, ctx) { return (ctx || document).querySelector(sel); }
  function $$(sel, ctx) { return Array.prototype.slice.call((ctx || document).querySelectorAll(sel)); }
  function clamp(v, a, b) { return Math.min(b, Math.max(a, v)); }

  // ── 版本信息：见 release.js ──
  var release = window.NEOBILI_RELEASE || {};
  $$("[data-release]").forEach(function (el) {
    var value = release[el.dataset.release];
    if (value != null) el.textContent = value;
  });
  $$("[data-release-href]").forEach(function (el) {
    var value = release[el.dataset.releaseHref];
    if (value) el.href = value;
  });

  // ── 语言 ──
  var onLanguage = [];
  function applyLanguage() {
    var l = lang();
    root.lang = l === "en" ? "en" : "zh-CN";
    document.title = TITLES[l];
    var desc = $('meta[name="description"]');
    if (desc) desc.content = desc.dataset[l];
    $$("[data-alt-zh]").forEach(function (img) { img.alt = img.dataset[l === "en" ? "altEn" : "altZh"]; });
    $$("[data-label-zh]").forEach(function (el) { el.setAttribute("aria-label", el.dataset[l === "en" ? "labelEn" : "labelZh"]); });
    onLanguage.forEach(function (fn) { fn(l); });
  }
  var toggle = $("[data-lang-toggle]");
  if (toggle) toggle.addEventListener("click", function () {
    root.dataset.lang = lang() === "en" ? "zh" : "en";
    store("neobili-lang", root.dataset.lang);
    applyLanguage();
  });

  // ── 浅色 / 深色：默认跟随系统，按钮切换后记住选择 ──
  var themeToggle = $("[data-theme-toggle]");
  var systemDark = window.matchMedia("(prefers-color-scheme: dark)");
  function isDark() { return root.dataset.theme ? root.dataset.theme === "dark" : systemDark.matches; }
  function syncThemeColor() {
    $$('meta[name="theme-color"]').forEach(function (m) { m.content = isDark() ? "#000000" : "#ffffff"; m.removeAttribute("media"); });
  }
  if (themeToggle) themeToggle.addEventListener("click", function () {
    root.dataset.theme = isDark() ? "light" : "dark";
    store("neobili-theme", root.dataset.theme);
    syncThemeColor();
  });
  if (root.dataset.theme) syncThemeColor();

  // ── 进入视口时浮现 ──
  var revealer = "IntersectionObserver" in window ? new IntersectionObserver(function (entries) {
    entries.forEach(function (e) { if (e.isIntersecting) { e.target.classList.add("in"); revealer.unobserve(e.target); } });
  }, { rootMargin: "0px 0px -8% 0px" }) : null;
  $$(".reveal").forEach(function (el) { if (revealer) revealer.observe(el); else el.classList.add("in"); });

  // 只在元素可见时回调，用于暂停屏幕外的动画
  function whenVisible(el, fn, margin) {
    if (!el) return;
    if (!("IntersectionObserver" in window)) { fn(true); return; }
    new IntersectionObserver(function (entries) { fn(entries[0].isIntersecting); }, { rootMargin: margin || "0px" }).observe(el);
  }

  // ── 首屏：鼠标视差（背景的 N、浮动标签，以及手机本身） ──
  var tilt = $("[data-tilt]"), pointer = { x: 0, y: 0 };
  var requestRig = function () {};
  if (tilt && window.matchMedia("(hover: hover) and (pointer: fine)").matches && !reduceMotion.matches) {
    var hero = $(".hero");
    var setPointer = function (x, y) {
      pointer.x = x; pointer.y = y;
      tilt.style.setProperty("--mx", x.toFixed(3));
      tilt.style.setProperty("--my", y.toFixed(3));
      requestRig();
    };
    hero.addEventListener("pointermove", function (e) {
      var r = hero.getBoundingClientRect();
      setPointer((e.clientX - r.left) / r.width * 2 - 1, (e.clientY - r.top) / r.height * 2 - 1);
    });
    hero.addEventListener("pointerleave", function () { setPointer(0, 0); });
  }

  // ── 首屏：弹幕 ──
  // hot 用主题色，self 模拟 App 里自己发的弹幕（绿色描边）
  var DANMAKU = {
    zh: ["无广告！", "SwiftUI 原生", "液态玻璃好好看", "前方高能", "24 种主题色，图标也跟着变", "终于没有开屏广告了",
         "2333", "关注页红点和 B 站同步", "缩略播放器好评", "字号能调 7 档", "不收集任何数据", "英文界面也有",
         "这才是 iOS 该有的样子", "下拉刷新距离都能调", "竖屏视频可以隐藏", "标签栏能自己排", "丝滑", "空降成功",
         "全屏控件避开灵动岛", "弹幕护体", "hhhhh", "UP 主更新了", "收藏了", "三连"],
    en: ["No ads!", "Pure SwiftUI", "Liquid Glass looks so good", "Incoming!", "24 colors, icons too", "no splash ads at last",
         "2333", "unread dots actually sync", "mini player ftw", "7 text sizes", "zero tracking", "English UI too",
         "this is what iOS should feel like", "even pull-to-refresh is tunable", "hide vertical videos", "reorder your tabs",
         "so smooth", "clears the Dynamic Island", "lmao", "new upload!", "saved", "like · coin · fav"]
  };
  var HOT = { "无广告！": 1, "SwiftUI 原生": 1, "No ads!": 1, "Pure SwiftUI": 1, "24 种主题色，图标也跟着变": 1, "24 colors, icons too": 1, "不收集任何数据": 1, "zero tracking": 1 };
  var dmBox = $("[data-danmaku]");
  if (dmBox) (function () {
    var LANES = 9, running = false, timers = [], pool = [];
    function pick() {
      if (!pool.length) pool = DANMAKU[lang()].slice().sort(function () { return Math.random() - 0.5; });
      return pool.pop();
    }
    function laneTop(i) { return (i + 0.3) / LANES * 100 + "%"; }
    function make(text, lane) {
      var s = document.createElement("span");
      s.className = "dm" + (HOT[text] ? " hot" : "") + (Math.random() < 0.06 ? " self" : "");
      s.textContent = text;
      s.style.top = laneTop(lane);
      s.style.setProperty("--fs", (15 + Math.round(Math.random() * 10)) + "px");
      return s;
    }
    function spawn(lane) {
      if (!running) return;
      var s = make(pick(), lane);
      var dur = 11 + Math.random() * 9;
      s.style.setProperty("--dur", dur.toFixed(1) + "s");
      s.addEventListener("animationend", function () { s.remove(); });
      dmBox.appendChild(s);
      // 下一条在这条完全离开右边缘之后再出发，避免同一轨道重叠
      timers[lane] = setTimeout(function () { spawn(lane); }, (dur * 0.45 + Math.random() * 4) * 1000);
    }
    function start() {
      if (running) return;
      running = true;
      dmBox.classList.remove("paused");
      for (var i = 0; i < LANES; i++) (function (i) { timers[i] = setTimeout(function () { spawn(i); }, Math.random() * 6000); })(i);
    }
    function stop() {
      running = false;
      dmBox.classList.add("paused");
      timers.forEach(clearTimeout);
    }
    function still() {
      stop();
      dmBox.textContent = "";
      for (var i = 0; i < LANES; i++) {
        var s = make(pick(), i);
        s.classList.add("still");
        s.style.left = (5 + Math.random() * 70) + "%";
        dmBox.appendChild(s);
      }
    }
    if (reduceMotion.matches) { still(); onLanguage.push(function () { pool = []; still(); }); return; }
    onLanguage.push(function () { pool = []; });
    var visible = true;
    whenVisible(dmBox, function (v) { visible = v; if (v && !document.hidden) start(); else stop(); });
    document.addEventListener("visibilitychange", function () { if (document.hidden) stop(); else if (visible) start(); });
  })();

  // ── 手机里的界面（device.css 画的）──
  var ui = $("[data-ui]");
  function setUi(name, value) { if (ui) ui.style.setProperty(name, value); }
  var adReplay = false;   // 01 里点「重播」时，广告横幅的收起由重播动画接管

  // ── 宣言：随滚动逐条划掉，手机上对应的东西也一样样拿掉 ──
  var manifesto = $("[data-manifesto]");
  if (manifesto) (function () {
    var strikes = $$("[data-strike]", manifesto), remains = $("[data-remains]", manifesto), ticking = false;
    if (reduceMotion.matches) manifesto.classList.add("static");
    function update() {
      ticking = false;
      var r = manifesto.getBoundingClientRect();
      var total = r.height - window.innerHeight;
      var p = reduceMotion.matches ? 1 : clamp(-r.top / (total || 1), 0, 1);
      var n = strikes.length, seg = 0.8 / n;
      strikes.forEach(function (li, i) {
        var v = clamp((p - 0.04 - i * seg) / (seg * 0.9), 0, 1).toFixed(3);
        li.style.setProperty("--p", v);
        setUi("--p" + (i + 1), v);                // 开屏广告 / 信息流广告 / 滑动卡顿 / 数据收集
        if (i === 1 && !adReplay) setUi("--ad", v);
      });
      remains.style.setProperty("--p", clamp((p - 0.82) / 0.14, 0, 1).toFixed(3));
    }
    function request() { if (!ticking) { ticking = true; requestAnimationFrame(update); } }
    window.addEventListener("scroll", request, { passive: true });
    window.addEventListener("resize", request);
    update();
  })();

  // ── 推荐流：同一份卡片生成两遍，一遍在屏幕里，一遍在屏幕下方（「还没进屏幕」的那些）──
  // 内容是虚构的示例：封面为渐变，标题与 UP 主名随页面语言切换。
  var ITEMS = [
    ["一台相机走完川西：海拔四千米的延时摄影", "Across western Sichuan with one camera: timelapses at 4,000 m", "山野记录", "Wildframe", "12:48", "32.1万", "321K", "川西", "4000 M", ""],
    ["三分钟看懂液态玻璃：它为什么这样折射", "Liquid Glass in three minutes: why it bends light", "设计札记", "Design Notes", "3:12", "8.6万", "86K", "液态<br>玻璃", "GLASS", ""],
    ["从 PCB 到键帽：做一把自己的机械键盘", "From PCB to keycaps: building my own keyboard", "键盘研究所", "Keeb Lab", "18:05", "15.3万", "153K", "DIY<br>键盘", "DIY", ""],
    ["猫咪第一次见到雪，反应太真实了", "A cat meets snow for the very first time", "喵星日报", "Cat Daily", "1:12", "45.7万", "457K", "初雪", "SNOW", "vertical"],
    ["十秒学会一个剪辑转场", "Learn a cut transition in ten seconds", "手势课", "Quick Cuts", "0:10", "2.3万", "23K", "10秒", "10 SEC", "short"],
    ["复刻深夜食堂：一碗番茄牛腩面", "Recreating a late-night classic: tomato beef noodles", "小厨房", "Tiny Kitchen", "9:26", "21.9万", "219K", "牛腩面", "NOODLES", ""],
    ["独立游戏开发日志 #12：整套光影重做", "Indie devlog #12: rebuilding all the lighting", "像素夜航", "Pixel Night", "14:37", "6.4万", "64K", "#12", "#12", ""],
    ["沿着江边骑五十公里是什么体验", "Fifty kilometers along the river by bike", "骑行的阿树", "Shu Rides", "22:10", "11.2万", "112K", "50KM", "50 KM", ""],
    ["钢琴改编：那首你一定听过的动画 OP", "Piano cover of an anime opening you know", "琴房日常", "Piano Room", "4:51", "38.5万", "385K", "钢琴", "PIANO", ""],
    ["用 ESP32 做一块桌面天气屏", "Building a desk weather display with ESP32", "硬件笔记", "Hardware Notes", "16:22", "9.8万", "98K", "ESP32", "ESP32", ""],
    ["一分钟整理好你的桌面", "Tidy your desk in one minute", "手势课", "Quick Cuts", "0:52", "3.1万", "31K", "1分钟", "1 MIN", "short"],
    ["城市夜景延时：一整晚只拍一个路口", "City timelapse: one intersection, all night", "山野记录", "Wildframe", "7:40", "17.4万", "174K", "夜景", "NIGHT", ""]
  ];
  var AD = '<div class="adb" data-kind="ad"><b><span data-l="zh">品牌大促 · 全场满减</span><span data-l="en">Mega sale · Everything must go</span></b>' +
    '<small><span data-l="zh">点击领取新人专享券</span><span data-l="en">Tap to claim your welcome coupon</span></small>' +
    '<em><span data-l="zh">广告</span><span data-l="en">Ad</span></em><span class="cta"><span data-l="zh">立即下载</span><span data-l="en">Get the app</span></span></div>';
  var feedGrid = $("[data-feed-grid]"), ghostGrid = $("[data-ghost-grid]");
  var feed = { cards: [], ghosts: [], hide: { vertical: false, short: false }, y: 0, timer: null, running: false };
  if (feedGrid && ghostGrid) (function () {
    var html = "";
    for (var i = 0; i < 36; i++) {
      // 横跨两列的行只插在偶数位置，前一行总是满的，不会在右边空出一格
      if (i === 2 || i === 10 || i === 20 || i === 30) html += AD;
      if (i === 4) html += '<div class="last-seen" data-kind="sep"><svg><use href="#i-refresh"/></svg><span data-l="zh">上次看到这里 · 点击刷新</span><span data-l="en">You were here · Tap to refresh</span></div>';
      var it = ITEMS[i % ITEMS.length], kind = it[9];
      var h = (i * 53 + 200) % 360;
      html += '<div class="fc' + (i < 6 ? " skel" : "") + '" data-kind="' + kind + '" style="--h:' + h + ";--x:" + (30 + (i * 37) % 50) + '%">' +
        '<div class="cv g' + (i % 6) + (kind === "vertical" ? " tall" : "") + '">' +
          '<span class="word' + (i % 3 === 1 ? " alt" : "") + '"><span data-l="zh">' + it[7] + '</span><span data-l="en">' + it[8] + "</span></span>" +
          (kind === "vertical" ? '<span class="badge"><span data-l="zh">竖屏</span><span data-l="en">Vertical</span></span>' : "") +
          '<span class="rdy"><svg width="11" height="11"><use href="#i-play"/></svg><span data-l="zh">已预取</span><span data-l="en">Ready</span></span>' +
          '<div class="st"><span><svg><use href="#i-views"/></svg><span data-l="zh">' + it[5] + '</span><span data-l="en">' + it[6] + "</span></span><span>" + it[4] + "</span></div>" +
        "</div>" +
        '<p class="tt"><span data-l="zh">' + it[0] + '</span><span data-l="en">' + it[1] + "</span></p>" +
        '<p class="au"><span data-l="zh">' + it[2] + '</span><span data-l="en">' + it[3] + "</span></p>" +
        '<i class="sk"></i></div>';
    }
    feedGrid.innerHTML = html;
    ghostGrid.innerHTML = html;
    feed.cards = $$(".fc", feedGrid);
    feed.ghosts = $$(".fc", ghostGrid);
  })();

  // 屏幕里 1pt 对应的页面像素（手机本身的缩放 × 画布缩放）
  var UI_SCALE = 0.70896;
  function feedScale() { return ((rigState && rigState.scale) || 1) * UI_SCALE; }

  // 01：竖屏视频、过短视频的过滤。卡片碎掉，其余卡片用 FLIP 补位
  function applyFilter(animate) {
    var hide = feed.hide;
    var leaving = feed.cards.filter(function (c) { return !c.hidden && hide[c.dataset.kind]; });
    var entering = feed.cards.filter(function (c) { return c.hidden && !hide[c.dataset.kind]; });
    function commit() {
      feed.cards.forEach(function (c, i) {
        c.hidden = !!hide[c.dataset.kind]; c.classList.remove("dying");
        feed.ghosts[i].hidden = c.hidden;
      });
    }
    if (!animate || reduceMotion.matches || !Element.prototype.animate) { commit(); return; }
    leaving.forEach(function (c) { c.classList.add("dying"); });
    setTimeout(function () {
      var before = new Map();
      feed.cards.forEach(function (c) { if (!c.hidden) before.set(c, c.getBoundingClientRect()); });
      commit();
      var k = feedScale();
      feed.cards.forEach(function (c) {
        if (c.hidden) return;
        var a = before.get(c), b = c.getBoundingClientRect();
        if (!a) { if (entering.indexOf(c) >= 0) c.animate([{ opacity: 0, transform: "scale(0.8)" }, { opacity: 1, transform: "none" }], { duration: 450, easing: "cubic-bezier(.2,.8,.2,1)" }); return; }
        var dx = (a.left - b.left) / k, dy = (a.top - b.top) / k;
        if (Math.abs(dx) > 0.5 || Math.abs(dy) > 0.5) c.animate([{ transform: "translate(" + dx + "px," + dy + "px)" }, { transform: "none" }], { duration: 550, easing: "cubic-bezier(.2,.8,.2,1)" });
      });
    }, leaving.length ? 480 : 0);
  }
  $$("[data-filter]").forEach(function (b) {
    b.addEventListener("click", function () {
      var on = b.getAttribute("aria-pressed") !== "true";
      b.setAttribute("aria-pressed", on ? "true" : "false");
      feed.hide[b.dataset.filter] = on;
      applyFilter(true);
    });
  });
  // 重播：广告横幅先回来，停一下，再在解析时被剔除（收起）
  var replay = $("[data-feed-replay]");
  if (replay) replay.addEventListener("click", function () {
    feed.hide = { vertical: false, short: false };
    $$("[data-filter]").forEach(function (b) { b.setAttribute("aria-pressed", "false"); });
    applyFilter(false);
    adReplay = true;
    setUi("--ad", 0);
    var start = performance.now() + 900;
    (function tick(now) {
      var t = clamp((now - start) / 700, 0, 1);
      setUi("--ad", ((1 - Math.cos(Math.PI * t)) / 2).toFixed(3));
      if (t < 1) requestAnimationFrame(tick); else adReplay = false;
    })(performance.now());
  });

  // 02：推荐流一下下甩动；停住片刻后，屏幕上的卡片挂上「已预取」
  var VIEWPORT_H = 874, HEADER_H = 132, GHOST_GAP = 42;   // pt；卡片从大标题下面滑过去，所以视口是整块屏幕
  function setFeedY(y, snap) {
    feed.y = y;
    [feedGrid, ghostGrid].forEach(function (g) { g.classList.toggle("snap", !!snap); });
    feedGrid.style.transform = "translateY(" + (-y) + "px)";
    ghostGrid.style.transform = "translateY(" + (-(y + VIEWPORT_H + GHOST_GAP)) + "px)";
  }
  function markReady() {
    feed.cards.forEach(function (c) {
      if (c.hidden) return;
      var top = c.offsetTop, bottom = top + c.offsetHeight;
      c.classList.toggle("ready", bottom > feed.y + HEADER_H + 10 && top < feed.y + VIEWPORT_H - 90);
    });
  }
  function clearReady() { feed.cards.forEach(function (c) { c.classList.remove("ready"); }); }
  function feedStep() {
    if (!feed.running) return;
    clearReady();
    var visible = feed.cards.filter(function (c) { return !c.hidden; });
    var rowH = visible.length > 2 ? visible[2].offsetTop - visible[0].offsetTop : 230;
    var rows = [1, 3, 2, 1, 4, 2][Math.floor(feed.y / rowH) % 6] || 2;   // 有轻有重的甩动
    var max = feedGrid.scrollHeight - VIEWPORT_H * 1.6;
    if (feed.y + rows * rowH > max) {
      feedGrid.animate([{ opacity: 1 }, { opacity: 0 }, { opacity: 1 }], { duration: 700 });
      setTimeout(function () { setFeedY(0, true); }, 350);
    } else {
      setFeedY(feed.y + rows * rowH);
    }
    feed.timer = setTimeout(function () {
      markReady();
      feed.timer = setTimeout(feedStep, 1500);
    }, 1200);
  }
  function startFeed() {
    if (feed.running) return;
    if (reduceMotion.matches) { markReady(); return; }
    feed.running = true;
    feed.timer = setTimeout(feedStep, 600);
  }
  function stopFeed() {
    if (!feed.running) return;
    feed.running = false;
    clearTimeout(feed.timer);
    clearReady();
    setFeedY(0);
  }
  if (feedGrid && ghostGrid) setFeedY(0, true);

  // ── 03 代码 ↔ 界面：点一行代码，手机切到对应的界面并高亮相关元素；停在这段时自动轮播，用户点过就停 ──
  var code = $("[data-code]"), codeLine = "home";
  var codeLines = code ? $$(".code-line", code) : [];
  var codeIndex = 0, codeTimer = null, codeUserTook = false, codeActive = false;
  var CODE_DWELL = { home: 3200, zoom: 4400, mini: 4800, video: 3600, land: 4800 };
  function showCode(i, focus) {
    codeIndex = i;
    codeLines.forEach(function (l, j) {
      l.setAttribute("aria-selected", j === i ? "true" : "false");
      l.tabIndex = j === i ? 0 : -1;
      if (j === i && focus) l.focus();
    });
    codeLine = codeLines[i].dataset.show;
    requestRig();
  }
  function scheduleCode() {
    clearTimeout(codeTimer);
    if (codeUserTook || !codeActive || reduceMotion.matches) return;
    codeTimer = setTimeout(function () { showCode((codeIndex + 1) % codeLines.length); scheduleCode(); }, CODE_DWELL[codeLines[codeIndex].dataset.show] || 3200);
  }
  codeLines.forEach(function (l, i) {
    l.addEventListener("click", function () { codeUserTook = true; clearTimeout(codeTimer); showCode(i); });
  });
  if (code) {
    code.addEventListener("keydown", function (e) {
      var step = { ArrowDown: 1, ArrowRight: 1, ArrowUp: -1, ArrowLeft: -1 }[e.key];
      if (!step) return;
      e.preventDefault(); codeUserTook = true; clearTimeout(codeTimer);
      showCode((codeIndex + step + codeLines.length) % codeLines.length, true);
    });
    showCode(0);
  }

  // ── 04 主题色：色板就是 24 个桌面图标 ──
  var swatchBox = $("[data-swatches]");
  var nameEl = $("[data-theme-name]"), hexEl = $("[data-theme-hex]"), bigIcon = $(".app-icon.huge");
  var current = (getComputedStyle(root).getPropertyValue("--accent").trim() || "#FB7AB3").toUpperCase();
  if (!THEMES.some(function (t) { return t[0] === current; })) current = THEMES[0][0];

  function renderThemeName() {
    var theme = THEMES.filter(function (t) { return t[0] === current; })[0] || THEMES[0];
    if (nameEl) nameEl.textContent = lang() === "en" ? theme[2] : theme[1];
    if (hexEl) hexEl.textContent = theme[0];
    if (swatchBox) $$(".swatch", swatchBox).forEach(function (b, i) {
      b.setAttribute("aria-label", lang() === "en" ? THEMES[i][2] : THEMES[i][1]);
      b.title = b.getAttribute("aria-label");
    });
  }
  onLanguage.push(renderThemeName);

  function select(hex, focus, persist) {
    var changed = hex !== current;
    current = hex;
    root.style.setProperty("--accent", hex);
    if (persist) store("neobili-accent", hex);
    $$(".swatch", swatchBox).forEach(function (b) {
      var on = b.dataset.hex === hex;
      b.setAttribute("aria-checked", on ? "true" : "false");
      b.tabIndex = on ? 0 : -1;
      if (on && focus) b.focus();
    });
    if (changed && bigIcon && !reduceMotion.matches) {
      bigIcon.classList.remove("pop"); void bigIcon.offsetWidth; bigIcon.classList.add("pop");
    }
    renderThemeName();
  }

  if (swatchBox) {
    var SVGNS = "http://www.w3.org/2000/svg";
    THEMES.forEach(function (t) {
      var b = document.createElement("button");
      b.type = "button";
      b.className = "swatch";
      b.setAttribute("role", "radio");
      b.dataset.hex = t[0];
      b.style.setProperty("--c", t[0]);
      var svg = document.createElementNS(SVGNS, "svg");
      svg.setAttribute("viewBox", "0 0 1024 1024");
      svg.setAttribute("aria-hidden", "true");
      svg.style.color = t[0];
      var use = document.createElementNS(SVGNS, "use");
      use.setAttribute("href", "#neobili-icon");
      svg.appendChild(use);
      b.appendChild(svg);
      b.addEventListener("click", function () { select(t[0], false, true); });
      swatchBox.appendChild(b);
    });
    // 方向键在色板间移动（radiogroup 的标准键盘行为）
    swatchBox.addEventListener("keydown", function (e) {
      var step = { ArrowRight: 1, ArrowDown: 1, ArrowLeft: -1, ArrowUp: -1 }[e.key];
      if (!step) return;
      e.preventDefault();
      var i = THEMES.findIndex(function (t) { return t[0] === current; });
      select(THEMES[(i + step + THEMES.length) % THEMES.length][0], true, true);
    });
    select(current, false);
  }

  // ── 04 标签栏：与 NeoBili/App/MainTabSettings.swift 一致——搜索固定在末尾，其余最多 4 个 ──
  // 就是手机里那条标签栏；图标对应 App 里的 SF Symbols。
  var ICONS = {
    live: '<g fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round"><path d="M8.5 8.5a5 5 0 0 0 0 7M15.5 8.5a5 5 0 0 1 0 7M5.6 5.6a9 9 0 0 0 0 12.8M18.4 5.6a9 9 0 0 1 0 12.8"/></g><circle cx="12" cy="12" r="2" fill="currentColor"/>',
    home: '<path fill="currentColor" d="M11.3 3.3a1 1 0 0 1 1.4 0l8 7.2c.6.6.2 1.5-.6 1.5H19v7.5a1.5 1.5 0 0 1-1.5 1.5H15v-5.5a1 1 0 0 0-1-1h-4a1 1 0 0 0-1 1V21H6.5A1.5 1.5 0 0 1 5 19.5V12H3.9c-.8 0-1.2-.9-.6-1.5Z"/>',
    following: '<g fill="currentColor"><circle cx="9" cy="8" r="3.6"/><path d="M2.5 19.2c0-3.2 2.9-5.7 6.5-5.7s6.5 2.5 6.5 5.7c0 .7-.5 1.1-1.1 1.1H3.6c-.6 0-1.1-.4-1.1-1.1Z"/><circle cx="17" cy="9" r="2.8"/><path d="M16.6 13.6c2.9 0 5 2 5 4.6 0 .6-.4 1-1 1h-3.4c.1-1.9-.2-3.8-.6-5.6Z"/></g>',
    watchLater: '<path fill="currentColor" d="M5 3.5a1 1 0 0 1 1 1V5h12.2c.8 0 1.2.9.7 1.5L16.3 10l2.6 3.5c.5.6.1 1.5-.7 1.5H6v5.5a1 1 0 1 1-2 0v-16a1 1 0 0 1 1-1Z"/>',
    favorites: '<path fill="currentColor" d="m12 2.8 2.8 5.8 6.3.9-4.6 4.4 1.1 6.3L12 17.2l-5.6 3 1.1-6.3-4.6-4.4 6.3-.9Z"/>',
    history: '<g fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M4 12a8 8 0 1 0 2.4-5.7M4 4v3.5h3.5"/><path d="M12 8v4l3 2"/></g>',
    search: '<g fill="none" stroke="currentColor" stroke-width="2.4" stroke-linecap="round"><circle cx="10.5" cy="10.5" r="6.2"/><path d="m15.2 15.2 5 5"/></g>'
  };
  // 英文名取自 NeoBili/Resources/Localizable.xcstrings
  var TABS = [
    ["live", "直播", "Live"], ["home", "推荐", "Recommended"], ["following", "关注", "Following"],
    ["watchLater", "稍后再看", "Watch Later"], ["favorites", "收藏", "Favorites"], ["history", "历史", "History"]
  ];
  var MAX_VISIBLE = 4;
  var bar = $("[data-tabbar]"), pool = $("[data-tabpool]");
  if (bar && pool) (function () {
    var shown = ["live", "home", "following"], launch = "home";
    function label(t) { return lang() === "en" ? t[2] : t[1]; }
    function item(id, text, on) {
      var b = document.createElement("button");
      b.type = "button";
      b.className = "tb" + (on ? " on" : "");
      b.tabIndex = -1;
      b.innerHTML = '<svg viewBox="0 0 24 24" aria-hidden="true">' + ICONS[id] + "</svg><span></span>";
      b.lastChild.textContent = text;
      return b;
    }
    function renderBar() {
      bar.innerHTML = "";
      TABS.forEach(function (t) {
        if (shown.indexOf(t[0]) < 0) return;
        var b = item(t[0], label(t), t[0] === launch);
        b.addEventListener("click", function () { launch = t[0]; renderBar(); });
        bar.appendChild(b);
      });
      bar.appendChild(item("search", lang() === "en" ? "Search" : "搜索", false));
    }
    function renderPool() {
      pool.innerHTML = "";
      TABS.forEach(function (t) {
        var on = shown.indexOf(t[0]) >= 0;
        var b = document.createElement("button");
        b.type = "button";
        b.className = "chip";
        b.setAttribute("aria-pressed", on ? "true" : "false");
        b.textContent = label(t);
        b.addEventListener("click", function () {
          var i = shown.indexOf(t[0]);
          if (i >= 0) {
            if (shown.length === 1) return shake(b);
            shown.splice(i, 1);
            if (launch === t[0]) launch = shown[0];
          } else {
            if (shown.length >= MAX_VISIBLE) return shake(b);
            shown.push(t[0]);
          }
          renderBar(); renderPool();
          var again = pool.children[TABS.indexOf(t)];
          if (again) again.focus();
        });
        pool.appendChild(b);
      });
    }
    function shake(b) { b.classList.remove("shake"); void b.offsetWidth; b.classList.add("shake"); }
    renderBar(); renderPool();
    onLanguage.push(function () { renderBar(); renderPool(); });
  })();

  // ── 04 字号：7 档，对应 App 里的 DynamicTypeSize .xSmall … .xxxLarge，默认第 4 档；手机上的卡片标题一起变 ──
  var sizeInput = $("[data-size]"), sample = $("[data-sample]"), sizeOut = $("[data-size-out]");
  var SCALES = [0.82, 0.88, 0.94, 1, 1.12, 1.24, 1.36];
  function renderSize() {
    var i = +sizeInput.value;
    sample.style.setProperty("--ts", SCALES[i]);
    setUi("--ts", SCALES[i]);
    sizeOut.textContent = (i + 1) + " / 7";
  }
  if (sizeInput && sample) { sizeInput.addEventListener("input", renderSize); renderSize(); }

  // ── 贯穿全页的手机 ──
  // 每个 [data-slot] 占位框对应一个「停靠点」，另有一个虚拟停靠点：宣言那段手机停在右侧。
  // 停靠点的滚动位置 = 占位框居中于视口时的 scrollY。离开一个停靠点就开始往下一个走（正弦缓动 +
  // 跳跃），停在占位框里时也随滚动轻微漂浮。首屏到宣言那一跳整部手机转一圈，露出白色背面。
  var rig = $("[data-rig]");
  var BASE_W = 300, BASE_H = 636;
  var rigState = { scale: 1 };
  if (rig) (function () {
    var device = $("[data-device]", rig);
    // 圆角处的铝框：一圈圈叠出厚度
    for (var e = 0; e <= 15; e++) {
      var edge = document.createElement("div");
      edge.className = "edge";
      edge.style.setProperty("--i", e);
      device.insertBefore(edge, device.querySelector(".side"));
    }
    var screens = $$(".scr", ui);
    var manifestoEl = $("[data-manifesto]");
    var stops = [], mode = null, ticking = false;
    var SCREEN = { hero: "splash", fall: "home", noads: "home", smooth: "home", yours: "home", download: "splash" };
    var LINE_SCREEN = { home: "home", zoom: "follow", mini: "home", video: "video", land: "land" };

    function slotStop(el) {
      var name = el.dataset.slot;
      // 贴边（sticky）的占位框用它的容器定位，取的是它本来的位置
      var anchor = name === "yours" ? el.parentElement : el;
      return {
        name: name, el: el,
        rx: +(el.dataset.rx || 0), ry: +(el.dataset.ry || 0), rz: +(el.dataset.rz || 0),
        key: function () {
          var r = anchor.getBoundingClientRect();
          return r.top + window.scrollY + el.offsetHeight / 2 - window.innerHeight / 2;
        },
        rect: function () {
          var r = el.getBoundingClientRect();
          var o = { cx: r.left + r.width / 2, cy: r.top + r.height / 2, w: r.width, rx: this.rx, ry: this.ry, rz: this.rz };
          if (name === "hero") { o.ry += pointer.x * 10; o.rx -= pointer.y * 8; }
          return o;
        }
      };
    }
    function fallStop() {
      // 宣言整段钉住时，手机留在画面右侧，屏幕朝着读者，轻轻摆动，好让人看清上面的东西一样样被拿掉
      return {
        name: "fall",
        key: function () { return manifestoEl.offsetTop; },
        rect: function () {
          var vw = document.documentElement.clientWidth, vh = window.innerHeight;
          var span = Math.max(1, manifestoEl.offsetHeight - vh);
          var f = clamp((window.scrollY - manifestoEl.offsetTop) / span, 0, 1);
          var narrow = vw < 720;
          var w = narrow ? Math.min(140, vw * 0.36) : Math.min(290, (vh - 170) * 0.43);
          var sway = reduceMotion.matches ? 0 : 1;
          return {
            cx: narrow ? vw - w * 0.45 : Math.min(vw * 0.75, vw - w * 0.75),
            cy: vh * (narrow ? 0.6 : 0.5) + f * vh * 0.1,
            w: w,
            rx: sway * 8 * Math.sin(f * Math.PI * 2),
            ry: sway * (-20 + 30 * f),
            rz: sway * (6 - 10 * f)
          };
        }
      };
    }
    function build() {
      var slotEls = $$("[data-slot]");
      stops = slotEls.map(slotStop);
      if (manifestoEl) stops.splice(1, 0, fallStop());
      var maxScroll = document.documentElement.scrollHeight - window.innerHeight, prev = -1;
      stops.forEach(function (s, i) {
        s.k = i === 0 ? 0 : clamp(s.key(), prev + 1, Math.max(prev + 1, maxScroll));
        prev = s.k;
      });
      update();
    }
    // 正弦缓动：两端也不会完全停住，手机随滚动始终在动
    function ease(t) { return (1 - Math.cos(Math.PI * t)) / 2; }
    function lerp(a, b, t) { return a + (b - a) * t; }

    // 03 里「缩略播放器」那一行：标签栏收起 / 展开来回演示
    var miniTimer = null;
    function miniLoop(on) {
      clearInterval(miniTimer);
      ui.classList.remove("minimized");
      if (!on) return;
      var down = false;
      function flip() {
        down = !down;
        ui.classList.toggle("minimized", down);
        setFeedY(down ? 460 : 0);
      }
      if (reduceMotion.matches) { ui.classList.add("minimized"); return; }
      miniTimer = setInterval(flip, 2200);
      setTimeout(flip, 500);
    }
    // 03 里「画质菜单」那一行：手机转成横屏，先看控件，再展开菜单
    var menuTimer = null;
    var hlEls = [];
    function highlight(els) {
      hlEls.forEach(function (el) { el.classList.remove("hl", "tap"); });
      hlEls = els.filter(Boolean);
      hlEls.forEach(function (el) { el.classList.add("hl"); });
    }
    var shown = {};
    function applyUi(name, line) {
      var screen = name === "native" ? LINE_SCREEN[line] : SCREEN[name];
      var key = name + "|" + (name === "native" ? line : "");
      if (shown.key === key) return;
      var prevLine = shown.line;
      shown = { key: key, line: name === "native" ? line : "" };
      ui.dataset.mode = name;
      ui.dataset.screen = screen;
      ui.dataset.line = shown.line;
      screens.forEach(function (s) { s.classList.toggle("on", s.dataset.scr === screen); });
      ui.classList.toggle("acc", shown.line === "mini");
      if (prevLine === "mini" || shown.line === "mini") { miniLoop(shown.line === "mini"); if (shown.line !== "mini" && !feed.running) setFeedY(0); }
      var land = $(".scr-land", ui);
      clearTimeout(menuTimer);
      land.classList.remove("menu-open");
      if (shown.line === "land") menuTimer = setTimeout(function () { land.classList.add("menu-open"); }, reduceMotion.matches ? 0 : 1500);
      // 高亮说明里提到的那个元素
      var play = $(".v-play", ui);
      if (shown.line === "home") highlight([bar]);
      else if (shown.line === "mini") highlight([$(".accessory", ui)]);
      else if (shown.line === "video") { highlight([play]); play.classList.add("tap"); }
      else if (shown.line === "land") highlight([$(".l-q", ui)]);
      else if (name === "yours") highlight([bar]);
      else highlight([]);
      if (shown.line === "zoom") {   // 重新从头播放缩放转场
        ui.dataset.line = ""; void ui.offsetWidth; ui.dataset.line = "zoom";
      }
    }
    function setMode(name) {
      if (name === mode) return;
      var prev = mode;
      mode = name;
      rig.dataset.mode = name;
      rig.classList.toggle("ghosted", name === "smooth");
      rig.classList.toggle("interactive", name === "yours");
      if (name === "smooth") startFeed(); else if (prev === "smooth") stopFeed();
      codeActive = name === "native";
      scheduleCode();
    }
    // 横屏程度 0…1：切到横屏那行时手机逆时针转 90° 并缩小，离开时转回来
    var land = 0, landTick = 0;

    function update() {
      ticking = false;
      if (!stops.length) return;
      var y = window.scrollY, i = 0;
      while (i < stops.length - 1 && y >= stops[i + 1].k) i++;
      var a = stops[i], b = stops[Math.min(i + 1, stops.length - 1)];
      var t = 0;
      if (a !== b) {
        // 宣言段：先留在右侧，让读者看清上面的东西一样样被拿掉，最后一屏才慢慢落向下一段；
        // 自定义段：贴在左侧，等设置卡片滚得差不多再出发，免得手机压在卡片上
        var travel = b.k - a.k;
        if (a.name === "fall") travel = Math.min(window.innerHeight * 1.2, travel);
        if (a.name === "yours") travel = Math.min(window.innerHeight, travel);
        t = ease(clamp((y - (b.k - travel)) / travel, 0, 1));
      }
      var A = a.rect(), B = a === b ? A : b.rect();
      // 首屏那一跳从手机原本的位置出发（不跟着首屏往上滚），整个翻转过程都留在画面里
      if (i === 0) A.cy += y;
      var still = reduceMotion.matches;
      var hop = still ? 0 : Math.sin(Math.PI * t) * (i === 0 ? 0.5 : 1);
      var w = lerp(A.w, B.w, t) * (1 - 0.08 * hop);
      var cx = lerp(A.cx, B.cx, t);
      var cy = lerp(A.cy, B.cy, t) - hop * Math.min(90, window.innerHeight * 0.1);
      var rz = lerp(A.rz, B.rz, t) + hop * (i % 2 ? -10 : 10);
      var rx = lerp(A.rx, B.rx, t), ry = lerp(A.ry, B.ry, t);
      // 首屏 → 宣言：整部手机绕竖轴转一圈，中途露出白色背面，屏幕内容在背对读者时换掉
      if (i === 0 && !still) { ry += 360 * t; rx += 14 * hop; }
      // 随滚动的轻微漂浮：停在占位框里时也跟着滚动转动，不会定住
      if (!still) {
        var phase = y / 520;
        rz += 3 * Math.sin(phase);
        ry += 7 * Math.sin(phase * 0.8 + 1);
        rx += 4 * Math.sin(phase * 1.1 + 2);
        cy += 8 * Math.sin(phase * 1.3);
      }
      var current = t < 0.5 ? a : b;
      var landTarget = current.name === "native" && codeLine === "land" ? 1 : 0;
      if (land !== landTarget) {
        var now = performance.now(), dt = landTick ? Math.min(50, now - landTick) : 16;
        landTick = now;
        land = still ? landTarget : clamp(land + (landTarget > land ? 1 : -1) * dt / 650, 0, 1);
        requestRig();
      } else {
        landTick = 0;
      }
      var le = ease(land);
      rz -= 90 * le;
      w *= 1 - 0.42 * le;
      var scale = w / BASE_W;
      if (le > 0) {
        // 横过来以后比占位框宽，别让它探出窗口左右边缘
        var half = BASE_H * scale / 2, vw = document.documentElement.clientWidth;
        cx = lerp(cx, clamp(cx, half + 16, vw - half - 16), le);
      }
      rigState.scale = scale;
      rig.style.transform = "translate3d(" + (cx - BASE_W / 2).toFixed(1) + "px," + (cy - BASE_H / 2).toFixed(1) + "px,0) perspective(1600px) rotateX(" + rx.toFixed(2) + "deg) rotateY(" + ry.toFixed(2) + "deg) rotateZ(" + rz.toFixed(2) + "deg) scale3d(" + scale.toFixed(4) + "," + scale.toFixed(4) + "," + scale.toFixed(4) + ")";

      setMode(current.name);
      applyUi(current.name, codeLine);
      rig.classList.add("on");
    }
    requestRig = function () { if (!ticking) { ticking = true; requestAnimationFrame(update); } };
    window.addEventListener("scroll", requestRig, { passive: true });
    window.addEventListener("resize", build);
    window.addEventListener("load", build);
    if ("ResizeObserver" in window) new ResizeObserver(function () { build(); }).observe(document.body);
    build();
  })();

  applyLanguage();
})();
