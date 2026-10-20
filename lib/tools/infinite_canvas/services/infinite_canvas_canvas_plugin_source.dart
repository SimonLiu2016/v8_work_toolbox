/// 画布节点插件的源码（spec: 画布节点插件的安装与持久化）。
///
/// **为什么插件源码由 Dart 侧持有**：无限画布的插件系统支持「按 URL 安装」，
/// 而 V8 已经在跑一个 loopback 服务（资产桥）。把插件挂在同一个服务上，用户
/// 只需装一次，安装态由无限画布自己持久化；V8 侧不必往上游仓库塞文件
/// （design D1：不改上游一行代码）。
///
/// **为什么是自包含 JS**：插件的加载方式是
/// `new Blob([source]) → URL.createObjectURL → import()`，它拿不到 V8 的构建
/// 产物，只能用宿主的 `runtime.React`（不打包自己的 React 副本）。
///
/// **插件只做「怎么落进画布」**：有哪些节点、各自是什么内容由 V8 的
/// `/api/export` 决定，插件只翻译成 `applyOps`（design D3）。
library;

/// 插件版本。握手时上报，V8 侧据此提示用户更新。
const String kPluginVersion = '1.1.0';

/// 插件 id。同时是它在无限画布插件面板里的标识。
const String kPluginId = 'v8workbox-canvas-bridge';

/// 生成插件源码。
///
/// [baseUrl] 是资产桥的地址，会被烤进源码——插件不需要用户再配任何东西。
String renderPluginSource({required String baseUrl}) =>
    // ignore: unused_element
    _kPluginSourceTemplate.replaceAll('__V8_BASE_URL__', baseUrl);

/// 源码模板。
///
/// 用 `__V8_BASE_URL__` 占位而不是字符串拼接，是为了让整段 JS 保持可读——
/// 它是要被人读的（上游 SDK 漂移时要照着改），不是生成的字节码。
const String _kPluginSourceTemplate = '''
(function () {
  var BASE = "__V8_BASE_URL__";
  var PLUGIN_ID = "v8workbox-canvas-bridge";
  var NODE_TYPE = PLUGIN_ID + ":bridge";

  function secret() {
    try {
      var s = window.localStorage.getItem("v8:bridge-secret");
      if (s) return s;
    } catch (e) {}
    return prompt("请输入 V8WorkToolbox 资产桥密钥（工具页「安装画布插件」卡片里可复制）") || "";
  }

  function saveSecret(s) {
    try { window.localStorage.setItem("v8:bridge-secret", s); } catch (e) {}
  }

  async function api(path, options) {
    var opts = options || {};
    var headers = { Authorization: secret() };
    if (opts.body !== undefined) headers["Content-Type"] = "application/octet-stream";
    var res = await fetch(BASE + path, { method: opts.method || "GET", headers: headers, body: opts.body });
    if (res.status === 401) {
      var s = prompt("资产桥拒绝了密钥，请重新输入：") || "";
      if (!s) throw new Error("未提供密钥");
      saveSecret(s);
      headers = { Authorization: s };
      if (opts.body !== undefined) headers["Content-Type"] = "application/octet-stream";
      var retry = await fetch(BASE + path, { method: opts.method || "GET", headers: headers, body: opts.body });
      return retry.json();
    }
    return res.json();
  }

  function readAsDataUrl(blob) {
    return new Promise(function (resolve, reject) {
      var r = new FileReader();
      r.onload = function () { resolve(r.result); };
      r.onerror = function () { reject(r.error); };
      r.readAsDataURL(blob);
    });
  }

  var React = null;
  var h = null;

  function Panel(props) {
    var ctx = props.ctx;

    // 参考图入库走宿主 SDK：插件无法 import 宿主 bundle 里的存储模块，ai.uploadReference
    // 是唯一入口（上游 fork 已加，见 web/src/types/canvas-plugin.ts）。
    async function uploadReference(url) {
      if (ctx.ai && typeof ctx.ai.uploadReference === "function") {
        try {
          return await ctx.ai.uploadReference(url);
        } catch (e) {
          return { fallback: String(e && e.message || e) };
        }
      }
      return { unsupported: true };
    }

    var st = React.useState({ tab: "import", loading: false, log: [], series: null, episode: null, options: [], picked: {} });
    var state = st[0];
    var setState = st[1];
    var patch = function (p) { setState(function (prev) { return Object.assign({}, prev, p); }); };

    async function loadEpisodes() {
      patch({ loading: true, log: [] });
      try {
        var data = await api("/api/episodes");
        patch({ options: data.series || [], loading: false });
        if (!data.series || !data.series.length) patch({ log: ["工坊里还没有剧集"] });
      } catch (e) {
        patch({ loading: false, log: ["加载剧集失败：" + String(e && e.message || e)] });
      }
    }

    async function doImport() {
      if (!state.series || !state.episode) { patch({ log: ["请先选择剧集与集"] }); return; }
      patch({ loading: true, log: [] });
      try {
        var data = await api("/api/export?seriesId=" + encodeURIComponent(state.series) + "&episodeId=" + encodeURIComponent(state.episode));
        if (!data.ok) { patch({ loading: false, log: ["导出失败：" + (data.detail || data.reason || "未知")] }); return; }
        var payload = data.payload;
        var nodes = ctx.getNodes();
        var ops = [];
        var notes = [];
        var col = 0;
        var row = 0;
        for (var i = 0; i < payload.nodes.length; i++) {
          var spec = payload.nodes[i];
          var exists = nodes.some(function (n) { return n.id === spec.id; });
          var x = col * (340 + (payload.layout.gapX || 96));
          var y = row * (240 + (payload.layout.gapY || 160));
          col += 1;
          if (col >= (payload.layout.columns || 3)) { col = 0; row += 1; }
          var metadata = Object.assign({}, spec.metadata, { v8: spec.metadata && spec.metadata.v8 });
          if (spec.kind === "text") {
            metadata.content = spec.markdown || "";
            ops.push({ type: "add_node", id: spec.id, nodeType: "text", title: spec.title, x: x, y: y, metadata: metadata });
          } else {
            metadata.prompt = spec.prompt || "";
            metadata.negativePrompt = spec.negativePrompt || "";
            if (spec.imageUrl) {
              try {
                var up = await uploadReference(spec.imageUrl);
                if (up && up.unsupported) {
                  notes.push("当前无限画布版本不支持参考图入库，请升级后重试「" + spec.title + "」");
                } else if (up && up.fallback) {
                  notes.push("「" + spec.title + "」的参考图入库失败：" + up.fallback);
                } else if (up && up.url && up.storageKey) {
                  metadata.content = up.url;
                  metadata.storageKey = up.storageKey;
                  metadata.status = "success";
                } else if (up && up.url) {
                  // 没有 storageKey：宿主读不到那张图。退回 data URL，让画布加载时
                  // 自己 uploadImage（hydrateCanvasImages 对 data:image/ 的处理）。
                  try {
                    var res = await fetch(up.url);
                    var blob = await res.blob();
                    metadata.content = await readAsDataUrl(blob);
                    metadata.status = "success";
                  } catch (e2) {
                    notes.push("「" + spec.title + "」的参考图读取失败：" + String(e2 && e2.message || e2));
                  }
                } else {
                  notes.push("「" + spec.title + "」的参考图上传失败，可稍后重试");
                }
              } catch (e) { notes.push("「" + spec.title + "」的参考图上传失败：" + String(e && e.message || e)); }
            }
            ops.push({ type: "add_node", id: spec.id, nodeType: "image", title: spec.title, x: x, y: y, metadata: metadata });
          }
        }
        // 已存在的节点走 update_node，避免重复添加。
        for (var j = 0; j < ops.length; j++) {
          var op = ops[j];
          if (nodes.some(function (n) { return n.id === op.id; })) {
            ops[j] = { type: "update_node", id: op.id, metadata: op.metadata, patch: { title: op.title } };
          }
        }
        ctx.applyOps(ops);
        var log = ["已写入 " + ops.length + " 个节点（未创建连线、未触发生成）"];
        for (var k = 0; k < notes.length; k++) log.push(notes[k]);
        for (var m = 0; m < (payload.skippedNotes || []).length; m++) log.push(payload.skippedNotes[m]);
        patch({ loading: false, log: log });
      } catch (e) {
        patch({ loading: false, log: ["导入失败：" + String(e && e.message || e)] });
      }
    }

    async function loadVideos() {
      var nodes = ctx.getNodes();
      var picked = {};
      for (var i = 0; i < nodes.length; i++) {
        var n = nodes[i];
        if (n.type !== "video" || !n.metadata || !n.metadata.content) continue;
        picked[n.id] = true;
      }
      patch({ picked: picked });
    }

    async function doCollect() {
      var nodes = ctx.getNodes();
      var ids = Object.keys(state.picked).filter(function (id) { return state.picked[id]; });
      if (!ids.length) { patch({ log: ["请先勾选要归集的视频节点"] }); return; }
      patch({ loading: true, log: [] });
      var log = [];
      var done = 0;
      for (var i = 0; i < ids.length; i++) {
        var node = nodes.filter(function (n) { return n.id === ids[i]; })[0];
        if (!node) continue;
        var meta = node.metadata || {};
        var v8 = meta.v8 || {};
        var seriesId = v8.seriesId || state.series;
        var episodeId = v8.episodeId || state.episode;
        if (!seriesId || !episodeId) { log.push("「" + (node.title || node.id) + "」不是本工具导出的节点，且未在导入页选过目标集，已跳过"); continue; }
        try {
          var res = await fetch(meta.content);
          var blob = await res.blob();
          var name = (node.title || node.id).replace(/[\\\\/:*?"<>|]/g, "_") + ".mp4";
          var r = await api(
            "/api/import?seriesId=" + encodeURIComponent(seriesId) +
            "&episodeId=" + encodeURIComponent(episodeId) +
            "&fileName=" + encodeURIComponent(name) +
            "&targetIsSegment=true",
            { method: "POST", body: blob }
          );
          if (r && r.ok) { done += 1; log.push("已归集「" + (node.title || node.id) + "」→ " + r.staged); }
          else log.push("「" + (node.title || node.id) + "」归集失败：" + ((r && r.reason) || "未知"));
        } catch (e) {
          log.push("「" + (node.title || node.id) + "」归集失败：" + String(e && e.message || e));
        }
      }
      log.unshift("完成 " + done + " / " + ids.length);
      patch({ loading: false, log: log });
    }

    function videoNodes() {
      return ctx.getNodes().filter(function (n) { return n.type === "video" && n.metadata && n.metadata.content; });
    }

    React.useEffect(function () { loadEpisodes(); loadVideos(); }, []);

    var box = { padding: 12, display: "flex", flexDirection: "column", gap: 10, fontSize: 13 };
    var btn = { padding: "6px 12px", borderRadius: 6, border: "1px solid rgba(128,128,128,.4)", background: "transparent", cursor: "pointer" };
    var tabs = { display: "flex", gap: 8 };
    var tabBtn = function (active) { return Object.assign({}, btn, { fontWeight: active ? 700 : 400 }); };
    var logBox = { whiteSpace: "pre-wrap", fontSize: 12, opacity: 0.8, maxHeight: 160, overflow: "auto" };

    return h("div", { style: box },
      h("div", { style: tabs },
        h("button", { style: tabBtn(state.tab === "import"), onClick: function () { patch({ tab: "import" }); loadEpisodes(); } }, "导入剧集到画布"),
        h("button", { style: tabBtn(state.tab === "collect"), onClick: function () { patch({ tab: "collect" }); loadVideos(); } }, "归集成片到工坊")
      ),
      state.loading ? h("div", null, "处理中…") : null,
      state.tab === "import"
        ? h("div", { style: { display: "flex", flexDirection: "column", gap: 8 } },
            h("div", null,
              h("div", null, "剧集"),
              h("select", {
                value: state.series || "",
                onChange: function (e) {
                  var sid = e.target.value;
                  var found = (state.options || []).filter(function (s) { return s.seriesId === sid; })[0];
                  patch({ series: sid, episode: (found && found.episodes[0] && found.episodes[0].episodeId) || null });
                }
              }, (state.options || []).map(function (s) { return h("option", { key: s.seriesId, value: s.seriesId }, s.seriesName); }))
            ),
            h("div", null,
              h("div", null, "集"),
              h("select", {
                value: state.episode || "",
                onChange: function (e) { patch({ episode: e.target.value }); }
              }, (((state.options || []).filter(function (s) { return s.seriesId === state.series; })[0] || {}).episodes || []).map(function (ep) {
                return h("option", { key: ep.episodeId, value: ep.episodeId }, "第" + ep.index + "集 " + (ep.title || ""));
              }))
            ),
            h("button", { style: btn, disabled: state.loading, onClick: function () { doImport(); } }, "导入到画布"),
            h("div", { style: { fontSize: 12, opacity: 0.7 } }, "只写内容节点与参考素材，不建连线、不触发生成——请在画布上自行连线。")
          )
        : h("div", { style: { display: "flex", flexDirection: "column", gap: 8 } },
            h("div", { style: { fontSize: 12, opacity: 0.7 } }, "勾选要归集的视频节点（目标集取自节点自带标识；本工具导出的节点无需再选）"),
            videoNodes().map(function (n) {
              return h("label", { key: n.id, style: { display: "flex", gap: 6, alignItems: "center" } },
                h("input", {
                  type: "checkbox",
                  checked: !!state.picked[n.id],
                  onChange: function (e) { var p = Object.assign({}, state.picked); p[n.id] = e.target.checked; patch({ picked: p }); }
                }),
                h("span", null, (n.title || n.id) + ((n.metadata && n.metadata.v8) ? " · 已标记" : ""))
              );
            }),
            videoNodes().length ? null : h("div", { style: { fontSize: 12, opacity: 0.7 } }, "画布上还没有视频节点"),
            h("button", { style: btn, disabled: state.loading, onClick: function () { doCollect(); } }, "归集到工坊")
          ),
      state.log.length ? h("div", { style: logBox }, state.log.join("\\n")) : null
    );
  }

  function setup(runtime) {
    React = runtime.React;
    h = runtime.jsx;
    try {
      fetch(BASE + "/api/handshake", { headers: { Authorization: secret() } }).catch(function () {});
    } catch (e) {}
  }

  var plugin = {
    id: PLUGIN_ID,
    name: "V8WorkToolbox 资产桥",
    version: "1.1.0",
    minAppVersion: "0.20.0",
    description: "把 AI 短视频工坊的剧集导入画布，并把画布上的成片归集回工坊。",
    nodes: [
      {
        type: NODE_TYPE,
        title: "V8 资产桥",
        description: "剧集导入与成片归集面板",
        defaultSize: { width: 420, height: 360 },
        defaultMetadata: {},
        showInCreateMenu: true,
        autoOpenPanel: true,
        hasSourceHandle: false,
        hidePanel: false,
        minimapColor: "#0ea5e9",
        Panel: Panel,
        resource: function () { return null; }
      }
    ],
    setup: setup
  };

  return plugin;
})();
''';
