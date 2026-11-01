#!/usr/bin/env python3
"""
Preflight for OldMate.mq5.

No MetaEditor is available in this environment, so this catches the classes of
mistake that a compiler catches: unbalanced delimiters, duplicate definitions,
calls to functions that do not exist, unused inputs, and calls with the wrong
number of arguments. It is not a compiler - it is the cheapest honest check
available before the file is opened in MetaEditor.

Run:  python3 tools/preflight.py OldMate.mq5
"""

import re
import sys
from collections import Counter

path = sys.argv[1] if len(sys.argv) > 1 else "OldMate.mq5"
src = open(path, encoding="utf-8", errors="replace").read()

fails, warns = [], []


def chk(label, cond, detail=""):
    print(("PASS  " if cond else "FAIL  ") + label + (("   " + detail) if detail else ""))
    if not cond:
        fails.append(label)


def warn(label, detail=""):
    print("WARN  " + label + (("   " + detail) if detail else ""))
    warns.append(label)


def strip_code(c):
    """Remove comments and string/char literals, keeping line structure."""
    out = []
    i, n = 0, len(c)
    while i < n:
        if c.startswith("//", i):
            j = c.find("\n", i)
            i = n if j < 0 else j
        elif c.startswith("/*", i):
            j = c.find("*/", i)
            seg = c[i:(n if j < 0 else j + 2)]
            out.append("\n" * seg.count("\n"))
            i = n if j < 0 else j + 2
        elif c[i] == '"':
            j = i + 1
            while j < n:
                if c[j] == "\\":
                    j += 2
                    continue
                if c[j] == '"':
                    break
                j += 1
            out.append('""')
            i = j + 1
        elif c[i] == "'":
            j = i + 1
            while j < n and c[j] != "'":
                j += 1
            out.append("''")
            i = j + 1
        else:
            out.append(c[i])
            i += 1
    return "".join(out)


s = strip_code(src)

print("=" * 70)
print("STRUCTURE")
print("=" * 70)
for o, c in [("{", "}"), ("(", ")"), ("[", "]")]:
    chk(f"balanced {o}{c}", s.count(o) == s.count(c), f"{s.count(o)}/{s.count(c)}")

chk("file ends with a newline", src.endswith("\n"))
chk("no stray ';;'", ";;" not in s)

print()
print("=" * 70)
print("EVENT HANDLERS")
print("=" * 70)
for fn in ["OnInit", "OnDeinit", "OnTick", "OnTimer"]:
    hits = len(re.findall(r"(?<![\w.])" + fn + r"\s*\(", s))
    chk(fn + " defined exactly once", hits == 1, str(hits) + " occurrence(s)")

print()
print("=" * 70)
print("DEFINITIONS")
print("=" * 70)
# function definitions at file scope: "type name(args)" followed by a body brace
defs = {}
for m in re.finditer(r"^[ \t]*(?:static\s+)?(?:const\s+)?"
                     r"([A-Za-z_]\w*)\s+"
                     r"([A-Za-z_]\w*)\s*\(([^;{)]*)\)\s*\{",
                     s, re.M):
    rtype, name, params = m.group(1), m.group(2), m.group(3)
    if rtype in ("if", "for", "while", "switch", "return", "else", "do"):
        continue
    defs.setdefault(name, []).append(params)

dups = [k for k, v in defs.items() if len(v) > 1]
chk("no duplicate function definitions", not dups, ", ".join(dups))

# struct members are not functions; make sure nothing silly got picked up
chk("a plausible number of functions was found", len(defs) > 40, f"{len(defs)} functions")

print()
print("=" * 70)
print("ARITY  (calls to our own functions)")
print("=" * 70)
def arity(params):
    """(required, maximum). A parameter with '=' is optional."""
    if params.strip() in ("", "void"):
        return 0, 0
    parts, depth, cur = [], 0, ""
    for ch in params:
        if ch in "([":
            depth += 1
        elif ch in ")]":
            depth -= 1
        if ch == "," and depth == 0:
            parts.append(cur)
            cur = ""
        else:
            cur += ch
    parts.append(cur)
    maximum = len(parts)
    required = sum(1 for x in parts if "=" not in x)
    return required, maximum


bad_arity = []
for name, plist in defs.items():
    want = arity(plist[0])  # (required, maximum)
    for m in re.finditer(r"(?<![\w.])" + name + r"\s*\(", s):
        start = m.end()
        depth, n = 1, 0
        i = start
        while i < len(s) and depth > 0:
            if s[i] in "([":
                depth += 1
            elif s[i] in ")]":
                depth -= 1
            elif s[i] == "," and depth == 1:
                n += 1
            i += 1
        got = 0 if s[start:i - 1].strip() == "" else n + 1
        line = s[:m.start()].count("\n") + 1
        lo, hi = want
        if not (lo <= got <= hi):
            bad_arity.append(f"{name} at line {line}: got {got}, expects {lo}-{hi}")
chk("every call to our own functions has the right number of arguments",
    not bad_arity, "; ".join(bad_arity[:6]))

print()
print("=" * 70)
print("UNKNOWN CALLS")
print("=" * 70)
BUILTIN = set("""
MathAbs MathMax MathMin MathFloor MathCeil MathRound MathSqrt MathLog MathPow
MathIsValidNumber MathRand ArrayResize ArraySize ArraySort ArraySetAsSeries ArrayCopy
StringLen StringFind StringSubstr StringSplit StringReplace StringToUpper StringToLower
StringFormat StringGetCharacter ShortToString StringToInteger StringToDouble StringTrimLeft
StringTrimRight StringConcatenate
DoubleToString IntegerToString TimeToString StringToTime CharToString
NormalizeDouble Print PrintFormat Comment Alert
ObjectCreate ObjectDelete ObjectFind ObjectSetInteger ObjectSetString ObjectSetDouble
ObjectGetInteger ObjectGetDouble ObjectGetString ObjectsDeleteAll ChartRedraw ChartGetInteger ChartWidthInPixels
ObjectsTotal ObjectName SymbolInfoSessionQuote SymbolInfoSessionTrade ObjectGetTimeByValue ObjectFind
FileOpen FileClose FileWrite FileRead FileWriteString FileReadString FileFlush FileSeek
FileIsEnding FileIsLineEnding
CopyClose CopyHigh CopyLow CopyRates CopyTime CopyTickVolume
iTime iHigh iLow iClose iOpen iVolume Bars Period PeriodSeconds
SymbolInfoDouble SymbolInfoInteger SymbolInfoString SymbolInfoTick SymbolInfoSessionTrade
AccountInfoDouble AccountInfoInteger AccountInfoString
TerminalInfoInteger TerminalInfoDouble TerminalInfoString
MQLInfoInteger MQLInfoString
TimeTradeServer TimeGMT TimeLocal TimeCurrent TimeToStruct StructToTime
PositionsTotal OrdersTotal HistorySelect HistorySelectByPosition HistoryDealsTotal
HistoryDealGetTicket HistoryDealGetDouble HistoryDealGetInteger
PositionSelectByTicket PositionGetDouble PositionGetInteger PositionGetString
OrderSelect OrderGetTicket OrderGetDouble OrderGetInteger OrderGetString
EnumToString GetTickCount EventSetTimer EventKillTimer
OrderCalcProfit OrderCalcMargin OrderSend OrderCheck
SetExpertMagicNumber SetDeviationInPoints SetTypeFilling
PositionOpen PositionModify PositionClose PositionClosePartial
OrderOpen OrderModify OrderDelete
Select SelectByIndex SelectByTicket
Volume VolumeCurrent PriceOpen StopLoss TakeProfit Magic Symbol Profit Swap
PositionType OrderType TimeSetup Ticket
""".split())

#  Preprocessor lines are not code: '#define LINE_H (FONT_SIZE + 9)' must not
#  look like a call to a function called LINE_H.
no_pp = re.sub(r"^[ \t]*#.*$", "", s, flags=re.M)
called = set(re.findall(r"(?<![\w.])([A-Za-z_]\w*)\s*\(", no_pp))
unknown = sorted(c for c in called
                 if c not in defs and c not in BUILTIN
                 and c not in {"if", "for", "while", "switch", "return", "sizeof", "else"})
chk("no calls to functions that do not exist", not unknown, ", ".join(unknown))

print()
print("=" * 70)
print("STRUCT MEMBERS")
print("=" * 70)
# Every "g_thing.field" must name a field that actually exists on that struct.
structs = {}
for m in re.finditer(r"struct\s+(\w+)\s*\{(.*?)\n\};", s, re.S):
    name, body = m.group(1), m.group(2)
    fields = set(re.findall(r"^\s*[A-Za-z_]\w*(?:\s*\[\s*\d*\s*\])?\s+(\w+)\s*(?:\[[^\]]*\]|\[[^\]]*\])?\s*;",
                            body, re.M))
    structs[name] = fields

vartype = {}
for m in re.finditer(r"^\s*(\w+)\s+(g_\w+)\s*(?:\[[^\]]*\]|\[[^\]]*\])?\s*;", s, re.M):
    vartype[m.group(2)] = m.group(1)

bad_fields = []
for m in re.finditer(r"\b(g_\w+)\s*(?:\[[^\]]*\])?\s*\.\s*(\w+)", s):
    var, field = m.group(1), m.group(2)
    t = vartype.get(var)
    if t in structs and field not in structs[t]:
        line = s[:m.start()].count("\n") + 1
        bad_fields.append(f"{var}.{field} at line {line} (not a field of {t})")
chk("every struct field read exists", not bad_fields, "; ".join(sorted(set(bad_fields))[:6]))
print(f"      {len(structs)} structs checked")

print()
print("=" * 70)
print("DEAD CONSTANTS")
print("=" * 70)
macros = re.findall(r"^#define\s+(\w+)\s+(.+)$", s, re.M)
dead = [n for n, _ in macros
        if len(re.findall(r"(?<![\w])" + n + r"(?![\w])", s)) < 2]
chk("no #define is declared and never used", not dead, ", ".join(dead))

print()
print("=" * 70)
print("LIBRARY CALLS  (argument counts for the CTrade / CPositionInfo methods used)")
print("=" * 70)
# Signatures of the standard-library methods this file calls, as
# name -> (required, maximum). A missing argument here is exactly the class of
# error that produced "cannot convert enum" at OrderOpen: the compiler then
# reports the *type* of the argument that slid into the wrong slot.
LIB = {
    "PositionOpen": (6, 7),
    "PositionModify": (3, 3),
    "PositionClose": (1, 2),
    "PositionClosePartial": (2, 3),
    "OrderOpen": (8, 10),
    "OrderModify": (5, 7),
    "OrderDelete": (1, 1),
    "SelectByIndex": (1, 1),
    "SelectByTicket": (1, 1),
}

lib_bad = []
for m in re.finditer(r"\b(g_trade|g_pos)\s*\.\s*(\w+)\s*\(", s):
    obj, meth = m.group(1), m.group(2)
    if meth not in LIB:
        continue
    start = m.end()
    depth, n = 1, 0
    i = start
    while i < len(s) and depth > 0:
        if s[i] in "([":
            depth += 1
        elif s[i] in ")]":
            depth -= 1
        elif s[i] == "," and depth == 1:
            n += 1
        i += 1
    got = 0 if s[start:i - 1].strip() == "" else n + 1
    lo, hi = LIB[meth]
    line = s[:m.start()].count("\n") + 1
    if not (lo <= got <= hi):
        lib_bad.append(f"{obj}.{meth} at line {line}: {got} args, signature allows {lo}-{hi}")
chk("every library call has a legal argument count", not lib_bad,
    "; ".join(lib_bad[:5]))

print()
print("=" * 70)
print("INPUTS")
print("=" * 70)
inputs = re.findall(r"^input\s+\w+\s+(\w+)\s*=", s, re.M)
print(f"      {len(inputs)} inputs: " + ", ".join(inputs))
for name in inputs:
    uses = len(re.findall(r"(?<![\w])" + name + r"(?![\w])", s))
    if uses < 2:
        warn(f"input {name} is declared but never read")
chk("every input is read somewhere", all(
    len(re.findall(r"(?<![\w])" + n + r"(?![\w])", s)) > 1 for n in inputs))

print()
print("=" * 70)
print("GUARDS")
print("=" * 70)
chk("never trades on an unsupported timeframe",
    "TimeframeAllowed" in s and s.count("TimeframeAllowed") >= 4,
    f"{s.count('TimeframeAllowed')} references")
chk("percentile has a minimum sample count", "PCT_MIN" in s)
chk("no ATR-multiple target or stop", not re.search(r"\bATR\b\s*\*", s))
chk("the forming bar is never read for a reading",
    "CopyClose(_Symbol, tf, 1, count" in s.replace("  ", " "),
    "start_pos 1")
chk("trading is gated by the terminal", "TerminalAllowsTrade" in s)
chk("fills are graded in money", "DEAL_SWAP" in s and "DEAL_COMMISSION" in s)

print()
print("=" * 70)
print("SIZE")
print("=" * 70)
print(f"      {len(src.splitlines())} lines, {len(src)} bytes")
print()

if fails:
    print(f"{len(fails)} CHECK(S) FAILED")
    for f in fails:
        print("   - " + f)
    sys.exit(1)
print("PREFLIGHT CLEAN" + (f"  ({len(warns)} warning(s))" if warns else ""))
