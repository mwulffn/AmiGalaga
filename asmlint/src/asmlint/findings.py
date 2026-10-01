"""The findings a lint run reports."""

from dataclasses import dataclass

ERROR = "error"
WARNING = "warning"


@dataclass(frozen=True, order=True)
class Finding:
    """One problem found, printed as ``file:line: severity: message``."""

    file: str
    line: int
    severity: str
    message: str

    def __str__(self) -> str:
        return f"{self.file}:{self.line}: {self.severity}: {self.message}"
