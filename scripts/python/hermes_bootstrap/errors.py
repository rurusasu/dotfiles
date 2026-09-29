"""Stable errors exposed by the Hermes bootstrap command."""

from __future__ import annotations

from typing import ClassVar


class BootstrapError(Exception):
    """Base class for failures reported by the bootstrap command."""

    exit_code: ClassVar[int] = 1


class InputError(BootstrapError):
    exit_code = 2


class CredentialError(BootstrapError):
    exit_code = 3


class RepositoryError(BootstrapError):
    exit_code = 4


class MigrationError(BootstrapError):
    exit_code = 5


class ApplyError(BootstrapError):
    exit_code = 6


class RollbackError(BootstrapError):
    exit_code = 7


class ValidationError(BootstrapError):
    exit_code = 8
