#!/usr/bin/env python3
"""
印象笔记导入脚本
支持三种迁移方式：
1. detect_local / import_local: 直接从本机已安装的印象笔记/Evernote 客户端 SQLite 及内容缓存目录一键免密全量迁移
2. parse_notes: 解析 .notes / .enex 离线文件，自动将文件主名作为笔记本归类，并尝试关联本地客户端明文解密
3. list / fetch / export_all: 通过 Evernote 开放 API 获取数据

用法:
  python3 evernote_import.py detect_local                   # 探测本机是否存在印象笔记客户端数据
  python3 evernote_import.py import_local --output <FILE>   # 从本机客户端全量导出笔记本与明文笔记
  python3 evernote_import.py parse_notes --file <FILE>      # 解析 .notes 离线文件
  python3 evernote_import.py list                           # API 模式: 列出所有笔记元数据
  python3 evernote_import.py fetch --guid <GUID>            # API 模式: 获取单条笔记内容
  python3 evernote_import.py export_all --output <FILE>     # API 模式: 批量导出全部笔记
"""

import argparse
import base64
from collections import defaultdict
from datetime import datetime, timezone
import glob
import json
import os
import plistlib
import sqlite3
import subprocess
import sys
import urllib.parse
import xml.etree.ElementTree as ET

# Monkey-patch for Python 3.13+ compatibility
import inspect
if not hasattr(inspect, 'getargspec'):
    inspect.getargspec = inspect.getfullargspec

import hashlib
import html
import re

COREDATA_EPOCH_OFFSET = 978307200  # 2001-01-01 00:00:00 UTC in Unix seconds


def convert_enml_to_markdown(enml_content):
    """将 Evernote ENML / HTML 转换为整洁的 Markdown"""
    if not enml_content:
        return ""
    try:
        codeblocks = []

        def store_code(raw_code):
            code = re.sub(r'<br\s*/?>', '\n', raw_code, flags=re.I)
            code = re.sub(r'</div>\s*<div[^>]*>', '\n', code, flags=re.I)
            code = re.sub(r'</p>\s*<p[^>]*>', '\n', code, flags=re.I)
            code = re.sub(r'<[^>]+>', '', code)
            code = html.unescape(code)
            idx = len(codeblocks)
            codeblocks.append(code.strip('\r\n'))
            return f"\n\n__EVERNOTE_CODEBLOCK_{idx}__\n\n"

        # 0. 预处理思维导图（提取 SVG 矢量图与结构树 JSON）
        mindmap_match = re.search(r'<img[^>]*src=["\'](data:image/svg\+xml;charset=utf-8,([^"\']+))["\'][^>]*>', enml_content)
        mindmap_json_match = re.search(r'<center[^>]*style=["\'][^"\']*display:\s*none[^"\']*["\'][^>]*>(\{.*?\})</center>', enml_content, re.DOTALL)
        if mindmap_match or mindmap_json_match:
            svg_data = ''
            svg_hash = ''
            if mindmap_match:
                svg_data = urllib.parse.unquote(mindmap_match.group(2))
                svg_hash = hashlib.md5(svg_data.encode('utf-8')).hexdigest()
            tree_data = {}
            if mindmap_json_match:
                try:
                    tree_str = mindmap_json_match.group(1)
                    tree_str_fixed = re.sub(r'\\([^"\\/bfnrtu])', r'\1', tree_str)
                    tree_data = json.loads(tree_str_fixed, strict=False)
                except Exception:
                    pass
            mindmap_payload = {
                'type': 'mindmap',
                'hash': svg_hash,
                'tree': tree_data,
            }
            placeholder = f"\n\n```mindmap\n{json.dumps(mindmap_payload, ensure_ascii=False)}\n```\n\n"
            if mindmap_match:
                enml_content = enml_content.replace(mindmap_match.group(0), placeholder)
            if mindmap_json_match:
                if not mindmap_match:
                    enml_content = enml_content.replace(mindmap_json_match.group(0), placeholder)
                else:
                    enml_content = enml_content.replace(mindmap_json_match.group(0), '')

        # 1.1 预处理标准 HTML pre/code 代码块
        def replace_pre_code(m):
            return store_code(m.group(1))

        enml = re.sub(r'<pre[^>]*><code[^>]*>(.*?)</code></pre>', replace_pre_code, enml_content, flags=re.DOTALL | re.I)
        enml = re.sub(r'<pre[^>]*>(.*?)</pre>', replace_pre_code, enml, flags=re.DOTALL | re.I)

        # 1.2 预处理网页剪藏 / ChatGPT 风格带 "Copy code" 的代码块
        def replace_chatgpt_block(m):
            return store_code(m.group(1))

        enml = re.sub(
            r'<div[^>]*>(?:<div[^>]*>[\s\S]*?Copy\s+code[\s\S]*?</div>)?\s*<div[^>]*>\s*<span[^>]*style=[\'"][^\'"]*color:\s*rgb\(255,\s*255,\s*255\)[\'"][^>]*>([\s\S]*?)</span>\s*</div>\s*</div>',
            replace_chatgpt_block,
            enml,
            flags=re.I
        )

        # 1.3 状态感知提取所有 -en-codeblock 或 --en-codeblock 的 div 代码块（支持多层 div 嵌套）
        pattern = re.compile(r'<div\s+[^>]*style=[\'\"][^\'\"]*-{1,2}en-codeblock:true[^\'\"]*[\'\"][^>]*>', re.I)
        pos = 0
        chunks = []
        while pos < len(enml):
            m = pattern.search(enml, pos)
            if not m:
                chunks.append(enml[pos:])
                break

            chunks.append(enml[pos:m.start()])
            start_idx = m.end()

            # 寻找配对闭合的 </div>
            depth = 1
            curr = start_idx
            while curr < len(enml) and depth > 0:
                next_open = enml.find('<div', curr)
                next_close = enml.find('</div>', curr)

                if next_close == -1:
                    break

                if next_open != -1 and next_open < next_close:
                    depth += 1
                    curr = next_open + 4
                else:
                    depth -= 1
                    curr = next_close + 6

            if depth == 0:
                block_content = enml[start_idx:curr - 6]
                placeholder = store_code(block_content)
                chunks.append(placeholder)
                pos = curr
            else:
                chunks.append(enml[m.start():m.end()])
                pos = m.end()

        enml = ''.join(chunks)

        # 2. 预处理待办勾选框
        enml = re.sub(r'<en-todo\s+checked=[\'"]true[\'"][^>]*/>', '\n- [x] ', enml, flags=re.I)
        enml = re.sub(r'<en-todo[^>]*/>', '\n- [ ] ', enml, flags=re.I)

        # 3. 预处理媒体资源
        enml = re.sub(r'<en-media[^>]*hash=[\'"]([a-f0-9]+)[\'"][^>]*>(?:</en-media>)?', r'\n\n![image](en-media://\1)\n\n', enml, flags=re.I)

        import html2text
        h = html2text.HTML2Text()
        h.ignore_links = False
        h.ignore_images = False
        h.body_width = 0
        h.unicode_snob = True
        md = h.handle(enml)

        # 4. 还原代码块为标准的 Markdown 围栏代码块
        for idx, code in enumerate(codeblocks):
            md = md.replace(f"__EVERNOTE_CODEBLOCK_{idx}__", f"```\n{code}\n```")

        return md.strip()
    except Exception as e:
        return enml_content


def find_local_evernote():
    """自动扫描并返回本机安装的印象笔记/Evernote 客户端数据路径"""
    home = os.path.expanduser('~')
    candidate_roots = [
        os.path.join(home, 'Library/Containers/com.yinxiang.Mac/Data/Library/Application Support/com.yinxiang.Mac/accounts/app.yinxiang.com'),
        os.path.join(home, 'Library/Containers/com.evernote.Evernote/Data/Library/Application Support/com.evernote.Evernote/accounts/www.evernote.com'),
        os.path.join(home, 'Library/Application Support/com.yinxiang.Mac/accounts/app.yinxiang.com'),
        os.path.join(home, 'Library/Application Support/Evernote/accounts/www.evernote.com'),
    ]

    for root in candidate_roots:
        if not os.path.exists(root):
            continue
        try:
            account_dirs = [d for d in os.listdir(root) if os.path.isdir(os.path.join(root, d))]
        except Exception:
            continue

        for acct in account_dirs:
            acct_dir = os.path.join(root, acct)
            db_path = os.path.join(acct_dir, 'localNoteStore', 'LocalNoteStore.sqlite')
            content_dir = os.path.join(acct_dir, 'content')
            if os.path.exists(db_path) and os.path.exists(content_dir):
                try:
                    conn = sqlite3.connect(f'file:{db_path}?mode=ro', uri=True)
                    nb_count = conn.execute('SELECT count(*) FROM ZENNOTEBOOK').fetchone()[0]
                    note_count = conn.execute('SELECT count(*) FROM ZENNOTE WHERE ZACTIVE = 1').fetchone()[0]
                    tag_count = conn.execute('SELECT count(*) FROM ZENTAG').fetchone()[0]
                    conn.close()
                    if note_count > 0 or nb_count > 0:
                        return {
                            'detected': True,
                            'app': '印象笔记' if 'yinxiang' in root else 'Evernote',
                            'account': acct,
                            'db_path': db_path,
                            'content_dir': content_dir,
                            'notebook_count': nb_count,
                            'note_count': note_count,
                            'tag_count': tag_count,
                        }
                except Exception:
                    continue
    return {'detected': False}


def import_local_client(output_file=None):
    """直接从本机客户端 SQLite 与 content/ 缓存目录全量导出数据"""
    local = find_local_evernote()
    if not local.get('detected'):
        return {'error': '未在系统中检测到印象笔记或 Evernote 客户端数据'}

    db_path = local['db_path']
    content_dir = local['content_dir']

    conn = sqlite3.connect(f'file:{db_path}?mode=ro', uri=True)

    # 1. 笔记本映射 (Z_PK -> ZNAME, ZSTACK)
    notebooks = {}
    notebook_stacks = {}
    for row in conn.execute('SELECT Z_PK, ZNAME, ZSTACK FROM ZENNOTEBOOK').fetchall():
        notebooks[row[0]] = row[1] or '默认笔记本'
        notebook_stacks[row[0]] = row[2]

    # 2. 标签映射 (Z_PK -> ZNAME)
    tags = {}
    for row in conn.execute('SELECT Z_PK, ZNAME FROM ZENTAG').fetchall():
        tags[row[0]] = row[1]

    # 3. 笔记与标签关联 (Z_10NOTES -> list of tag names)
    note_tags_map = defaultdict(list)
    try:
        for row in conn.execute('SELECT Z_10NOTES, Z_23TAGS FROM Z_10TAGS').fetchall():
            tag_name = tags.get(row[1])
            if tag_name:
                note_tags_map[row[0]].append(tag_name)
    except Exception:
        pass

    # 4. 笔记附件信息 (ZNOTE -> list of ZENRESOURCE)
    note_res_map = defaultdict(list)
    try:
        for row in conn.execute('SELECT ZNOTE, ZLOCALUUID, ZFILENAME, ZMIME, ZDATAHASH FROM ZENRESOURCE').fetchall():
            h_hex = row[4].hex() if row[4] else None
            note_res_map[row[0]].append({
                'uuid': row[1],
                'filename': row[2],
                'mime': row[3] or 'application/octet-stream',
                'hash': h_hex,
            })
    except Exception:
        pass

    # 5. 遍历所有未删除的活跃笔记 (ZACTIVE = 1)
    notes_rows = conn.execute(
        'SELECT Z_PK, ZTITLE, ZLOCALUUID, ZGUID, ZNOTEBOOK, ZDATECREATED, ZDATEUPDATED '
        'FROM ZENNOTE WHERE ZACTIVE = 1 ORDER BY ZDATECREATED DESC'
    ).fetchall()

    notes_result = []
    total_notes = len(notes_rows)

    for i, row in enumerate(notes_rows):
        pk, title, local_uuid, guid, nb_pk, date_created, date_updated = row
        title = title or '无标题笔记'
        nb_name = notebooks.get(nb_pk, '默认笔记本')
        note_tags = note_tags_map.get(pk, [])

        # 时间转换
        created_iso = None
        if date_created is not None:
            ts = date_created + COREDATA_EPOCH_OFFSET
            created_iso = datetime.fromtimestamp(ts, tz=timezone.utc).isoformat()

        updated_iso = None
        if date_updated is not None:
            ts = date_updated + COREDATA_EPOCH_OFFSET
            updated_iso = datetime.fromtimestamp(ts, tz=timezone.utc).isoformat()

        # 读取正文 content.enml
        markdown = ''
        note_folder = os.path.join(content_dir, local_uuid) if local_uuid else None
        if note_folder and os.path.isdir(note_folder):
            enml_path = os.path.join(note_folder, 'content.enml')
            if os.path.exists(enml_path):
                try:
                    with open(enml_path, 'r', encoding='utf-8', errors='ignore') as f:
                        raw_enml = f.read()
                    markdown = convert_enml_to_markdown(raw_enml)
                except Exception as e:
                    markdown = f'读取笔记正文失败: {e}'

        # 读取附件资源
        resources = []
        if note_folder and os.path.isdir(note_folder):
            # 先按 ZENRESOURCE 关联查找
            attached_uuids = set()
            for res_meta in note_res_map.get(pk, []):
                r_uuid = res_meta['uuid']
                attached_uuids.add(r_uuid)
                matched_files = glob.glob(os.path.join(note_folder, f'{r_uuid}.*'))
                for fpath in matched_files:
                    if fpath.endswith('.en-reco'):
                        continue
                    try:
                        with open(fpath, 'rb') as f:
                            bdata = f.read()
                        ext = os.path.splitext(fpath)[1].lstrip('.')
                        h_val = res_meta.get('hash')
                        if not h_val:
                            h_val = hashlib.md5(bdata).hexdigest()
                        resources.append({
                            'filename': res_meta['filename'] or f'attachment.{ext}',
                            'mime': res_meta['mime'],
                            'base64': base64.b64encode(bdata).decode('ascii'),
                            'hash': h_val,
                        })
                    except Exception:
                        pass

            # 遍历文件夹补充其他图片文件（排除系统预生成缓存文件）
            ignored_prefixes = ('content', 'snippet', 'card', 'lower-card', 'quickLook')
            for fname in os.listdir(note_folder):
                if any(fname.startswith(p) for p in ignored_prefixes) or fname.endswith('.en-reco'):
                    continue
                uuid_part = os.path.splitext(fname)[0]
                if uuid_part in attached_uuids:
                    continue
                fpath = os.path.join(note_folder, fname)
                if os.path.isfile(fpath):
                    try:
                        with open(fpath, 'rb') as f:
                            bdata = f.read()
                        ext = os.path.splitext(fname)[1].lstrip('.').lower()
                        mime = f'image/{ext}' if ext in ('png', 'jpg', 'jpeg', 'gif', 'webp') else 'application/octet-stream'
                        resources.append({
                            'filename': fname,
                            'mime': mime,
                            'base64': base64.b64encode(bdata).decode('ascii'),
                            'hash': hashlib.md5(bdata).hexdigest(),
                        })
                    except Exception:
                        pass

            # 提取思维导图的 SVG 矢量图资源
            if raw_enml and 'data:image/svg+xml' in raw_enml:
                svg_m = re.search(r'src=["\'](data:image/svg\+xml;charset=utf-8,([^"\']+))["\']', raw_enml)
                if svg_m:
                    svg_decoded = urllib.parse.unquote(svg_m.group(2))
                    svg_bytes = svg_decoded.encode('utf-8')
                    svg_hash = hashlib.md5(svg_bytes).hexdigest()
                    resources.append({
                        'filename': f'mindmap_{svg_hash[:8]}.svg',
                        'mime': 'image/svg+xml',
                        'base64': base64.b64encode(svg_bytes).decode('ascii'),
                        'hash': svg_hash,
                    })

        notes_result.append({
            'guid': guid,
            'title': title,
            'notebook': nb_name,
            'stack': notebook_stacks.get(nb_pk),
            'tags': note_tags,
            'markdown': markdown,
            'created': created_iso,
            'updated': updated_iso,
            'resources': resources,
        })
        if (i + 1) % 50 == 0 or (i + 1) == total_notes:
            print(f'[{i + 1}/{total_notes}] {title}', file=sys.stderr)

    conn.close()

    notebooks_payload = [
        {'name': name, 'stack': notebook_stacks.get(pk)}
        for pk, name in notebooks.items()
    ]

    result = {
        'account': local['account'],
        'app': local['app'],
        'total': len(notes_result),
        'notebooks': notebooks_payload,
        'tags': list(tags.values()),
        'notes': notes_result,
    }

    if output_file:
        with open(output_file, 'w', encoding='utf-8') as f:
            json.dump(result, f, ensure_ascii=False, indent=2)
        return {'output': output_file, 'total': len(notes_result)}

    return result


def parse_notes_file(file_path):
    """解析 .notes / .enex 文件，若正文加密且存在本地客户端，则智能关联补全明文"""
    tree = ET.parse(file_path)
    root = tree.getroot()

    default_notebook = os.path.splitext(os.path.basename(file_path))[0]
    local_info = find_local_evernote()
    local_db_notes = {}  # title -> {local_uuid, pk}

    if local_info.get('detected'):
        try:
            conn = sqlite3.connect(f"file:{local_info['db_path']}?mode=ro", uri=True)
            for r in conn.execute('SELECT ZTITLE, ZLOCALUUID, Z_PK FROM ZENNOTE WHERE ZACTIVE = 1').fetchall():
                if r[0]:
                    local_db_notes[r[0]] = (r[1], r[2])
            conn.close()
        except Exception:
            pass

    notes = []
    for note_el in root.findall('note'):
        title_el = note_el.find('title')
        title = title_el.text if title_el is not None and title_el.text else '无标题笔记'
        created_el = note_el.find('created')
        updated_el = note_el.find('updated')
        tags = [t.text for t in note_el.findall('tag') if t.text]
        notebook_el = note_el.find('notebook')
        notebook_name = notebook_el.text if (notebook_el is not None and notebook_el.text) else default_notebook

        content_el = note_el.find('content')
        is_encrypted = False
        markdown = None
        if content_el is not None:
            encoding = content_el.get('encoding', '')
            is_encrypted = 'aes' in encoding
            if not is_encrypted and content_el.text:
                markdown = convert_enml_to_markdown(content_el.text)

        resources = []
        for res_el in note_el.findall('resource'):
            data_el = res_el.find('data')
            mime_el = res_el.find('mime')
            fname_el = res_el.find('filename')
            if data_el is not None and data_el.text:
                encoding = data_el.get('encoding', '')
                if 'aes' not in encoding:
                    bdata_str = data_el.text.strip()
                    try:
                        bdata = base64.b64decode(bdata_str)
                        h_val = hashlib.md5(bdata).hexdigest()
                    except Exception:
                        h_val = None
                    resources.append({
                        'mime': mime_el.text if mime_el is not None else None,
                        'filename': fname_el.text if fname_el is not None else None,
                        'base64': bdata_str,
                        'hash': h_val,
                    })

        # 本地明文回退机制
        if (is_encrypted or len(resources) == 0) and title in local_db_notes and local_info.get('content_dir'):
            local_uuid = local_db_notes[title][0]
            if local_uuid:
                note_folder = os.path.join(local_info['content_dir'], local_uuid)
                enml_path = os.path.join(note_folder, 'content.enml')
                if os.path.exists(enml_path) and (is_encrypted or not markdown or '[加密内容' in markdown):
                    try:
                        with open(enml_path, 'r', encoding='utf-8', errors='ignore') as f:
                            raw_enml = f.read()
                        markdown = convert_enml_to_markdown(raw_enml)
                        is_encrypted = False  # 已成功还原为明文
                    except Exception:
                        pass
                # 补全本地附件资源
                if os.path.isdir(note_folder) and len(resources) == 0:
                    ignored_prefixes = ('content', 'snippet', 'card', 'lower-card', 'quickLook')
                    for fname in os.listdir(note_folder):
                        if any(fname.startswith(p) for p in ignored_prefixes) or fname.endswith('.en-reco'):
                            continue
                        fpath = os.path.join(note_folder, fname)
                        if os.path.isfile(fpath):
                            try:
                                with open(fpath, 'rb') as f:
                                    bdata = f.read()
                                ext = os.path.splitext(fname)[1].lstrip('.').lower()
                                mime = f'image/{ext}' if ext in ('png', 'jpg', 'jpeg', 'gif', 'webp') else 'application/octet-stream'
                                resources.append({
                                    'filename': fname,
                                    'mime': mime,
                                    'base64': base64.b64encode(bdata).decode('ascii'),
                                    'hash': hashlib.md5(bdata).hexdigest(),
                                })
                            except Exception:
                                pass

        # 提取思维导图的 SVG 矢量图资源
        if markdown and '```mindmap' in markdown:
            m_payload = re.search(r'```mindmap\s*(\{.*?\})\s*```', markdown, re.DOTALL)
            if m_payload:
                try:
                    p_data = json.loads(m_payload.group(1))
                    s_data = p_data.get('svg', '')
                    s_hash = p_data.get('hash', '')
                    if s_data and s_hash:
                        s_bytes = s_data.encode('utf-8')
                        resources.append({
                            'filename': f'mindmap_{s_hash[:8]}.svg',
                            'mime': 'image/svg+xml',
                            'base64': base64.b64encode(s_bytes).decode('ascii'),
                            'hash': s_hash,
                        })
                except Exception:
                    pass

        notes.append({
            'title': title,
            'created': created_el.text if created_el is not None else None,
            'updated': updated_el.text if updated_el is not None else None,
            'tags': tags,
            'notebook': notebook_name,
            'is_encrypted': is_encrypted,
            'markdown': markdown,
            'resources': resources,
        })

    return {
        'total': len(notes),
        'default_notebook': default_notebook,
        'encrypted': sum(1 for n in notes if n['is_encrypted']),
        'notes': notes,
    }


def get_tokens():
    """从 macOS 钥匙串获取所有 Evernote Token"""
    tokens = []
    accounts = ['22012340/Evernote-China/smd', '54282628/Evernote-China/smd']
    for acct in accounts:
        try:
            raw = subprocess.check_output(
                ['security', 'find-generic-password', '-s', 'Evernote', '-a', acct, '-w'],
                stderr=subprocess.DEVNULL, timeout=2
            ).decode().strip()
            plist = plistlib.loads(bytes.fromhex(raw))
            for obj in plist.get('$objects', []):
                if isinstance(obj, str) and obj.startswith('S=s'):
                    tokens.append({'token': obj, 'account': acct})
                    break
        except Exception:
            continue
    return tokens


def get_note_store(token):
    """连接印象笔记 API，返回 NoteStore"""
    from evernote.api.client import EvernoteClient
    client = EvernoteClient(token=token, sandbox=False, service_host='app.yinxiang.com')
    return client.get_note_store()


def list_notes(token_info):
    """API 模式: 列出所有笔记元数据"""
    from evernote.edam.notestore.ttypes import NoteFilter, NotesMetadataResultSpec
    note_store = get_note_store(token_info['token'])
    nf = NoteFilter()
    spec = NotesMetadataResultSpec()
    spec.includeTitle = True
    spec.includeCreated = True
    spec.includeUpdated = True
    spec.includeTagGuids = True
    spec.includeNotebookGuid = True

    all_notes = []
    offset = 0
    while True:
        results = note_store.findNotesMetadata(token_info['token'], nf, offset, 100, spec)
        all_notes.extend(results.notes)
        if len(all_notes) >= results.totalNotes:
            break
        offset += 100

    notebooks = {nb.guid: nb.name for nb in note_store.listNotebooks()}
    tags = {tag.guid: tag.name for tag in note_store.listTags()}

    notes_meta = []
    for meta in all_notes:
        note_tags = [tags.get(g, g) for g in (meta.tagGuids or [])]
        notes_meta.append({
            'guid': meta.guid,
            'title': meta.title,
            'created': str(meta.created) if meta.created else None,
            'updated': str(meta.updated) if meta.updated else None,
            'notebook': notebooks.get(meta.notebookGuid, None),
            'tags': note_tags,
        })

    return {
        'account': token_info['account'],
        'total': len(notes_meta),
        'notebooks': list(notebooks.values()),
        'tags': list(tags.values()),
        'notes': notes_meta,
    }


def fetch_note(token_info, guid):
    """API 模式: 获取单条笔记内容"""
    note_store = get_note_store(token_info['token'])
    note = note_store.getNote(token_info['token'], guid, True, True, False, False)
    content = note.content
    if isinstance(content, bytes):
        content = content.decode('utf-8', errors='ignore')
    markdown = convert_enml_to_markdown(content)
    resources = []
    if note.resources:
        for r in note.resources:
            resources.append({
                'hash': r.data.bodyHash.hex() if r.data and r.data.bodyHash else None,
                'mime': r.mime,
                'size': len(r.data.body) if r.data else 0,
                'base64': base64.b64encode(r.data.body).decode() if r.data else None,
            })
    return {
        'guid': guid,
        'title': note.title,
        'markdown': markdown,
        'resources': resources,
    }


def export_all(token_info, output_file):
    """API 模式: 批量导出全部笔记"""
    meta = list_notes(token_info)
    note_store = get_note_store(token_info['token'])
    notes = []
    total = len(meta['notes'])
    for i, note_meta in enumerate(meta['notes']):
        try:
            note = note_store.getNote(token_info['token'], note_meta['guid'], True, True, False, False)
            content = note.content
            if isinstance(content, bytes):
                content = content.decode('utf-8', errors='ignore')
            markdown = convert_enml_to_markdown(content)
            resources = []
            if note.resources:
                for r in note.resources:
                    resources.append({
                        'hash': r.data.bodyHash.hex() if r.data and r.data.bodyHash else None,
                        'mime': r.mime,
                        'filename': r.attributes.fileName if r.attributes else None,
                        'base64': base64.b64encode(r.data.body).decode() if r.data else None,
                    })
            notes.append({
                'guid': note_meta['guid'],
                'title': note_meta['title'],
                'markdown': markdown,
                'notebook': note_meta.get('notebook'),
                'tags': note_meta.get('tags', []),
                'created': note_meta.get('created'),
                'updated': note_meta.get('updated'),
                'resources': resources,
            })
        except Exception as e:
            notes.append({
                'guid': note_meta['guid'],
                'title': note_meta['title'],
                'markdown': None,
                'error': str(e),
                'notebook': note_meta.get('notebook'),
                'tags': note_meta.get('tags', []),
                'created': note_meta.get('created'),
                'updated': note_meta.get('updated'),
                'resources': [],
            })

    result = {
        'account': token_info['account'],
        'total': len(notes),
        'notebooks': meta['notebooks'],
        'tags': meta['tags'],
        'notes': notes,
    }
    with open(output_file, 'w', encoding='utf-8') as f:
        json.dump(result, f, ensure_ascii=False, indent=2)
    return {'output': output_file, 'total': len(notes)}


def main():
    parser = argparse.ArgumentParser(description='Evernote / 印象笔记 迁移与导入工具')
    subparsers = parser.add_subparsers(dest='command')

    subparsers.add_parser('detect_local', help='探测本机是否存在印象笔记/Evernote 客户端数据')

    import_local_parser = subparsers.add_parser('import_local', help='从本机客户端直接全量提取所有笔记本与明文笔记')
    import_local_parser.add_argument('--output', help='输出 JSON 文件路径（可选，推荐）')

    parse_parser = subparsers.add_parser('parse_notes', help='解析 .notes / .enex 离线文件')
    parse_parser.add_argument('--file', required=True, help='.notes / .enex 文件路径')
    parse_parser.add_argument('--output', help='输出 JSON 文件路径（可选，推荐）')

    subparsers.add_parser('list', help='API 模式: 列出所有笔记元数据')
    fetch_parser = subparsers.add_parser('fetch', help='API 模式: 获取单条笔记内容')
    fetch_parser.add_argument('--guid', required=True, help='Note GUID')
    export_parser = subparsers.add_parser('export_all', help='API 模式: 批量导出全部笔记')
    export_parser.add_argument('--output', required=True, help='输出 JSON 文件路径')

    args = parser.parse_args()

    if args.command == 'detect_local':
        result = find_local_evernote()
        print(json.dumps(result, ensure_ascii=False, indent=2))
        return

    if args.command == 'import_local':
        result = import_local_client(args.output)
        if args.output:
            print(json.dumps(result, ensure_ascii=False, indent=2))
        else:
            print(json.dumps(result, ensure_ascii=False))
        return

    if args.command == 'parse_notes':
        result = parse_notes_file(args.file)
        if args.output:
            with open(args.output, 'w', encoding='utf-8') as f:
                json.dump(result, f, ensure_ascii=False, indent=2)
            print(json.dumps({'output': args.output, 'total': result['total']}, ensure_ascii=False, indent=2))
        else:
            print(json.dumps(result, ensure_ascii=False, indent=2))
        return

    # API 相关的处理
    tokens = get_tokens()
    if not tokens:
        print(json.dumps({'error': '未在钥匙串中找到 Evernote Token'}))
        sys.exit(1)

    token_info = None
    for t in tokens:
        try:
            meta = list_notes(t)
            if meta['total'] > 0:
                token_info = t
                break
        except Exception:
            continue

    if not token_info:
        print(json.dumps({'error': '未找到有效的 Evernote Token'}))
        sys.exit(1)

    if args.command == 'list':
        result = list_notes(token_info)
        print(json.dumps(result, ensure_ascii=False, indent=2))
    elif args.command == 'fetch':
        result = fetch_note(token_info, args.guid)
        print(json.dumps(result, ensure_ascii=False, indent=2))
    elif args.command == 'export_all':
        result = export_all(token_info, args.output)
        print(json.dumps(result, ensure_ascii=False, indent=2))


if __name__ == '__main__':
    main()
