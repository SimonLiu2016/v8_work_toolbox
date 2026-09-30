// V8 工作工具箱 - 浏览器伴侣后台服务 (Manifest V3)

chrome.runtime.onInstalled.addListener(() => {
  setupContextMenus();
});

chrome.runtime.onStartup.addListener(() => {
  setupContextMenus();
});

function setupContextMenus() {
  chrome.contextMenus.removeAll(() => {
    // 一级根菜单：V8 工作工具箱（展示扩展自身图标）
    chrome.contextMenus.create({
      id: 'v8_root',
      title: 'V8 工作工具箱',
      contexts: ['selection'],
    });

    // 二级子菜单：查词
    chrome.contextMenus.create({
      id: 'v8_lookup',
      parentId: 'v8_root',
      title: '查词 — V8',
      contexts: ['selection'],
    });

    // 二级子菜单：保存笔记
    chrome.contextMenus.create({
      id: 'v8_save_note',
      parentId: 'v8_root',
      title: '保存笔记 — V8',
      contexts: ['selection'],
    });
  });
}

chrome.contextMenus.onClicked.addListener((info, tab) => {
  const text = (info.selectionText || '').trim();
  if (!text) return;

  if (info.menuItemId === 'v8_lookup') {
    // 优先尝试让当前网页的 content script 原地弹出高保真气泡
    if (tab && tab.id) {
      chrome.tabs.sendMessage(tab.id, { action: 'lookupSelection', text: text }, (res) => {
        if (chrome.runtime.lastError || !res?.success) {
          // 若网页内无法弹出（如非普通网页），回退至桌面端唤起
          const deepLink = `v8toolbox://lookup?text=${encodeURIComponent(text)}`;
          dispatchDeepLink(tab, deepLink);
        }
      });
    } else {
      const deepLink = `v8toolbox://lookup?text=${encodeURIComponent(text)}`;
      dispatchDeepLink(tab, deepLink);
    }
  } else if (info.menuItemId === 'v8_save_note') {
    const pageUrl = tab?.url || '';
    const pageTitle = tab?.title || '';
    const deepLink = `v8toolbox://savenote?text=${encodeURIComponent(text)}&url=${encodeURIComponent(pageUrl)}&title=${encodeURIComponent(pageTitle)}`;
    dispatchDeepLink(tab, deepLink);
  }
});

function dispatchDeepLink(tab, url) {
  if (tab && tab.id && tab.url && !tab.url.startsWith('chrome://') && !tab.url.startsWith('edge://')) {
    chrome.scripting.executeScript({
      target: { tabId: tab.id },
      func: (targetUrl) => {
        const link = document.createElement('a');
        link.href = targetUrl;
        link.style.display = 'none';
        document.body.appendChild(link);
        link.click();
        setTimeout(() => link.remove(), 1000);
      },
      args: [url],
    }).catch(() => {
      openHiddenTab(url);
    });
  } else {
    openHiddenTab(url);
  }
}

function openHiddenTab(url) {
  chrome.tabs.create({ url, active: false }, (newTab) => {
    if (newTab && newTab.id) {
      setTimeout(() => {
        chrome.tabs.remove(newTab.id).catch(() => {});
      }, 600);
    }
  });
}

// ---------------------------------------------------------------------------
// 本地词典桥（local-dictionary-bridge）
//
// 为什么不直连外部词典：实测 dict.youdao.com/jsonapi 对带 `Origin:
// chrome-extension://…` 的请求恒返 403 "Invalid CORS request"，备用源
// api.dictionaryapi.dev 约 20s 后回 Cloudflare 522。host_permissions 只让
// Chrome 跳过浏览器这一侧的 CORS 检查，不会抹掉 Origin 请求头，所以这两个
// 端点从扩展上下文里永远打不通——与代码怎么写无关。桌面应用把同一个词典查询
// 包成回环端点（ACAO 由它自己写），这里改为打那个端点。
// ---------------------------------------------------------------------------

// 与 SettingsStore.defaultBridgePort 保持一致；端口可在桌面应用设置中改，
// 改的是两端都要改的常量（见 proposals/design 的 Decision 3）。
const BRIDGE_PORT = 8797;
// 与桌面应用 SettingsStore 生成的同一密钥。读取位置：
//   ~/Library/Application Support/V8WorkToolbox/app.json → localBridgeSecret
// 何时需要重新同步：重装/迁移桌面应用、桥密钥被重新生成。密钥不匹配时气泡会
// 显示「本地词典桥拒绝访问」而不是含糊的查询失败。
const BRIDGE_SECRET = '1rVOk7DvbImjMqu2nxzjxQ4UtDxFNkwK';

// 客户端超时。MV3 的硬规则：service worker 在一次 fetch 响应超过 30s 时被杀
// 掉，那一次 sendResponse 就永远发不出去。桌面端词典自身 4s 超时，这里留足
// 余量但仍远低于 30s 天花板。
const BRIDGE_TIMEOUT_MS = 2500;

chrome.runtime.onMessage.addListener((message, sender, sendResponse) => {
  if (message.action === 'fetchDictionary') {
    handleFetchDictionary(message.word)
      .then((data) => sendResponse({ success: true, data }))
      .catch((err) =>
        sendResponse({ success: false, reason: err.reason || 'unknown', message: err.message || String(err) }),
      );
    return true; // 保持异步消息通道开放
  }
});

async function handleFetchDictionary(word) {
  const cleanWord = (word || '').trim();
  if (!cleanWord) throw Object.assign(new Error('Empty query'), { reason: 'bad_request' });

  const url =
    `http://127.0.0.1:${BRIDGE_PORT}/dictionary?q=${encodeURIComponent(cleanWord)}`;

  let resp;
  try {
    resp = await fetch(url, {
      headers: {
        Authorization: BRIDGE_SECRET,
        Accept: 'application/json',
      },
      signal: AbortSignal.timeout(BRIDGE_TIMEOUT_MS),
    });
  } catch (e) {
    // 桌面应用没开 / 桥没起来 / 超时：统一归为桥不可达，让气泡报"桥未启动"，
    // 而不是含糊的"查询失败"——这两件事用户能采取的行动完全不同。
    const reason = e.name === 'TimeoutError' || e.name === 'AbortError'
      ? 'bridge_timeout'
      : 'bridge_offline';
    throw Object.assign(new Error(`${reason}: ${e.message}`), { reason });
  }

  if (resp.status === 401 || resp.status === 403) {
    throw Object.assign(new Error('bridge unauthorized'), { reason: 'bridge_unauthorized' });
  }
  if (!resp.ok) {
    throw Object.assign(new Error(`bridge http ${resp.status}`), { reason: 'bridge_error' });
  }

  let payload;
  try {
    payload = await resp.json();
  } catch (e) {
    throw Object.assign(new Error('bridge bad json'), { reason: 'bridge_error' });
  }

  // 桥的"没收录"是 200 + matched:false，不是错误：要让气泡能把它和传输失败
  // 区分开，否则文案会骗人（这也是原实现的坑：兜底链死掉和真没收录长得一样）。
  if (!payload || payload.matched !== true) {
    return { word: cleanWord, matched: false, phonetic: '', audioUrl: '', definitions: [] };
  }

  return {
    word: payload.word || cleanWord,
    matched: true,
    phonetic: payload.phonetic || '',
    audioUrl: payload.audioUrl || '',
    definitions: Array.isArray(payload.definitions) ? payload.definitions : [],
  };
}

