#!/usr/bin/env python3
"""
印象笔记导入脚本
从 macOS 钥匙串读取 Evernote Token，通过 API 获取笔记内容，转换为 JSON 输出。

用法:
  python3 evernote_import.py list                          # 列出所有笔记元数据
  python3 evernote_import.py fetch --guid <GUID>           # 获取单条笔记内容
  python3 evernote_import.py export_all --output <FILE>    # 批量导出全部笔记
  python3 evernote_import.py parse_notes --file <FILE>     # 解析 .notes 文件元数据

输出: JSON 格式
"""

import argparse
import base64
import json
import os
import plistlib
import subprocess
import sys
import xml.etree.ElementTree as ET

# Monkey-patch for Python 3.13+ compatibility
import inspect
if not hasattr(inspect, 'getargspec'):
    inspect.getargspec = inspect.getfullargspec

def get_tokens():
    """从 macOS 钥匙串获取所有 Evernote Token"""
    tokens = []
    # 列出所有可能的账号 ID
    try:
        raw = subprocess.check_output(
            ['security', 'dump-keychain'],
            stderr=subprocess.DEVNULL
        ).decode('utf-8', errors='ignore')
        import re
        accounts = re.findall(r'"acct"<blob>="(\d+/Evernote-China/smd)"', raw)
        accounts = list(set(accounts))
    except Exception:
        accounts = ['54282628/Evernote-China/smd', '22012340/Evernote-China/smd']

    for acct in accounts:
        try:
            raw = subprocess.check_output(
                ['security', 'find-generic-password', '-s', 'Evernote', '-a', acct, '-w'],
                stderr=subprocess.DEVNULL
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
    """列出所有笔记元数据"""
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

    # 获取笔记本和标签映射
    notebooks = {nb.guid: nb.name for nb in note_store.listNotebooks()}
    tags = {tag.guid: tag.name for tag in note_store.listTags()}

    notes_meta = []
    for meta in all_notes:
        note_tags = []
        if meta.tagGuids:
            note_tags = [tags.get(g, g) for g in meta.tagGuids]
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
    """获取单条笔记的完整内容"""
    import html2text

    note_store = get_note_store(token_info['token'])
    note = note_store.getNote(token_info['token'], guid, True, True, False, False)

    content = note.content
    if isinstance(content, bytes):
        content = content.decode('utf-8', errors='ignore')

    # ENML → Markdown
    h = html2text.HTML2Text()
    h.ignore_links = False
    h.ignore_images = True
    h.body_width = 0
    markdown = h.handle(content)

    # 获取资源
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
    """批量导出全部笔记"""
    import html2text

    meta = list_notes(token_info)
    note_store = get_note_store(token_info['token'])
    h = html2text.HTML2Text()
    h.ignore_links = False
    h.ignore_images = True
    h.body_width = 0

    notes = []
    total = len(meta['notes'])
    for i, note_meta in enumerate(meta['notes']):
        try:
            note = note_store.getNote(token_info['token'], note_meta['guid'], True, True, False, False)
            content = note.content
            if isinstance(content, bytes):
                content = content.decode('utf-8', errors='ignore')
            markdown = h.handle(content)

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
            print(f'[{i+1}/{total}] {note_meta["title"]}', file=sys.stderr)
        except Exception as e:
            print(f'[{i+1}/{total}] FAILED: {note_meta["title"]} - {e}', file=sys.stderr)
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


def parse_notes_file(file_path):
    """解析 .notes 文件的元数据和附件"""
    tree = ET.parse(file_path)
    root = tree.getroot()

    notes = []
    for note_el in root.findall('note'):
        title_el = note_el.find('title')
        created_el = note_el.find('created')
        updated_el = note_el.find('updated')
        tags = [t.text for t in note_el.findall('tag') if t.text]
        notebook_el = note_el.find('notebook')

        # 检查内容是否加密
        content_el = note_el.find('content')
        is_encrypted = False
        if content_el is not None:
            encoding = content_el.get('encoding', '')
            is_encrypted = 'aes' in encoding

        # 提取附件
        resources = []
        for res_el in note_el.findall('resource'):
            data_el = res_el.find('data')
            mime_el = res_el.find('mime')
            fname_el = res_el.find('filename')
            if data_el is not None and data_el.text:
                encoding = data_el.get('encoding', '')
                if 'aes' not in encoding:
                    resources.append({
                        'mime': mime_el.text if mime_el is not None else None,
                        'filename': fname_el.text if fname_el is not None else None,
                        'base64': data_el.text.strip(),
                    })

        notes.append({
            'title': title_el.text if title_el is not None else 'Untitled',
            'created': created_el.text if created_el is not None else None,
            'updated': updated_el.text if updated_el is not None else None,
            'tags': tags,
            'notebook': notebook_el.text if notebook_el is not None else None,
            'is_encrypted': is_encrypted,
            'resources': resources,
        })

    return {
        'total': len(notes),
        'encrypted': sum(1 for n in notes if n['is_encrypted']),
        'notes': notes,
    }


def main():
    parser = argparse.ArgumentParser(description='Evernote Import Tool')
    subparsers = parser.add_subparsers(dest='command')

    subparsers.add_parser('list', help='List all notes metadata')

    fetch_parser = subparsers.add_parser('fetch', help='Fetch single note content')
    fetch_parser.add_argument('--guid', required=True, help='Note GUID')

    export_parser = subparsers.add_parser('export_all', help='Export all notes')
    export_parser.add_argument('--output', required=True, help='Output JSON file path')

    parse_parser = subparsers.add_parser('parse_notes', help='Parse .notes file metadata')
    parse_parser.add_argument('--file', required=True, help='Path to .notes file')

    args = parser.parse_args()

    if args.command == 'parse_notes':
        result = parse_notes_file(args.file)
        print(json.dumps(result, ensure_ascii=False, indent=2))
        return

    # Get token
    tokens = get_tokens()
    if not tokens:
        print(json.dumps({'error': 'No Evernote token found in keychain'}))
        sys.exit(1)

    # Try tokens until one works
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
        print(json.dumps({'error': 'No valid token found', 'tried': [t['account'] for t in tokens]}))
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
