"""Public-market helper parsing and bounded requests, with no network access."""
import contextlib
import importlib.machinery
import importlib.util
import io
import json
import os
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[1]
SCRIPT = ROOT / 'dotfiles/.local/bin/desktop-markets'


class Response:
    status = 200

    def __init__(self, payload):
        self.payload = json.dumps(payload).encode()

    def __enter__(self):
        return self

    def __exit__(self, *_args):
        return None

    def read(self, limit):
        return self.payload[:limit]


class DesktopMarketsTests(unittest.TestCase):
    def test_default_pairs_and_public_quotes_emit_sidebar_protocol(self):
        with tempfile.TemporaryDirectory() as temporary:
            home = Path(temporary)
            config = home / '.config/desktop-control-center/market-pairs.json'
            config.parent.mkdir(parents=True)
            config.write_text(json.dumps({"version": 1, "pairs": [
                {"base": "EUR", "quote": "PLN"}, {"base": "USD", "quote": "PLN"}]}))
            env = dict(os.environ, HOME=str(home), XDG_CONFIG_HOME=str(home / '.config'))
            loader = importlib.machinery.SourceFileLoader('desktop_markets', str(SCRIPT))
            spec = importlib.util.spec_from_loader(loader.name, loader)
            module = importlib.util.module_from_spec(spec)
            with patch.dict(os.environ, env):
                spec.loader.exec_module(module)
                urls = []

                def open_url(request, timeout):
                    self.assertLessEqual(timeout, 7)
                    urls.append(request.full_url)
                    if 'frankfurter.app' in request.full_url:
                        base = request.full_url.split('from=', 1)[1].split('&', 1)[0]
                        return Response({"base": base, "rates": {"PLN": 4.2 if base == "EUR" else 4.0}})
                    return Response({"price": 3100.5 if request.full_url.endswith("XAU") else 33.75})

                output = io.StringIO()
                with patch.object(module.urllib.request, 'urlopen', side_effect=open_url), \
                     patch.object(module.sys, 'argv', [str(SCRIPT), '--sidebar-data']), \
                     contextlib.redirect_stdout(output):
                    self.assertEqual(module.main(), 0)
                lines = output.getvalue().splitlines()
                self.assertRegex(lines[0], r'^markets-v1\t\d+$')
                values = {parts[1]: float(parts[2]) for line in lines[1:]
                          if (parts := line.split('\t')) and len(parts) == 3}
                self.assertEqual(values, {"EURPLN": 4.2, "USDPLN": 4.0, "XAU": 3100.5, "XAG": 33.75})
                self.assertEqual(len(urls), 4)
                self.assertTrue(any('from=EUR&to=PLN' in url for url in urls))
                self.assertTrue(any('from=USD&to=PLN' in url for url in urls))

    def test_invalid_config_does_not_construct_arbitrary_urls(self):
        with tempfile.TemporaryDirectory() as temporary:
            home = Path(temporary)
            config = home / '.config/desktop-control-center/market-pairs.json'
            config.parent.mkdir(parents=True)
            config.write_text('{"version":1,"pairs":[{"base":"EUR","quote":"PLN","url":"https://evil"}]}')
            loader = importlib.machinery.SourceFileLoader('desktop_markets_invalid', str(SCRIPT))
            spec = importlib.util.spec_from_loader(loader.name, loader)
            module = importlib.util.module_from_spec(spec)
            with patch.dict(os.environ, {"HOME": str(home), "XDG_CONFIG_HOME": str(home / '.config')}):
                spec.loader.exec_module(module)
                self.assertEqual(module.load_config()['pairs'], [
                    {"base": "EUR", "quote": "PLN"}, {"base": "USD", "quote": "PLN"}])


if __name__ == '__main__':
    unittest.main()
