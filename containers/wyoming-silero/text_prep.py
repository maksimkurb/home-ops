"""Text preparation for Silero Russian TTS.

Silero understands only Cyrillic, and treats ``**word**`` as its own emphasis
markup. Assistant replies contain markdown, emoji and English words, so they
are cleaned and transcribed to Cyrillic before synthesis.
"""
import re
from functools import lru_cache

import cmudict

_CMU = cmudict.dict()

# ARPAbet -> Russian approximation (stress is marked with "+" before the vowel)
_VOWELS = {
    "AA": "а", "AE": "э", "AH": "а", "AO": "о", "AW": "ау", "AY": "ай",
    "EH": "э", "ER": "ер", "EY": "эй", "IH": "и", "IY": "и", "OW": "оу",
    "OY": "ой", "UH": "у", "UW": "у",
}
_CONSONANTS = {
    "B": "б", "CH": "ч", "D": "д", "DH": "з", "F": "ф", "G": "г", "HH": "х",
    "JH": "дж", "K": "к", "L": "л", "M": "м", "N": "н", "NG": "нг", "P": "п",
    "R": "р", "S": "с", "SH": "ш", "T": "т", "TH": "с", "V": "в", "W": "в",
    "Y": "й", "Z": "з", "ZH": "ж",
}
_Y_VOWEL = {"AA": "я", "AH": "я", "UW": "ю", "UH": "ю", "EH": "е", "IY": "и", "IH": "и", "AO": "ё"}

_LETTERS = {
    "a": "а", "b": "б", "c": "к", "d": "д", "e": "е", "f": "ф", "g": "г", "h": "х",
    "i": "и", "j": "дж", "k": "к", "l": "л", "m": "м", "n": "н", "o": "о", "p": "п",
    "q": "к", "r": "р", "s": "с", "t": "т", "u": "у", "v": "в", "w": "в", "x": "кс",
    "y": "и", "z": "з",
}
_LETTER_NAMES = {
    "a": "эй", "b": "би", "c": "си", "d": "ди", "e": "и", "f": "эф", "g": "джи",
    "h": "эйч", "i": "ай", "j": "джей", "k": "кей", "l": "эл", "m": "эм", "n": "эн",
    "o": "оу", "p": "пи", "q": "кью", "r": "ар", "s": "эс", "t": "ти", "u": "ю",
    "v": "ви", "w": "дабл ю", "x": "экс", "y": "вай", "z": "зед",
}

_MARKDOWN = [
    (re.compile(r"```.*?```", re.S), " "),
    (re.compile(r"!\[[^\]]*\]\([^)]*\)"), " "),
    (re.compile(r"\[([^\]]*)\]\([^)]*\)"), r"\1"),
    (re.compile(r"https?://\S+"), " "),
    (re.compile(r"^\s{0,3}#{1,6}\s*", re.M), ""),
    (re.compile(r"^\s*[-*+•]\s+", re.M), ""),
    (re.compile(r"[*_`~#|>]+"), " "),
]
_EMOJI = re.compile(
    "[\U0001F000-\U0001FAFF\U00002600-\U000027BF\U0000FE0F\U0000200D\U00002190-\U000021FF\U00002B00-\U00002BFF]"
)
_LATIN_WORD = re.compile("[A-Za-z][A-Za-z'\u2019]*")
_ALLOWED = re.compile(r"[^0-9А-Яа-яЁё\s.,!?…:;()\-–—+%°/\"«»]")


def _phones_to_ru(phones: list[str]) -> str:
    out: list[str] = []
    i = 0
    while i < len(phones):
        base = phones[i].rstrip("012")
        stress = phones[i].endswith("1")
        if base == "Y" and i + 1 < len(phones) and phones[i + 1].rstrip("012") in _Y_VOWEL:
            nxt = phones[i + 1]
            out.append(("+" if nxt.endswith("1") else "") + _Y_VOWEL[nxt.rstrip("012")])
            i += 2
            continue
        if base in _VOWELS:
            out.append(("+" if stress else "") + _VOWELS[base])
        else:
            out.append(_CONSONANTS.get(base, ""))
        i += 1
    return "".join(out)


def _spell(word: str) -> str:
    return "".join(_LETTERS.get(ch, "") for ch in word.lower())


@lru_cache(maxsize=4096)
def transcribe_word(word: str) -> str:
    key = word.replace("\u2019", "'").lower()
    if key in _CMU:
        return _phones_to_ru(_CMU[key][0])
    if key.endswith("'s") and key[:-2] in _CMU:
        return _phones_to_ru(_CMU[key[:-2]][0]) + "с"
    if word.isupper() and 2 <= len(word) <= 5:  # acronym: LED, HVAC
        return " ".join(_LETTER_NAMES.get(ch, "") for ch in key if ch.isalpha())
    return _spell(key.replace("'", ""))


def prepare_text(text: str) -> str:
    for pattern, repl in _MARKDOWN:
        text = pattern.sub(repl, text)
    text = _EMOJI.sub(" ", text)
    text = _LATIN_WORD.sub(lambda m: " " + transcribe_word(m.group(0)) + " ", text)
    text = text.replace("&", " и ")
    text = _ALLOWED.sub(" ", text)
    return re.sub(r"[ \t]+", " ", text).strip()
