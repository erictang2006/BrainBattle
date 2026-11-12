#!/usr/bin/env python3
"""Reproducible Xcode project with no package-manager or generator dependencies."""
import hashlib
from pathlib import Path
import json

root = Path(__file__).resolve().parents[1]
project = root / "BrainBattle.xcodeproj"
project.mkdir(exist_ok=True)
objects = {}
def uid(name): return hashlib.sha1(name.encode()).hexdigest()[:24].upper()
def quote(value): return json.dumps(str(value))
def add(name, value):
    objects[uid(name)] = value
    return uid(name)
def settings(values): return "{ " + " ".join(f"{k} = {quote(v)};" for k, v in values.items()) + " }"
def refs(values): return "(" + ", ".join(values) + ")"

targets = ["BrainBattle", "BrainBattleTests", "BrainBattleUITests"]
products = []
groups = []
for target in targets:
    files = []
    sources = []
    resources = []
    for path in sorted((root / target).rglob("*")):
        if not path.is_file() or ".xcassets/" in str(path): continue
        relative = path.relative_to(root).as_posix()
        kind = {".swift": "sourcecode.swift", ".plist": "text.plist.xml", ".xcprivacy": "text.xml"}.get(path.suffix, "text")
        ref = add("file:" + relative, f"{{ isa = PBXFileReference; lastKnownFileType = {kind}; path = {quote(relative)}; sourceTree = SOURCE_ROOT; }}")
        files.append(ref)
        if path.suffix in [".swift", ".xcprivacy"]:
            build = add("build:" + relative, f"{{ isa = PBXBuildFile; fileRef = {ref}; }}")
            (sources if path.suffix == ".swift" else resources).append(build)
    if target == "BrainBattle":
        relative = "BrainBattle/Resources/Assets.xcassets"
        ref = add("assets", f"{{ isa = PBXFileReference; lastKnownFileType = folder.assetcatalog; path = {quote(relative)}; sourceTree = SOURCE_ROOT; }}")
        files.append(ref)
        resources.append(add("assets-build", f"{{ isa = PBXBuildFile; fileRef = {ref}; }}"))
    groups.append(add("group:" + target, f"{{ isa = PBXGroup; name = {target}; children = {refs(files)}; sourceTree = \"<group>\"; }}"))
    is_app = target == "BrainBattle"
    extension = "app" if is_app else "xctest"
    product = add("product:" + target, f"{{ isa = PBXFileReference; explicitFileType = {'wrapper.application' if is_app else 'wrapper.cfbundle'}; path = {target}.{extension}; sourceTree = BUILT_PRODUCTS_DIR; }}")
    products.append(product)
    phases = [add("sources:" + target, f"{{ isa = PBXSourcesBuildPhase; buildActionMask = 2147483647; files = {refs(sources)}; runOnlyForDeploymentPostprocessing = 0; }}"),
              add("frameworks:" + target, "{ isa = PBXFrameworksBuildPhase; buildActionMask = 2147483647; files = (); runOnlyForDeploymentPostprocessing = 0; }"),
              add("resources:" + target, f"{{ isa = PBXResourcesBuildPhase; buildActionMask = 2147483647; files = {refs(resources)}; runOnlyForDeploymentPostprocessing = 0; }}")]
    configurations = []
    for config in ["Debug", "Release"]:
        s = {"PRODUCT_NAME": "$(TARGET_NAME)", "PRODUCT_BUNDLE_IDENTIFIER": "com.brainbattle." + target,
             "SWIFT_VERSION": "6.0", "IPHONEOS_DEPLOYMENT_TARGET": "18.0", "TARGETED_DEVICE_FAMILY": "1",
             "CODE_SIGN_STYLE": "Automatic", "CURRENT_PROJECT_VERSION": "1", "MARKETING_VERSION": "0.1.0",
             "SUPPORTED_PLATFORMS": "iphoneos iphonesimulator", "SDKROOT": "iphoneos",
             "SWIFT_OPTIMIZATION_LEVEL": "-Onone" if config == "Debug" else "-O",
             "ENABLE_TESTABILITY": "YES" if config == "Debug" else "NO", "GENERATE_INFOPLIST_FILE": "NO" if is_app else "YES"}
        if is_app:
            s.update({"INFOPLIST_FILE": "BrainBattle/Resources/Info.plist", "ASSETCATALOG_COMPILER_APPICON_NAME": "AppIcon", "ASSETCATALOG_COMPILER_GLOBAL_ACCENT_COLOR_NAME": "AccentColor", "LD_RUNPATH_SEARCH_PATHS": "$(inherited) @executable_path/Frameworks"})
            s['"CODE_SIGN_ENTITLEMENTS[sdk=iphonesimulator*]"'] = 'Configuration/Simulator.entitlements'
        elif target == "BrainBattleTests":
            s.update({"TEST_HOST": "$(BUILT_PRODUCTS_DIR)/BrainBattle.app/$(BUNDLE_EXECUTABLE_FOLDER_PATH)/BrainBattle", "BUNDLE_LOADER": "$(TEST_HOST)", "LD_RUNPATH_SEARCH_PATHS": "$(inherited) @executable_path/Frameworks @loader_path/Frameworks"})
        else: s.update({"TEST_TARGET_NAME": "BrainBattle"})
        config_file = add("configfile:" + config, f'{{ isa = PBXFileReference; lastKnownFileType = text.xcconfig; path = "Configuration/{config}.xcconfig"; sourceTree = SOURCE_ROOT; }}')
        configurations.append(add(f"config:{target}:{config}", f"{{ isa = XCBuildConfiguration; baseConfigurationReference = {config_file}; buildSettings = {settings(s)}; name = {config}; }}"))
    config_list = add("configs:" + target, f"{{ isa = XCConfigurationList; buildConfigurations = {refs(configurations)}; defaultConfigurationIsVisible = 0; defaultConfigurationName = Release; }}")
    dependencies = []
    if not is_app:
        proxy = add("proxy:" + target, f"{{ isa = PBXContainerItemProxy; containerPortal = {uid('project')}; proxyType = 1; remoteGlobalIDString = {uid('target:BrainBattle')}; remoteInfo = BrainBattle; }}")
        dependencies.append(add("dependency:" + target, f"{{ isa = PBXTargetDependency; target = {uid('target:BrainBattle')}; targetProxy = {proxy}; }}"))
    product_type = "application" if is_app else "bundle.unit-test" if target == "BrainBattleTests" else "bundle.ui-testing"
    add("target:" + target, f"{{ isa = PBXNativeTarget; buildConfigurationList = {config_list}; buildPhases = {refs(phases)}; buildRules = (); dependencies = {refs(dependencies)}; name = {target}; productName = {target}; productReference = {product}; productType = \"com.apple.product-type.{product_type}\"; }}")

groups.append(add("configuration-group", f'{{ isa = PBXGroup; name = Configuration; children = {refs([uid("configfile:Debug"),uid("configfile:Release")])}; sourceTree = "<group>"; }}'))
product_group = add("products", f'{{ isa = PBXGroup; name = Products; children = {refs(products)}; sourceTree = "<group>"; }}')
main = add("main", f'{{ isa = PBXGroup; children = {refs(groups + [product_group])}; sourceTree = "<group>"; }}')
configs = [add("project-config:" + c, f"{{ isa = XCBuildConfiguration; buildSettings = {{ CLANG_ENABLE_MODULES = YES; ENABLE_USER_SCRIPT_SANDBOXING = YES; DEBUG_INFORMATION_FORMAT = {quote('dwarf' if c == 'Debug' else 'dwarf-with-dsym')}; }}; name = {c}; }}") for c in ["Debug","Release"]]
config_list = add("project-configs", f"{{ isa = XCConfigurationList; buildConfigurations = {refs(configs)}; defaultConfigurationIsVisible = 0; defaultConfigurationName = Release; }}")
add("project", f'{{ isa = PBXProject; attributes = {{ LastUpgradeCheck = 2600; }}; buildConfigurationList = {config_list}; compatibilityVersion = "Xcode 14.0"; developmentRegion = en; hasScannedForEncodings = 0; knownRegions = (en, Base); mainGroup = {main}; productRefGroup = {product_group}; projectDirPath = ""; projectRoot = ""; targets = {refs([uid("target:"+t) for t in targets])}; }}')
(project / "project.pbxproj").write_text("// !$*UTF8*$!\n{ archiveVersion = 1; classes = {}; objectVersion = 56; objects = {\n" + "\n".join(f"{k} = {v};" for k,v in sorted(objects.items())) + f"\n}}; rootObject = {uid('project')}; }}\n")
schemes = project / "xcshareddata/xcschemes"
schemes.mkdir(parents=True, exist_ok=True)
def ref(t): return f'<BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="{uid("target:"+t)}" BuildableName="{t}.{"app" if t == "BrainBattle" else "xctest"}" BlueprintName="{t}" ReferencedContainer="container:BrainBattle.xcodeproj"/>'
(schemes / "BrainBattle.xcscheme").write_text(f'''<?xml version="1.0" encoding="UTF-8"?>
<Scheme LastUpgradeVersion="2600" version="1.7">
<BuildAction parallelizeBuildables="YES" buildImplicitDependencies="YES"><BuildActionEntries><BuildActionEntry buildForTesting="YES" buildForRunning="YES" buildForProfiling="YES" buildForArchiving="YES" buildForAnalyzing="YES">{ref("BrainBattle")}</BuildActionEntry></BuildActionEntries></BuildAction>
<TestAction buildConfiguration="Debug" selectedDebuggerIdentifier="Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier="Xcode.IDEFoundation.Launcher.LLDB" shouldUseLaunchSchemeArgsEnv="YES"><Testables><TestableReference skipped="NO" parallelizable="NO">{ref("BrainBattleTests")}</TestableReference><TestableReference skipped="NO" parallelizable="NO">{ref("BrainBattleUITests")}</TestableReference></Testables></TestAction>
<LaunchAction buildConfiguration="Debug" selectedDebuggerIdentifier="Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier="Xcode.IDEFoundation.Launcher.LLDB" launchStyle="0" useCustomWorkingDirectory="NO" ignoresPersistentStateOnLaunch="NO" debugDocumentVersioning="YES" debugServiceExtension="internal" allowLocationSimulation="YES"><BuildableProductRunnable runnableDebuggingMode="0">{ref("BrainBattle")}</BuildableProductRunnable></LaunchAction>
<ProfileAction buildConfiguration="Release" shouldUseLaunchSchemeArgsEnv="YES" savedToolIdentifier="" useCustomWorkingDirectory="NO" debugDocumentVersioning="YES"><BuildableProductRunnable runnableDebuggingMode="0">{ref("BrainBattle")}</BuildableProductRunnable></ProfileAction>
<AnalyzeAction buildConfiguration="Debug"/><ArchiveAction buildConfiguration="Release" revealArchiveInOrganizer="YES"/>
</Scheme>''')
print(project)
