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
// 运行时消息监听：处理来自 Content Script 的安全网络请求（绕过网页 CSP / CORS）
// ---------------------------------------------------------------------------
chrome.runtime.onMessage.addListener((message, sender, sendResponse) => {
  if (message.action === 'fetchDictionary') {
    handleFetchDictionary(message.word)
      .then((data) => sendResponse({ success: true, data }))
      .catch((err) => sendResponse({ success: false, error: err.message || String(err) }));
    return true; // 保持异步消息通道开放
  }
});

async function handleFetchDictionary(word) {
  const cleanWord = (word || '').trim();
  if (!cleanWord) throw new Error('Empty query');

  // 1. 优先调用有道词典开放接口
  try {
    const youdaoUrl = `https://dict.youdao.com/jsonapi?q=${encodeURIComponent(cleanWord)}&le=en&dicts=${encodeURIComponent('{"count":99,"dicts":[["ec","fanyi"]]}')}`;
    const resp = await fetch(youdaoUrl, {
      headers: {
        'User-Agent': 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7)',
        'Referer': 'https://dict.youdao.com/',
      },
    });
    if (resp.ok) {
      const data = await resp.json();
      let phonetic = '';
      let audioUrl = '';
      const definitions = [];

      const ec = data.ec;
      if (ec && ec.word && ec.word.length > 0) {
        const w = ec.word[0];
        phonetic = w.usphone ? `/${w.usphone}/` : (w.ukphone ? `/${w.ukphone}/` : (w.phone ? `/${w.phone}/` : ''));
        if (w.usspeech) audioUrl = `https://dict.youdao.com/dictvoice?audio=${encodeURIComponent(w.usspeech)}`;

        if (w.trs && Array.isArray(w.trs)) {
          for (const tr of w.trs) {
            if (tr.tr && tr.tr.length > 0 && tr.tr[0].l && tr.tr[0].l.i) {
              definitions.push(tr.tr[0].l.i.join(' '));
            }
          }
        }
      }

      if (definitions.length === 0 && data.fanyi && data.fanyi.trs) {
        definitions.push(data.fanyi.trs);
      }

      if (definitions.length > 0 || phonetic) {
        return {
          word: cleanWord,
          phonetic,
          audioUrl,
          definitions,
        };
      }
    }
  } catch (e) {
    console.warn('[V8 Background] Youdao fetch failed, fallback to FreeDict:', e);
  }

  // 2. 备用词典：Free Dictionary API
  try {
    const freeDictUrl = `https://api.dictionaryapi.dev/api/v2/entries/en/${encodeURIComponent(cleanWord)}`;
    const resp = await fetch(freeDictUrl);
    if (resp.ok) {
      const list = await resp.json();
      if (Array.isArray(list) && list.length > 0) {
        const item = list[0];
        let phonetic = item.phonetic || '';
        let audioUrl = '';
        if (item.phonetics && Array.isArray(item.phonetics)) {
          for (const p of item.phonetics) {
            if (!phonetic && p.text) phonetic = p.text;
            if (p.audio && !audioUrl) audioUrl = p.audio;
          }
        }
        const definitions = [];
        if (item.meanings && Array.isArray(item.meanings)) {
          for (const m of item.meanings) {
            const pos = m.partOfSpeech ? `${m.partOfSpeech}. ` : '';
            if (m.definitions && Array.isArray(m.definitions)) {
              for (const d of m.definitions.slice(0, 3)) {
                if (d.definition) definitions.push(`${pos}${d.definition}`);
              }
            }
          }
        }
        return {
          word: cleanWord,
          phonetic,
          audioUrl,
          definitions,
        };
      }
    }
  } catch (e) {
    console.warn('[V8 Background] FreeDict fetch failed:', e);
  }

  return {
    word: cleanWord,
    phonetic: '',
    audioUrl: '',
    definitions: [],
  };
}

