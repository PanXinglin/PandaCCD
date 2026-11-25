"""Read-only APK download page for a local Tailscale Serve proxy."""

import argparse
import html
import io
import re
from functools import partial
from http.server import SimpleHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from urllib.parse import urlsplit


APK = re.compile(r"panda-ccd-(\d+)\.(\d+)\.(\d+)-debug\.apk")


class Downloads(SimpleHTTPRequestHandler):
    extensions_map = {
        **SimpleHTTPRequestHandler.extensions_map,
        ".apk": "application/vnd.android.package-archive",
    }

    def end_headers(self):
        self.send_header("Cache-Control", "no-store")
        super().end_headers()

    def send_head(self):
        route = urlsplit(self.path).path
        if route == "/":
            return self.list_directory(self.directory)
        name = route.removeprefix("/")
        file = Path(self.directory, name)
        if (
            (not APK.fullmatch(name) and name != "SHA256SUMS.txt")
            or file.is_symlink()
            or not file.is_file()
        ):
            self.send_error(404)
            return None
        return super().send_head()

    def list_directory(self, path):
        packages = []
        for file in Path(path).iterdir():
            match = APK.fullmatch(file.name)
            if match and not file.is_symlink() and file.is_file():
                packages.append((tuple(map(int, match.groups())), file))
        packages.sort(reverse=True)
        links = []
        for index, (version, file) in enumerate(packages):
            label = ".".join(map(str, version))
            badge = "最新版本 · " if index == 0 else ""
            size = file.stat().st_size / 1024**2
            links.append(
                f'<li><a download href="/{html.escape(file.name)}">'
                f'{badge}{label} · {size:.0f} MB</a></li>'
            )
        body = (
            '<!doctype html><html lang="zh-CN"><meta charset="utf-8">'
            '<meta name="viewport" content="width=device-width,initial-scale=1">'
            '<title>熊猫 CCD 测试包</title>'
            '<style>body{max-width:34rem;margin:2rem auto;padding:0 1rem;'
            'font:1rem system-ui}ul{padding:0;list-style:none}'
            'li a{display:block;padding:.8rem 0;border-bottom:1px solid #ddd}</style>'
            '<h1>熊猫 CCD 测试包</h1><p>点版本号下载 APK，下载后打开安装。</p>'
            f'<ul>{"".join(links) or "<li>暂无测试包</li>"}</ul>'
            '<p><a href="/SHA256SUMS.txt">文件校验值</a></p></html>'
        ).encode()
        self.send_response(200)
        self.send_header("Content-Type", "text/html; charset=utf-8")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        return io.BytesIO(body)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--port", type=int, default=8784)
    args = parser.parse_args()
    dist = Path(__file__).resolve().parents[1] / "dist"
    handler = partial(Downloads, directory=str(dist))
    with ThreadingHTTPServer(("127.0.0.1", args.port), handler) as server:
        server.serve_forever()
