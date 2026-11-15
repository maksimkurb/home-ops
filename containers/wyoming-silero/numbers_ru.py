"""Spell out numbers in Russian text (Silero drops digits).

Handles integers (gender and simple case agreement), decimals ("20.3"),
times ("15:30"), percents, degrees and signs.
"""
import re
from functools import lru_cache

import pymorphy3

_MORPH = pymorphy3.MorphAnalyzer()

_ONES = {
    "m": ["", "один", "два", "три", "четыре", "пять", "шесть", "семь", "восемь", "девять"],
    "f": ["", "одна", "две", "три", "четыре", "пять", "шесть", "семь", "восемь", "девять"],
    "n": ["", "одно", "два", "три", "четыре", "пять", "шесть", "семь", "восемь", "девять"],
}
_TEENS = ["десять", "одиннадцать", "двенадцать", "тринадцать", "четырнадцать", "пятнадцать",
          "шестнадцать", "семнадцать", "восемнадцать", "девятнадцать"]
_TENS = ["", "", "двадцать", "тридцать", "сорок", "пятьдесят", "шестьдесят", "семьдесят",
         "восемьдесят", "девяносто"]
_HUNDREDS = ["", "сто", "двести", "триста", "четыреста", "пятьсот", "шестьсот", "семьсот",
             "восемьсот", "девятьсот"]
_SCALES = [  # (forms for 1 / 2-4 / 5+, gender)
    ("тысяча", "тысячи", "тысяч", "f"),
    ("миллион", "миллиона", "миллионов", "m"),
    ("миллиард", "миллиарда", "миллиардов", "m"),
    ("триллион", "триллиона", "триллионов", "m"),
]
_FRACTION_NAMES = {1: ("десятая", "десятых"), 2: ("сотая", "сотых"), 3: ("тысячная", "тысячных")}
_GENITIVE_PREPOSITIONS = {"до", "от", "из", "без", "около", "для", "после", "возле", "кроме", "среди", "вместо"}
_DATIVE_PREPOSITIONS = {"к"}
_RU_WORD = r"[А-Яа-яЁё]+"


def plural(n: int, forms: tuple[str, str, str]) -> str:
    n = abs(n)
    if n % 100 in range(11, 15):
        return forms[2]
    if n % 10 == 1:
        return forms[0]
    if n % 10 in (2, 3, 4):
        return forms[1]
    return forms[2]


def _triplet(n: int, gender: str) -> list[str]:
    words = []
    if n >= 100:
        words.append(_HUNDREDS[n // 100])
    n %= 100
    if 10 <= n < 20:
        words.append(_TEENS[n - 10])
    else:
        if n >= 20:
            words.append(_TENS[n // 10])
        if n % 10:
            words.append(_ONES[gender][n % 10])
    return words


def cardinal(n: int, gender: str = "m") -> list[str]:
    if n == 0:
        return ["ноль"]
    if n >= 1000 ** (len(_SCALES) + 1):
        return [w for ch in str(n) for w in cardinal(int(ch))]
    groups = []
    while n:
        groups.append(n % 1000)
        n //= 1000
    words: list[str] = []
    for index in range(len(groups) - 1, -1, -1):
        value = groups[index]
        if not value:
            continue
        if index == 0:
            words += _triplet(value, gender)
        else:
            *forms, scale_gender = _SCALES[index - 1]
            words += _triplet(value, scale_gender)
            words.append(plural(value, tuple(forms)))
    return words


@lru_cache(maxsize=2048)
def _inflect_word(word: str, case: str) -> str:
    parses = _MORPH.parse(word)
    parse = next((p for p in parses if "NUMR" in p.tag), parses[0])
    inflected = parse.inflect({case})
    return inflected.word if inflected else word


def _inflect(words: list[str], case: str | None) -> list[str]:
    return [_inflect_word(w, case) for w in words] if case else words


@lru_cache(maxsize=2048)
def _noun_gender(word: str) -> str:
    gender = _MORPH.parse(word)[0].tag.gender
    return {"femn": "f", "neut": "n"}.get(gender, "m")


def _context(text: str, start: int, end: int) -> tuple[str, str | None, str | None]:
    """Return (gender, case, unit_word) from the words around a number."""
    before = re.search(rf"({_RU_WORD})\s+$", text[:start])
    after = re.match(rf"\s*({_RU_WORD})", text[end:])
    prev = before.group(1).lower() if before else ""
    case = None
    if prev in _GENITIVE_PREPOSITIONS:
        case = "gent"
    elif prev in _DATIVE_PREPOSITIONS:
        case = "datv"
    elif prev == "с" and after and after.group(1).lower() == "до":
        case = "gent"
    gender = _noun_gender(after.group(1).lower()) if after else "m"
    return gender, case, after.group(1) if after else None


def _decimal_words(integer: str, fraction: str) -> list[str]:
    if len(fraction) > 3:
        return cardinal(int(integer)) + ["запятая"] + [w for ch in fraction for w in cardinal(int(ch))]
    whole = int(integer)
    numerator = int(fraction)
    whole_word = "целая" if whole % 10 == 1 and whole % 100 != 11 else "целых"
    names = _FRACTION_NAMES[len(fraction)]
    fraction_word = names[0] if numerator % 10 == 1 and numerator % 100 != 11 else names[1]
    return cardinal(whole, "f") + [whole_word] + cardinal(numerator, "f") + [fraction_word]


_ORDINAL_BASE = {
    "один": "первый", "два": "второй", "три": "третий", "четыре": "четвёртый", "пять": "пятый",
    "шесть": "шестой", "семь": "седьмой", "восемь": "восьмой", "девять": "девятый",
    "десять": "десятый", "одиннадцать": "одиннадцатый", "двенадцать": "двенадцатый",
    "тринадцать": "тринадцатый", "четырнадцать": "четырнадцатый", "пятнадцать": "пятнадцатый",
    "шестнадцать": "шестнадцатый", "семнадцать": "семнадцатый", "восемнадцать": "восемнадцатый",
    "девятнадцать": "девятнадцатый", "двадцать": "двадцатый", "тридцать": "тридцатый",
    "сорок": "сороковой", "пятьдесят": "пятидесятый", "шестьдесят": "шестидесятый",
    "семьдесят": "семидесятый", "восемьдесят": "восьмидесятый", "девяносто": "девяностый",
    "сто": "сотый", "двести": "двухсотый", "триста": "трёхсотый", "четыреста": "четырёхсотый",
    "пятьсот": "пятисотый", "шестьсот": "шестисотый", "семьсот": "семисотый",
    "восемьсот": "восьмисотый", "девятьсот": "девятисотый",
}
_MONTHS_GENITIVE = ["января", "февраля", "марта", "апреля", "мая", "июня", "июля", "августа",
                    "сентября", "октября", "ноября", "декабря"]
_YEAR_WORD_CASE = {"год": "nomn", "года": "gent", "году": "loct", "годом": "ablt"}


def ordinal(n: int, case: str = "nomn", gender: str = "masc", year: bool = False) -> list[str]:
    words = cardinal(n)
    if year and words[:2] == ["одна", "тысяча"]:
        words = words[1:]
    base = _ORDINAL_BASE.get(words[-1])
    if base is None:
        return words
    parse = _MORPH.parse(base)[0]
    inflected = parse.inflect({case, gender})
    return words[:-1] + [inflected.word if inflected else base]


_TIME = re.compile(r"(?<![\d:.,])(\d{1,2}):(\d{2})(?![\d:])")
_NUMBER = re.compile(
    r"(?P<sign>(?<![\w.,])[-−–+](?=\d))?"
    r"(?P<int>\d+)(?:[.,](?P<frac>\d+)(?![.,]\d))?"
    r"(?P<unit>\s*(?:%|℃|°\s*[CFCFС]?))?"
)


def _time(m: re.Match) -> str:
    hours, minutes = int(m.group(1)), m.group(2)
    words = cardinal(hours)
    if minutes == "00":
        words.append("ровно")
    elif minutes[0] == "0":
        words += ["ноль"] + cardinal(int(minutes))
    else:
        words += cardinal(int(minutes))
    return " ".join(words)


def _number(text: str):
    def repl(m: re.Match) -> str:
        integer, fraction = m.group("int"), m.group("frac")
        unit = (m.group("unit") or "").strip()
        words: list[str] = []
        sign = m.group("sign")
        if sign:
            words.append("плюс" if sign == "+" else "минус")

        if fraction is not None:
            number_words = _decimal_words(integer, fraction)
            plural_n = None
        elif len(integer) > 12:
            number_words = [w for ch in integer for w in cardinal(int(ch))]
            plural_n = None
        else:
            plural_n = int(integer)
            gender, case, next_word = _context(text, m.start("int"), m.end())
            year_case = _YEAR_WORD_CASE.get((next_word or "").lower())
            prev_match = re.search(rf"({_RU_WORD})\s+$", text[: m.start("int")])
            prev_word = prev_match.group(1).lower() if prev_match else ""
            if next_word and next_word.lower() in _MONTHS_GENITIVE and not unit and 1 <= plural_n <= 31:
                day_case = "gent" if case == "gent" or prev_word == "с" else "nomn"
                return " ".join(words + ordinal(plural_n, day_case, "neut" if day_case == "nomn" else "masc"))
            if prev_word in _MONTHS_GENITIVE and len(integer) == 4 and not unit and 1000 <= plural_n <= 2999:
                tail = [] if year_case else ["года"]
                return " ".join(words + ordinal(plural_n, "gent", year=True) + tail)
            if year_case and len(integer) == 4 and not unit and 1000 <= plural_n <= 2999:
                if year_case == "loct" and prev_word == "к":
                    year_case = "datv"
                return " ".join(words + ordinal(plural_n, year_case, year=True))
            if unit.startswith(("%", "°", "℃")):
                gender = "m"
            number_words = _inflect(cardinal(plural_n, gender), case)
            if fraction is None and not unit and case is None:
                pass
        if fraction is not None and not unit:
            _, case, _ = _context(text, m.start("int"), m.end())
            number_words = _inflect(number_words, case)
        words += number_words

        if unit.startswith("%"):
            words.append("процента" if plural_n is None else plural(plural_n, ("процент", "процента", "процентов")))
        elif unit:
            words.append("градуса" if plural_n is None else plural(plural_n, ("градус", "градуса", "градусов")))
            if unit.endswith("F"):
                words.append("по Фаренгейту")
            elif unit.endswith(("C", "С")) or unit == "℃":
                words.append("Цельсия")
        return " ".join(words)

    return repl


_DATE = re.compile(r"(?<![\d.])(\d{1,2})\.(\d{1,2})\.(\d{4})(?![\d])|(?<![\d-])(\d{4})-(\d{2})-(\d{2})(?![\d-])")


def _date(m: re.Match) -> str:
    day, month, year = (int(g) for g in (m.group(1, 2, 3) if m.group(1) else m.group(6, 5, 4)))
    if not (1 <= day <= 31 and 1 <= month <= 12):
        return m.group(0)
    words = ordinal(day, "nomn", "neut") + [_MONTHS_GENITIVE[month - 1]]
    words += ordinal(year, "gent", year=True) + ["года"]
    return " ".join(words)


_DOTTED = re.compile(r"(?<![\d.])\d+(?:\.\d+){2,}(?![\d])")


def _dotted(m: re.Match) -> str:
    return " точка ".join(" ".join(cardinal(int(part))) for part in m.group(0).split("."))


def spell_numbers(text: str) -> str:
    text = _DATE.sub(_date, text)
    text = _DOTTED.sub(_dotted, text)
    text = _TIME.sub(_time, text)
    return _NUMBER.sub(_number(text), text)
