#!/usr/bin/env python3
import sqlite3, os, sys, json, re, hashlib, urllib.parse
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import evernote_import

def heal():
    db_path = os.path.expanduser('~/Documents/notebook.db')
    conn = sqlite3.connect(db_path)
    cur = conn.cursor()

    evernote_content = '/Users/simon/Library/Containers/com.yinxiang.Mac/Data/Library/Application Support/com.yinxiang.Mac/accounts/app.yinxiang.com/22012340/content'
    evernote_db = '/Users/simon/Library/Containers/com.yinxiang.Mac/Data/Library/Application Support/com.yinxiang.Mac/accounts/app.yinxiang.com/22012340/localNoteStore/LocalNoteStore.sqlite'
    e_conn = sqlite3.connect(f'file:{evernote_db}?mode=ro', uri=True)

    e_notes = {}
    for row in e_conn.execute('SELECT ZTITLE, ZLOCALUUID FROM ZENNOTE WHERE ZACTIVE = 1').fetchall():
        t, u = row[0] or '无标题笔记', row[1]
        if u:
            p = os.path.join(evernote_content, u, 'content.enml')
            if os.path.exists(p):
                e_notes[t] = p

    print(f'Found {len(e_notes)} notes in Evernote')
    db_notes = cur.execute('SELECT id, title, delta_json FROM notes').fetchall()
    print(f'Found {len(db_notes)} notes in notebook.db')

    updated = 0
    for note_id, title, existing_delta in db_notes:
        if title in e_notes:
            enml_path = e_notes[title]
            with open(enml_path, 'r', encoding='utf-8', errors='ignore') as f:
                enml = f.read()
            md = evernote_import.convert_enml_to_markdown(enml)

            existing_images = re.findall(r'\"image\":\"(.*?)\"', existing_delta)
            existing_svgs = re.findall(r'\"svg_path\":\"(.*?)\"', existing_delta)

            lines = md.split('\n')
            ops = []
            i = 0
            img_idx = 0
            svg_idx = 0
            while i < len(lines):
                line = lines[i]

                # mindmap
                if line.strip().startswith('```mindmap'):
                    i += 1
                    map_buf = []
                    while i < len(lines) and not lines[i].strip().startswith('```'):
                        map_buf.append(lines[i])
                        i += 1
                    raw_json = '\n'.join(map_buf)
                    try:
                        p_map = json.loads(raw_json)
                        if svg_idx < len(existing_svgs):
                            p_map['svg_path'] = existing_svgs[svg_idx]
                            svg_idx += 1
                        raw_json = json.dumps(p_map, ensure_ascii=False)
                    except Exception:
                        pass
                    ops.append({'insert': {'mindmap': raw_json}})
                    ops.append({'insert': '\n'})
                    if i < len(lines):
                        i += 1
                    continue

                # code block
                if line.strip().startswith('```'):
                    lang = line.strip()[3:].strip()
                    i += 1
                    code_buf = []
                    while i < len(lines) and not lines[i].strip().startswith('```'):
                        code_buf.append(lines[i])
                        i += 1
                    full_code = '\n'.join(code_buf)
                    ops.append({'insert': {'code_block': json.dumps({'code': full_code, 'language': lang or 'plaintext'}, ensure_ascii=False)}})
                    ops.append({'insert': '\n'})
                    if i < len(lines):
                        i += 1
                    continue

                # heading
                hm = re.match(r'^(#{1,6})\s+(.+)$', line)
                if hm:
                    level = len(hm.group(1))
                    ops.append({'insert': hm.group(2)})
                    ops.append({'insert': '\n', 'attributes': {'header': level}})
                    i += 1
                    continue

                # todo
                tm = re.match(r'^[-*+]\s+\[([ xX])\]\s*(.*)$', line)
                if tm:
                    checked = tm.group(1).lower() == 'x'
                    ops.append({'insert': tm.group(2)})
                    ops.append({'insert': '\n', 'attributes': {'list': 'checked' if checked else 'unchecked'}})
                    i += 1
                    continue

                # bullet
                bm = re.match(r'^[-*+]\s+(.+)$', line)
                if bm:
                    ops.append({'insert': bm.group(1)})
                    ops.append({'insert': '\n', 'attributes': {'list': 'bullet'}})
                    i += 1
                    continue

                # ordered
                om = re.match(r'^\d+\.\s+(.+)$', line)
                if om:
                    ops.append({'insert': om.group(1)})
                    ops.append({'insert': '\n', 'attributes': {'list': 'ordered'}})
                    i += 1
                    continue

                # image
                im = re.match(r'^!\[(.*?)\]\((.*?)\)$', line)
                if im:
                    img_path = im.group(2)
                    if img_path.startswith('en-media://') and img_idx < len(existing_images):
                        img_path = existing_images[img_idx]
                        img_idx += 1
                    ops.append({'insert': {'image': img_path}})
                    ops.append({'insert': '\n'})
                    i += 1
                    continue

                if not line:
                    ops.append({'insert': '\n'})
                else:
                    ops.append({'insert': line})
                    ops.append({'insert': '\n'})
                i += 1

            new_delta = json.dumps(ops, ensure_ascii=False)
            cur.execute('UPDATE notes SET delta_json = ? WHERE id = ?', (new_delta, note_id))
            updated += 1

    conn.commit()
    print(f'Successfully updated {updated} notes in notebook.db!')

if __name__ == '__main__':
    heal()
