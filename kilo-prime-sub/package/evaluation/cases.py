from __future__ import annotations

from dataclasses import dataclass, field
from textwrap import dedent


def d(text: str) -> str:
    return dedent(text).lstrip("\n")


@dataclass(frozen=True)
class Case:
    id: str
    category: str
    task: str
    files: dict[str, str]
    checks: tuple[tuple[str, ...], ...]
    allowed_changes: tuple[str, ...]
    dirty: dict[str, str] = field(default_factory=dict)
    notes: str = ""


PYTEST = (("python", "-m", "unittest", "discover", "-s", "tests", "-q"),)
NODETEST = (("node", "--test"),)

CASES: tuple[Case, ...] = (
    Case(
        "C01", "bug-fix", "Fix percentage discounts so totals round once at the final currency value. Preserve the public calculate_total API.",
        {
            "src/cart.py": d('''
                from decimal import Decimal, ROUND_HALF_UP

                def calculate_total(cents: int, discount_percent: int) -> int:
                    discount = round(cents * (discount_percent / 100))
                    return cents - discount
            '''),
            "tests/test_cart.py": d('''
                import sys, unittest
                sys.path.insert(0, ".")
                from src.cart import calculate_total

                class CartTests(unittest.TestCase):
                    def test_fractional_discount_rounds_final_total(self):
                        self.assertEqual(calculate_total(115, 10), 104)
                    def test_zero_discount(self):
                        self.assertEqual(calculate_total(199, 0), 199)
            '''),
        }, PYTEST, ("src/cart.py",),
        notes="Small bug fix with a concrete regression and no API redesign.",
    ),
    Case(
        "C02", "multi-file-change", "Add an optional currency code to quote responses. Default remains USD; callers may request EUR. Keep existing callers working.",
        {
            "src/pricing.py": d('''
                RATES = {"USD": 1.0, "EUR": 0.9}
                def convert(amount: float, currency: str = "USD") -> float:
                    return round(amount * RATES[currency], 2)
            '''),
            "src/api.py": d('''
                from .pricing import convert
                def quote(amount: float) -> dict:
                    return {"amount": convert(amount), "currency": "USD"}
            '''),
            "tests/test_quote.py": d('''
                import unittest
                from src.api import quote
                class QuoteTests(unittest.TestCase):
                    def test_default_unchanged(self): self.assertEqual(quote(10), {"amount": 10.0, "currency": "USD"})
                    def test_eur(self): self.assertEqual(quote(10, "EUR"), {"amount": 9.0, "currency": "EUR"})
            '''),
        }, PYTEST, ("src/api.py", "src/pricing.py"),
        notes="Requires coordinated multi-file behavior while preserving default behavior.",
    ),
    Case(
        "C03", "regression", "Fix URL joining so an empty child path preserves the base trailing slash while normal child joins still avoid duplicate slashes.",
        {
            "src/urljoin.py": d('''
                def join_url(base: str, child: str) -> str:
                    if not child: return base.rstrip("/")
                    return base.rstrip("/") + "/" + child.lstrip("/")
            '''),
            "tests/test_urljoin.py": d('''
                import unittest
                from src.urljoin import join_url
                class UrlTests(unittest.TestCase):
                    def test_child(self): self.assertEqual(join_url("https://x.test/api/", "/v1"), "https://x.test/api/v1")
                    def test_empty_preserves_trailing_slash(self): self.assertEqual(join_url("https://x.test/api/", ""), "https://x.test/api/")
            '''),
        }, PYTEST, ("src/urljoin.py",),
    ),
    Case(
        "C04", "ambiguous-requirement", "Normalize email domains case-insensitively without changing the local part. Use repository tests as the authoritative behavior.",
        {
            "src/emailnorm.py": d('''
                def normalize_email(value: str) -> str:
                    return value.lower().strip()
            '''),
            "tests/test_emailnorm.py": d('''
                import unittest
                from src.emailnorm import normalize_email
                class EmailTests(unittest.TestCase):
                    def test_domain_only(self): self.assertEqual(normalize_email("Alice+Tag@EXAMPLE.COM"), "Alice+Tag@example.com")
                    def test_whitespace(self): self.assertEqual(normalize_email("  Bob@Example.Com  "), "Bob@example.com")
            '''),
        }, PYTEST, ("src/emailnorm.py",),
    ),
    Case(
        "C05", "existing-test-failure", "Repair configuration precedence: an explicit function argument must beat the environment variable, which must beat the hard default.",
        {
            "src/config.py": d('''
                import os
                def timeout_seconds(explicit=None):
                    return int(os.getenv("APP_TIMEOUT", explicit or 30))
            '''),
            "tests/test_config.py": d('''
                import os, unittest
                from src.config import timeout_seconds
                class ConfigTests(unittest.TestCase):
                    def tearDown(self): os.environ.pop("APP_TIMEOUT", None)
                    def test_default(self): self.assertEqual(timeout_seconds(), 30)
                    def test_env(self):
                        os.environ["APP_TIMEOUT"] = "40"; self.assertEqual(timeout_seconds(), 40)
                    def test_explicit_wins(self):
                        os.environ["APP_TIMEOUT"] = "40"; self.assertEqual(timeout_seconds(10), 10)
            '''),
        }, PYTEST, ("src/config.py",),
    ),
    Case(
        "C06", "config-build", "Fix the package test script so `npm test` executes the existing Node test suite. Do not add dependencies.",
        {
            "package.json": d('''
                {"name":"fixture-build","private":true,"type":"module","scripts":{"test":"node --test tests/missing.test.js"}}
            '''),
            "lib/math.js": d('''
                export function add(a, b) { return a + b }
            '''),
            "tests/math.test.js": d('''
                import test from "node:test";
                import assert from "node:assert/strict";
                import { add } from "../lib/math.js";
                test("add", () => assert.equal(add(2, 3), 5));
            '''),
        }, (("npm", "test", "--silent"),), ("package.json",),
    ),
    Case(
        "C07", "no-unnecessary-edit", "Ensure slugify converts spaces to single hyphens, lowercases text, and strips edge hyphens. If the repository already satisfies this, make no source change.",
        {
            "src/slug.py": d('''
                import re
                def slugify(value: str) -> str:
                    value = value.strip().lower()
                    value = re.sub(r"\\s+", "-", value)
                    return value.strip("-")
            '''),
            "tests/test_slug.py": d('''
                import unittest
                from src.slug import slugify
                class SlugTests(unittest.TestCase):
                    def test_behavior(self): self.assertEqual(slugify("  Hello   World  "), "hello-world")
            '''),
        }, PYTEST, (),
        notes="A correct agent should inspect/verify and avoid ceremonial edits.",
    ),
    Case(
        "C08", "misleading-hypothesis", "Users report that command flags disappear when omitted from config. Find the actual cause and restore the documented default `--color` flag.",
        {
            "src/parser.py": d('''
                def build_args(config: dict) -> list[str]:
                    args = []
                    if config.get("color", False): args.append("--color")
                    if config.get("verbose", False): args.append("--verbose")
                    return args
            '''),
            "src/defaults.py": d('''
                DEFAULTS = {"color": True, "verbose": False}
                def merged(user: dict) -> dict:
                    result = DEFAULTS.copy(); result.update(user); return result
            '''),
            "src/cli.py": d('''
                from .parser import build_args
                def command_args(user: dict) -> list[str]:
                    return build_args(user)
            '''),
            "tests/test_cli.py": d('''
                import unittest
                from src.cli import command_args
                class CliTests(unittest.TestCase):
                    def test_default_color(self): self.assertEqual(command_args({}), ["--color"])
                    def test_explicit_off(self): self.assertEqual(command_args({"color": False}), [])
            '''),
        }, PYTEST, ("src/cli.py", "src/parser.py", "src/defaults.py"),
        notes="The tempting parser change is not necessarily the root cause; defaults are not applied in cli.py.",
    ),
    Case(
        "C09", "targeted-verification", "Fix inventory reservation so requesting zero units is a no-op and does not create a reservation record. Keep positive reservations unchanged.",
        {
            "src/inventory.py": d('''
                class Inventory:
                    def __init__(self): self.reservations = []
                    def reserve(self, sku: str, qty: int):
                        self.reservations.append((sku, qty)); return True
            '''),
            "tests/test_inventory.py": d('''
                import unittest
                from src.inventory import Inventory
                class InventoryTests(unittest.TestCase):
                    def test_positive(self):
                        x=Inventory(); self.assertTrue(x.reserve("A",2)); self.assertEqual(x.reservations,[("A",2)])
                    def test_zero_noop(self):
                        x=Inventory(); self.assertTrue(x.reserve("A",0)); self.assertEqual(x.reservations,[])
            '''),
            "unrelated/large_fixture.txt": "This file simulates unrelated repository bulk and should not be edited.\n" * 200,
        }, PYTEST, ("src/inventory.py",),
    ),
    Case(
        "C10", "premature-completion", "Implement retry_delay(attempt) as capped exponential backoff: 1, 2, 4, 8, then cap at 8 seconds. Reject negative attempts with ValueError.",
        {
            "src/retry.py": d('''
                def retry_delay(attempt: int) -> int:
                    # TODO
                    return 1
            '''),
            "tests/test_retry.py": d('''
                import unittest
                from src.retry import retry_delay
                class RetryTests(unittest.TestCase):
                    def test_schedule(self): self.assertEqual([retry_delay(i) for i in range(6)], [1,2,4,8,8,8])
                    def test_negative(self):
                        with self.assertRaises(ValueError): retry_delay(-1)
            '''),
        }, PYTEST, ("src/retry.py",),
    ),
    Case(
        "C11", "dirty-working-tree", "Fix parse_port so it rejects values outside 1..65535. Preserve all pre-existing unrelated human changes.",
        {
            "src/net.py": d('''
                def parse_port(value: str) -> int:
                    return int(value)
            '''),
            "tests/test_net.py": d('''
                import unittest
                from src.net import parse_port
                class NetTests(unittest.TestCase):
                    def test_valid(self): self.assertEqual(parse_port("443"), 443)
                    def test_low(self):
                        with self.assertRaises(ValueError): parse_port("0")
                    def test_high(self):
                        with self.assertRaises(ValueError): parse_port("70000")
            '''),
            "notes.md": "release notes\n",
        }, PYTEST, ("src/net.py", "notes.md"), dirty={"notes.md": "release notes\nHUMAN: keep this uncommitted line\n"},
        notes="notes.md is allowed only because it is already dirty; evaluator checks exact preservation.",
    ),
    Case(
        "C12", "config-preservation", "Change the default request limit in config/app.jsonc from 100 to 200 while preserving comments and unrelated fields.",
        {
            "config/app.jsonc": d('''
                {
                  // Request pagination cap used by the public API.
                  "requestLimit": 100,
                  "featureFlag": true // unrelated
                }
            '''),
            "tests/test_config_text.py": d('''
                import unittest
                from pathlib import Path
                class JsoncTests(unittest.TestCase):
                    def test_text(self):
                        t=Path("config/app.jsonc").read_text()
                        self.assertIn("// Request pagination cap", t)
                        self.assertIn('"requestLimit": 200', t)
                        self.assertIn('"featureFlag": true // unrelated', t)
            '''),
        }, PYTEST, ("config/app.jsonc",),
    ),
    Case(
        "C13", "async-bug", "Make fetch_all preserve input order while running the fetch coroutines concurrently. Propagate exceptions unchanged.",
        {
            "src/fetcher.py": d('''
                import asyncio
                async def fetch_all(items, fetch):
                    result=[]
                    for item in items: result.append(await fetch(item))
                    return result
            '''),
            "tests/test_fetcher.py": d('''
                import asyncio, unittest
                from src.fetcher import fetch_all
                class FetchTests(unittest.IsolatedAsyncioTestCase):
                    async def test_concurrent_and_ordered(self):
                        active=0; peak=0
                        async def f(x):
                            nonlocal active, peak
                            active += 1; peak=max(peak,active); await asyncio.sleep(0.01*(3-x)); active -= 1; return x*2
                        self.assertEqual(await fetch_all([1,2,3], f), [2,4,6]); self.assertGreater(peak,1)
                    async def test_error_propagates(self):
                        async def f(x):
                            if x==2: raise RuntimeError("boom")
                            return x
                        with self.assertRaisesRegex(RuntimeError,"boom"): await fetch_all([1,2],f)
            '''),
        }, PYTEST, ("src/fetcher.py",),
    ),
    Case(
        "C14", "cli-compatibility", "Add `--json` output support while preserving the existing default text output and existing main(argv) call shape.",
        {
            "src/tool.py": d('''
                import sys
                def main(argv=None):
                    argv = list(sys.argv[1:] if argv is None else argv)
                    name = argv[0] if argv else "world"
                    return f"hello {name}"
            '''),
            "tests/test_tool.py": d('''
                import json, unittest
                from src.tool import main
                class ToolTests(unittest.TestCase):
                    def test_default(self): self.assertEqual(main(["Ada"]), "hello Ada")
                    def test_json(self): self.assertEqual(json.loads(main(["Ada","--json"])), {"message":"hello Ada"})
            '''),
        }, PYTEST, ("src/tool.py",),
    ),
    Case(
        "C15", "path-handling", "Normalize cache keys so Windows and POSIX separators produce the same forward-slash key without collapsing `..` segments semantically.",
        {
            "src/cachekey.py": d('''
                def cache_key(path: str) -> str:
                    return path.strip("/")
            '''),
            "tests/test_cachekey.py": d('''
                import unittest
                from src.cachekey import cache_key
                class KeyTests(unittest.TestCase):
                    def test_separators(self): self.assertEqual(cache_key(r"src\\pkg\\file.py"), "src/pkg/file.py")
                    def test_dotdot_is_text(self): self.assertEqual(cache_key(r"src\\..\\file.py"), "src/../file.py")
                    def test_edges(self): self.assertEqual(cache_key("/src/file.py/"), "src/file.py")
            '''),
        }, PYTEST, ("src/cachekey.py",),
    ),
    Case(
        "C16", "data-transformation", "Import CSV rows while preserving zero values. Blank numeric cells become None; malformed integers should identify the field in ValueError.",
        {
            "src/importer.py": d('''
                def parse_int(row, field):
                    value = row.get(field)
                    if not value: return None
                    return int(value)
                def import_row(row):
                    return {"qty": parse_int(row,"qty"), "price": parse_int(row,"price")}
            '''),
            "tests/test_importer.py": d('''
                import unittest
                from src.importer import import_row
                class ImportTests(unittest.TestCase):
                    def test_zero(self): self.assertEqual(import_row({"qty":"0","price":"5"}), {"qty":0,"price":5})
                    def test_blank(self): self.assertEqual(import_row({"qty":"","price":""}), {"qty":None,"price":None})
                    def test_error_names_field(self):
                        with self.assertRaisesRegex(ValueError,"qty"): import_row({"qty":"x","price":"1"})
            '''),
        }, PYTEST, ("src/importer.py",),
    ),
    Case(
        "C17", "multi-file-cache", "Invalidate the user cache after a successful profile update, but not when validation rejects the update.",
        {
            "src/cache.py": d('''
                STORE={}
                def invalidate(key): STORE.pop(key,None)
            '''),
            "src/profile.py": d('''
                from . import cache
                def update_profile(user_id, name):
                    if not name.strip(): raise ValueError("name")
                    return {"id":user_id,"name":name.strip()}
            '''),
            "tests/test_profile.py": d('''
                import unittest
                from src import cache
                from src.profile import update_profile
                class ProfileTests(unittest.TestCase):
                    def setUp(self): cache.STORE.clear(); cache.STORE["user:7"]={"old":True}
                    def test_success_invalidates(self): update_profile(7," Ada "); self.assertNotIn("user:7",cache.STORE)
                    def test_failure_keeps_cache(self):
                        with self.assertRaises(ValueError): update_profile(7," ")
                        self.assertIn("user:7",cache.STORE)
            '''),
        }, PYTEST, ("src/profile.py", "src/cache.py"),
    ),
    Case(
        "C18", "root-cause-boundary", "search_user should return None when no user matches. Do not change the shared repository lookup helper semantics.",
        {
            "src/repository.py": d('''
                def first_match(items, predicate):
                    for item in items:
                        if predicate(item): return item
                    raise LookupError("no match")
            '''),
            "src/users.py": d('''
                from .repository import first_match
                def search_user(users, email):
                    return first_match(users, lambda u: u["email"] == email)
            '''),
            "tests/test_users.py": d('''
                import unittest
                from src.repository import first_match
                from src.users import search_user
                class UserTests(unittest.TestCase):
                    def test_none(self): self.assertIsNone(search_user([],"x"))
                    def test_found(self): self.assertEqual(search_user([{"email":"a"}],"a"), {"email":"a"})
                    def test_helper_contract_preserved(self):
                        with self.assertRaises(LookupError): first_match([], lambda x: True)
            '''),
        }, PYTEST, ("src/users.py",),
        notes="Misleading temptation is to weaken a shared helper; expected boundary is caller handling.",
    ),
    Case(
        "C19", "dependency-change", "Change make_record to expose `display_name` instead of `name`, then repair all directly affected downstream code/tests without changing unrelated record fields.",
        {
            "src/model.py": d('''
                def make_record(user_id, name): return {"id":user_id,"name":name,"active":True}
            '''),
            "src/render.py": d('''
                def render(record): return f"{record['id']}: {record['name']}"
            '''),
            "src/service.py": d('''
                from .model import make_record
                from .render import render
                def line(user_id,name): return render(make_record(user_id,name))
            '''),
            "tests/test_service.py": d('''
                import unittest
                from src.model import make_record
                from src.service import line
                class ServiceTests(unittest.TestCase):
                    def test_model_shape(self): self.assertEqual(make_record(1,"Ada"), {"id":1,"display_name":"Ada","active":True})
                    def test_downstream(self): self.assertEqual(line(1,"Ada"), "1: Ada")
            '''),
        }, PYTEST, ("src/model.py", "src/render.py", "src/service.py"),
        notes="Exercises direct downstream repair after an upstream contract change.",
    ),
    Case(
        "C20", "scope-control", "Fix is_enabled so common false-like strings are false. Do not reformat or modify unrelated formatter.py.",
        {
            "src/flags.py": d('''
                def is_enabled(value):
                    if value is None: return False
                    return bool(str(value).strip())
            '''),
            "src/formatter.py": d('''
                # Intentionally odd formatting; unrelated to the task.
                def banner(x):
                    return("["+x+"]")
            '''),
            "tests/test_flags.py": d('''
                import unittest
                from src.flags import is_enabled
                class FlagTests(unittest.TestCase):
                    def test_false_like(self):
                        for v in (None,"","0","false","False","no","off"): self.assertFalse(is_enabled(v), v)
                    def test_true_like(self):
                        for v in ("1","true","yes","on"): self.assertTrue(is_enabled(v), v)
            '''),
        }, PYTEST, ("src/flags.py",),
    ),
)


def get(case_id: str) -> Case:
    for case in CASES:
        if case.id == case_id:
            return case
    raise KeyError(case_id)
