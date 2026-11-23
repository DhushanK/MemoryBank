#!/usr/bin/env python3
"""Minimal Xcode project generator for TelepathyEngine (macOS + iOS destinations)."""

from __future__ import annotations

import uuid
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
APP_SOURCES = sorted((ROOT / "Apps/TelepathyEngine/Shared").glob("*.swift"))
ENTITLEMENTS = "Apps/TelepathyEngine/TelepathyEngine.entitlements"
PROJECT = ROOT / "TelepathyEngine.xcodeproj"


def xid() -> str:
    return uuid.uuid4().hex[:24].upper()


def main() -> None:
    project_id = xid()
    target_id = xid()
    sources_phase = xid()
    resources_phase = xid()
    frameworks_phase = xid()
    product_ref = xid()
    main_group = xid()
    products_group = xid()
    app_group = xid()
    packages_group = xid()
    config_list_project = xid()
    config_list_target = xid()
    debug_project = xid()
    release_project = xid()
    debug_target = xid()
    release_target = xid()
    package_ref = xid()
    neural_product = xid()
    session_product = xid()
    memory_product = xid()
    llm_product = xid()

    file_entries = []
    build_files = []
    source_build_ids = []
    source_file_ids = []

    for path in APP_SOURCES:
        fid = xid()
        bid = xid()
        source_file_ids.append((fid, path.name))
        source_build_ids.append((bid, fid, path.name))
        file_entries.append(
            f'\t\t{fid} /* {path.name} */ = {{isa = PBXFileReference; lastKnownFileType = sourcecode.swift; name = {path.name}; path = {path.name}; sourceTree = "<group>"; }};'
        )
        build_files.append(
            f"\t\t{bid} /* {path.name} */ = {{isa = PBXBuildFile; fileRef = {fid} /* {path.name} */; }};"
        )

    seed_fid = xid()
    seed_bid = xid()
    bin_fid = xid()
    bin_bid = xid()
    file_entries.append(
        f'\t\t{seed_fid} /* seed_memory.json */ = {{isa = PBXFileReference; lastKnownFileType = text.json; name = seed_memory.json; path = ../../../Samples/context/seed_memory.json; sourceTree = "<group>"; }};'
    )
    file_entries.append(
        f'\t\t{bin_fid} /* synthetic_neural.bin */ = {{isa = PBXFileReference; lastKnownFileType = archive.macbinary; name = synthetic_neural.bin; path = ../Resources/synthetic_neural.bin; sourceTree = "<group>"; }};'
    )
    build_files.append(
        f"\t\t{seed_bid} /* seed_memory.json */ = {{isa = PBXBuildFile; fileRef = {seed_fid} /* seed_memory.json */; }};"
    )
    build_files.append(
        f"\t\t{bin_bid} /* synthetic_neural.bin */ = {{isa = PBXBuildFile; fileRef = {bin_fid} /* synthetic_neural.bin */; }};"
    )

    ent_fid = xid()
    file_entries.append(
        f'\t\t{ent_fid} /* TelepathyEngine.entitlements */ = {{isa = PBXFileReference; lastKnownFileType = text.plist.entitlements; path = ../TelepathyEngine.entitlements; sourceTree = "<group>"; }};'
    )

    product_entry = (
        f'\t\t{product_ref} /* TelepathyEngine.app */ = {{isa = PBXFileReference; explicitFileType = wrapper.application; includeInIndex = 0; path = TelepathyEngine.app; sourceTree = BUILT_PRODUCTS_DIR; }};'
    )

    sources_list = "\n".join(f"\t\t\t\t{bid} /* {name} */," for bid, _, name in source_build_ids)
    shared_children = "\n".join(f"\t\t\t\t{fid} /* {name} */," for fid, name in source_file_ids)

    pkg_build_neural = xid()
    pkg_build_session = xid()
    pkg_build_memory = xid()
    pkg_build_llm = xid()
    build_files += [
        f"\t\t{pkg_build_neural} /* NeuralCore */ = {{isa = PBXBuildFile; productRef = {neural_product} /* NeuralCore */; }};",
        f"\t\t{pkg_build_session} /* SessionKit */ = {{isa = PBXBuildFile; productRef = {session_product} /* SessionKit */; }};",
        f"\t\t{pkg_build_memory} /* MemoryBankKit */ = {{isa = PBXBuildFile; productRef = {memory_product} /* MemoryBankKit */; }};",
        f"\t\t{pkg_build_llm} /* LLMBridge */ = {{isa = PBXBuildFile; productRef = {llm_product} /* LLMBridge */; }};",
    ]

    package_product_deps = f"""
\t\t{neural_product} /* NeuralCore */ = {{
\t\t\tisa = XCSwiftPackageProductDependency;
\t\t\tpackage = {package_ref} /* TelepathyEngineLibs */;
\t\t\tproductName = NeuralCore;
\t\t}};
\t\t{session_product} /* SessionKit */ = {{
\t\t\tisa = XCSwiftPackageProductDependency;
\t\t\tpackage = {package_ref} /* TelepathyEngineLibs */;
\t\t\tproductName = SessionKit;
\t\t}};
\t\t{memory_product} /* MemoryBankKit */ = {{
\t\t\tisa = XCSwiftPackageProductDependency;
\t\t\tpackage = {package_ref} /* TelepathyEngineLibs */;
\t\t\tproductName = MemoryBankKit;
\t\t}};
\t\t{llm_product} /* LLMBridge */ = {{
\t\t\tisa = XCSwiftPackageProductDependency;
\t\t\tpackage = {package_ref} /* TelepathyEngineLibs */;
\t\t\tproductName = LLMBridge;
\t\t}};
"""

    pbx = f"""// !$*UTF8*$!
{{
\tarchiveVersion = 1;
\tclasses = {{
\t}};
\tobjectVersion = 56;
\tobjects = {{

/* Begin PBXBuildFile section */
{chr(10).join(build_files)}
/* End PBXBuildFile section */

/* Begin PBXFileReference section */
{chr(10).join(file_entries)}
{product_entry}
/* End PBXFileReference section */

/* Begin PBXFrameworksBuildPhase section */
\t\t{frameworks_phase} /* Frameworks */ = {{
\t\t\tisa = PBXFrameworksBuildPhase;
\t\t\tbuildActionMask = 2147483647;
\t\t\tfiles = (
\t\t\t\t{pkg_build_neural} /* NeuralCore */,
\t\t\t\t{pkg_build_session} /* SessionKit */,
\t\t\t\t{pkg_build_memory} /* MemoryBankKit */,
\t\t\t\t{pkg_build_llm} /* LLMBridge */,
\t\t\t);
\t\t\trunOnlyForDeploymentPostprocessing = 0;
\t\t}};
/* End PBXFrameworksBuildPhase section */

/* Begin PBXGroup section */
\t\t{main_group} = {{
\t\t\tisa = PBXGroup;
\t\t\tchildren = (
\t\t\t\t{app_group} /* TelepathyEngine */,
\t\t\t\t{packages_group} /* Packages */,
\t\t\t\t{products_group} /* Products */,
\t\t\t);
\t\t\tsourceTree = "<group>";
\t\t}};
\t\t{products_group} /* Products */ = {{
\t\t\tisa = PBXGroup;
\t\t\tchildren = (
\t\t\t\t{product_ref} /* TelepathyEngine.app */,
\t\t\t);
\t\t\tname = Products;
\t\t\tsourceTree = "<group>";
\t\t}};
\t\t{app_group} /* TelepathyEngine */ = {{
\t\t\tisa = PBXGroup;
\t\t\tchildren = (
{shared_children}
\t\t\t\t{seed_fid} /* seed_memory.json */,
\t\t\t\t{bin_fid} /* synthetic_neural.bin */,
\t\t\t\t{ent_fid} /* TelepathyEngine.entitlements */,
\t\t\t);
\t\t\tpath = Apps/TelepathyEngine/Shared;
\t\t\tname = TelepathyEngine;
\t\t\tsourceTree = "<group>";
\t\t}};
\t\t{packages_group} /* Packages */ = {{
\t\t\tisa = PBXGroup;
\t\t\tchildren = (
\t\t\t);
\t\t\tname = Packages;
\t\t\tsourceTree = "<group>";
\t\t}};
/* End PBXGroup section */

/* Begin PBXNativeTarget section */
\t\t{target_id} /* TelepathyEngine */ = {{
\t\t\tisa = PBXNativeTarget;
\t\t\tbuildConfigurationList = {config_list_target} /* Build configuration list for PBXNativeTarget "TelepathyEngine" */;
\t\t\tbuildPhases = (
\t\t\t\t{sources_phase} /* Sources */,
\t\t\t\t{frameworks_phase} /* Frameworks */,
\t\t\t\t{resources_phase} /* Resources */,
\t\t\t);
\t\t\tbuildRules = (
\t\t\t);
\t\t\tdependencies = (
\t\t\t);
\t\t\tname = TelepathyEngine;
\t\t\tpackageProductDependencies = (
\t\t\t\t{neural_product} /* NeuralCore */,
\t\t\t\t{session_product} /* SessionKit */,
\t\t\t\t{memory_product} /* MemoryBankKit */,
\t\t\t\t{llm_product} /* LLMBridge */,
\t\t\t);
\t\t\tproductName = TelepathyEngine;
\t\t\tproductReference = {product_ref} /* TelepathyEngine.app */;
\t\t\tproductType = "com.apple.product-type.application";
\t\t}};
/* End PBXNativeTarget section */

/* Begin PBXProject section */
\t\t{project_id} /* Project object */ = {{
\t\t\tisa = PBXProject;
\t\t\tattributes = {{
\t\t\t\tBuildIndependentTargetsInParallel = 1;
\t\t\t\tLastSwiftUpdateCheck = 1600;
\t\t\t\tLastUpgradeCheck = 1600;
\t\t\t}};
\t\t\tbuildConfigurationList = {config_list_project} /* Build configuration list for PBXProject "TelepathyEngine" */;
\t\t\tcompatibilityVersion = "Xcode 15.0";
\t\t\tdevelopmentRegion = en;
\t\t\thasScannedForEncodings = 0;
\t\t\tknownRegions = (
\t\t\t\ten,
\t\t\t\tBase,
\t\t\t);
\t\t\tmainGroup = {main_group};
\t\t\tpackageReferences = (
\t\t\t\t{package_ref} /* XCLocalSwiftPackageReference */,
\t\t\t);
\t\t\tproductRefGroup = {products_group} /* Products */;
\t\t\tprojectDirPath = "";
\t\t\tprojectRoot = "";
\t\t\ttargets = (
\t\t\t\t{target_id} /* TelepathyEngine */,
\t\t\t);
\t\t}};
/* End PBXProject section */

/* Begin PBXResourcesBuildPhase section */
\t\t{resources_phase} /* Resources */ = {{
\t\t\tisa = PBXResourcesBuildPhase;
\t\t\tbuildActionMask = 2147483647;
\t\t\tfiles = (
\t\t\t\t{seed_bid} /* seed_memory.json */,
\t\t\t\t{bin_bid} /* synthetic_neural.bin */,
\t\t\t);
\t\t\trunOnlyForDeploymentPostprocessing = 0;
\t\t}};
/* End PBXResourcesBuildPhase section */

/* Begin PBXSourcesBuildPhase section */
\t\t{sources_phase} /* Sources */ = {{
\t\t\tisa = PBXSourcesBuildPhase;
\t\t\tbuildActionMask = 2147483647;
\t\t\tfiles = (
{sources_list}
\t\t\t);
\t\t\trunOnlyForDeploymentPostprocessing = 0;
\t\t}};
/* End PBXSourcesBuildPhase section */

/* Begin XCBuildConfiguration section */
\t\t{debug_project} /* Debug */ = {{
\t\t\tisa = XCBuildConfiguration;
\t\t\tbuildSettings = {{
\t\t\t\tALWAYS_SEARCH_USER_PATHS = NO;
\t\t\t\tCLANG_ENABLE_MODULES = YES;
\t\t\t\tCOPY_PHASE_STRIP = NO;
\t\t\t\tDEBUG_INFORMATION_FORMAT = dwarf;
\t\t\t\tONLY_ACTIVE_ARCH = YES;
\t\t\t\tSDKROOT = macosx;
\t\t\t\tSWIFT_ACTIVE_COMPILATION_CONDITIONS = "DEBUG";
\t\t\t\tSWIFT_OPTIMIZATION_LEVEL = "-Onone";
\t\t\t}};
\t\t\tname = Debug;
\t\t}};
\t\t{release_project} /* Release */ = {{
\t\t\tisa = XCBuildConfiguration;
\t\t\tbuildSettings = {{
\t\t\t\tALWAYS_SEARCH_USER_PATHS = NO;
\t\t\t\tCLANG_ENABLE_MODULES = YES;
\t\t\t\tSDKROOT = macosx;
\t\t\t\tSWIFT_COMPILATION_MODE = wholemodule;
\t\t\t}};
\t\t\tname = Release;
\t\t}};
\t\t{debug_target} /* Debug */ = {{
\t\t\tisa = XCBuildConfiguration;
\t\t\tbuildSettings = {{
\t\t\t\tCODE_SIGN_ENTITLEMENTS = {ENTITLEMENTS};
\t\t\t\tCODE_SIGN_STYLE = Automatic;
\t\t\t\tCOMBINE_HIDPI_IMAGES = YES;
\t\t\t\tCURRENT_PROJECT_VERSION = 1;
\t\t\t\tENABLE_HARDENED_RUNTIME = YES;
\t\t\t\tGENERATE_INFOPLIST_FILE = YES;
\t\t\t\tINFOPLIST_KEY_CFBundleDisplayName = "Telepathy Engine";
\t\t\t\tINFOPLIST_KEY_NSLocalNetworkUsageDescription = "Receive simulated neural UDP streams.";
\t\t\t\tLD_RUNPATH_SEARCH_PATHS = (
\t\t\t\t\t"$(inherited)",
\t\t\t\t\t"@executable_path/../Frameworks",
\t\t\t\t);
\t\t\t\tMACOSX_DEPLOYMENT_TARGET = 14.0;
\t\t\t\tIPHONEOS_DEPLOYMENT_TARGET = 17.0;
\t\t\t\tMARKETING_VERSION = 0.1.0;
\t\t\t\tPRODUCT_BUNDLE_IDENTIFIER = com.memorybank.TelepathyEngine;
\t\t\t\tPRODUCT_NAME = "$(TARGET_NAME)";
\t\t\t\tSDKROOT = auto;
\t\t\t\tSUPPORTED_PLATFORMS = "macosx iphoneos iphonesimulator";
\t\t\t\tSUPPORTS_MACCATALYST = YES;
\t\t\t\tSWIFT_EMIT_LOC_STRINGS = YES;
\t\t\t\tSWIFT_VERSION = 5.0;
\t\t\t\tTARGETED_DEVICE_FAMILY = "1,2";
\t\t\t}};
\t\t\tname = Debug;
\t\t}};
\t\t{release_target} /* Release */ = {{
\t\t\tisa = XCBuildConfiguration;
\t\t\tbuildSettings = {{
\t\t\t\tCODE_SIGN_ENTITLEMENTS = {ENTITLEMENTS};
\t\t\t\tCODE_SIGN_STYLE = Automatic;
\t\t\t\tCOMBINE_HIDPI_IMAGES = YES;
\t\t\t\tCURRENT_PROJECT_VERSION = 1;
\t\t\t\tENABLE_HARDENED_RUNTIME = YES;
\t\t\t\tGENERATE_INFOPLIST_FILE = YES;
\t\t\t\tINFOPLIST_KEY_CFBundleDisplayName = "Telepathy Engine";
\t\t\t\tINFOPLIST_KEY_NSLocalNetworkUsageDescription = "Receive simulated neural UDP streams.";
\t\t\t\tLD_RUNPATH_SEARCH_PATHS = (
\t\t\t\t\t"$(inherited)",
\t\t\t\t\t"@executable_path/../Frameworks",
\t\t\t\t);
\t\t\t\tMACOSX_DEPLOYMENT_TARGET = 14.0;
\t\t\t\tIPHONEOS_DEPLOYMENT_TARGET = 17.0;
\t\t\t\tMARKETING_VERSION = 0.1.0;
\t\t\t\tPRODUCT_BUNDLE_IDENTIFIER = com.memorybank.TelepathyEngine;
\t\t\t\tPRODUCT_NAME = "$(TARGET_NAME)";
\t\t\t\tSDKROOT = auto;
\t\t\t\tSUPPORTED_PLATFORMS = "macosx iphoneos iphonesimulator";
\t\t\t\tSUPPORTS_MACCATALYST = YES;
\t\t\t\tSWIFT_EMIT_LOC_STRINGS = YES;
\t\t\t\tSWIFT_VERSION = 5.0;
\t\t\t\tTARGETED_DEVICE_FAMILY = "1,2";
\t\t\t}};
\t\t\tname = Release;
\t\t}};
/* End XCBuildConfiguration section */

/* Begin XCConfigurationList section */
\t\t{config_list_project} /* Build configuration list for PBXProject "TelepathyEngine" */ = {{
\t\t\tisa = XCConfigurationList;
\t\t\tbuildConfigurations = (
\t\t\t\t{debug_project} /* Debug */,
\t\t\t\t{release_project} /* Release */,
\t\t\t);
\t\t\tdefaultConfigurationIsVisible = 0;
\t\t\tdefaultConfigurationName = Release;
\t\t}};
\t\t{config_list_target} /* Build configuration list for PBXNativeTarget "TelepathyEngine" */ = {{
\t\t\tisa = XCConfigurationList;
\t\t\tbuildConfigurations = (
\t\t\t\t{debug_target} /* Debug */,
\t\t\t\t{release_target} /* Release */,
\t\t\t);
\t\t\tdefaultConfigurationIsVisible = 0;
\t\t\tdefaultConfigurationName = Release;
\t\t}};
/* End XCConfigurationList section */

/* Begin XCLocalSwiftPackageReference section */
\t\t{package_ref} /* XCLocalSwiftPackageReference */ = {{
\t\t\tisa = XCLocalSwiftPackageReference;
\t\t\trelativePath = .;
\t\t}};
/* End XCLocalSwiftPackageReference section */

/* Begin XCSwiftPackageProductDependency section */
{package_product_deps}
/* End XCSwiftPackageProductDependency section */
\t}};
\trootObject = {project_id} /* Project object */;
}}
"""

    PROJECT.mkdir(exist_ok=True)
    (PROJECT / "project.pbxproj").write_text(pbx)
    workspace = PROJECT / "project.xcworkspace"
    workspace.mkdir(exist_ok=True)
    (workspace / "contents.xcworkspacedata").write_text(
        """<?xml version="1.0" encoding="UTF-8"?>
<Workspace
   version = "1.0">
   <FileRef
      location = "self:">
   </FileRef>
</Workspace>
"""
    )
    print(f"Wrote {PROJECT}")


if __name__ == "__main__":
    main()
