"""
core/parser/processing/types.py — dataclasses for blueprint parsing
"""

from dataclasses import dataclass, field
import os


@dataclass
class StorageNode:
    name:     str
    mount:    str                          # mount path inside container
    children: list["StorageNode"] = field(default_factory=list)

    def paths(self, prefix: str = "") -> list[tuple[str, str]]:
        """Returns list of (profile_path, mount_path) tuples."""
        full = os.path.join(prefix, self.name) if prefix else self.name
        if not self.children:
            return [(full, self.mount)]
        return [(full, self.mount)] + [
            p for c in self.children for p in c.paths(full)
        ]


@dataclass
class BuildConfig:
    rootfs:  str                              = "ubuntu:latest"
    deps:    list[tuple[str, str]]            = field(default_factory=list)  # (manager, args)
    install: list[str]                        = field(default_factory=list)


@dataclass
class RunConfig:
    entrypoint:  str                  = ""
    port:        str                  = ""
    restart:     str                  = "no"
    restart_max: int                  = 0
    user:        str                  = ""
    workdir:     str                  = "/"
    depends:     str                  = ""
    env:         dict[str, object]    = field(default_factory=dict)
    resources:   dict[str, object]    = field(default_factory=dict)
    isolation:   dict[str, object]    = field(default_factory=dict)
    health:      dict[str, object]    = field(default_factory=dict)
    storage:     list[StorageNode]    = field(default_factory=list)
    security_preset: str              = ""  # AppArmor: strict|default|permissive


@dataclass
class Service:
    name:  str
    meta:  dict[str, object] = field(default_factory=dict)
    build: BuildConfig       = field(default_factory=BuildConfig)
    run:   RunConfig         = field(default_factory=RunConfig)
    extra: dict              = field(default_factory=dict)


@dataclass
class MainConfig:
    meta:     dict[str, object] = field(default_factory=dict)
    services: list[str]         = field(default_factory=list)
    startup:  list[str]         = field(default_factory=list)


@dataclass
class Blueprint:
    main:     MainConfig
    parsed:   dict[str, Service] = field(default_factory=dict)
    errors:   list[str]          = field(default_factory=list)
    warnings: list[str]          = field(default_factory=list)