#!/usr/bin/env python3
"""Regression tests for strip_mlx_cuda_plugin.sh.

Runs the script against a throwaway SourcePackages directory holding an
mlx-swift manifest in each layout it has to handle. The manifests are trimmed
copies of the real ones: the CUDA declarations and the `#if os(Linux)` blocks
around them are kept verbatim, and unrelated targets and settings are cut.

Run with: python3 -m unittest discover -s Resources/DevKit/tests
"""

import os
import subprocess
import tempfile
import unittest

SCRIPT = os.path.abspath(
    os.path.join(os.path.dirname(__file__), "..", "scripts", "strip_mlx_cuda_plugin.sh")
)

HEADER = """\
// swift-tools-version: 6.3;(experimentalCGen)
// The swift-tools-version declares the minimum version of Swift required to build this package.
// Copyright © 2024 Apple Inc.

import PackageDescription

"""

# mlx-swift 0.31.x: the plugin is attached to Cmlx and declared for every
# platform, so the script has to remove these three pieces.
LEGACY_PLUGIN_USAGE = """\
    plugins: [
        .plugin(name: "CudaBuild")
    ],
"""

LEGACY_ENCUDA_TARGET = """\
        .executableTarget(
            name: "encuda",
            dependencies: [
                .product(name: "ArgumentParser", package: "swift-argument-parser")
            ],
            path: "Source/Encuda",
        ),
"""

LEGACY_CUDABUILD_TARGET = """\
        .plugin(
            name: "CudaBuild",
            capability: .buildTool(),
            dependencies: [
                .target(name: "encuda")
            ],
        ),
"""

LEGACY_PIECES = [
    HEADER,
    """\
#if os(Linux)
    let cxxSettings: [CXXSetting] = [
        .unsafeFlags(["-I/usr/local/cuda/include"]),
    ]
#else
    // Apple's platforms with Metal

    let cxxSettings: [CXXSetting] = [
        .define("MLX_USE_ACCELERATE"),
    ]
#endif

let cmlx = Target.target(
    name: "Cmlx",
    path: "Source/Cmlx",
    cxxSettings: cxxSettings + [
        .define("MLX_VERSION", to: "\\"0.31.1\\""),
    ],
    linkerSettings: linkerSettings,
""",
    LEGACY_PLUGIN_USAGE,
    """\
)

let package = Package(
    name: "mlx-swift",
    products: [
        .library(name: "MLX", targets: ["MLX"]),
    ],
    dependencies: [
        // for Complex type
        .package(url: "https://github.com/apple/swift-numerics", from: "1.0.0"),
        .package(url: "https://github.com/apple/swift-argument-parser", from: "1.0.0"),
    ],
    targets: [
        cmlx,
        .executableTarget(
            name: "Tutorial",
            dependencies: ["MLX"],
            path: "Source/Examples",
            sources: ["Tutorial.swift"]
        ),
""",
    LEGACY_ENCUDA_TARGET,
    LEGACY_CUDABUILD_TARGET,
    """\
    ],
    cxxLanguageStandard: .gnucxx20
)
""",
]

LEGACY_MANIFEST = "".join(LEGACY_PIECES)
LEGACY_STRIPPED = "".join(
    piece
    for piece in LEGACY_PIECES
    if piece not in (LEGACY_PLUGIN_USAGE, LEGACY_ENCUDA_TARGET, LEGACY_CUDABUILD_TARGET)
)

# mlx-swift 0.32 and later: every CUDA declaration sits in an `#if os(Linux)`
# block, and a later Linux block still names CudaBuild in a comment.
LINUX_ONLY_MANIFEST = HEADER + """\
#if os(Linux)
    let cudaBuildPlugins: [Target.PluginUsage] = [
        .plugin(name: "CudaBuild")
    ]
    let cudaPackageDependencies: [Package.Dependency] = [
        .package(url: "https://github.com/apple/swift-argument-parser", from: "1.0.0")
    ]
    let cudaTargets: [Target] = [
        .executableTarget(
            name: "encuda",
            dependencies: [
                .product(name: "ArgumentParser", package: "swift-argument-parser")
            ],
            path: "Source/Encuda",
        ),
        .plugin(
            name: "CudaBuild",
            capability: .buildTool(),
            dependencies: [
                .target(name: "encuda")
            ],
        ),
    ]
#else
    let cudaBuildPlugins: [Target.PluginUsage] = []
    let cudaPackageDependencies: [Package.Dependency] = []
    let cudaTargets: [Target] = []
#endif

#if os(Linux)
    let platformExcludes: [String] = [
        // built by the CudaBuild plugin (nvcc), not by SwiftPM
        "mlx/mlx/backend/cuda/quantized/qmm",
    ]
#else
    // Apple's platforms with Metal

    let platformExcludes: [String] = [
        "mlx/mlx/backend/no_gpu",
    ]
#endif

let cmlx = Target.target(
    name: "Cmlx",
    path: "Source/Cmlx",
    exclude: platformExcludes,
    plugins: cudaBuildPlugins,
)

let package = Package(
    name: "mlx-swift",
    products: [
        .library(name: "MLX", targets: ["MLX"]),
    ],
    dependencies: [
        // for Complex type
        .package(url: "https://github.com/apple/swift-numerics", from: "1.0.0")
    ] + cudaPackageDependencies,
    targets: [
        cmlx,
    ] + cudaTargets,
    cxxLanguageStandard: .gnucxx20
)
"""

# A future layout the patterns do not recognise: the plugin is declared for
# every platform, but not in the shape the script knows how to remove.
UNKNOWN_LAYOUT_MANIFEST = HEADER + """\
let encuda = Target.executableTarget(name: "encuda", path: "Source/Encuda")
let cudaBuild = Target.plugin(name: "CudaBuild", capability: .buildTool(), dependencies: ["encuda"])

let package = Package(
    name: "mlx-swift",
    targets: [encuda, cudaBuild]
)
"""


class StripMLXCudaPluginTests(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory()
        root = self.directory.name
        self.source_packages = os.path.join(root, "SourcePackages")
        self.checkout = os.path.join(self.source_packages, "checkouts", "mlx-swift")
        self.manifest = os.path.join(self.checkout, "Package.swift")

        self.environment = dict(os.environ)
        for variable in ("CI_DERIVED_DATA_PATH", "DERIVED_DATA", "GIT_DIR", "GIT_WORK_TREE", "GIT_INDEX_FILE"):
            self.environment.pop(variable, None)
        self.environment["HOME"] = root
        self.environment["ZDOTDIR"] = root

    def tearDown(self):
        self.directory.cleanup()

    def write_manifest(self, content):
        os.makedirs(self.checkout, exist_ok=True)
        with open(self.manifest, "wb") as handle:
            handle.write(content.encode("utf-8"))
        # SwiftPM write-protects checkouts; the script has to cope with that.
        os.chmod(self.manifest, 0o444)

    def read_manifest(self):
        with open(self.manifest, "rb") as handle:
            return handle.read()

    def run_script(self, *arguments):
        return subprocess.run(
            ["/bin/zsh", SCRIPT, *arguments, self.source_packages],
            env=self.environment,
            capture_output=True,
            text=True,
        )

    def assert_succeeded(self, result):
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)

    def test_legacy_manifest_drops_the_cuda_plugin(self):
        self.write_manifest(LEGACY_MANIFEST)

        result = self.run_script()

        self.assert_succeeded(result)
        self.assertIn("patched:", result.stdout)
        self.assertEqual(self.read_manifest().decode("utf-8"), LEGACY_STRIPPED)

    def test_patched_manifest_is_left_alone_on_a_second_run(self):
        self.write_manifest(LEGACY_MANIFEST)
        self.assert_succeeded(self.run_script())
        patched = self.read_manifest()

        result = self.run_script()

        self.assert_succeeded(result)
        self.assertIn("already patched", result.stdout)
        self.assertEqual(self.read_manifest(), patched)

    def test_linux_only_manifest_is_left_byte_for_byte(self):
        self.write_manifest(LINUX_ONLY_MANIFEST)
        before = self.read_manifest()

        for _ in range(2):
            result = self.run_script()

            self.assert_succeeded(result)
            self.assertIn("nothing to strip", result.stdout)
            self.assertEqual(self.read_manifest(), before)

    def test_unknown_layout_fails_without_writing(self):
        self.write_manifest(UNKNOWN_LAYOUT_MANIFEST)
        before = self.read_manifest()

        result = self.run_script()

        self.assertEqual(result.returncode, 1, result.stdout + result.stderr)
        self.assertIn("manifest layout changed?", result.stderr)
        self.assertEqual(self.read_manifest(), before)

    def test_restore_puts_the_pristine_legacy_manifest_back(self):
        self.write_manifest(LEGACY_MANIFEST)
        git = ["git", "-C", self.checkout, "-c", "user.name=test", "-c", "user.email=test@example.com"]
        for command in (["init", "--quiet"], ["add", "Package.swift"], ["commit", "--quiet", "-m", "pristine"]):
            subprocess.run(git + command, env=self.environment, check=True, capture_output=True)
        self.assert_succeeded(self.run_script())
        self.assertEqual(self.read_manifest().decode("utf-8"), LEGACY_STRIPPED)

        result = self.run_script("--restore")

        self.assert_succeeded(result)
        self.assertIn("restored pristine manifest", result.stdout)
        self.assertEqual(self.read_manifest().decode("utf-8"), LEGACY_MANIFEST)

    def test_missing_checkout_fails_strip_and_skips_restore(self):
        os.makedirs(self.source_packages)

        strip = self.run_script()
        restore = self.run_script("--restore")

        self.assertEqual(strip.returncode, 1, strip.stdout + strip.stderr)
        self.assertIn("resolve packages first", strip.stderr)
        self.assert_succeeded(restore)
        self.assertIn("nothing to do", restore.stdout)


if __name__ == "__main__":
    unittest.main()
