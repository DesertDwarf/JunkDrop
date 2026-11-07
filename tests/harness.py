"""Loads JunkDrop's real Lua files, in TOC order, into a Lua 5.1 runtime with a stand-in WoW API."""
import os
import unittest

try:
    from lupa.lua51 import LuaRuntime
except ImportError as error:  # pragma: no cover - only without the test dependency
    raise unittest.SkipTest("lupa is not installed; run: py -m pip install -r tests/requirements.txt") from error

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)


def read(path):
    with open(path, encoding="utf-8-sig") as handle:
        return handle.read()


def toc_lua_files():
    """The addon's own Lua files, in the order the TOC loads them (libraries are mocked)."""
    files = []
    for line in read(os.path.join(ROOT, "JunkDrop.toc")).splitlines():
        line = line.strip().replace("\\", "/")
        if line.endswith(".lua") and not line.startswith(("#", "libs/")):
            files.append(line)
    return files


def quality_dots(*qualities):
    """The inline textures the bar text uses for the given item qualities."""
    return "".join("|TInterface\\AddOns\\JunkDrop\\JunkDrop-Dot%d:0|t" % q for q in qualities)


class Env:
    """One fresh addon instance. Lua values come back as plain Python values where they can."""

    def __init__(self, ellesmere=False):
        self.lua = LuaRuntime(unpack_returned_tuples=True)
        self.lua.execute(read(os.path.join(HERE, "wow_mock.lua")))
        if ellesmere:  # EllesmereUI loads first, so it exists when our files register their skin
            self.lua.execute(
                "EllesmereUI = { RegisterSkin = function(name, fn) tinsert(Registrations, { name = name, fn = fn }) end }"
            )
        load = self.lua.eval("LoadFile")
        for name in toc_lua_files():
            source = read(os.path.join(ROOT, name))
            checked = self.lua.eval("function(s, n) return loadstring(s, n) end")(source, name)
            if isinstance(checked, tuple):  # (nil, message) is a syntax error
                raise SyntaxError("%s: %s" % (name, checked[1]))
            load(name, source)

    def run(self, code):
        self.lua.execute(code)

    def ev(self, code):
        return self.lua.eval(code)

    def bag(self, items):
        """Set the bag to a list of (name, quality, price, count, item class[, max stack, family]).
        An emptied slot is ("", -1, 0, 0, 0)."""
        rows = ", ".join('{ "%s", %s }' % (item[0], ", ".join(str(v) for v in item[1:])) for item in items)
        self.run("SetBag({ %s })" % rows)

    def loot(self, items):
        """Set the loot window to a list of dicts: name, quality, price, qty, class, max, family,
        quest, slot (1 item, 2 money, 0 looted), uncached. Anything left out gets a default."""
        def lua(value):
            # bool is checked first because Python counts 1 as True and 0 as False.
            if isinstance(value, bool):
                return "true" if value else "false"
            return '"%s"' % value if isinstance(value, str) else str(value)
        rows = ", ".join("{ %s }" % ", ".join("%s = %s" % (k, lua(v)) for k, v in item.items()) for item in items)
        self.run("SetLoot({ %s })" % rows)

    def fire(self, event):
        self.lua.eval("function(e) FireEvent(e) end")(event)

    def set(self, **settings):
        for key, value in settings.items():
            self.lua.eval("function(k, v) NS.Set(k, v) end")(key, value)

    def cmd(self, text):
        """Run a /jd command and return what it printed to chat."""
        self.lua.eval("function(t) SlashCmdList['JUNKDROP'](t) end")(text)
        return self.ev("FlushChat()")

    def order(self):
        """Names of every stack that may be dropped, in drop order."""
        return self.ev(
            "(function() local t = {} for _, s in ipairs(NS.GetJunkStacks()) do t[#t+1] = s.Name end"
            " return table.concat(t, ', ') end)()"
        )

    def deleted(self):
        return self.ev("table.concat(Deleted, ', ')")

    def apply_skin(self, fail_on=None):
        """Have EllesmereUI run our registered skin function, as it does at login."""
        self.lua.eval("function(f) ApplySkin(f) end")(fail_on)

    def next_frame(self):
        self.run("Now = Now + 1")

    def bar_text(self):
        self.run("NS.RefreshText()")
        return self.ev("LDB.text")

    def popup_count(self):
        return self.ev("#Popups")

    def accept_popup(self, which="JUNKDROP_CONFIRM_RUN"):
        self.run('StaticPopupDialogs["%s"].OnAccept(nil, Popups[1].data)' % which)


def default_bag():
    """name, quality, price, count, item class (12 is quest items)"""
    return [
        ("Chipped Claw", 0, 4, 1, 15),
        ("Broken Boar Tusk", 0, 6, 1, 15),
        ("Hearthstone", 1, 0, 1, 15),  # sells for nothing
        ("Crate of Quest Stuff", 1, 10, 1, 12),  # a quest item
        ("Wooden Sword", 1, 3, 1, 2),
        ("Linen Cloth", 1, 5, 20, 7),  # 100 copper for the stack
        ("Green Cloak", 2, 40, 1, 4),
        ("Blue Ring", 3, 20000, 1, 4),
        ("Purple Helm", 4, 50000, 1, 4),
    ]


__all__ = ["Env", "default_bag", "quality_dots", "toc_lua_files", "ROOT"]
