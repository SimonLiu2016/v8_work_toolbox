// V8 工作工具箱 - 浏览器伴侣网页内原地划词气泡 (Content Script)

(function () {
  'use strict';

  let currentBubbleHost = null;
  let shadowRoot = null;
  let lastSelectionText = '';
  let lastSelectionRect = null;
  let hideTimeout = null;

  // 监听网页鼠标松开事件
  document.addEventListener('mouseup', onMouseUp, true);
  document.addEventListener('mousedown', onMouseDown, true);

  // 监听来自 background.js 的直接指令（如右键菜单触发）
  chrome.runtime.onMessage.addListener((request, sender, sendResponse) => {
    if (request.action === 'lookupSelection') {
      const text = request.text || window.getSelection().toString().trim();
      if (text) {
        showBubble(text, lastSelectionRect, true);
        sendResponse({ success: true });
      }
    }
  });

  function onMouseDown(e) {
    if (currentBubbleHost && !currentBubbleHost.contains(e.target)) {
      dismissBubble();
    }
  }

  function onMouseUp(e) {
    // 忽略点击在自身浮层内部的事件
    if (currentBubbleHost && currentBubbleHost.contains(e.target)) return;

    setTimeout(() => {
      const selection = window.getSelection();
      const text = selection ? selection.toString().trim() : '';

      // 仅当选中文本为 1 到 60 个字符时触发
      if (!text || text.length > 80 || /^[\s\d.,;?!@#$%^&*()_+=\-[\]{}|\\/<>`~]*$/.test(text)) {
        if (!currentBubbleHost || !shadowRoot.querySelector('.v8-card')) {
          dismissBubble();
        }
        return;
      }

      if (selection.rangeCount > 0) {
        const range = selection.getRangeAt(0);
        const rect = range.getBoundingClientRect();
        if (rect.width === 0 && rect.height === 0) return;

        lastSelectionText = text;
        lastSelectionRect = rect;

        // 展示迷你触发按钮
        showMiniTrigger(text, rect);
      }
    }, 50);
  }

  function getOrCreateHost() {
    if (!currentBubbleHost) {
      currentBubbleHost = document.createElement('div');
      currentBubbleHost.id = 'v8-companion-bubble-host';
      currentBubbleHost.style.position = 'absolute';
      currentBubbleHost.style.top = '0px';
      currentBubbleHost.style.left = '0px';
      currentBubbleHost.style.zIndex = '2147483647';
      currentBubbleHost.style.pointerEvents = 'auto';
      document.documentElement.appendChild(currentBubbleHost);
      shadowRoot = currentBubbleHost.attachShadow({ mode: 'open' });
    }
    return shadowRoot;
  }

  function dismissBubble() {
    if (currentBubbleHost) {
      currentBubbleHost.remove();
      currentBubbleHost = null;
      shadowRoot = null;
    }
    if (hideTimeout) clearTimeout(hideTimeout);
  }

  // 展示微型触发按钮（V8 Logo 悬浮按钮）
  function showMiniTrigger(text, rect) {
    const shadow = getOrCreateHost();
    const iconUrl = chrome.runtime.getURL('icons/icon-32.png');

    const top = rect.bottom + window.scrollY + 6;
    let left = rect.right + window.scrollX - 24;
    if (left < 10) left = 10;

    shadow.innerHTML = `
      <style>
        .v8-mini-btn {
          position: absolute;
          top: ${top}px;
          left: ${left}px;
          width: 26px;
          height: 26px;
          border-radius: 6px;
          background: #ffffff;
          box-shadow: 0 4px 12px rgba(0, 0, 0, 0.15), 0 0 0 1px rgba(0, 0, 0, 0.08);
          cursor: pointer;
          display: flex;
          align-items: center;
          justify-content: center;
          transition: transform 0.15s ease, box-shadow 0.15s ease;
          animation: v8-pop 0.15s ease-out;
          user-select: none;
        }
        .v8-mini-btn:hover {
          transform: scale(1.1);
          box-shadow: 0 6px 16px rgba(99, 102, 241, 0.3), 0 0 0 1px #6366f1;
        }
        .v8-mini-btn img {
          width: 16px;
          height: 16px;
          pointer-events: none;
        }
        @keyframes v8-pop {
          0% { transform: scale(0.6); opacity: 0; }
          100% { transform: scale(1); opacity: 1; }
        }
      </style>
      <div class="v8-mini-btn" title="V8 快速查词 / 存笔记">
        <img src="${iconUrl}" alt="V8" />
      </div>
    `;

    const btn = shadow.querySelector('.v8-mini-btn');
    btn.addEventListener('click', (e) => {
      e.stopPropagation();
      showBubble(text, rect, false);
    });

    if (hideTimeout) clearTimeout(hideTimeout);
    hideTimeout = setTimeout(() => {
      if (shadow.querySelector('.v8-mini-btn')) dismissBubble();
    }, 4500);
  }

  // 展开完整的高保真原地查词卡片（浅色/深色自适应，1:1 豆包体验）
  function showBubble(text, rect, immediate) {
    if (hideTimeout) clearTimeout(hideTimeout);
    const shadow = getOrCreateHost();

    // 默认居中贴靠选区下方，若靠底则贴靠上方
    const cardWidth = 340;
    const cardHeightEst = 220;
    const scrollX = window.scrollX;
    const scrollY = window.scrollY;

    let top = (rect ? rect.bottom : 100) + scrollY + 8;
    if (rect && rect.bottom + cardHeightEst > window.innerHeight && rect.top > cardHeightEst + 20) {
      top = rect.top + scrollY - cardHeightEst - 8;
    }

    let left = rect ? (rect.left + rect.width / 2 - cardWidth / 2 + scrollX) : 100;
    if (left < 12) left = 12;
    if (left + cardWidth > window.innerWidth - 12) {
      left = window.innerWidth - cardWidth - 12;
    }

    shadow.innerHTML = `
      <style>
        .v8-card {
          position: absolute;
          top: ${top}px;
          left: ${left}px;
          width: ${cardWidth}px;
          background: #ffffff;
          color: #0f172a;
          border-radius: 12px;
          box-shadow: 0 10px 30px -5px rgba(0, 0, 0, 0.2), 0 0 0 1px rgba(0, 0, 0, 0.08);
          font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, "Helvetica Neue", sans-serif;
          font-size: 13px;
          line-height: 1.5;
          z-index: 2147483647;
          overflow: hidden;
          animation: v8-fade-in 0.18s ease-out;
        }
        @media (prefers-color-scheme: dark) {
          .v8-card {
            background: #252528;
            color: #f1f5f9;
            box-shadow: 0 12px 36px rgba(0, 0, 0, 0.45), 0 0 0 1px rgba(255, 255, 255, 0.12);
          }
        }
        .v8-header {
          display: flex;
          align-items: center;
          justify-content: space-between;
          padding: 10px 14px;
          background: rgba(0, 0, 0, 0.02);
          border-bottom: 1px solid rgba(0, 0, 0, 0.06);
        }
        .v8-word-title {
          font-size: 16px;
          font-weight: 700;
          color: #6366f1;
        }
        .v8-phonetic {
          font-size: 12px;
          color: #64748b;
          margin-left: 6px;
        }
        .v8-audio-btn {
          cursor: pointer;
          background: none;
          border: none;
          padding: 2px 6px;
          font-size: 13px;
          border-radius: 4px;
          color: #6366f1;
        }
        .v8-audio-btn:hover { background: rgba(99, 102, 241, 0.12); }
        .v8-close-btn {
          cursor: pointer;
          background: none;
          border: none;
          font-size: 16px;
          color: #94a3b8;
          padding: 0 4px;
        }
        .v8-close-btn:hover { color: #0f172a; }
        .v8-body {
          padding: 12px 14px;
          max-height: 220px;
          overflow-y: auto;
        }
        .v8-loading {
          display: flex;
          align-items: center;
          justify-content: center;
          padding: 24px 0;
          color: #94a3b8;
        }
        .v8-def-group { margin-bottom: 8px; }
        .v8-pos {
          display: inline-block;
          font-size: 11px;
          font-weight: 600;
          padding: 1px 6px;
          border-radius: 4px;
          background: #e0e7ff;
          color: #4338ca;
          margin-right: 6px;
        }
        .v8-footer {
          display: flex;
          align-items: center;
          justify-content: flex-end;
          gap: 8px;
          padding: 8px 12px;
          background: rgba(0, 0, 0, 0.02);
          border-top: 1px solid rgba(0, 0, 0, 0.06);
        }
        .v8-btn {
          padding: 5px 10px;
          border-radius: 6px;
          font-size: 12px;
          font-weight: 500;
          cursor: pointer;
          border: none;
          transition: background 0.15s;
        }
        .v8-btn-secondary {
          background: rgba(0, 0, 0, 0.06);
          color: #334155;
        }
        .v8-btn-secondary:hover { background: rgba(0, 0, 0, 0.1); }
        .v8-btn-primary {
          background: #6366f1;
          color: #ffffff;
        }
        .v8-btn-primary:hover { background: #4f46e5; }
        @keyframes v8-fade-in {
          0% { opacity: 0; transform: translateY(4px); }
          100% { opacity: 1; transform: translateY(0); }
        }
      </style>
      <div class="v8-card">
        <div class="v8-header">
          <div style="display: flex; align-items: baseline;">
            <span class="v8-word-title">${escapeHtml(text)}</span>
            <span class="v8-phonetic" id="v8-ph"></span>
            <button class="v8-audio-btn" id="v8-speak-btn" style="display:none;" title="发音">🔊</button>
          </div>
          <button class="v8-close-btn" id="v8-close">✕</button>
        </div>
        <div class="v8-body" id="v8-content">
          <div class="v8-loading">查询中…</div>
        </div>
        <div class="v8-footer">
          <button class="v8-btn v8-btn-secondary" id="v8-btn-note">📝 存入笔记</button>
          <button class="v8-btn v8-btn-primary" id="v8-btn-vocab">📚 加生词本</button>
        </div>
      </div>
    `;

    shadow.querySelector('#v8-close').addEventListener('click', dismissBubble);

    // 存入笔记
    shadow.querySelector('#v8-btn-note').addEventListener('click', () => {
      const pageUrl = window.location.href;
      const pageTitle = document.title || '';
      window.location.href = `v8toolbox://savenote?text=${encodeURIComponent(text)}&url=${encodeURIComponent(pageUrl)}&title=${encodeURIComponent(pageTitle)}`;
      const btn = shadow.querySelector('#v8-btn-note');
      btn.innerText = '已发送 ✓';
      btn.disabled = true;
      setTimeout(dismissBubble, 1200);
    });

    // 加入生词本
    shadow.querySelector('#v8-btn-vocab').addEventListener('click', () => {
      window.location.href = `v8toolbox://lookup?text=${encodeURIComponent(text)}`;
      const btn = shadow.querySelector('#v8-btn-vocab');
      btn.innerText = '已呼起生词本 ✓';
      setTimeout(dismissBubble, 1200);
    });

    // 发起极速词典查询（直连有道词典 API，毫秒级无延迟）
    fetchDictionary(text, shadow);
  }

  // 极速高可用词典解析：通过 background 代理请求，彻底绕过宿主页面的 CSP / CORS 限制
  function fetchDictionary(word, shadow) {
    const contentEl = shadow.querySelector('#v8-content');
    const phEl = shadow.querySelector('#v8-ph');
    const speakBtn = shadow.querySelector('#v8-speak-btn');

    chrome.runtime.sendMessage({ action: 'fetchDictionary', word: word }, (response) => {
      if (chrome.runtime.lastError || !response || !response.success) {
        contentEl.innerHTML = `
          <div style="color: #64748b; text-align: center; padding: 10px 0;">
            查询失败
            <div style="margin-top: 8px;">
              <button class="v8-btn v8-btn-primary" id="v8-fallback-desktop">在桌面端打开</button>
            </div>
          </div>
        `;
        shadow.querySelector('#v8-fallback-desktop')?.addEventListener('click', () => {
          window.location.href = `v8toolbox://lookup?text=${encodeURIComponent(word)}`;
          dismissBubble();
        });
        return;
      }

      const data = response.data;
      const phonetic = data.phonetic || '';
      const audioUrl = data.audioUrl || '';
      const definitions = data.definitions || [];

      if (phonetic && phEl) {
        phEl.innerText = phonetic;
      }

      if (audioUrl && speakBtn) {
        speakBtn.style.display = 'inline-block';
        speakBtn.onclick = () => {
          new Audio(audioUrl).play().catch(() => {});
        };
      }

      if (definitions.length > 0) {
        contentEl.innerHTML = definitions.map((def) => {
          const match = def.match(/^([a-z]+\.)\s*(.*)$/i);
          if (match) {
            return `<div class="v8-def-group"><span class="v8-pos">${match[1]}</span><span>${escapeHtml(match[2])}</span></div>`;
          }
          return `<div class="v8-def-group"><span>${escapeHtml(def)}</span></div>`;
        }).join('');
      } else {
        contentEl.innerHTML = `
          <div style="color: #64748b; text-align: center; padding: 12px 0;">
            本地词典未收录该词条
            <div style="margin-top: 10px;">
              <button class="v8-btn v8-btn-secondary" id="v8-ask-ai-btn">问 AI 深度解析</button>
            </div>
          </div>
        `;
        shadow.querySelector('#v8-ask-ai-btn')?.addEventListener('click', () => {
          window.location.href = `v8toolbox://lookup?text=${encodeURIComponent(word)}`;
          dismissBubble();
        });
      }
    });
  }

  function escapeHtml(str) {
    return str.replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;').replace(/"/g, '&quot;');
  }
})();
