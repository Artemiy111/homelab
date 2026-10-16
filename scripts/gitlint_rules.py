import re

from gitlint.rules import CommitRule, RuleViolation

TITLE_RE = re.compile(r"^[a-z]+(?:\([^()]+\))?!?: (?P<subject>.*)$")
FOOTER_RE = re.compile(r"^[A-Za-z][A-Za-z -]*(?:: .+| #\d+)$")
QUOTED_RE = re.compile(r"`.*?`|\".*?\"|'.*?'")
WORD_RE = re.compile(r"[A-Z]?[a-z]+|[A-Z]+(?![a-z])|\d+")


def _camel(value):
    words = WORD_RE.findall(value)
    if not words:
        return ""
    return words[0].lower() + "".join(w[:1].upper() + w[1:].lower() for w in words[1:])


def _start(value):
    words = []
    for word in WORD_RE.findall(value):
        if word == word.upper():
            words.append(word)
        else:
            words.append(word[:1].upper() + word[1:].lower())
    return " ".join(words)


class SubjectRules(CommitRule):
    name = "subject-conventional"
    id = "UC1"

    def validate(self, commit):
        match = TITLE_RE.match(commit.message.title)
        if not match:
            return []
        subject = match.group("subject")
        if not subject.strip():
            return [RuleViolation(self.id, "subject must not be empty", line_nr=1)]
        if subject.endswith("."):
            return [RuleViolation(self.id, "subject must not end with a full stop", line_nr=1)]
        bare = QUOTED_RE.sub("", subject).strip()
        if not bare or bare[0].isdigit():
            return []
        transforms = (
            ("upper-case", str.upper),
            ("pascal-case", lambda value: _camel(value)[:1].upper() + _camel(value)[1:]),
            ("start-case", _start),
        )
        for case, transform in transforms:
            if transform(bare) == bare:
                return [RuleViolation(self.id, f"subject must not be in {case}", line_nr=1)]
        return []


class BodyForbidden(CommitRule):
    name = "body-forbidden"
    id = "UC2"

    def validate(self, commit):
        for line_nr, line in enumerate(commit.message.body, start=2):
            if not line.strip():
                continue
            if not FOOTER_RE.match(line):
                message = f"body is forbidden, only a footer like `Refs #12` is allowed: `{line}`"
                return [RuleViolation(self.id, message, line_nr=line_nr)]
        return []
